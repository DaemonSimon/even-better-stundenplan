import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../models/timetable_result.dart';
import '../providers/date_utilities.dart';
import 'connectivity_monitor.dart';
import 'session_manager.dart';
import 'stundenplan_api.dart';
import 'stundenplan_parser.dart';
import 'timetable_cache.dart';

/// Ergebnis des Wochen-Abrufs.
sealed class _FetchResult {}

class _FetchSuccess extends _FetchResult {
  _FetchSuccess(this.week);
  final WeeklyTimetable week;
}

class _FetchAuthExpired extends _FetchResult {}

class _FetchFailed extends _FetchResult {}

/// Holt eine komplette Woche (Mo–Fr) über einen einzigen page-5-Request
/// und parst die Antwort.
///
/// Offline-first: Liegt die Woche schon im Cache (Speicher oder Platte),
/// wird sie sofort geliefert und nur im Hintergrund aktualisiert. Erst
/// wenn sich dabei etwas geändert hat, werden die Listener benachrichtigt.
/// Ohne Internet bleibt der gespeicherte Stand stehen; sobald der
/// [ConnectivityMonitor] wieder Verbindung meldet, wird neu geladen.
///
/// Bei abgelaufener Sitzung wird im Hintergrund (ohne User-Interaktion)
/// eine neue Sitzung über die gespeicherten Zugangsdaten geholt und die
/// Woche erneut geladen; in der Zwischenzeit wird der Cache angezeigt.
class StundenplanRepository extends ChangeNotifier {
  StundenplanRepository({
    required SessionManager sessionManager,
    StundenplanApi? api,
    StundenplanParser? parser,
    TimetableCache? cache,
    ConnectivityMonitor? connectivity,
  }) : _sessionManager = sessionManager,
       _api = api ?? StundenplanApi(),
       _parser = parser ?? StundenplanParser(),
       _cache = cache ?? TimetableCache(),
       _connectivity = connectivity ?? ConnectivityMonitor.instance {
    _connectivity.addListener(_onConnectivityChanged);
  }

  final SessionManager _sessionManager;
  final StundenplanApi _api;
  final StundenplanParser _parser;
  final TimetableCache _cache;
  final ConnectivityMonitor _connectivity;

  bool _reauthRunning = false;

  /// Wochen, die gerade im Hintergrund aktualisiert werden.
  final Set<String> _refreshing = {};

  /// Zeigt weiter den gespeicherten Stand, lädt aber im Hintergrund neu.
  void refresh() {
    _cache.markAllStale();
    notifyListeners();
  }

  void _onConnectivityChanged() {
    if (_connectivity.isOnline) refresh();
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  Future<TimetableResult> getTimetable(
    String dateString, {
    required bool weeklyMode,
  }) async {
    final weekStart = getMondayOfWeek(dateString);
    final weekKey = DateFormat('dd.MM.yyyy').format(weekStart);

    // Frisch im Speicher: kein Netz nötig.
    final fresh = _cache.getFresh(weekKey);
    if (fresh != null) return _wrapResult(fresh, weeklyMode, dateString);

    // Gespeicherter Stand vorhanden: sofort anzeigen, im Hintergrund
    // aktualisieren.
    final cached = await _getCached(weekKey);
    if (cached != null) {
      unawaited(_refreshInBackground(weekKey, weekStart, cached));
      return _wrapResult(cached, weeklyMode, dateString);
    }

    // Nichts gespeichert: auf das Netz warten.
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return _handleAuthExpired(weekKey, weekStart, weeklyMode, dateString);
    }

    final fetched = await _tryFetchWeek(weekStart, weekKey);

    switch (fetched) {
      case _FetchSuccess(:final week):
        await _cache.put(weekKey, week);
        return _wrapResult(week, weeklyMode, dateString);

      case _FetchAuthExpired():
        return _handleAuthExpired(weekKey, weekStart, weeklyMode, dateString);

      case _FetchFailed():
        return const TimetableNetworkError();
    }
  }

  /// Lädt eine bereits angezeigte Woche im Hintergrund neu und meldet sich
  /// nur, wenn sich etwas geändert hat.
  Future<void> _refreshInBackground(
    String weekKey,
    DateTime weekStart,
    WeeklyTimetable shown,
  ) async {
    if (!_refreshing.add(weekKey)) return;
    try {
      final sessionId = _sessionManager.sessionId;
      if (sessionId == null || sessionId.isEmpty) {
        unawaited(_silentReauthenticate(weekKey, weekStart));
        return;
      }
      final fetched = await _tryFetchWeek(weekStart, weekKey);
      switch (fetched) {
        case _FetchSuccess(:final week):
          await _cache.put(weekKey, week);
          if (!_sameWeek(week, shown)) notifyListeners();
        case _FetchAuthExpired():
          unawaited(_silentReauthenticate(weekKey, weekStart));
        case _FetchFailed():
          // Offline oder Server down: gespeicherten Stand behalten.
          break;
      }
    } finally {
      _refreshing.remove(weekKey);
    }
  }

  bool _sameWeek(WeeklyTimetable a, WeeklyTimetable b) =>
      jsonEncode([for (final d in a.days) d.toJson()]) ==
      jsonEncode([for (final d in b.days) d.toJson()]);

  Future<TimetableResult> _handleAuthExpired(
    String weekKey,
    DateTime weekStart,
    bool weeklyMode,
    String dateString,
  ) async {
    // Cache sofort liefern (falls vorhanden) …
    final cached = await _getCached(weekKey);

    // … und im Hintergrund neu anmelden + neu laden.
    _silentReauthenticate(weekKey, weekStart);

    if (cached != null) {
      return _wrapResult(cached, weeklyMode, dateString);
    }
    return const TimetableAuthExpired();
  }

  /// Wendet an, ob die ganze Woche oder nur ein einzelner Tag geliefert wird.
  TimetableResult _wrapResult(
    WeeklyTimetable week,
    bool weeklyMode,
    String dateString,
  ) {
    if (!weeklyMode) {
      final day = _dayMatching(week, dateString);
      return TimetableSuccess(
        timetable: WeeklyTimetable(weekStart: week.weekStart, days: [day]),
      );
    }
    return TimetableSuccess(timetable: week);
  }

  DailyTimetable _dayMatching(WeeklyTimetable week, String dateString) {
    final target = DateFormat('dd.MM.yyyy').parse(dateString);
    for (final day in week.days) {
      if (day.date.year == target.year &&
          day.date.month == target.month &&
          day.date.day == target.day) {
        return day;
      }
    }
    // Fallback: erster Tag der Woche.
    return week.days.isNotEmpty
        ? week.days.first
        : DailyTimetable(date: week.weekStart, timeSlots: const []);
  }

  /// Stille Neu-Anmeldung + erneuter Abruf im Hintergrund.
  /// Nach erfolgreichem Refresh werden die Listener benachrichtigt.
  Future<void> _silentReauthenticate(String weekKey, DateTime weekStart) async {
    if (_reauthRunning) return;
    _reauthRunning = true;
    try {
      final ok = await _sessionManager.tryReAuthenticate();
      if (!ok) return;
      final refetched = await _tryFetchWeek(weekStart, weekKey);
      if (refetched is _FetchSuccess) {
        await _cache.put(weekKey, refetched.week);
        notifyListeners();
      }
    } finally {
      _reauthRunning = false;
    }
  }

  Future<_FetchResult> _tryFetchWeek(DateTime weekStart, String weekKey) async {
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return _FetchAuthExpired();
    }

    try {
      final response = await _api.fetchWeek(
        sessionId,
        DateFormat('dd.MM.yyyy').format(weekStart),
      );

      if (response.statusCode >= 300 && response.statusCode < 400) {
        return _FetchAuthExpired();
      }
      if (response.statusCode != 200) {
        return _FetchFailed();
      }
      if (_parser.isLoginPage(response.body)) {
        return _FetchAuthExpired();
      }
      if (!_parser.hasTimetableStructure(response.body)) {
        return _FetchFailed();
      }
      // Server hat geantwortet: Verbindung steht.
      _connectivity.reportSuccess();

      final weeklySlots = _parser.parseWeeklyTimetable(response.body);
      // Mo–Fr Datum zuweisen.
      final days = <DailyTimetable>[];
      for (int i = 0; i < weeklySlots.length; i++) {
        days.add(
          DailyTimetable(
            date: weekStart.add(Duration(days: i)),
            timeSlots: weeklySlots[i],
          ),
        );
      }
      return _FetchSuccess(WeeklyTimetable(weekStart: weekStart, days: days));
    } catch (error) {
      if (isNetworkError(error)) _connectivity.reportFailure();
      return _FetchFailed();
    }
  }

  Future<WeeklyTimetable?> _getCached(String weekKey) async {
    final fresh = _cache.getFresh(weekKey);
    if (fresh != null) return fresh;
    final stale = _cache.getStale(weekKey);
    if (stale != null) return stale;
    final disk = await _cache.getFromDisk(weekKey);
    if (disk != null) _cache.rememberStale(weekKey, disk);
    return disk;
  }
}

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../models/timetable_result.dart';
import '../providers/date_utilities.dart';
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

/// Holt eine komplette Woche (Mo–Fr) über einen einzigen page-5-Request,
/// parst die Antwort und nutzt den Cache als Offline-/Reauth-Fallback.
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
  }) : _sessionManager = sessionManager,
       _api = api ?? StundenplanApi(),
       _parser = parser ?? StundenplanParser(),
       _cache = cache ?? TimetableCache();

  final SessionManager _sessionManager;
  final StundenplanApi _api;
  final StundenplanParser _parser;
  final TimetableCache _cache;

  bool _reauthRunning = false;

  Future<TimetableResult> getTimetable(
    String dateString, {
    required bool weeklyMode,
  }) async {
    final weekStart = getMondayOfWeek(dateString);
    final weekKey = DateFormat('dd.MM.yyyy').format(weekStart);

    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      // Keine Sitzung vorhanden – ggf. aus dem Cache bedienen und still
      // neu anmelden.
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
        final cached = await _getCached(weekKey);
        if (cached != null) {
          return _wrapResult(cached, weeklyMode, dateString);
        }
        return const TimetableNetworkError();
    }
  }

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

  Future<_FetchResult> _tryFetchWeek(
    DateTime weekStart,
    String weekKey,
  ) async {
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
      return _FetchSuccess(
        WeeklyTimetable(weekStart: weekStart, days: days),
      );
    } catch (_) {
      return _FetchFailed();
    }
  }

  Future<WeeklyTimetable?> _getCached(String weekKey) async {
    final fresh = _cache.getFresh(weekKey);
    if (fresh != null) return fresh;
    final stale = _cache.getStale(weekKey);
    if (stale != null) return stale;
    return _cache.getFromDisk(weekKey);
  }
}

import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../models/timetable_result.dart';
import '../providers/date_utilities.dart';
import 'session_manager.dart';
import 'stundenplan_api.dart';
import 'stundenplan_parser.dart';
import 'timetable_cache.dart';

enum _DayStatus { ok, authExpired, failed }

typedef _DayResult = ({_DayStatus status, DailyTimetable? day});

/// Holt eine Woche (Mo–So) oder einen einzelnen Tag, parst die Antworten
/// und nutzt den Cache als Offline-Fallback.
class StundenplanRepository {
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

  Future<TimetableResult> getTimetable(
    String dateString, {
    required bool weeklyMode,
  }) async {
    if (!weeklyMode) {
      return _getSingleDay(dateString);
    }

    final weekStart = getMondayOfWeek(dateString);
    final dayKeys = [
      for (int i = 0; i < 7; i++)
        DateFormat('dd.MM.yyyy').format(weekStart.add(Duration(days: i))),
    ];

    final results = await Future.wait([
      for (final key in dayKeys) _fetchDayOrFallback(key),
    ]);

    // Sitzung abgelaufen: dann ist die ganze Woche betroffen.
    for (final result in results) {
      if (result.status == _DayStatus.authExpired) {
        return const TimetableAuthExpired();
      }
    }

    final days = <DailyTimetable>[];
    for (final result in results) {
      if (result.day == null) {
        // Kein Netz und kein Cache -> Fehler für die ganze Woche
        return const TimetableNetworkError();
      }
      days.add(result.day!);
    }

    return TimetableSuccess(
      timetable: WeeklyTimetable(weekStart: weekStart, days: days),
    );
  }

  Future<TimetableResult> _getSingleDay(String dateString) async {
    final result = await _fetchDayOrFallback(dateString);

    if (result.status == _DayStatus.authExpired) {
      return const TimetableAuthExpired();
    }
    if (result.day == null) {
      return const TimetableNetworkError();
    }

    return TimetableSuccess(
      timetable: WeeklyTimetable(weekStart: result.day!.date, days: [result.day!]),
    );
  }

  /// Liefert den Tag aus dem Cache, sonst vom Netz (mit Cache-Fallback).
  Future<_DayResult> _fetchDayOrFallback(String dateKey) async {
    final fresh = _cache.getFresh(dateKey);
    if (fresh != null) return (status: _DayStatus.ok, day: fresh);

    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return (status: _DayStatus.authExpired, day: null);
    }

    try {
      final response = await _api.fetchDay(sessionId, dateKey);

      if (response.statusCode >= 300 && response.statusCode < 400) {
        return (status: _DayStatus.authExpired, day: null);
      }
      if (response.statusCode != 200) {
        return _fallbackOrFail(dateKey);
      }
      if (_parser.isLoginPage(response.body)) {
        return (status: _DayStatus.authExpired, day: null);
      }
      if (!_parser.hasTimetableStructure(response.body)) {
        return _fallbackOrFail(dateKey);
      }

      final day = DailyTimetable(
        date: DateFormat('dd.MM.yyyy').parse(dateKey),
        timeSlots: _parser.parseDayTimetable(response.body),
      );
      await _cache.put(dateKey, day);
      return (status: _DayStatus.ok, day: day);
    } catch (_) {
      return _fallbackOrFail(dateKey);
    }
  }

  /// Bei Fehlern auf veralteten Speicher- oder Platten-Cache zurückgreifen.
  Future<_DayResult> _fallbackOrFail(String dateKey) async {
    final stale = _cache.getStale(dateKey) ?? await _cache.getFromDisk(dateKey);
    if (stale != null) {
      return (status: _DayStatus.ok, day: stale);
    }
    return (status: _DayStatus.failed, day: null);
  }
}
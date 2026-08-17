import 'timetable.dart';

sealed class TimetableResult {
  const TimetableResult();
}

class TimetableSuccess extends TimetableResult {
  const TimetableSuccess({required this.timetable});

  final WeeklyTimetable timetable;
}

/// Sitzung abgelaufen; der Nutzer muss sich neu anmelden.
class TimetableAuthExpired extends TimetableResult {
  const TimetableAuthExpired();
}

/// Netzwerk- oder Serverfehler und kein Cache-Fallback verfügbar.
class TimetableNetworkError extends TimetableResult {
  const TimetableNetworkError();
}
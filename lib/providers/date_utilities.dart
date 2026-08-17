import 'package:intl/intl.dart';

DateTime getNthDayOfWeek(DateTime date, int targetWeekday) {
  int difference = targetWeekday - date.weekday;
  return date.add(Duration(days: difference));
}

/// Montag der Woche, die das Datum (dd.MM.yyyy) enthält.
DateTime getMondayOfWeek(String dateString) {
  final parsedDate = DateFormat('dd.MM.yyyy').parse(dateString);
  return getNthDayOfWeek(parsedDate, DateTime.monday);
}
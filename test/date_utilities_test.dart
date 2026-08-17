import 'package:flutter_test/flutter_test.dart';
import 'package:better_stundenplan/providers/date_utilities.dart';

void main() {
  group('dateUtilities', () {
    test('getMondayOfWeek returns the Monday of the week', () {
      // 14.08.2026 ist ein Freitag
      final monday = getMondayOfWeek('14.08.2026');
      expect(monday.weekday, DateTime.monday);
      expect(monday.day, 10);
    });

    test('getMondayOfWeek is identity on a Monday', () {
      // 10.08.2026 ist ein Montag
      final monday = getMondayOfWeek('10.08.2026');
      expect(monday.day, 10);
    });

    test('getMondayOfWeek handles year boundaries', () {
      // 01.01.2027 ist ein Freitag -> Montag liegt in 2026 (28.12.)
      final monday = getMondayOfWeek('01.01.2027');
      expect(monday.year, 2026);
      expect(monday.month, 12);
      expect(monday.day, 28);
    });

    test('getNthDayOfWeek returns the target weekday', () {
      final date = DateTime(2026, 8, 14); // Freitag
      final sunday = getNthDayOfWeek(date, DateTime.sunday);
      expect(sunday.day, 16);
      final monday = getNthDayOfWeek(date, DateTime.monday);
      expect(monday.day, 10);
    });
  });
}

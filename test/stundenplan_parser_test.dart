import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:better_stundenplan/models/timetable.dart';
import 'package:better_stundenplan/services/stundenplan_parser.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  final parser = StundenplanParser();

  group('StundenplanParser', () {
    test('parses a whole week Mo–Fr, dropping Sa/So', () {
      final week = parser.parseWeeklyTimetable(
        fixture('week_page5_real.html'),
      );

      expect(week.length, 5); // Mo, Di, Mi, Do, Fr

      // Montag (Index 0), Stunde 1
      final mo1 = week[0].firstWhere((s) => s.period == 1);
      expect(mo1.lessons.single.lesson, 'L02T');
      expect(mo1.lessons.single.teacher, 'HSWT');
      expect(mo1.lessons.single.room, 'A101');

      // Freitag (Index 4), Stunde 5
      final fr5 = week[4].firstWhere((s) => s.period == 5);
      expect(fr5.lessons.single.lesson, 'PH');
      expect(fr5.lessons.single.teacher, 'LAET');
      expect(fr5.lessons.single.room, 'B007');
    });

    test('parallel courses in one period stay side by side', () {
      final week = parser.parseWeeklyTimetable(
        fixture('week_page5_real.html'),
      );

      // Dienstag (Index 1), Stunde 5: zwei Kurse (A/B-Gruppen).
      final di5 = week[1].firstWhere((s) => s.period == 5);
      expect(di5.lessons.length, 2);
      expect(di5.lessons[0].lesson, 'A:L07P');
      expect(di5.lessons[0].teacher, 'A:KREP');
      expect(di5.lessons[0].room, 'A:C003');
      expect(di5.lessons[1].lesson, 'B:L07P');
      expect(di5.lessons[1].teacher, 'B:SYEP');
      expect(di5.lessons[1].room, 'B:C008');
    });

    test('a room without a subject is still parsed as a lesson with a teacher', () {
      final week = parser.parseWeeklyTimetable(
        fixture('week_page5_real.html'),
      );

      // Freitag (Index 4), Stunde 7: "SWET, B004" (kein Fach) + "SYEP, B004".
      final fr7 = week[4].firstWhere((s) => s.period == 7);
      expect(fr7.lessons.length, 2);
      expect(fr7.lessons[0].teacher, 'SWET');
      expect(fr7.lessons[0].room, 'B004');
      expect(fr7.lessons[1].teacher, 'SYEP');
      expect(fr7.lessons[1].room, 'B004');
    });

    test('empty days and empty periods produce no slots', () {
      final week = parser.parseWeeklyTimetable(
        fixture('week_page5_real.html'),
      );

      // Montag (Index 0): Stunde 7 und 8 sind frei.
      final mo = week[0];
      expect(mo.any((s) => s.period == 7), isFalse);
      expect(mo.any((s) => s.period == 8), isFalse);
      // Dienstag (Index 1): Stunde 7/8 vorhanden (A/B-Kurse).
      final di = week[1];
      expect(di.any((s) => s.period == 7), isTrue);
    });

    test('a fully empty week returns five empty day-lists', () {
      final week = parser.parseWeeklyTimetable(fixture('week_empty.html'));
      expect(week.length, 5);
      expect(week.every((day) => day.isEmpty), isTrue);
    });

    test('detects timetable structure', () {
      expect(
        parser.hasTimetableStructure(fixture('week_page5_real.html')),
        isTrue,
      );
      expect(parser.hasTimetableStructure(fixture('week_empty.html')), isTrue);
      expect(
        parser.hasTimetableStructure(fixture('page_without_structure.html')),
        isFalse,
      );
    });

    test('detects the login page', () {
      expect(parser.isLoginPage(fixture('login_page.html')), isTrue);
      expect(parser.isLoginPage(fixture('week_page5_real.html')), isFalse);
    });

    test('double hours are represented as identical consecutive slots', () {
      final week = parser.parseWeeklyTimetable(
        fixture('week_with_double_hours.html'),
      );
      final fr = week[4];
      final p1 = fr.firstWhere((s) => s.period == 1);
      final p2 = fr.firstWhere((s) => s.period == 2);
      expect(sameLessonList(
        p1.lessons.map((e) => e).toList(),
        p2.lessons.map((e) => e).toList(),
      ), isTrue);
    });

    test('combines teacher-only LK cells with separate Fach/Raum tables', () {
      final week = parser.parseWeeklyTimetable(
        fixture('week_teachers_only.html'),
      );

      // Montag (Index 0), Stunde 1: TUWT + DE + A116.
      final mo1 = week[0].firstWhere((s) => s.period == 1);
      expect(mo1.lessons.single.teacher, 'TUWT');
      expect(mo1.lessons.single.lesson, 'DE');
      expect(mo1.lessons.single.room, 'A116');

      // Dienstag (Index 1), Stunde 1: HYWT + L01P + C019.
      final di1 = week[1].firstWhere((s) => s.period == 1);
      expect(di1.lessons.single.teacher, 'HYWT');
      expect(di1.lessons.single.lesson, 'L01P');
      expect(di1.lessons.single.room, 'C019');
    });

    test('a substitution becomes one entry keeping the original teacher', () {
      final week = parser.parseWeeklyTimetable(
        fixture('week_vertretung.html'),
      );

      // Montag (Index 0), Stunde 3: <del>BSMT</del> + BDET, Fach SP, Raum T3.
      final mo3 = week[0].firstWhere((s) => s.period == 3);
      expect(mo3.lessons.length, 1);
      final lesson = mo3.lessons.single;
      expect(lesson.teacher, 'BSMT'); // eigentlicher Lehrer
      expect(lesson.substituteTeacher, 'BDET'); // Vertreter
      expect(lesson.lesson, 'SP');
      expect(lesson.room, 'T3');
      expect(lesson.isSubstitution, isTrue);
    });

    test('a substitution double hour stays identical for collapsing', () {
      final week = parser.parseWeeklyTimetable(
        fixture('week_vertretung.html'),
      );
      final mo3 = week[0].firstWhere((s) => s.period == 3);
      final mo4 = week[0].firstWhere((s) => s.period == 4);
      expect(sameLessonList(mo3.lessons, mo4.lessons), isTrue);
    });

    test('substitution in a parallel course keeps both tracks', () {
      final week = parser.parseWeeklyTimetable(
        fixture('week_vertretung.html'),
      );

      // Dienstag (Index 1), Stunde 8: A normal, B vertreten (B:SYEP -> B:KREP).
      final di8 = week[1].firstWhere((s) => s.period == 8);
      expect(di8.lessons.length, 2);
      expect(di8.lessons[0].teacher, 'A:KREP');
      expect(di8.lessons[0].substituteTeacher, isNull);
      expect(di8.lessons[0].lesson, 'A:L07P');
      expect(di8.lessons[0].room, 'A:C003');

      expect(di8.lessons[1].teacher, 'B:SYEP');
      expect(di8.lessons[1].substituteTeacher, 'B:KREP');
      expect(di8.lessons[1].lesson, 'B:L07P');
      expect(di8.lessons[1].room, 'B:C008');
      expect(di8.lessons[1].isSubstitution, isTrue);
    });
  });
}

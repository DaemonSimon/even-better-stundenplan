import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:better_stundenplan/services/stundenplan_parser.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  final parser = StundenplanParser();

  group('StundenplanParser', () {
    test('parses lessons from the three tables row by row', () {
      final slots = parser.parseDayTimetable(fixture('day_with_lessons.html'));

      expect(slots.length, 3);

      // Period 1: single entry
      final slot1 = slots[0];
      expect(slot1.period, 1);
      expect(slot1.lessons.single.lesson, 'Ma');
      expect(slot1.lessons.single.teacher, 'Müller');
      expect(slot1.lessons.single.room, '101');

      // Period 2: bold elements mark changes
      final slot2 = slots[1];
      expect(slot2.lessons.single.lesson, 'De');
      expect(slot2.lessons.single.teacher, 'Schmidt');
      expect(slot2.lessons.single.room, '102');

      // Period 3: two lessons in one slot, including class marker in []
      final slot3 = slots[2];
      expect(slot3.lessons.length, 2);
      expect(slot3.lessons[0].lesson, 'En');
      expect(slot3.lessons[0].teacher, 'Müller');
      expect(slot3.lessons[0].room, '201');
      expect(slot3.lessons[1].lesson, 'PO [Kl. 10]');
      expect(slot3.lessons[1].teacher, 'Weber');
      expect(slot3.lessons[1].room, '202');

      // Period 4 with "-" only is skipped entirely
      expect(slots.any((s) => s.period == 4), isFalse);
    });

    test('parses empty day with tables but no rows', () {
      final slots = parser.parseDayTimetable(fixture('day_empty.html'));
      expect(slots, isEmpty);
    });

    test('handles br variants, entities and "+ " prefixes', () {
      final slots = parser.parseDayTimetable(
        fixture('day_br_variants_and_entities.html'),
      );

      expect(slots.length, 3);

      final slot1 = slots[0];
      expect(slot1.lessons.length, 2);
      expect(slot1.lessons[0].lesson, 'Ma');
      expect(slot1.lessons[0].teacher, 'Müller & Co');
      expect(slot1.lessons[0].room, '101');
      expect(slot1.lessons[1].lesson, 'En');
      expect(slot1.lessons[1].teacher, 'Weber');
      expect(slot1.lessons[1].room, '102');

      // &nbsp; is decoded, trailing <br/> ignored
      final slot2 = slots[1];
      expect(slot2.lessons.single.teacher, 'Frei Tag');

      // "+ " prefix is stripped
      final slot3 = slots[2];
      expect(slot3.lessons.single.teacher, 'Vertretung');
    });

    test('returns empty list for pages without tables', () {
      final slots = parser.parseDayTimetable(
        fixture('page_without_structure.html'),
      );
      expect(slots, isEmpty);
    });

    test('detects timetable structure', () {
      expect(
        parser.hasTimetableStructure(fixture('day_with_lessons.html')),
        isTrue,
      );
      expect(parser.hasTimetableStructure(fixture('day_empty.html')), isTrue);
      expect(
        parser.hasTimetableStructure(fixture('page_without_structure.html')),
        isFalse,
      );
    });

    test('detects the login page', () {
      expect(parser.isLoginPage(fixture('login_page.html')), isTrue);
      expect(parser.isLoginPage(fixture('day_with_lessons.html')), isFalse);
    });
  });
}

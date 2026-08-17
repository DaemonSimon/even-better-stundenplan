import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/models/timetable.dart';

void main() {
  const ma1 = LessonEntry(lesson: 'Ma', teacher: 'Müller', room: '101');
  const ma2 = LessonEntry(lesson: 'Ma', teacher: 'Müller', room: '101');
  const de = LessonEntry(lesson: 'De', teacher: 'Schmidt', room: '102');
  const en = LessonEntry(lesson: 'En', teacher: 'Weber', room: '201');
  const po = LessonEntry(lesson: 'PO', teacher: 'Müller', room: '202');

  group('sameLesson', () {
    test('identifies identical double-hour entries', () {
      expect(sameLesson(ma1, ma2), isTrue);
      expect(sameLesson(ma1, de), isFalse);
      expect(sameLesson(en, po), isFalse);
    });
  });

  group('sameLessonList', () {
    test('compares full parallel-course rows', () {
      expect(sameLessonList([en, po], [en, po]), isTrue);
      expect(sameLessonList([en, po], [po, en]), isFalse);
      expect(sameLessonList([en, po], [en]), isFalse);
    });
  });

  group('collapseConsecutiveSlots', () {
    test('collapses an identical double hour into one slot', () {
      final result = collapseConsecutiveSlots([
        [ma1],
        [ma2],
      ]);
      expect(result.length, 1);
      expect(result.first.first.lesson, 'Ma');
    });

    test('collapses a repeated parallel-course row into one slot', () {
      final result = collapseConsecutiveSlots([
        [en, po],
        [en, po],
      ]);
      expect(result.length, 1);
      expect(result.first.length, 2);
    });

    test('keeps consecutive different lessons separate', () {
      final result = collapseConsecutiveSlots([
        [ma1],
        [de],
      ]);
      expect(result.length, 2);
    });
  });
}
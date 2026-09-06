import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/models/timetable.dart';

void main() {
  const ma1 = LessonEntry(lesson: 'Ma', teacher: 'Müller', room: '101');
  const ma2 = LessonEntry(lesson: 'Ma', teacher: 'Müller', room: '101');
  const de = LessonEntry(lesson: 'De', teacher: 'Schmidt', room: '102');
  const en = LessonEntry(lesson: 'En', teacher: 'Weber', room: '201');
  const po = LessonEntry(lesson: 'PO', teacher: 'Müller', room: '202');

  group('LessonEntry', () {
    test('isSubstitution is false without a substitute teacher', () {
      expect(ma1.isSubstitution, isFalse);
    });

    test('isSubstitution is true when a substitute teacher is present', () {
      const substitute = LessonEntry(
        lesson: 'Ma',
        teacher: 'Müller',
        room: '101',
        substituteTeacher: 'Weber',
      );
      expect(substitute.isSubstitution, isTrue);
    });

    test('JSON round-trip preserves the substitute teacher', () {
      const substitute = LessonEntry(
        lesson: 'Ma',
        teacher: 'Müller',
        room: '101',
        substituteTeacher: 'Weber',
      );
      final roundTripped = LessonEntry.fromJson(substitute.toJson());
      expect(roundTripped.substituteTeacher, 'Weber');
      expect(roundTripped.lesson, 'Ma');
      expect(roundTripped.teacher, 'Müller');
      expect(roundTripped.room, '101');
    });

    test('JSON without substituteTeacher yields null', () {
      final entry = LessonEntry.fromJson(const {'a': 1});
      expect(entry.substituteTeacher, isNull);
      expect(entry.isSubstitution, isFalse);
    });
  });

  group('sameLesson', () {
    test('ignores the substitute teacher when comparing', () {
      const withSubstitute = LessonEntry(
        lesson: 'Ma',
        teacher: 'Müller',
        room: '101',
        substituteTeacher: 'Weber',
      );
      expect(sameLesson(ma1, withSubstitute), isFalse);
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
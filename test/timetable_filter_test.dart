import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/services/timetable_filter.dart';

void main() {
  group('TimetableFilter', () {
    const ungrouped = RawLessonData(
      subject: 'Ma',
      teacher: 'Müller',
      room: '101',
    );
    const groupA = RawLessonData(
      subject: 'En',
      teacher: 'A:KREP',
      room: 'A:101',
      classMarkers: ['A:L07P'],
    );
    const groupB = RawLessonData(
      subject: 'En',
      teacher: 'B:SYEP',
      room: 'B:102',
      classMarkers: ['B:L07P'],
    );
    const klasse10b = RawLessonData(
      subject: 'PO',
      teacher: 'Weber',
      room: '202',
      classMarkers: ['Kl. 10b'],
    );
    const klasse10a = RawLessonData(
      subject: 'PO',
      teacher: 'Müller',
      room: '203',
      classMarkers: ['Kl. 10a'],
    );

    test('keeps everything without a configured profile', () {
      const filter = TimetableFilter();
      expect(filter.include(ungrouped), isTrue);
      expect(filter.include(groupA), isTrue);
      expect(filter.include(groupB), isTrue);
    });

    test('keeps only the users group plus ungrouped courses', () {
      const filter = TimetableFilter(UserTimetableProfile(groupPrefix: 'A'));

      expect(filter.include(ungrouped), isTrue);
      expect(filter.include(groupA), isTrue);
      expect(filter.include(groupB), isFalse);
    });

    test('group comparison is case-insensitive', () {
      const filter = TimetableFilter(UserTimetableProfile(groupPrefix: 'a'));

      expect(filter.include(groupA), isTrue);
    });

    test('keeps only allowed class markers plus unmarked courses', () {
      const filter = TimetableFilter(
        UserTimetableProfile(classMarkers: {'Kl. 10b'}),
      );

      expect(filter.include(ungrouped), isTrue);
      expect(filter.include(klasse10b), isTrue);
      expect(filter.include(klasse10a), isFalse);
    });

    test('subject allowlist filters other subjects', () {
      const filter = TimetableFilter(
        UserTimetableProfile(subjects: {'en'}),
      );

      expect(filter.include(groupA), isTrue);
      expect(filter.include(ungrouped), isFalse);
    });

    test('profile is serializable', () {
      const profile = UserTimetableProfile(
        groupPrefix: 'A',
        classMarkers: {'Kl. 10b'},
        subjects: {'en', 'ma'},
      );

      final restored = UserTimetableProfile.fromJson(profile.toJson());

      expect(restored.groupPrefix, 'A');
      expect(restored.classMarkers, {'Kl. 10b'});
      expect(restored.subjects, {'en', 'ma'});
      expect(restored.isConfigured, isTrue);
    });
  });
}
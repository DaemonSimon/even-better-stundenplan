class LessonEntry {
  final String lesson;
  final String teacher;
  final String room;

  const LessonEntry({
    required this.lesson,
    required this.teacher,
    required this.room,
  });

  factory LessonEntry.fromJson(Map<String, dynamic> json) => LessonEntry(
    lesson: json['lesson'] as String? ?? ' ',
    teacher: json['teacher'] as String? ?? ' ',
    room: json['room'] as String? ?? ' ',
  );

  Map<String, dynamic> toJson() =>
      {'lesson': lesson, 'teacher': teacher, 'room': room};

  bool get isEmpty =>
      lesson.trim().isEmpty && teacher.trim().isEmpty && room.trim().isEmpty;

  @override
  String toString() =>
      'LessonEntry(lesson: $lesson, teacher: $teacher, room: $room)';
}

bool sameLesson(LessonEntry a, LessonEntry b) =>
    a.lesson == b.lesson && a.teacher == b.teacher && a.room == b.room;

/// Zwei Listen sind identisch, wenn jedes Element paarweise gleich ist.
bool sameLessonList(List<LessonEntry> a, List<LessonEntry> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (!sameLesson(a[i], b[i])) return false;
  }
  return true;
}

/// Fasst direkt aufeinanderfolgende identische Stunden zusammen, damit eine
/// Doppelstunde als EIN Unterricht angezeigt wird.
List<List<LessonEntry>> collapseConsecutiveSlots(
  List<List<LessonEntry>> slots,
) {
  final result = <List<LessonEntry>>[];
  for (final slot in slots) {
    if (result.isEmpty || !sameLessonList(result.last, slot)) {
      result.add(slot);
    }
  }
  return result;
}

class TimeSlot {
  final int period;
  final List<LessonEntry> lessons;

  const TimeSlot({required this.period, required this.lessons});

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    final rawLessons = json['lessons'] as List<dynamic>? ?? [];
    return TimeSlot(
      period: json['period'] as int? ?? 0,
      lessons: rawLessons
          .map((e) => LessonEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'period': period,
    'lessons': lessons.map((e) => e.toJson()).toList(),
  };

  @override
  String toString() => 'TimeSlot(period: $period, lessons: $lessons)';
}

class DailyTimetable {
  final DateTime date;
  final List<TimeSlot> timeSlots;

  const DailyTimetable({required this.date, required this.timeSlots});

  factory DailyTimetable.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['timeSlots'] as List<dynamic>? ?? [];
    return DailyTimetable(
      date: DateTime.parse(json['date'] as String),
      timeSlots: rawSlots
          .map((e) => TimeSlot.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'timeSlots': timeSlots.map((e) => e.toJson()).toList(),
  };

  bool get isEmpty => timeSlots.isEmpty;

  @override
  String toString() =>
      'DailyTimetable(date: $date, slots: ${timeSlots.length})';
}

class WeeklyTimetable {
  final DateTime weekStart;
  final List<DailyTimetable> days;

  const WeeklyTimetable({required this.weekStart, required this.days});

  @override
  String toString() =>
      'WeeklyTimetable(weekStart: $weekStart, days: ${days.length})';
}
class LessonEntry {
  final String lesson;
  final String teacher;
  final String room;

  /// Vertretungslehrkraft (z. B. aus einer durchgestrichenen Zelle mit
  /// `+ Vertreter`); `null` = normale Stunde ohne Vertretung.
  final String? substituteTeacher;

  /// Stundennummer (1-basiert), zu der dieser Eintrag gehört.
  final int period;

  const LessonEntry({
    required this.lesson,
    required this.teacher,
    required this.room,
    this.substituteTeacher,
    this.period = 0,
  });

  factory LessonEntry.fromJson(Map<String, dynamic> json) => LessonEntry(
    lesson: json['lesson'] as String? ?? ' ',
    teacher: json['teacher'] as String? ?? ' ',
    room: json['room'] as String? ?? ' ',
    substituteTeacher: json['substituteTeacher'] as String?,
    period: json['period'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'lesson': lesson,
    'teacher': teacher,
    'room': room,
    'substituteTeacher': substituteTeacher,
    'period': period,
  };

  /// Ist diese Stunde eine Vertretung (eine Vertretungslehrkraft vorhanden)?
  bool get isSubstitution =>
      substituteTeacher != null && substituteTeacher!.trim().isNotEmpty;

  bool get isEmpty =>
      lesson.trim().isEmpty && teacher.trim().isEmpty && room.trim().isEmpty;

  @override
  String toString() =>
      'LessonEntry(lesson: $lesson, teacher: $teacher, room: $room, '
      'substituteTeacher: $substituteTeacher)';
}

bool sameLesson(LessonEntry a, LessonEntry b) =>
    a.lesson == b.lesson &&
    a.teacher == b.teacher &&
    a.room == b.room &&
    a.substituteTeacher == b.substituteTeacher;

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

/// Gruppen-Präfix eines Eintrags (z. B. "A" aus "A:L07P" / "A:KREP") oder
/// null, wenn keiner vorhanden ist.
String? groupPrefixOf(String value) {
  final colon = value.indexOf(':');
  if (colon <= 0) return null;
  final prefix = value.substring(0, colon).trim();
  if (RegExp(r'^[A-Za-z]$').hasMatch(prefix)) return prefix.toUpperCase();
  return null;
}

/// Entfernt ein Gruppen-Präfix ("A:"/"B:") aus einem Wert, falls vorhanden.
String stripGroupPrefix(String value) {
  final colon = value.indexOf(':');
  if (colon > 0) {
    final prefix = value.substring(0, colon).trim();
    if (RegExp(r'^[A-Za-z]$').hasMatch(prefix)) {
      return value.substring(colon + 1).trim();
    }
  }
  return value;
}

/// Eine zusammengefasste Unterrichts-Einheit (Einzel- oder Doppelstunde).
///
/// Doppelstunden werden anhand von Fach + Gruppe zusammengeführt, nicht
/// anhand strikt identischer Einträge – so bleibt eine Stunde, in der nur
/// eine der beiden Stunden vertreten ist, EINE Karte (Card 3).
class LessonBlock {
  const LessonBlock({
    required this.subject,
    required this.room,
    required this.periods,
    this.group,
  });

  /// Fach, ohne Gruppen-Präfix (z. B. "L07P" statt "A:L07P").
  final String subject;

  final String room;

  /// Kursgruppe des Nutzers (z. B. "A") oder null bei ungruppierten Kursen.
  final String? group;

  /// Eine Stunde je Perioden-Schritt; bei Vertretungen trägt jeder Eintrag
  /// seinen eigenen [LessonEntry.substituteTeacher].
  final List<LessonEntry> periods;

  /// Erste Stunde der Einheit (z. B. 7 bei "7+8").
  int get firstPeriod => periods.isEmpty ? 0 : periods.first.period;

  bool get hasSubstitution => periods.any((p) => p.isSubstitution);

  /// Voll-Vertretung: alle Stunden der Einheit sind vertreten.
  bool get isFullSubstitution =>
      periods.isNotEmpty && periods.every((p) => p.isSubstitution);

  /// Partielle Vertretung: mindestens eine, aber nicht alle Stunden vertreten.
  bool get isPartialSubstitution => hasSubstitution && !isFullSubstitution;
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
import '../models/timetable.dart';

/// Rohdaten eines Eintrags aus dem generellen Plan (page-5), bevor sie
/// in ein [LessonEntry] überführt werden.
class RawLessonData {
  const RawLessonData({
    required this.subject,
    required this.teacher,
    required this.room,
    this.classMarkers = const [],
  });

  final String subject;
  final String teacher;
  final String room;

  /// Klassen-/Stufen-Kennungen des Kurses, z. B. "Kl. 10" oder "A:L07P".
  final List<String> classMarkers;

  bool get isEmpty =>
      subject.trim().isEmpty &&
      teacher.trim().isEmpty &&
      room.trim().isEmpty &&
      classMarkers.isEmpty;
}

/// Profil eines Nutzers, mit dem die Filter-Logik bestimmt, welche Kurse
/// des generellen Plans für ihn relevant sind.
class UserTimetableProfile {
  const UserTimetableProfile({
    this.groupPrefix,
    this.classMarkers = const {},
    this.subjects = const {},
  });

  /// Kursgruppe des Nutzers (z. B. "A"), erkannt an Präfixen wie "A:KREP".
  final String? groupPrefix;

  /// Erlaubte Klassen-/Stufen-Kennungen (z. B. {"Kl. 10b"}).
  final Set<String> classMarkers;

  /// Weiße Liste von Fächern (normalisiert, z. B. {"ma", "en"}).
  final Set<String> subjects;

  bool get isConfigured =>
      groupPrefix != null ||
      classMarkers.isNotEmpty ||
      subjects.isNotEmpty;

  Map<String, dynamic> toJson() => {
    if (groupPrefix != null) 'groupPrefix': groupPrefix,
    'classMarkers': classMarkers.toList()..sort(),
    'subjects': subjects.toList()..sort(),
  };

  factory UserTimetableProfile.fromJson(Map<String, dynamic> json) {
    List<String> toStringList(dynamic value) =>
        (value as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
    return UserTimetableProfile(
      groupPrefix: json['groupPrefix'] as String?,
      classMarkers: toStringList(json['classMarkers']).toSet(),
      subjects: toStringList(json['subjects']).toSet(),
    );
  }
}

/// Filtert die Kurse des generellen Plans auf die des Nutzers.
/// Ohne konfiguriertes Profil werden alle Kurse behalten – die Klasse wird
/// auf page-5 bereits serverseitig zur Sitzung ausgewählt.
class TimetableFilter {
  const TimetableFilter([this.profile = const UserTimetableProfile()]);

  final UserTimetableProfile profile;

  bool include(RawLessonData lesson) {
    if (profile.isConfigured == false || lesson.isEmpty) return true;

    if (profile.subjects.isNotEmpty) {
      final subject = _normalize(lesson.subject);
      if (!profile.subjects.contains(subject)) return false;
    }

    if (profile.classMarkers.isNotEmpty && lesson.classMarkers.isNotEmpty) {
      final lessonMarkers = lesson.classMarkers.map(_normalize).toSet();
      final allowedMarkers = profile.classMarkers.map(_normalize);
      if (!lessonMarkers.any(allowedMarkers.contains)) return false;
    }

    final group = _groupPrefix(lesson);
    if (profile.groupPrefix != null && group != null) {
      if (group != profile.groupPrefix!.toUpperCase()) return false;
    }

    return true;
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String? _groupPrefix(RawLessonData lesson) {
    for (final token in [
      lesson.teacher,
      lesson.room,
      ...lesson.classMarkers,
    ]) {
      final colon = token.indexOf(':');
      if (colon <= 0) continue;
      final prefix = token.substring(0, colon).trim();
      if (RegExp(r'^[A-Za-z]$').hasMatch(prefix)) {
        return prefix.toUpperCase();
      }
    }
    return null;
  }
}
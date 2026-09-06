import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../pages/homework_list_page.dart';
import '../routes.dart';
import '../services/teacher_directory.dart';
import '../utils/block_schedule.dart';
import '../utils/room_info.dart';
import '../utils/teacher_photo.dart';
import 'class_card.dart';

/// Öffnet die Detail-Modal (Bottom Sheet) für eine Unterrichtsstunde
/// aus Tagesansicht oder Wochenmatrix.
void showLessonDetailModal(
  BuildContext context, {
  required DailyTimetable day,
  required int block,
  required List<LessonEntry> lessons,
  BlockTime? time,
  List<int>? periods,
  TeacherLookup? teacherLookup,
  String? sessionId,
  bool stripGroup = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: cardBackground,
    builder: (sheetContext) {
      return _LessonDetailSheet(
        day: day,
        block: block,
        periods: periods ?? [block],
        time:
            time ??
            BlockSchedule.timeFor(block) ??
            BlockSchedule.fallbackTimeFor(block),
        lessons: lessons,
        teacherLookup: teacherLookup,
        sessionId: sessionId,
        stripGroup: stripGroup,
        onEditAlias: () {
          final lesson = lessons.first;
          Navigator.of(sheetContext).pop();
          final route = DetailsRoute(
            lesson: lesson.lesson.trim(),
            teacher: lesson.teacher.trim(),
            room: lesson.room.trim(),
            date: DateFormat('dd.MM.yyyy').format(day.date),
            hour: '$block',
          );
          context.push(route.location);
        },
      );
    },
  );
}

class _LessonDetailSheet extends StatelessWidget {
  const _LessonDetailSheet({
    required this.day,
    required this.block,
    required this.periods,
    required this.time,
    required this.lessons,
    required this.onEditAlias,
    this.teacherLookup,
    this.sessionId,
    this.stripGroup = false,
  });

  final DailyTimetable day;
  final int block;
  final List<int> periods;
  final BlockTime time;
  final List<LessonEntry> lessons;
  final VoidCallback onEditAlias;
  final TeacherLookup? teacherLookup;
  final String? sessionId;

  /// Gruppen-Präfixe ("A:"/"B:") aus Lehrkraft-Anzeigen entfernen (Regel 5).
  final bool stripGroup;

  static String _format(TimeOfDay time) =>
      DateFormat('HH:mm').format(DateTime(0, 1, 1, time.hour, time.minute));

  String get _timeText => '${_format(time.start)} – ${_format(time.end)}';

  /// Stunden-Label: "1.+2. Stunde" bei Doppelstunden, sonst "3. Stunde".
  String get _periodLabel => periods.length > 1
      ? '${periods.first}.+${periods.last}. Stunde'
      : '${periods.first}. Stunde';

  String get _summary {
    return lessons
        .map((lesson) {
          final teachers = lesson.isSubstitution
              ? '${lesson.substituteTeacher?.trim()} statt ${lesson.teacher.trim()}'
              : lesson.teacher.trim();
          return '${lesson.lesson.trim()} · $teachers · '
              '${lesson.room.trim()} · $_periodLabel · $_timeText';
        })
        .join('\n');
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _summary));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Kopiert')));
  }

  void _openHomework(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HomeworkListPage(
          subject: lessons.first.lesson.trim(),
          sessionId: sessionId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lesson = lessons.first;
    final dayName = DateFormat('EEEE, dd.MM.yyyy').format(day.date);
    final subjectText = lesson.lesson.trim().isEmpty
        ? '—'
        : (stripGroup ? stripGroupPrefix(lesson.lesson).trim() : lesson.lesson.trim());

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    subjectText,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _periodLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dayName · $_timeText',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cardGrey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final lesson in lessons)
              _LessonInfo(
                lesson: lesson,
                teacherLookup: teacherLookup,
                stripGroup: stripGroup,
              ),
            const SizedBox(height: 8),
            Divider(color: scheme.outlineVariant),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Kopieren'),
                ),
                TextButton.icon(
                  onPressed: sessionId != null && sessionId!.isNotEmpty
                      ? () => _openHomework(context)
                      : null,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Hausaufgaben ansehen'),
                ),
                TextButton.icon(
                  onPressed: onEditAlias,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Alias bearbeiten'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Zeile mit Lehrkraft- bzw. Raum-Information (mit Icon).
///
/// Die Lehrkraft wird über [teacherLookup] zum vollen Namen aufgelöst
/// (Kürzel in Klammern); die E-Mail-Adresse aus dem Kollegium wird
/// angezeigt und per Tap kopiert. Bei einer Vertretung stehen links die
/// Vertretungslehrkraft (rot) und rechts der eigentliche Lehrer (durch-
/// gestrichen) – beide per Tap auf ihr Portrait-Foto klickbar.
class _LessonInfo extends StatelessWidget {
  const _LessonInfo({
    required this.lesson,
    this.teacherLookup,
    this.stripGroup = false,
  });

  final LessonEntry lesson;
  final TeacherLookup? teacherLookup;

  /// Gruppen-Präfixe aus den Lehrkraft-Anzeigen entfernen (Regel 5).
  final bool stripGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: cardGrey);

    final teacher = lesson.teacher.trim();
    final room = lesson.room.trim();

    final rows = <Widget>[];

    if (lesson.isSubstitution) {
      final substitute = (lesson.substituteTeacher ?? '').trim();
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TeacherLine(
                name: _displayFor(substitute),
                photoTap: _photoTap(context, substitute),
                color: substituteRed,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _TeacherLine(
                name: _displayFor(teacher),
                photoTap: _photoTap(context, teacher),
                strikethrough: true,
              ),
            ),
          ],
        ),
      );
    } else if (teacher.isNotEmpty) {
      rows.add(
        Align(
          alignment: Alignment.centerLeft,
          child: _TeacherLine(
            name: _displayFor(teacher),
            photoTap: _photoTap(context, teacher),
          ),
        ),
      );
    }

    if (teacher.isNotEmpty && room.isNotEmpty) {
      rows.add(const SizedBox(height: 8));
    }
    if (room.isNotEmpty) {
      rows.add(
        InkWell(
          onTap: () => showRoomInfoDialog(context, room),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Row(
              children: [
                Icon(
                  Icons.meeting_room,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(room, style: muted)),
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  /// Anzeigename der Lehrkraft: voller Name, geprefixtes Kürzel bleibt
  /// ("A: Helga Müller (KREP)"). Bei [stripGroup] wird das Präfix entfernt
  /// ("Helga Müller (KREP)"). Ohne Treffer das rohe Kürzel.
  String _displayFor(String raw) {
    if (raw.isEmpty) return raw;
    final split = splitTeacherPrefix(raw);
    final entry = teacherLookup?.call(split.kuerzel);
    final resolved = entry?.fullName ?? split.kuerzel;
    if (entry == null || resolved == split.kuerzel) {
      return split.prefix != null && stripGroup
          ? stripGroupPrefix(raw)
          : raw;
    }
    return split.prefix != null && stripGroup
        ? '$resolved (${split.kuerzel})'
        : split.prefix == null
            ? '$resolved ($raw)'
            : '${split.prefix}: $resolved (${split.kuerzel})';
  }

  /// Öffnet das Portrait-Foto zur Lehrkraft, falls ein Foto existiert.
  VoidCallback? _photoTap(BuildContext context, String raw) {
    if (raw.isEmpty) return null;
    final split = splitTeacherPrefix(raw);
    final entry = teacherLookup?.call(split.kuerzel);
    final photoUrl = entry?.photoUrl;
    if (photoUrl == null) return null;
    return () => showTeacherPhotoDialog(context, _displayFor(raw), photoUrl);
  }
}

/// Eine Lehrkraft-Zeile: Icon, Name – bei Vertretung rot und/oder durch-
/// gestrichen (Original), per Tap das Portrait-Foto (falls vorhanden).
class _TeacherLine extends StatelessWidget {
  const _TeacherLine({
    required this.name,
    this.photoTap,
    this.color,
    this.strikethrough = false,
  });

  final String name;
  final VoidCallback? photoTap;
  final Color? color;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final baseColor = color ?? cardGrey;

    return InkWell(
      onTap: photoTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          children: [
            Icon(Icons.person, size: 18, color: baseColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: baseColor,
                  decoration: strikethrough ? TextDecoration.lineThrough : null,
                  decorationThickness: strikethrough ? 1.2 : null,
                  decorationColor: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (photoTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.badge_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

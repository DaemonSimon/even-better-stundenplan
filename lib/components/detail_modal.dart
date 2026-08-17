import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../routes.dart';
import '../services/teacher_directory.dart';
import '../utils/block_schedule.dart';
import '../utils/room_info.dart';
import '../utils/subject_colors.dart';

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
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return _LessonDetailSheet(
        day: day,
        block: block,
        periods: periods ?? [block],
        time: time ?? BlockSchedule.timeFor(block) ?? BlockSchedule.fallbackTimeFor(block),
        lessons: lessons,
        teacherLookup: teacherLookup,
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
  });

  final DailyTimetable day;
  final int block;
  final List<int> periods;
  final BlockTime time;
  final List<LessonEntry> lessons;
  final VoidCallback onEditAlias;
  final TeacherLookup? teacherLookup;

  static String _format(TimeOfDay time) =>
      DateFormat('HH:mm').format(DateTime(0, 1, 1, time.hour, time.minute));

  String get _timeText => '${_format(time.start)} – ${_format(time.end)}';

  /// Stunden-Label: "1.+2. Stunde" bei Doppelstunden, sonst "3. Stunde".
  String get _periodLabel => periods.length > 1
      ? '${periods.first}.+${periods.last}. Stunde'
      : '${periods.first}. Stunde';

  String get _summary {
    return lessons
        .map(
          (lesson) =>
              '${lesson.lesson.trim()} · ${lesson.teacher.trim()} · '
              '${lesson.room.trim()} · $_periodLabel · $_timeText',
        )
        .join('\n');
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _summary));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kopiert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lesson = lessons.first;
    final dayName = DateFormat('EEEE, dd.MM.yyyy').format(day.date);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: SubjectColors.pastelBackgroundFor(
                      lesson.lesson,
                      scheme,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    lesson.lesson.trim().isEmpty ? '—' : lesson.lesson.trim(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _periodLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dayName · $_timeText',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final lesson in lessons)
              _LessonInfo(
                lesson: lesson,
                teacherLookup: teacherLookup,
              ),
            const SizedBox(height: 8),
            Divider(color: scheme.outlineVariant),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Kopieren'),
                ),
                const Spacer(),
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
/// angezeigt und per Tap kopiert.
class _LessonInfo extends StatelessWidget {
  const _LessonInfo({required this.lesson, this.teacherLookup});

  final LessonEntry lesson;
  final TeacherLookup? teacherLookup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurface,
    );

    final teacher = lesson.teacher.trim();
    final room = lesson.room.trim();
    final split = splitTeacherPrefix(teacher);
    final entry = teacherLookup?.call(split.kuerzel);
    final photoUrl = entry?.photoUrl;

    final teacherDisplay = entry != null && entry.fullName != split.kuerzel
        ? split.prefix == null
            ? '${entry.fullName} ($teacher)'
            : '${split.prefix}: ${entry.fullName} (${split.kuerzel})'
        : teacher;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (teacher.isNotEmpty)
            InkWell(
              onTap: photoUrl == null
                  ? null
                  : () => _showTeacherPhoto(context, teacherDisplay, photoUrl),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.person, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(teacherDisplay, style: muted),
                    ),
                    if (photoUrl != null) ...[
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
            ),
          if (teacher.isNotEmpty && room.isNotEmpty)
            const SizedBox(height: 8),
          if (room.isNotEmpty)
            InkWell(
              onTap: () => showRoomInfoDialog(context, room),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
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
        ],
      ),
    );
  }

  /// Zeigt das Portrait-Foto der Lehrkraft in einem Dialog.
  void _showTeacherPhoto(
    BuildContext context,
    String teacherDisplay,
    String photoUrl,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  photoUrl,
                  width: 240,
                  height: 240,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => SizedBox(
                    width: 240,
                    height: 240,
                    child: Icon(
                      Icons.person_off,
                      size: 64,
                      color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                teacherDisplay,
                style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
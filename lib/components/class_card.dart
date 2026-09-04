import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../utils/block_schedule.dart';
import '../utils/dashed_border.dart';
import '../utils/room_info.dart';
import '../utils/subject_colors.dart';

String _formatTime(TimeOfDay time) =>
    DateFormat('HH:mm').format(DateTime(0, 1, 1, time.hour, time.minute));

/// Amber-Farbe des "Urgency"-Zustands (Balken links an der Karte).
const Color _urgencyAmber = Color(0xFFFFA000);

/// Textfarbe im Urgency-Badge: dunkel für hohen Kontrast.
const Color _urgencyText = Color(0xDE000000);

/// Countdown-Badge für Klassen, die gleich beginnen: "Beginnt in Xm".
/// Überlappt die Kartenoberkante (halb innen, halb außen).
class UrgencyBadge extends StatelessWidget {
  const UrgencyBadge({super.key, required this.remainingMinutes});

  final int remainingMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _urgencyAmber,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_run, size: 12, color: _urgencyText),
          const SizedBox(width: 4),
          Text(
            'Beginnt in ${remainingMinutes}m',
            style: const TextStyle(
              color: _urgencyText,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Karte für eine einzelne Unterrichtsstunde im Tages-Agenda.
///
/// Im Live-Zustand (Unterricht läuft gerade) bekommt die Karte einen
/// primären Rahmen und einen Schatten.
class ClassCard extends StatelessWidget {
  const ClassCard({
    super.key,
    required this.lesson,
    required this.block,
    required this.blockTime,
    this.teacherLabel,
    this.isLive = false,
    this.isUrgent = false,
    this.onTap,
  });

  final LessonEntry lesson;
  final int block;
  final BlockTime blockTime;

  /// Anzeigename der Lehrkraft (z. B. voller Name statt Kürzel);
  /// fällt auf [LessonEntry.teacher] zurück.
  final String? teacherLabel;

  final bool isLive;

  /// Stunde beginnt gleich: dezenter Amber-Balken links statt Glow.
  final bool isUrgent;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final lessonText = lesson.lesson.trim();
    final teacherText = (teacherLabel ?? lesson.teacher).trim();
    final roomText = lesson.room.trim();

    final border = isLive
        ? Border.all(color: scheme.primary, width: 1.5)
        : isUrgent
        ? const Border(left: BorderSide(color: _urgencyAmber, width: 4))
        : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        color: SubjectColors.pastelBackgroundFor(lesson.lesson, scheme),
        border: border,
        boxShadow: isLive
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lessonText.isEmpty ? '—' : lessonText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (teacherText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          teacherText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                      if (roomText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => showRoomInfoDialog(context, roomText),
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  roomText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.8,
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.info_outline,
                                size: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Karte für eine freie Stunde: gestrichelter Rahmen, bewusst leer.
/// Füllt die ihr zugewiesene Zeilenhöhe aus (kein eigener Height-Wert).
class FreePeriodCard extends StatelessWidget {
  const FreePeriodCard({super.key, required this.blockTime});

  final BlockTime blockTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DashedBorder(
      radius: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.self_improvement,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Freie Stunde',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text(
            '${_formatTime(blockTime.start)} – ${_formatTime(blockTime.end)}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontaler Trenner für die Mittagspause (13:15 – 13:45).
///
/// Während die Pause läuft, zeigt ein kleines Countdown-Pill an, wann
/// sie endet – kein Aufleuchten des Trenners, die Information zählt.
class LunchDivider extends StatelessWidget {
  const LunchDivider({super.key, this.countdownMinutes});

  /// Läuft die Mittagspause gerade? Dann erscheint neben dem Text ein
  /// "Endet in Xm"-Countdown (null = kein Countdown).
  final int? countdownMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Standard-Zustand: dezent, Text mit deckendem Hintergrund, damit
    // die rote Jetzt-Linie unter ihm verschwindet (kein hässliches
    // Kreuz, wenn sie den Trenner kreuzt). Center hält den Trenner
    // vertikal zentriert, wenn die Zeile zur Füllung des Screens
    // gestreckt wird.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Row(
          children: [
            const Expanded(child: Divider()),
            Container(
              color: scheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.restaurant,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Mittagspause 13:15 – 13:45',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (countdownMinutes != null) ...[
                    const SizedBox(width: 8),
                    _LunchCountdownPill(minutes: countdownMinutes!),
                  ],
                ],
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
      ),
    );
  }
}

/// Countdown-Pill während der Mittagspause: "Endet in Xm".
class _LunchCountdownPill extends StatelessWidget {
  const _LunchCountdownPill({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _urgencyAmber,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 12, color: _urgencyText),
          const SizedBox(width: 4),
          Text(
            'Endet in ${minutes}m',
            style: const TextStyle(
              color: _urgencyText,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../services/teacher_directory.dart';
import '../utils/block_schedule.dart';
import '../utils/dashed_border.dart';

/// App-Hintergrund (Regel 1).
const Color appBackground = Color(0xFF1C1C22);

/// Karten-Hintergrund (Regel 1).
const Color cardBackground = Color(0xFF323642);

/// Rot für die Vertretung auf der Karte.
const Color substituteRed = Color(0xFFF23838);

/// Karten-Textfarbe: Weiß für das Fach, Hellgrau für Lehrkraft/Raum,
/// abgestimmt auf den dunklen [cardBackground].
const Color _cardWhite = Color(0xFFFFFFFF);
const Color cardGrey = Color(0xFF9AA0AC);

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

/// Karte für eine Unterrichts-Einheit im Tages-Agenda.
///
/// Flaches, dunkles Design (Regel 1): [cardBackground], 16px Radius,
/// 16px Innenabstand, keine Rahmen, keine Schatten. Je nach Block-Typ
/// wird die passende Kartenstruktur (Regel 3) gezeichnet.
class ClassCard extends StatelessWidget {
  const ClassCard({
    super.key,
    required this.block,
    required this.blockTime,
    this.isLive = false,
    this.isUrgent = false,
    this.compact = false,
    this.teacherLookup,
    this.stripGroup = false,
    this.onTap,
  });

  /// Zusammenfassung der Einheit (Einzel- oder Doppelstunde) mit den
  /// Lehrkraft-Zuständen je Stunde.
  final LessonBlock block;

  final BlockTime blockTime;

  /// Gruppen-Präfixe ("A:"/"B:") aus Fach, Lehrkraft und Raum entfernen
  /// (Regel 5, nach der Gruppen-Filterung).
  final bool stripGroup;

  /// Liegt das aktuelle Zeitfenster im Unterricht? Die Karte wird dann
  /// NICHT mit einem Rahmen hervorgehoben (Regel 2), nur die rote
  /// Jetzt-Linie übernimmt die Markierung.
  final bool isLive;

  /// Stunde beginnt gleich: dezenter Amber-Balken links statt Glow.
  final bool isUrgent;

  /// Kompakte Darstellung bei vielen parallelen Kursen.
  final bool compact;

  /// Kollegiums-Nachschlagefunktion für die vollen Namen.
  final TeacherLookup? teacherLookup;

  final VoidCallback? onTap;

  /// Voller Name einer Lehrkraft (Kürzel -> Verzeichnis); ohne Treffer
  /// das rohe Kürzel. Bei [stripGroup] wird ein Gruppen-Präfix entfernt.
  String _name(String raw) {
    final lookup = teacherLookup;
    final split = splitTeacherPrefix(raw);
    final entry = lookup?.call(split.kuerzel);
    final resolved = entry?.fullName ?? split.kuerzel;
    if (!stripGroup) {
      return split.prefix == null
          ? resolved
          : '${split.prefix}: $resolved';
    }
    return resolved;
  }

  String _clean(String raw) =>
      stripGroup ? stripGroupPrefix(raw).trim() : raw.trim();

  @override
  Widget build(BuildContext context) {
    final subject = block.subject.isEmpty ? '—' : _clean(block.subject);
    final room = _clean(block.room);

    final hPadding = compact ? 10.0 : 16.0;
    final fontSize = compact ? 12.0 : 14.0;
    final subjectSize = compact ? 16.0 : 18.0;

    final rows = <Widget>[
      Padding(
        padding: EdgeInsets.fromLTRB(hPadding, 0, hPadding, 4),
        child: Text(
          subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _cardWhite,
            fontSize: subjectSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ];

    if (block.hasSubstitution && !block.isPartialSubstitution) {
      // Card 2: Voll-Vertretung, eine Zeile "[Rot Vertreter] [Grau Original]".
      final first = block.periods.first;
      final subName = _name(first.substituteTeacher ?? '');
      final oldName = _name(first.teacher);
      rows.add(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                subName.isEmpty ? '—' : subName,
                style: TextStyle(
                  color: substituteRed,
                  fontWeight: FontWeight.w600,
                  fontSize: fontSize,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                oldName.isEmpty ? '' : oldName,
                style: TextStyle(
                  color: cardGrey,
                  fontSize: fontSize,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (block.isPartialSubstitution) {
      // Card 3: Partielle Vertretung – eine Zeile je Stunde:
      // links Lehrkraft, rechts "N. Std". Vertretene Stunden in Rot.
      for (final p in block.periods) {
        final isSub = p.isSubstitution;
        final name = isSub
            ? _name(p.substituteTeacher ?? '')
            : _name(p.teacher);
        rows.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name.isEmpty ? '—' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSub ? substituteRed : cardGrey,
                      fontSize: fontSize,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${p.period}. Std',
                  style: TextStyle(
                    color: isSub ? substituteRed : cardGrey,
                    fontSize: fontSize,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      // Card 1: Normale Stunde – Lehrkraft, dann Raum.
      final teacher = block.periods.isEmpty
          ? ''
          : _name(block.periods.first.teacher);
      if (teacher.isNotEmpty) {
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(hPadding, 2, hPadding, 2),
            child: Text(
              teacher,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cardGrey, fontSize: fontSize),
            ),
          ),
        );
      }
    }

    if (room.isNotEmpty) {
      rows.add(
        Padding(
          padding: EdgeInsets.fromLTRB(hPadding, 2, hPadding, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  room,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cardGrey,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.info_outline, size: 13, color: cardGrey),
            ],
          ),
        ),
      );
    }

    final border = isUrgent
        ? const Border(left: BorderSide(color: _urgencyAmber, width: 4))
        : null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        color: cardBackground,
        border: border,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows,
              ),
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

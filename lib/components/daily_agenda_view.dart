import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../services/teacher_directory.dart';
import '../utils/block_schedule.dart';
import 'class_card.dart';
import 'detail_modal.dart';

/// Farbe der roten "Jetzt"-Linie.
const Color _nowRed = Color(0xFFE53935);

/// Tagesansicht: vertikale Timeline mit Zeit-Spalte links und
/// Unterrichtskarten rechts.
///
/// Doppelstunden sind EIN Unterricht: erscheint dieselbe Stunde in zwei
/// aufeinanderfolgenden Stunden (gleicher Block), wird sie zu einer
/// einzigen 90-Minuten-Karte zusammengefasst. Gibt es Nachmittagsunterricht
/// (7./8. Stunde), wird die Mittagspause zwischen der 6. und der 7. Stunde
/// eingezeichnet – endet der Tag mit der 6. Stunde, bleibt sie weg.
class DailyAgendaView extends StatefulWidget {
  const DailyAgendaView({
    super.key,
    required this.day,
    required this.isToday,
    this.clock,
    this.tickInterval,
    this.teacherLookup,
  });

  /// Stundenplan des angezeigten Tages (leere Liste = freier Tag).
  final DailyTimetable day;

  /// Nur für den heutigen Tag werden Live-Badges gezeigt.
  final bool isToday;

  /// Uhr-Quelle (testbar); standardmäßig [DateTime.now].
  final DateTime Function()? clock;

  /// Takt für Live-Updates; standardmäßig 30 Sekunden.
  final Duration? tickInterval;

  /// Kollegiums-Nachschlagefunktion: Kürzel -> voller Name / E-Mail.
  final TeacherLookup? teacherLookup;

  @override
  State<DailyAgendaView> createState() => _DailyAgendaViewState();
}

class _DailyAgendaViewState extends State<DailyAgendaView> {
  static const Duration _tick = Duration(seconds: 30);

  late DateTime _now;
  Timer? _timer;

  /// Keys der Tageszeilen (Segment-IDs wie "p1-2", "lunch") für die
  /// Messung der Zeilenhöhen.
  final Map<String, GlobalKey> _rowKeys = {};

  /// Gemessene Höhen der Zeilen – Grundlage für die Position der
  /// "Jetzt"-Linie.
  Map<String, double> _rowHeights = {};

  DateTime _readClock() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _now = _readClock();
    _updateTimer();
  }

  @override
  void didUpdateWidget(DailyAgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isToday) {
      _now = _readClock();
    }
    if (oldWidget.isToday != widget.isToday ||
        oldWidget.tickInterval != widget.tickInterval) {
      _updateTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.isToday) {
      _now = _readClock();
      _timer = Timer.periodic(widget.tickInterval ?? _tick, (_) {
        if (mounted) {
          setState(() => _now = _readClock());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final slotsByPeriod = <int, TimeSlot>{
      for (final slot in widget.day.timeSlots) slot.period: slot,
    };

    if (slotsByPeriod.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text('Kein Unterricht an diesem Tag')),
      );
    }

    // Ein Schultag hat 8 Stunden; zusätzliche Stunden aus den Daten
    // werden ebenfalls angezeigt.
    var maxPeriod = 8;
    for (final period in slotsByPeriod.keys) {
      if (period > maxPeriod) maxPeriod = period;
    }

    // Letzte Stunde mit Unterricht: danach endet der Tag. Stunden NACH
    // der Mittagspause ohne Unterricht werden gar nicht mehr gezeichnet.
    var lastLessonPeriod = 0;
    for (final period in slotsByPeriod.keys) {
      if (_nonEmptyLessons(slotsByPeriod[period]!).isNotEmpty) {
        lastLessonPeriod = period;
      }
    }

    final nowMinutes = _now.hour * 60 + _now.minute;
    final lunchStartM =
        BlockSchedule.lunchStart.hour * 60 + BlockSchedule.lunchStart.minute;
    final lunchEndM =
        BlockSchedule.lunchEnd.hour * 60 + BlockSchedule.lunchEnd.minute;

    // Läuft gerade die Mittagspause? Dann verschwindet die rote Linie
    // und der Mittagspausen-Trenner wird hervorgehoben.
    final lunchActive = nowMinutes >= lunchStartM && nowMinutes < lunchEndM;

    final segments = <_DaySegment>[];
    for (int period = 1; period <= maxPeriod; period++) {
      // Mittagspause zwischen der 6. und der 7. Stunde – aber nur,
      // wenn es überhaupt Nachmittagsunterricht gibt (7./8. Stunde).
      // Endet der Tag mit der 6. Stunde, entfällt der Trenner komplett.
      if (period == 7 && lastLessonPeriod >= 7) {
        segments.add(
          _DaySegment(
            id: 'lunch',
            time: const BlockTime(
              BlockSchedule.lunchStart,
              BlockSchedule.lunchEnd,
            ),
            isBreak: true,
            child: LunchDivider(
              countdownMinutes: lunchActive ? lunchEndM - nowMinutes : null,
            ),
          ),
        );
      }

      // Nach der letzten Unterrichtsstunde endet der Tag.
      if (period > lastLessonPeriod) break;

      final block = BlockSchedule.blockForPeriod(period);
      final periods = <int>[period];

      // Doppelstunde: identischer Unterricht in zwei aufeinanderfolgenden
      // Stunden desselben Blocks -> eine gemeinsame Karte.
      final slot = slotsByPeriod[period];
      final nextSlot = slotsByPeriod[period + 1];
      if (period == BlockSchedule.firstPeriodOfBlock(block) &&
          slot != null &&
          nextSlot != null &&
          sameLessonList(
            _nonEmptyLessons(slot),
            _nonEmptyLessons(nextSlot),
          )) {
        periods.add(period + 1);
      }

      segments.add(
        _DaySegment(
          id: 'p${periods.join('-')}',
          time: _timeFor(block, periods),
          child: _buildPeriodRow(
            block: block,
            periods: periods,
            slots: slotsByPeriod,
          ),
        ),
      );
      if (periods.length > 1) {
        period++; // zusammengefasste zweite Stunde überspringen
      }
    }

    // Zeilen in ihrer natürlichen Höhe (Kartenhöhe bestimmt die Zeile).
    Widget content = Column(
      children: [
        for (final segment in segments)
          KeyedSubtree(
            key: _rowKeys.putIfAbsent(segment.id, () => GlobalKey()),
            child: segment.child,
          ),
      ],
    );

    // Rote "Jetzt"-Linie: wandert über den Tag. Sie wird nur am heutigen
    // Tag UND innerhalb der Schulzeit gezeichnet – vor der ersten bzw.
    // nach der letzten Stunde existiert sie nicht. Während der
    // Mittagspause ist sie ausgeblendet (der Trenner übernimmt die
    // Hervorhebung).
    final dayStart = segments.isEmpty
        ? 0
        : (segments.first.time?.startInMinutes ?? 0);
    final dayEnd = segments.isEmpty
        ? 0
        : (segments.last.time?.endInMinutes ?? dayStart);
    final inSchoolDay = nowMinutes >= dayStart && nowMinutes < dayEnd;

    if (widget.isToday && inSchoolDay && !lunchActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureRows(segments);
      });
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeInOut,
                    left: 0,
                    right: 0,
                    top: _linePosition(_now, segments),
                    child: _NowLine(key: const Key('now-line'), now: _now),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return content;
  }

  /// Zeitfenster einer Zeile: Doppelstunden bekommen den vollen Block,
  /// Einzelstunden ihre 45 Minuten.
  BlockTime _timeFor(int block, List<int> periods) {
    if (periods.length > 1) {
      return BlockSchedule.timeFor(block) ??
          BlockSchedule.fallbackTimeFor(block);
    }
    return BlockSchedule.periodTimeFor(periods.first) ??
        BlockSchedule.fallbackPeriodTimeFor(periods.first);
  }

  /// Misst die Höhen aller Tageszeilen (für die Position der Jetzt-Linie).
  void _measureRows(List<_DaySegment> segments) {
    final heights = <String, double>{};
    for (final segment in segments) {
      final box = _rowKeys[segment.id]
          ?.currentContext
          ?.findRenderObject() as RenderBox?;
      if (box != null) heights[segment.id] = box.size.height;
    }

    var changed = heights.length != _rowHeights.length;
    if (!changed) {
      for (final entry in heights.entries) {
        if (_rowHeights[entry.key] != entry.value) {
          changed = true;
          break;
        }
      }
    }
    if (changed && mounted) {
      setState(() => _rowHeights = heights);
    }
  }

  /// Vertikale Position der Jetzt-Linie. Das Zeitfenster einer Zeile wird
  /// auf den KARTEN-Bereich der Zeile abgebildet (ohne die senkrechten
  /// Abstände): bei exaktem Stundenbeginn sitzt die Linie auf der
  /// Oberkante der Karte, bei exaktem Ende auf deren Unterkante –
  /// dazwischen proportional zur vergangenen Zeit.
  double _linePosition(DateTime now, List<_DaySegment> segments) {
    const rowSpacing = 12.0; // senkrechte Abstände der Tageszeilen
    final minutes = now.hour * 60 + now.minute;
    var top = 0.0;
    for (final segment in segments) {
      final height = _rowHeights[segment.id] ?? 0;
      final time = segment.time;
      if (time == null) {
        top += height;
        continue;
      }
      if (minutes < time.startInMinutes) return top;
      if (minutes < time.endInMinutes) {
        // Pausen (Mittagspause): die Linie hält am oberen Rand der
        // Zeile an, statt durch sie hindurchzuwandern.
        if (segment.isBreak) return top + rowSpacing;
        final innerHeight = (height - 2 * rowSpacing).clamp(0.0, height);
        final fraction =
            (minutes - time.startInMinutes) / time.durationInMinutes;
        return top + rowSpacing + fraction * innerHeight;
      }
      top += height;
    }
    return top;
  }

  List<LessonEntry> _nonEmptyLessons(TimeSlot slot) {
    return [
      for (final lesson in slot.lessons)
        if (!lesson.isEmpty) lesson,
    ];
  }

  Widget _buildPeriodRow({
    required int block,
    required List<int> periods,
    required Map<int, TimeSlot> slots,
  }) {
    final firstPeriod = periods.first;

    final time = _timeFor(block, periods);

    final slot = slots[firstPeriod];
    final lessons = slot == null ? const <LessonEntry>[] : _nonEmptyLessons(slot);

    final isLive = lessons.isNotEmpty && BlockSchedule.isWithin(time, _now);

    // "Urgency": Die Stunde beginnt in <= 5 Minuten, hat aber noch
    // nicht angefangen -> Karte bekommt einen Amber-Balken + Countdown.
    final minutesNow = _now.hour * 60 + _now.minute;
    final urgent =
        widget.isToday &&
        lessons.isNotEmpty &&
        minutesNow >= time.startInMinutes - BlockSchedule.urgencyWindowMinutes &&
        minutesNow < time.startInMinutes;
    final urgentRemaining = time.startInMinutes - minutesNow;

    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TimeColumn(
              label: periods.join('+'),
              blockTime: time,
              isLive: isLive,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: lessons.isEmpty
                  ? FreePeriodCard(blockTime: time)
                  : Row(
                      // Karten füllen die volle Zeilenhöhe, damit die
                      // Jetzt-Linie exakt an ihren Ober-/Unterkanten
                      // anliegt (kein vertikales Zentrieren).
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < lessons.length; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                              child: Stack(
                                clipBehavior: Clip.none,
                                fit: StackFit.passthrough,
                                children: [
                                  ClassCard(
                                    lesson: lessons[i],
                                    block: block,
                                    blockTime: time,
                                    teacherLabel: _teacherLabel(
                                      lessons[i].teacher,
                                    ),
                                    isLive: isLive,
                                    isUrgent: urgent,
                                    onTap: () => _openDetails(
                                      lessons[i],
                                      block,
                                      periods,
                                      time,
                                    ),
                                  ),
                                  if (urgent)
                                    Positioned(
                                      top: -12,
                                      left: -6,
                                      child: UrgencyBadge(
                                        remainingMinutes: urgentRemaining,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetails(
    LessonEntry lesson,
    int block,
    List<int> periods,
    BlockTime time,
  ) {
    showLessonDetailModal(
      context,
      day: widget.day,
      block: block,
      periods: periods,
      time: time,
      lessons: [lesson],
      teacherLookup: widget.teacherLookup,
    );
  }

  /// Anzeigename der Lehrkraft: vollen Namen aus dem Verzeichnis, ein
  /// Präfix wie "A:KREP" bleibt dabei erhalten ("A: Helga Müller").
  String? _teacherLabel(String raw) {
    final lookup = widget.teacherLookup;
    if (lookup == null) return null;
    final split = splitTeacherPrefix(raw);
    final entry = lookup(split.kuerzel);
    if (entry == null) return null;
    return split.prefix == null
        ? entry.fullName
        : '${split.prefix}: ${entry.fullName}';
  }
}

/// Eine Zeile der Tagesansicht mit ihrem Zeitfenster. `time == null`
/// überspringt die Zeile bei der Interpolation der Jetzt-Linie.
class _DaySegment {
  const _DaySegment({
    required this.id,
    required this.time,
    required this.child,
    this.isBreak = false,
  });

  final String id;
  final BlockTime? time;
  final Widget child;

  /// Pause (z. B. Mittagspause): die Jetzt-Linie hält am oberen Rand der
  /// Zeile an, statt durch sie hindurchzuwandern.
  final bool isBreak;
}

/// Rote "Jetzt"-Linie quer über die Tagesansicht mit Uhrzeit-Pille.
class _NowLine extends StatelessWidget {
  const _NowLine({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final timeText = DateFormat('HH:mm').format(now);

    return SizedBox(
      height: 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: ColoredBox(color: _nowRed)),
          Positioned(
            right: 8,
            top: -9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _nowRed,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    timeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Linke Zeit-Spalte der Timeline: Haarlinie, Stunden-Label (z. B. "1+2")
/// und Start-/Endzeit.
class _TimeColumn extends StatelessWidget {
  const _TimeColumn({
    required this.label,
    required this.blockTime,
    required this.isLive,
  });

  final String label;
  final BlockTime blockTime;
  final bool isLive;

  static String _format(TimeOfDay time) =>
      DateFormat('HH:mm').format(DateTime(0, 1, 1, time.hour, time.minute));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = isLive ? scheme.primary : scheme.outlineVariant;

    return SizedBox(
      width: 76,
      child: Container(
        padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(width: 2, color: accent)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isLive
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isLive
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            _MaskedTimeText(
              text: _format(blockTime.start),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
              scheme: scheme,
            ),
            _MaskedTimeText(
              text: _format(blockTime.end),
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              scheme: scheme,
            ),
          ],
        ),
      ),
    );
  }
}

/// Uhrzeit in der linken Spalte mit deckendem App-Hintergrund: Die rote
/// Jetzt-Linie läuft unter dem Text durch, statt ihn durchzustreichen.
class _MaskedTimeText extends StatelessWidget {
  const _MaskedTimeText({
    required this.text,
    required this.style,
    required this.scheme,
  });

  final String text;
  final TextStyle? style;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(text, style: style),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../models/timetable_result.dart';
import '../providers/teacher_directory_provider.dart';
import '../services/iserv_calendar.dart';
import '../services/stundenplan_repository.dart';
import 'daily_agenda_view.dart';
import 'day_selector.dart';
import 'iserv_tasks_view.dart';
import 'scale_to_fit_height.dart';

/// Anzeigemodus der Stundenplan-Ansicht.
enum TimetableViewMode {
  /// Tages-Agenda mit Zeit-Timeline und Live-Tracking.
  daily,

  /// IServ-Aufgaben.
  weekly,
}

/// Lädt eine komplette Woche (Mo–So) über das Repository und rendert
/// daraus je nach [viewMode] die Tages-Agenda oder die IServ-Aufgaben.
class StundenplanWidget extends StatefulWidget {
  const StundenplanWidget({
    super.key,
    required this.weekStart,
    required this.viewMode,
    required this.selectedDayIndex,
    required this.repository,
    required this.onDaySelected,
    this.onNextWeek,
    this.onPreviousWeek,
    this.teacherDirectory,
    this.clock,
    this.tickInterval,
    this.sessionId,
    this.group,
    this.calendarEvents = const [],
  });

  /// Montag der anzuzeigenden Woche.
  final DateTime weekStart;

  final TimetableViewMode viewMode;

  /// Ausgewählter Wochentag (0 = Montag), nur für die Tagesansicht.
  final int selectedDayIndex;

  final StundenplanRepository repository;

  final ValueChanged<int> onDaySelected;

  /// Wird aufgerufen, wenn am Freitag nach links weitergewischt wird.
  /// Ist er gesetzt, folgt auf Freitag eine Übergangsseite zur nächsten
  /// Woche.
  final VoidCallback? onNextWeek;

  /// Gegenstück zu [onNextWeek]: am Montag nach rechts weitergewischt.
  /// Ist er gesetzt, steht vor Montag eine Übergangsseite zur Vorwoche.
  final VoidCallback? onPreviousWeek;

  /// Kollegiums-Verzeichnis für die Auflösung der Kürzel zu vollen Namen.
  final TeacherDirectoryProvider? teacherDirectory;

  /// Uhr-Quelle (testbar); standardmäßig [DateTime.now].
  final DateTime Function()? clock;

  /// Takt für Live-Updates der Tagesansicht; standardmäßig 30 Sekunden.
  final Duration? tickInterval;

  /// Sitzungs-ID für virtueller-stundenplan.org.
  final String? sessionId;

  /// Kursgruppe des Nutzers (z. B. "A"/"B"); null = alle Gruppen zeigen.
  /// Steuert die Gruppen-Filterung (Regel 5).
  final String? group;
  final List<IservCalendarEvent> calendarEvents;

  @override
  State<StundenplanWidget> createState() => _StundenplanWidgetState();
}

class _StundenplanWidgetState extends State<StundenplanWidget> {
  late Future<TimetableResult> _future;
  late final PageController _pageController;

  /// Anzahl der Tage in der Tagesansicht (Mo–Fr; kann bei unvollständigen
  /// Wochen kleiner sein).
  int _dayCount = 5;

  /// Gesperrt, solange eine programmatische Seiten-Animation läuft –
  /// verhindert, dass die dabei durchlaufenen onPageChanged-Rufe die
  /// Animation abbrechen.
  bool _animatingToDay = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _pageController = PageController(
      initialPage: _pageFor(widget.selectedDayIndex),
    );
    // Nach einer stillen Re-Authentifizierung (Hintergrund) erscheinen
    // frische Daten – dann neu laden, ohne den Nutzer umzuleiten.
    widget.repository.addListener(_onRepositoryChanged);
  }

  @override
  void didUpdateWidget(StundenplanWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.removeListener(_onRepositoryChanged);
      widget.repository.addListener(_onRepositoryChanged);
    }
    if (oldWidget.weekStart != widget.weekStart) {
      _future = _load();
    }
    if (widget.viewMode == TimetableViewMode.daily &&
        oldWidget.selectedDayIndex != widget.selectedDayIndex &&
        !_animatingToDay &&
        _pageController.hasClients) {
      _animatingToDay = true;
      _pageController
          .animateToPage(
            _pageFor(widget.selectedDayIndex),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          )
          .whenComplete(() => _animatingToDay = false);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepositoryChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onRepositoryChanged() {
    if (!mounted) return;
    _reload();
  }

  /// Seite der Tagesansicht für einen Wochentag: Die Tage sind in
  /// Wochenreihenfolge angeordnet (Montag zuerst), sodass Wischen nach
  /// links zum nächsten Tag führt.
  int _pageFor(int dayIndex) =>
      dayIndex.clamp(0, _dayCount - 1) + _leadingPages;

  /// 1, wenn vor Montag die Übergangsseite zur Vorwoche steht.
  int get _leadingPages => widget.onPreviousWeek != null ? 1 : 0;

  Future<TimetableResult> _load() {
    return widget.repository.getTimetable(
      DateFormat('dd.MM.yyyy').format(widget.weekStart),
      weeklyMode: true,
    );
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  Widget _buildContent(WeeklyTimetable timetable) {
    final allDays = timetable.days;
    if (allDays.isEmpty) {
      return _buildEmptyState();
    }

    // Mo–Fr für die Auswahl.
    final weekDays = allDays.length >= 5 ? allDays.sublist(0, 5) : allDays;


    // Tagesansicht: oben die feste Tagesauswahl, darunter die per Wisch
    // durchblätterbaren Tage (Montag zuerst -> nach links wischen
    // wechselt zum nächsten Tag).
    final index = widget.selectedDayIndex.clamp(0, weekDays.length - 1);
    final now = _now();
    final todayIndex = _todayIndexWithin(weekDays, now);
    _dayCount = weekDays.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const _SmoothPagePhysics(),
            // Vor Montag / nach Freitag je eine zusätzliche Seite: Wer
            // dorthin wischt, landet am Freitag der Vorwoche bzw. am
            // Montag der nächsten Woche.
            itemCount: _leadingPages +
                weekDays.length +
                (widget.onNextWeek != null ? 1 : 0),
            onPageChanged: (page) {
              if (_animatingToDay) return;
              final dayIndex = page - _leadingPages;
              if (dayIndex < 0) {
                widget.onPreviousWeek?.call();
                return;
              }
              if (dayIndex >= weekDays.length) {
                widget.onNextWeek?.call();
                return;
              }
              if (dayIndex != widget.selectedDayIndex) {
                widget.onDaySelected(dayIndex);
              }
            },
            itemBuilder: (context, page) {
              final dayIndex = page - _leadingPages;
              if (dayIndex < 0) {
                return _buildWeekChangePage(next: false);
              }
              if (dayIndex >= weekDays.length) {
                return _buildWeekChangePage(next: true);
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  // Die Tagesansicht ist fest im Viewport verankert (kein
                  // Scrollen). Damit auch ein langer (8-Stunden-)Tag vollständig
                  // sichtbar bleibt, wird der gesamte Tag gleichmäßig
                  // herunterskaliert, bis er in die verfügbare Höhe passt
                  // (nie hoch). Anders als FittedBox füllt ScaleToFitHeight
                  // dabei weiterhin die volle Breite (keine leeren Ränder).
                  // Kurze Tage bleiben 1:1 und strecken ihre Zeilen wie
                  // bisher bis zur Mindesthöhe.
                  return Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ScaleToFitHeight(
                        child: DailyAgendaView(
                          day: weekDays[dayIndex],
                          isToday: todayIndex == dayIndex,
                          clock: widget.clock,
                          tickInterval: widget.tickInterval,
                          teacherLookup: widget.teacherDirectory?.lookup,
                          calendarEvents: widget.calendarEvents,
                          group: widget.group,
                          minHeight: constraints.maxHeight,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: DaySelector(
            days: [for (final d in weekDays) d.date],
            selectedIndex: index,
            todayIndex: todayIndex,
            onSelected: widget.onDaySelected,
          ),
        ),
      ],
    );
  }

  int? _todayIndexWithin(List<DailyTimetable> days, DateTime now) {
    for (int i = 0; i < days.length; i++) {
      final d = days[i].date;
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return i;
      }
    }
    return null;
  }

  /// Übergangsseite vor Montag bzw. hinter Freitag (sichtbar nur während
  /// des Wischens).
  Widget _buildWeekChangePage({required bool next}) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            next ? Icons.arrow_forward : Icons.arrow_back,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            next ? 'Nächste Woche' : 'Vorherige Woche',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(child: Text('Kein Unterricht in dieser Woche'));
  }

  /// Fehler-/Info-Zustände mit optionalem Retry-Button.
  Widget _buildStateMessage(String message, {VoidCallback? onRetry}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(message, textAlign: TextAlign.center),
          ),
          if (onRetry != null)
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Erneut versuchen'),
            ),
        ],
      ),
    );
  }

  /// IServ-Aufgaben + Termine der nächsten zwei Wochen (ab heute,
  /// unabhängig von der gewählten Woche). Hängt nicht vom
  /// Stundenplan-Abruf ab und wird daher auch bei dessen Fehlern gezeigt.
  Widget _buildTasksView() {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final until = today.add(const Duration(days: 15));
    final upcoming = widget.calendarEvents.where((event) {
      final eventEnd = event.end ?? event.start;
      return event.start.isBefore(until) &&
          (eventEnd.isAfter(today) || event.start.isAtSameMomentAs(today));
    }).toList()..sort((a, b) => a.start.compareTo(b.start));
    return IservTasksView(upcomingEvents: upcoming);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.viewMode == TimetableViewMode.weekly) {
      return _buildTasksView();
    }
    return FutureBuilder<TimetableResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildStateMessage(
            'Fehler: ${snapshot.error}',
            onRetry: _reload,
          );
        }

        if (!snapshot.hasData) {
          return _buildStateMessage('Keine Daten gefunden', onRetry: _reload);
        }

        return switch (snapshot.data!) {
          TimetableSuccess(:final timetable) => _buildContent(timetable),
          TimetableAuthExpired() => _buildStateMessage(
            'Sitzung abgelaufen – bitte neu anmelden.',
            onRetry: () => context.go('/authenticate'),
          ),
          TimetableNetworkError() => _buildStateMessage(
            'Netzwerkfehler – bitte erneut versuchen.',
            onRetry: _reload,
          ),
        };
      },
    );
  }
}

/// Sanftes Einrasten der Tages-Seiten: Ersetzt die federnde
/// Standard-Spring-Physik durch ein ruhiges, überdämpftes Ausklingen.
class _SmoothPagePhysics extends PageScrollPhysics {
  const _SmoothPagePhysics({super.parent});

  @override
  _SmoothPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _SmoothPagePhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final simulation = super.createBallisticSimulation(position, velocity);
    if (simulation is SpringSimulation) {
      return SpringSimulation(
        const SpringDescription(mass: 0.5, stiffness: 100.0, damping: 16.0),
        simulation.x(0),
        simulation.x(1),
        simulation.dx(0),
      );
    }
    return simulation;
  }
}

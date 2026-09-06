import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/timetable.dart';
import '../models/timetable_result.dart';
import '../providers/teacher_directory_provider.dart';
import '../services/stundenplan_repository.dart';
import 'daily_agenda_view.dart';
import 'day_selector.dart';
import 'iserv_tasks_view.dart';

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
    this.teacherDirectory,
    this.clock,
    this.tickInterval,
    this.sessionId,
    this.group,
  });

  /// Montag der anzuzeigenden Woche.
  final DateTime weekStart;

  final TimetableViewMode viewMode;

  /// Ausgewählter Wochentag (0 = Montag), nur für die Tagesansicht.
  final int selectedDayIndex;

  final StundenplanRepository repository;

  final ValueChanged<int> onDaySelected;

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
  int _pageFor(int dayIndex) => dayIndex.clamp(0, _dayCount - 1);

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

    if (widget.viewMode == TimetableViewMode.weekly) {
      return IservTasksView();
    }

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
            itemCount: weekDays.length,
            onPageChanged: (page) {
              if (_animatingToDay) return;
              final dayIndex = page;
              if (dayIndex != widget.selectedDayIndex) {
                widget.onDaySelected(dayIndex);
              }
            },
            itemBuilder: (context, page) {
              final dayIndex = page;
              return LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: DailyAgendaView(
                        day: weekDays[dayIndex],
                        isToday: todayIndex == dayIndex,
                        clock: widget.clock,
                        tickInterval: widget.tickInterval,
                        teacherLookup: widget.teacherDirectory?.lookup,
                        sessionId: widget.sessionId,
                        group: widget.group,
                        minHeight: constraints.maxHeight,
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

  @override
  Widget build(BuildContext context) {
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

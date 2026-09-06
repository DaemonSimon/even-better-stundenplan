import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../components/debug_clock_sheet.dart';
import '../components/group_settings_sheet.dart';
import '../components/stundenplan_widget.dart';
import '../providers/date_utilities.dart';
import '../providers/teacher_directory_provider.dart';
import '../services/group_preference.dart';
import '../services/session_manager.dart';
import '../services/stundenplan_repository.dart';
import '../utils/simulated_clock.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.title,
    required this.sessionManager,
    required this.teacherDirectory,
    this.groupStore,
    this.initialGroup,
  });

  final String title;
  final SessionManager sessionManager;
  final TeacherDirectoryProvider teacherDirectory;

  /// Ablage der Kursgruppe; standardmäßig SharedPreferences (Regel 5).
  final GroupPreferenceStore? groupStore;

  /// Bereits geladene Gruppe (optional, verhindert ein Einblenden aller
  /// Gruppen vor dem Laden).
  final String? initialGroup;

  @override
  State<HomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<HomePage> {
  // Anker-Datum für die aktuelle Woche (Montag wird daraus berechnet)
  late DateTime _baseDate;

  // Ausgewählter Wochentag (0 = Montag .. 4 = Freitag)
  late int _selectedDayIndex;

  // Anzeigemodus: Tages-Agenda oder IServ-Aufgaben
  TimetableViewMode _viewMode = TimetableViewMode.daily;

  // Kursgruppe des Nutzers (z. B. "A"/"B"); null = alle Gruppen zeigen.
  String? _group;

  // Debug-Uhr: Zeit und Geschwindigkeit simulierbar (nur für Tests/Dev)
  late final SimulatedClock _clock = SimulatedClock();

  late final StundenplanRepository _repository;

  late final GroupPreferenceStore _groupStore =
      widget.groupStore ?? SharedPreferencesGroupStore();

  DateTime get _weekStart => getNthDayOfWeek(_baseDate, 1);

  /// Datum des aktuell ausgewählten Wochentags.
  DateTime get _selectedDate =>
      getNthDayOfWeek(_baseDate, _selectedDayIndex + 1);

  int get _todayIndex => (_clock.now().weekday - 1).clamp(0, 4);

  /// Liegt der ausgewählte Tag auf dem heutigen Datum?
  bool get _isTodaySelected {
    final now = _clock.now();
    final selected = _selectedDate;
    return now.year == selected.year &&
        now.month == selected.month &&
        now.day == selected.day;
  }

  @override
  void initState() {
    super.initState();
    _baseDate = _clock.now();
    _selectedDayIndex = _todayIndex;
    _group = widget.initialGroup;
    _repository = StundenplanRepository(sessionManager: widget.sessionManager);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkAuth());
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    final stored = await _groupStore.getGroup();
    if (!mounted || stored == _group) return;
    setState(() => _group = stored);
  }

  void _openSettings() {
    showGroupSettingsSheet(
      context,
      group: _group,
      onChanged: (value) {
        if (!mounted) return;
        setState(() => _group = value);
        _groupStore.saveGroup(value);
      },
    );
  }

  void checkAuth() async {
    bool authStatus = await widget.sessionManager.checkAuthentication();

    if (!authStatus) {
      // Stille Re-Anmeldung im Hintergrund über die gespeicherten
      // Zugangsdaten – nur wenn das scheitert (z. B. keine Daten
      // gespeichert), zur manuellen Anmeldung weiterleiten.
      final reauthOk = await widget.sessionManager.tryReAuthenticate();
      if (reauthOk) {
        if (mounted) setState(() {});
        return;
      }
      if (!mounted) return;
      context.pushReplacement('/authenticate');
      return;
    }
  }

  void _goToToday() {
    setState(() {
      _baseDate = _clock.now();
      _selectedDayIndex = _todayIndex;
    });
  }

  void _openDebugClock() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Das Sheet darf größer als die Standard-Begrenzung werden,
      // aber nie den ganzen Bildschirm verdecken.
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: (sheetContext) => DebugClockSheet(
        clock: _clock,
        onDatePicked: (date) {
          if (!mounted) return;
          setState(() {
            _baseDate = date;
            _selectedDayIndex = (date.weekday - 1).clamp(0, 4);
          });
        },
      ),
    );
  }

  Future<void> _chooseWeek(BuildContext context) async {
    final current = _weekStart;

    DateTime? date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(
        current.year - 1,
        current.month,
        current.day,
      ),
      lastDate: DateTime(
        current.year + 1,
        current.month,
        current.day,
      ),
    );

    if (date != null && mounted) {
      setState(() {
        _baseDate = getNthDayOfWeek(date, 1);
        _selectedDayIndex = (date.weekday - 1).clamp(0, 4);
      });
    }
  }

  Widget _buildTimetable() {
    // Key = Woche: Der State (und damit die geladenen Daten) bleibt beim
    // Umschalten zwischen Tages-/Wochenansicht innerhalb derselben Woche
    // erhalten; bei einem Wochenwechsel wird neu geladen.
    return StundenplanWidget(
      key: ValueKey(DateFormat('dd.MM.yyyy').format(_weekStart)),
      weekStart: _weekStart,
      viewMode: _viewMode,
      selectedDayIndex: _selectedDayIndex,
      repository: _repository,
      teacherDirectory: widget.teacherDirectory,
      clock: _clock.now,
      tickInterval: _clock.tickInterval,
      sessionId: widget.sessionManager.sessionId,
      group: _group,
      onDaySelected: (index) {
        setState(() {
          _selectedDayIndex = index;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final monday = _weekStart;
    final friday = getNthDayOfWeek(monday, 5);
    final dateSpan =
        '${DateFormat('dd.MM.').format(monday)} – ${DateFormat('dd.MM.yyyy').format(friday)}';

    return Scaffold(
      bottomNavigationBar: BottomAppBar(
        color: theme.colorScheme.onInverseSurface,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SegmentedButton<TimetableViewMode>(
              segments: const [
                ButtonSegment(
                  value: TimetableViewMode.daily,
                  icon: Icon(Icons.view_agenda_outlined),
                  tooltip: 'Tagesansicht',
                ),
                ButtonSegment(
                  value: TimetableViewMode.weekly,
                  icon: Icon(Icons.task_outlined),
                  tooltip: 'Aufgaben',
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (selection) {
                setState(() {
                  _viewMode = selection.first;
                });
              },
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surfaceDim,
        title: GestureDetector(
          // Debug-Uhr: lange auf den Titel drücken (statt sichtbarem
          // Icon in der AppBar).
          onLongPress: _openDebugClock,
          child: Text(widget.title),
        ),
        actions: [
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          if (_clock.isCustomized) _DebugClockBadge(clock: _clock),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WeekHeader(
            selectedDate: _selectedDate,
            weekSpan: dateSpan,
            showTodayButton: !_isTodaySelected,
            onPickWeek: () => _chooseWeek(context),
            onGoToToday: _goToToday,
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([widget.teacherDirectory, _clock]),
              builder: (context, _) => _buildTimetable(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kopfzeile der Tagesansicht: großer Wochentag mit Datum, darunter die
/// Wochenspanne (antippbar zum Wochentausch) und ein "Heute"-Sprung.
class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.selectedDate,
    required this.weekSpan,
    required this.onPickWeek,
    this.showTodayButton = false,
    this.onGoToToday,
  });

  final DateTime selectedDate;
  final String weekSpan;
  final VoidCallback onPickWeek;
  final bool showTodayButton;
  final VoidCallback? onGoToToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    var dayLabel = DateFormat('EEEE, d. MMMM').format(selectedDate);
    dayLabel = dayLabel[0].toUpperCase() + dayLabel.substring(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayLabel,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: onPickWeek,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_month,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          weekSpan,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showTodayButton && onGoToToday != null) ...[
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onGoToToday,
              icon: const Icon(Icons.today, size: 16),
              label: const Text('Heute'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kleines Live-Badge in der AppBar: zeigt simulierte Zeit + Geschwindigkeit,
/// solange die Debug-Uhr von der Echtzeit abweicht.
class _DebugClockBadge extends StatefulWidget {
  const _DebugClockBadge({required this.clock});

  final SimulatedClock clock;

  @override
  State<_DebugClockBadge> createState() => _DebugClockBadgeState();
}

class _DebugClockBadgeState extends State<_DebugClockBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sim = widget.clock.now();
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(
          '${DateFormat('HH:mm:ss').format(sim)} · x${widget.clock.speed.round()}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
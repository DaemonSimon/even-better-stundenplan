import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'homework_image_viewer.dart';
import '../pages/iserv_task_page.dart';
import '../pages/iserv_web_page.dart';
import '../services/iserv_task_detail.dart';

import '../services/homework_attachments.dart';
import '../services/app_settings.dart';
import '../services/connectivity_monitor.dart';
import '../services/homework_reminders.dart';
import '../services/iserv_mapping.dart';
import '../services/iserv_offline_store.dart';
import '../services/iserv_calendar.dart';
import '../services/iserv_session.dart';
import '../services/iserv_tasks.dart';
import 'subject_name_label.dart';

/// IServ-Ansicht (Ersatz für den Wochen-Modus): zeigt Aufgaben direkt
/// aus der App – Login, Scraping und temporäre Aufgaben laufen komplett
/// lokal, ohne externen Server.
class IservTasksView extends StatefulWidget {
  const IservTasksView({
    super.key,
    this.session,
    this.upcomingEvents = const [],
  });

  /// Nur für Tests injizierbare Session (Standard: echte IServ-Session).
  final IservSession? session;

  /// Kalendertermine der nächsten zwei Wochen (Klausuren werden rot
  /// hervorgehoben).
  final List<IservCalendarEvent> upcomingEvents;

  @override
  State<IservTasksView> createState() => _IservTasksViewState();
}

class _IservTasksViewState extends State<IservTasksView>
    with WidgetsBindingObserver {
  late final IservSession _session;
  late final IservMappingEngine _mapping = IservMappingEngine();
  late final TempAssignmentStore _store = TempAssignmentStore();
  final IservTaskCache _taskCache = IservTaskCache();

  /// Zuletzt erfolgreich geladene offene IServ-Aufgaben.
  List<IservTask> _lastIservTasks = const [];

  List<Map<String, dynamic>>? _tasks;
  List<IservTask> _pastTasks = const [];
  bool _showPastTasks = false;
  bool _loading = true;
  bool _iservAuthenticated = false;
  bool _showLoginForm = false;
  String? _error;
  Timer? _cleanupTimer;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _loginError;

  /// Letzter Fehler der automatischen IServ-Anmeldung (zur Fehlersuche).
  String? _reloginError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.session ?? IservSession();
    AppSettingsStore.revision.addListener(_onAppSettingsChanged);
    ConnectivityMonitor.instance.addListener(_onConnectivityChanged);
    IservSession.logoutRevision.addListener(_onLoggedOut);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupTimer?.cancel();
    AppSettingsStore.revision.removeListener(_onAppSettingsChanged);
    ConnectivityMonitor.instance.removeListener(_onConnectivityChanged);
    IservSession.logoutRevision.removeListener(_onLoggedOut);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refresh());
    }
  }

  Future<void> _init() async {
    await _session.restore();
    await _mapping.restore();
    await _showCachedTasks();
    await _refresh();
  }

  /// Sobald wieder Internet da ist, die gespeicherten Aufgaben auffrischen.
  void _onConnectivityChanged() {
    if (mounted && ConnectivityMonitor.instance.isOnline) {
      unawaited(_refresh());
    }
  }

  /// Zeigt die zuletzt geladenen IServ-Aufgaben sofort an, bevor das Netz
  /// antwortet. Gibt `false` zurück, wenn nichts gespeichert ist.
  Future<bool> _showCachedTasks() async {
    final cached = await _taskCache.load();
    if (cached == null) return false;
    final List<TempAssignment> tempTasks;
    try {
      tempTasks = await _store.load();
    } catch (_) {
      return false;
    }
    if (!mounted) return false;
    final merged = mergeTasks(
      iservTasks: cached.open,
      tempTasks: tempTasks,
      engine: _mapping,
    );
    setState(() {
      _iservAuthenticated = true;
      _tasks = merged;
      _pastTasks = cached.past;
      _error = null;
      _loading = false;
    });
    unawaited(_syncReminders(merged));
    return true;
  }

  Future<void> _onAppSettingsChanged() async {
    final tasks = _tasks;
    if (tasks != null) unawaited(_syncReminders(tasks));
    final settings = await AppSettingsStore().load();
    if (!settings.preloadIservFiles) {
      // Vorab-Laden aus: gespeicherte Dateien freigeben.
      await IservOfflineStore.instance.clear();
    } else if (_iservAuthenticated && _lastIservTasks.isNotEmpty) {
      unawaited(IservOfflineStore.instance.sync(_session, _lastIservTasks));
    }
  }

  /// Abmeldung (z. B. aus den Einstellungen): eigene Session verwerfen
  /// und neu laden, damit die Anmeldemaske erscheint.
  Future<void> _onLoggedOut() async {
    await _session.clear();
    _lastIservTasks = const [];
    if (mounted) await _refresh();
  }

  Future<void> _syncReminders(List<Map<String, dynamic>> tasks) async {
    try {
      final calendarEvents = await IservCalendarStore().load();
      await HomeworkReminders.sync(tasks, calendarEvents: calendarEvents);
    } catch (error) {
      debugPrint(
        'Hausaufgabenerinnerungen konnten nicht geplant werden: $error',
      );
    }
  }

  Future<void> _refresh() async {
    setState(() {
      // Vorhandene (ggf. gespeicherte) Liste stehen lassen.
      _loading = _tasks == null;
      _error = null;
    });
    try {
      final expired = await _store.purgeCompleted();
      for (final task in expired) {
        await HomeworkAttachments.deleteOwned(task.imagePaths);
      }
      final authenticated = await _session.ensureAuthenticated();
      final reloginError = authenticated
          ? null
          : await IservSession.lastReloginError();
      List<IservTask> iservTasks = const <IservTask>[];
      List<IservTask> pastTasks = const <IservTask>[];
      if (authenticated) {
        iservTasks = await fetchTasks(_session);
        // Vergangene Aufgaben sind optional – Fehler dort ignorieren.
        try {
          pastTasks = await fetchPastTasks(_session);
        } catch (error) {
          debugPrint('Vergangene IServ-Aufgaben nicht ladbar: $error');
        }
      }
      if (authenticated) {
        ConnectivityMonitor.instance.reportSuccess();
        await _taskCache.save(open: iservTasks, past: pastTasks);
        _lastIservTasks = iservTasks;
        // Anhänge laufender Aufgaben vorab laden, vorbei Aufgaben löschen.
        if ((await AppSettingsStore().load()).preloadIservFiles) {
          unawaited(IservOfflineStore.instance.sync(_session, iservTasks));
        }
      }
      final tempTasks = await _store.load();
      _scheduleCleanup(tempTasks);
      final merged = mergeTasks(
        iservTasks: iservTasks,
        tempTasks: tempTasks,
        engine: _mapping,
      );
      if (!mounted) return;
      setState(() {
        _reloginError = reloginError;
        _iservAuthenticated = authenticated;
        _showLoginForm = false;
        _tasks = merged;
        _pastTasks = pastTasks;
        _loading = false;
      });
      unawaited(_syncReminders(merged));
    } on IservException catch (exc) {
      if (!mounted) return;
      if (isNetworkError(exc)) {
        ConnectivityMonitor.instance.reportFailure();
        if (await _showCachedTasks()) return;
      }
      if (!mounted) return;
      final tempTasks = await _store.load();
      _scheduleCleanup(tempTasks);
      final localTasks = mergeTasks(
        iservTasks: const <IservTask>[],
        tempTasks: tempTasks,
        engine: _mapping,
      );
      setState(() {
        _iservAuthenticated = false;
        _tasks = localTasks;
        _error = exc.message;
        _loading = false;
      });
      unawaited(_syncReminders(localTasks));
    } catch (error) {
      if (!mounted) return;
      if (isNetworkError(error)) {
        ConnectivityMonitor.instance.reportFailure();
        if (await _showCachedTasks()) return;
      }
      if (!mounted) return;
      try {
        final tempTasks = await _store.load();
        _scheduleCleanup(tempTasks);
        final localTasks = mergeTasks(
          iservTasks: const <IservTask>[],
          tempTasks: tempTasks,
          engine: _mapping,
        );
        setState(() {
          _iservAuthenticated = false;
          _tasks = localTasks;
          _error = 'IServ nicht erreichbar: $error';
          _loading = false;
        });
        unawaited(_syncReminders(localTasks));
      } catch (storageError) {
        setState(() {
          _iservAuthenticated = false;
          _tasks = const [];
          _error =
              'Lokale Hausaufgaben konnten nicht geladen werden: '
              '$storageError';
          _loading = false;
        });
      }
    }
  }

  void _scheduleCleanup(List<TempAssignment> tasks) {
    _cleanupTimer?.cancel();
    final nextCleanup = TempAssignmentStore.nextCleanupAt(tasks);
    if (nextCleanup == null) return;
    _cleanupTimer = Timer(nextCleanup.difference(DateTime.now()), () {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _login() async {
    setState(() {
      _loginError = null;
      _loading = true;
    });
    try {
      final ok = await _session.login(
        _usernameController.text,
        _passwordController.text,
      );
      if (!ok) {
        throw const IservLoginException(
          'Anmeldung fehlgeschlagen – Zugangsdaten prüfen',
        );
      }
      // Login hat geklappt: Passwortmanager darf die Daten speichern
      // (vor dem Leeren des Passwortfelds).
      TextInput.finishAutofillContext();
      _passwordController.clear();
      _showLoginForm = false;
      await _refresh();
    } on IservException catch (exc) {
      if (!mounted) return;
      setState(() {
        _loginError = exc.message;
        _loading = false;
      });
    } catch (exc) {
      // Unerwartete Fehler dürfen die Ansicht nicht im Ladezustand
      // hängen lassen.
      if (!mounted) return;
      setState(() {
        _loginError = 'Anmeldung fehlgeschlagen: $exc';
        _loading = false;
      });
    }
  }

  Future<void> _editTempAssignment(Map<String, dynamic> task) async {
    final current = TempAssignment(
      id: task['id'] as int,
      title: task['title'] as String,
      subject: task['subject'] as String? ?? '',
      teacher: task['teacher'] as String? ?? '',
      dueDate: task['due_date'] as String?,
      description: task['description'] as String? ?? '',
      links: (task['links'] as List?)?.cast<String>() ?? const [],
      imagePaths: (task['image_paths'] as List?)?.cast<String>() ?? const [],
      lessonDate: task['lesson_date'] as String?,
      hour: task['hour'] as String?,
      completedAt: task['completed_at'] as String?,
    );
    final result = await showDialog<TempAssignment>(
      context: context,
      builder: (context) => _TempAssignmentDialog(initial: current),
    );
    if (result == null || !mounted) return;
    await _store.update(result);
    await HomeworkAttachments.deleteOwned(
      current.imagePaths.where((path) => !result.imagePaths.contains(path)),
    );
    await _refresh();
  }

  Future<void> _deleteTempAssignment(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aufgabe löschen?'),
        content: Text('"${task['title']}" wird entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _store.remove(task['id'] as int);
    await HomeworkAttachments.deleteOwned(
      (task['image_paths'] as List? ?? const []).whereType<String>(),
    );
    await _refresh();
  }

  Future<void> _toggleCompleted(Map<String, dynamic> task) async {
    final assignment = TempAssignment(
      id: task['id'] as int,
      title: task['title'] as String,
      subject: task['subject'] as String? ?? '',
      teacher: task['teacher'] as String? ?? '',
      dueDate: task['due_date'] as String?,
      description: task['description'] as String? ?? '',
      links: (task['links'] as List?)?.cast<String>() ?? const [],
      imagePaths: (task['image_paths'] as List?)?.cast<String>() ?? const [],
      lessonDate: task['lesson_date'] as String?,
      hour: task['hour'] as String?,
      completedAt: task['completed_at'] as String?,
    );
    try {
      await _store.update(
        assignment.copyWith(
          completedAt: assignment.completedAt == null
              ? DateTime.now().toIso8601String()
              : null,
          clearCompletedAt: assignment.completedAt != null,
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status konnte nicht gespeichert werden: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (_tasks == null || _tasks!.isEmpty)) {
      return _buildStateMessage(
        context,
        icon: Icons.cloud_off,
        title: 'IServ nicht erreichbar',
        detail: _error!,
        action: OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Erneut versuchen'),
        ),
        extra: _error!.contains('Redirects') ? _buildRequestLog(context) : null,
      );
    }
    if (!_iservAuthenticated && _showLoginForm) {
      return _buildLogin(context);
    }
    return _buildTaskList(context);
  }

  Widget _buildLogin(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.lock_outline,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                'IServ-Anmeldung',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              Text(
                'Mit deinem IServ-Account anmelden, um die Aufgaben zu sehen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              // AutofillGroup: Passwortmanager erkennen Account + Passwort
              // als IServ-Login und bieten Ausfüllen/Speichern an.
              AutofillGroup(
                child: Column(
                  children: [
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      autofocus: true,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Passwort',
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                    ),
                  ],
                ),
              ),
              if (_loginError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _loginError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _login,
                icon: const Icon(Icons.login),
                label: const Text('Anmelden'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskList(BuildContext context) {
    final tasks = _tasks ?? const [];
    final theme = Theme.of(context);
    final events = widget.upcomingEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'IServ gerade nicht erreichbar. Lokale Aufgaben bleiben verfügbar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        // Ohne IServ-Anmeldung fehlen die IServ-Aufgaben – deutlich sagen,
        // statt nur "Keine Hausaufgaben" zu zeigen.
        if (!_iservAuthenticated && _error == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Material(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nicht bei IServ angemeldet – IServ-Aufgaben '
                            'werden erst nach der Anmeldung angezeigt.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                          if (_reloginError != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Automatische Anmeldung fehlgeschlagen: '
                              '$_reloginError',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _showLoginForm = true),
                      child: const Text('Anmelden'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            // Aufbau: Termine (inkl. Klausuren) -> offene Aufgaben ->
            // vergangene Aufgaben (eingeklappt) -> IServ abmelden.
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                if (events.isNotEmpty) ...[
                  const _SectionHeader(title: 'Termine (nächste 2 Wochen)'),
                  for (final event in events) _CalendarTaskEntry(event: event),
                ],
                _SectionHeader(title: 'Offene Aufgaben (${tasks.length})'),
                if (tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Keine offenen Aufgaben',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final task in tasks)
                    _TaskCard(
                      task: task,
                      onEdit: task['source'] == 'temp'
                          ? () => _editTempAssignment(task)
                          : null,
                      onDelete: task['source'] == 'temp'
                          ? () => _deleteTempAssignment(task)
                          : null,
                      onToggleCompleted: task['source'] == 'temp'
                          ? () => _toggleCompleted(task)
                          : null,
                      onOpen: (task['links'] as List).isEmpty
                          ? null
                          : () => _openLink(
                              context,
                              _session,
                              (task['links'] as List).first.toString(),
                              title: task['title'] as String,
                            ),
                    ),
                if (_pastTasks.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Vergangene Aufgaben (${_pastTasks.length})',
                    expanded: _showPastTasks,
                    onTap: () =>
                        setState(() => _showPastTasks = !_showPastTasks),
                  ),
                  if (_showPastTasks)
                    for (final task in _pastTasks)
                      _PastTaskEntry(
                        task: task,
                        onTap: task.links.isEmpty
                            ? null
                            : () => _openLink(
                                context,
                                _session,
                                task.links.first,
                                title: task.title,
                              ),
                      ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestLog(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _session.requestLog.toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final text = lines.join('\n');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Text('Letzte Requests:', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Request-Log kopiert')),
            );
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Log kopieren'),
        ),
      ],
    );
  }

  Widget _buildStateMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
    required Widget action,
    Widget? extra,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            action,
            if (extra != null) extra,
          ],
        ),
      ),
    );
  }
}

/// Einheitliche Abschnittsüberschrift; mit [onTap] auf-/zuklappbar.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.expanded, this.onTap});

  final String title;
  final bool? expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (expanded != null)
              Icon(
                expanded! ? Icons.expand_less : Icons.expand_more,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// Kalendertermin; Klausuren mit rotem Rand und "Klausur"-Kennzeichnung.
class _CalendarTaskEntry extends StatelessWidget {
  const _CalendarTaskEntry({required this.event});

  final IservCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDay =
        event.start.hour == 0 &&
        event.start.minute == 0 &&
        (event.end == null || event.end!.difference(event.start).inHours >= 23);
    final day = DateFormat('EEE, dd.MM.', 'de_DE').format(event.start);
    final time = allDay
        ? 'ganztägig'
        : event.end == null
        ? DateFormat('HH:mm').format(event.start)
        : '${DateFormat('HH:mm').format(event.start)}–'
              '${DateFormat('HH:mm').format(event.end!)}';
    final accent = event.isExam
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                if (event.isExam)
                  _MetaRow(
                    icon: Icons.assignment_late_outlined,
                    text: 'Klausur',
                  ),
                _MetaRow(icon: Icons.event, text: '$day · $time'),
              ],
            ),
            if (event.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(event.description.trim(), style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kompakter Eintrag einer vergangenen IServ-Aufgabe.
class _PastTaskEntry extends StatelessWidget {
  const _PastTaskEntry({required this.task, this.onTap});

  final IservTask task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(
          task.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text('Abgabe: ${_formatDueDate(task.dueDate)}'),
        trailing: onTap == null
            ? null
            : const Icon(Icons.open_in_new, size: 18),
        onTap: onTap,
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    this.onEdit,
    this.onDelete,
    this.onToggleCompleted,
    this.onOpen,
  });

  final Map<String, dynamic> task;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleCompleted;

  /// IServ-Aufgabe in der App öffnen.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTemp = task['source'] == 'temp';
    final dueDate = _formatDueDate(task['due_date'] as String?);
    final completed = task['completed_at'] is String;
    final hour = task['hour'] as String?;

    final links = (task['links'] as List).cast<Object>();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        // Eigene Aufgaben: bearbeiten. IServ-Aufgaben: in der App öffnen.
        onTap: onEdit ?? onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task['title'] as String,
                      style: theme.textTheme.titleSmall?.copyWith(
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (onToggleCompleted != null)
                    Tooltip(
                      message: completed
                          ? 'Wieder öffnen'
                          : 'Als erledigt markieren',
                      child: Checkbox(
                        value: completed,
                        onChanged: (_) => onToggleCompleted!(),
                      ),
                    ),
                  if (isTemp && onDelete != null)
                    IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                    ),
                  if (!isTemp && links.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  if (isTemp) ...[
                    if ((task['subject'] as String).isNotEmpty)
                      _SubjectMetaRow(subject: task['subject'] as String),
                    if (hour != null)
                      _MetaRow(
                        icon: Icons.school_outlined,
                        text: _formatLessonPeriods(hour),
                      ),
                    _MetaRow(icon: Icons.event, text: 'Abgabe: $dueDate'),
                  ] else ...[
                    const _MetaRow(icon: Icons.cloud_outlined, text: 'IServ'),
                    if ((task['subject'] as String).isNotEmpty)
                      _MetaRow(
                        icon: Icons.menu_book,
                        text: task['subject'] as String,
                      ),
                    if ((task['teacher'] as String).isNotEmpty)
                      _MetaRow(
                        icon: Icons.person_outline,
                        text: task['teacher'] as String,
                      ),
                    _MetaRow(icon: Icons.event, text: 'Abgabe: $dueDate'),
                    if (task['slot'] != null)
                      _MetaRow(
                        icon: Icons.schedule,
                        text: 'Slot ${task['slot']}',
                      ),
                  ],
                ],
              ),
              if ((task['description'] as String).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  task['description'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if ((task['image_paths'] as List? ?? const []).isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: (task['image_paths'] as List).length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final path =
                          (task['image_paths'] as List)[index] as String;
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => HomeworkImageViewer(path: path),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 84,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Öffnet einen Link: IServ-Seiten direkt in der App (angemeldet),
/// alles andere im Browser.
Future<void> _openLink(
  BuildContext context,
  IservSession session,
  String url, {
  String title = 'IServ',
}) async {
  // Aufgaben: eigene Detailseite der App.
  if (session.isIservUrl(url) && isTaskDetailUrl(url)) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IservTaskPage(url: url, session: session, title: title),
      ),
    );
    return;
  }
  if (session.isIservUrl(url)) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IservWebPage(url: url, session: session, title: title),
      ),
    );
    return;
  }
  final uri = Uri.tryParse(url);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link konnte nicht geöffnet werden')),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SubjectMetaRow extends StatelessWidget {
  const _SubjectMetaRow({required this.subject});

  final String subject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.menu_book,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        SubjectNameLabel(
          raw: subject,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Dialog zum Anlegen/Bearbeiten einer temporären Aufgabe.
class _TempAssignmentDialog extends StatefulWidget {
  const _TempAssignmentDialog({required this.initial});

  final TempAssignment initial;

  @override
  State<_TempAssignmentDialog> createState() => _TempAssignmentDialogState();
}

class _TempAssignmentDialogState extends State<_TempAssignmentDialog> {
  final _picker = ImagePicker();
  late final _title = TextEditingController(text: widget.initial.title);
  late final _description = TextEditingController(
    text: widget.initial.description,
  );
  late final _existingImages = List<String>.of(widget.initial.imagePaths);
  final List<XFile> _newImages = [];
  bool _pickingImages = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    setState(() => _pickingImages = true);
    try {
      final images = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (mounted && images.isNotEmpty) {
        setState(() => _newImages.addAll(images));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotos konnten nicht geöffnet werden: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      final savedImages = await HomeworkAttachments.copyPicked(_newImages);
      if (!mounted) return;
      Navigator.pop(
        context,
        widget.initial.copyWith(
          title: title,
          description: _description.text.trim(),
          imagePaths: [..._existingImages, ...savedImages],
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotos konnten nicht gespeichert werden: $error'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Hausaufgabe bearbeiten'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Titel *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickingImages ? null : _pickImages,
                icon: _pickingImages
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  _pickingImages ? 'Fotos werden geöffnet' : 'Fotos hinzufügen',
                ),
              ),
            ),
            if (_existingImages.isNotEmpty || _newImages.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _existingImages.length; index++)
                    _AttachmentPreview(
                      path: _existingImages[index],
                      onRemove: () =>
                          setState(() => _existingImages.removeAt(index)),
                    ),
                  for (var index = 0; index < _newImages.length; index++)
                    _AttachmentPreview(
                      path: _newImages[index].path,
                      onRemove: () =>
                          setState(() => _newImages.removeAt(index)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

String _formatDueDate(String? value) {
  if (value == null || value.isEmpty) return 'Ohne Termin';
  final date = _parseDueDate(value);
  if (date == null) return value;
  return DateFormat('EEE, dd.MM.yyyy', 'de_DE').format(date);
}

String _formatLessonPeriods(String value) {
  final periods = value.split('+').map(int.tryParse).whereType<int>().toList();
  if (periods.isEmpty) return '$value. Stunde';
  return periods.length == 1
      ? '${periods.single}. Stunde'
      : '${periods.first}.+${periods.last}. Stunde';
}

DateTime? _parseDueDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return parsed;
  try {
    return DateFormat('dd.MM.yyyy').parseStrict(value);
  } on FormatException {
    return null;
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

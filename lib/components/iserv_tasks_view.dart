import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'homework_image_viewer.dart';

import '../services/homework_attachments.dart';
import '../services/app_settings.dart';
import '../services/homework_reminders.dart';
import '../services/iserv_mapping.dart';
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
    this.calendarEvents = const [],
  });

  /// Nur für Tests injizierbare Session (Standard: echte IServ-Session).
  final IservSession? session;
  final List<IservCalendarEvent> calendarEvents;

  @override
  State<IservTasksView> createState() => _IservTasksViewState();
}

class _IservTasksViewState extends State<IservTasksView>
    with WidgetsBindingObserver {
  late final IservSession _session;
  late final IservMappingEngine _mapping = IservMappingEngine();
  late final TempAssignmentStore _store = TempAssignmentStore();

  List<Map<String, dynamic>>? _tasks;
  bool _loading = true;
  bool _iservAuthenticated = false;
  bool _showLoginForm = false;
  String? _error;
  Timer? _cleanupTimer;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _loginError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.session ?? IservSession();
    AppSettingsStore.revision.addListener(_onAppSettingsChanged);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupTimer?.cancel();
    AppSettingsStore.revision.removeListener(_onAppSettingsChanged);
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
    await _refresh();
  }

  void _onAppSettingsChanged() {
    final tasks = _tasks;
    if (tasks != null) unawaited(_syncReminders(tasks));
  }

  Future<void> _syncReminders(List<Map<String, dynamic>> tasks) async {
    try {
      final calendarEvents = await IservCalendarStore().load();
      await HomeworkReminders.sync(
        tasks,
        calendarEvents: calendarEvents,
      );
    } catch (error) {
      debugPrint('Hausaufgabenerinnerungen konnten nicht geplant werden: $error');
    }
  }

  /// Kopiert Fehlermeldung + Request-Log automatisch in die
  /// Zwischenablage, damit der Nutzer sie dem Entwickler schicken kann.
  Future<void> _copyErrorToClipboard(String message) async {
    final log = _session.requestLog.toList();
    final text = log.isEmpty
        ? message
        : '$message\n\nLetzte Requests:\n${log.join('\n')}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fehler + Log kopiert – bitte an den Entwickler schicken'),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final expired = await _store.purgeCompleted();
      for (final task in expired) {
        await HomeworkAttachments.deleteOwned(task.imagePaths);
      }
      final authenticated = await _session.isAuthenticated();
      List<IservTask> iservTasks = const <IservTask>[];
      if (authenticated) {
        iservTasks = await fetchTasks(_session);
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
        _iservAuthenticated = authenticated;
        _showLoginForm = false;
        _tasks = merged;
        _loading = false;
      });
      unawaited(_syncReminders(merged));
    } on IservException catch (exc) {
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
      await _copyErrorToClipboard(exc.message);
    } catch (error) {
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
          _error = 'Lokale Hausaufgaben konnten nicht geladen werden: '
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
      _passwordController.clear();
      _showLoginForm = false;
      await _refresh();
    } on IservException catch (exc) {
      if (!mounted) return;
      setState(() {
        _loginError = exc.message;
        _loading = false;
      });
      await _copyErrorToClipboard(exc.message);
    }
  }

  Future<void> _logout() async {
    await _session.logout();
    await _refresh();
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
      builder: (context) => _TempAssignmentDialog(
        initial: current,
      ),
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
        SnackBar(content: Text('Status konnte nicht gespeichert werden: $error')),
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
        extra: _error!.contains('Redirects')
            ? _buildRequestLog(context)
            : null,
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
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Account',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                autofocus: true,
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
                obscureText: true,
                onSubmitted: (_) => _login(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Hausaufgaben (${tasks.length})',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (!_iservAuthenticated)
                IconButton(
                  tooltip: 'Bei IServ anmelden',
                  icon: const Icon(Icons.login),
                  onPressed: () => setState(() => _showLoginForm = true),
                ),
              if (_iservAuthenticated)
                IconButton(
                  tooltip: 'Abmelden',
                  icon: const Icon(Icons.logout),
                  onPressed: _logout,
                ),
            ],
          ),
        ),
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: tasks.isEmpty && widget.calendarEvents.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 240,
                        child: Center(
                          child: Text(
                            'Keine Hausaufgaben',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (widget.calendarEvents.isNotEmpty) ...[
                        Text(
                          'Kalendereinträge dieser Woche',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        for (final event in widget.calendarEvents)
                          _CalendarTaskEntry(event: event),
                        const SizedBox(height: 12),
                      ],
                      if (tasks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('Keine Hausaufgaben')),
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
                          ),
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

class _CalendarTaskEntry extends StatelessWidget {
  const _CalendarTaskEntry({required this.event});

  final IservCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final when =
        event.start.hour == 0 &&
            event.start.minute == 0 &&
            (event.end == null ||
                event.end!.difference(event.start).inHours >= 23)
        ? 'Ganztägig'
        : DateFormat('EEE, dd.MM. · HH:mm', 'de_DE').format(event.start);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: const Icon(Icons.event_outlined),
        title: Text(event.title),
        subtitle: Text(
          event.description.isEmpty ? when : '$when\n${event.description}',
        ),
        isThreeLine: event.description.isNotEmpty,
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
  });

  final Map<String, dynamic> task;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTemp = task['source'] == 'temp';
    final dueDate = _formatDueDate(task['due_date'] as String?);
    final completed = task['completed_at'] is String;
    final hour = task['hour'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onEdit,
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
                        decoration:
                            completed ? TextDecoration.lineThrough : null,
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
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  if (isTemp) ...[
                    if ((task['subject'] as String).isNotEmpty)
                      _SubjectMetaRow(
                        subject: task['subject'] as String,
                      ),
                    if (hour != null)
                      _MetaRow(
                        icon: Icons.school_outlined,
                        text: _formatLessonPeriods(hour),
                      ),
                    _MetaRow(icon: Icons.event, text: 'Abgabe: $dueDate'),
                  ] else ...[
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
                    _MetaRow(icon: Icons.event, text: dueDate),
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
                      final path = (task['image_paths'] as List)[index] as String;
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
              if ((task['links'] as List).isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final link in (task['links'] as List).take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.link,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            link.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
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
  late final _existingImages = List<String>.of(
    widget.initial.imagePaths,
  );
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
          SnackBar(content: Text('Fotos konnten nicht geöffnet werden: $error')),
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
          SnackBar(content: Text('Fotos konnten nicht gespeichert werden: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Hausaufgabe bearbeiten',
      ),
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
                      onRemove: () => setState(() => _existingImages.removeAt(index)),
                    ),
                  for (var index = 0; index < _newImages.length; index++)
                    _AttachmentPreview(
                      path: _newImages[index].path,
                      onRemove: () => setState(() => _newImages.removeAt(index)),
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
  final periods = value
      .split('+')
      .map(int.tryParse)
      .whereType<int>()
      .toList();
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
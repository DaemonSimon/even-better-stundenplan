import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/iserv_mapping.dart';
import '../services/iserv_session.dart';
import '../services/iserv_tasks.dart';

/// IServ-Ansicht (Ersatz für den Wochen-Modus): zeigt Aufgaben direkt
/// aus der App – Login, Scraping und temporäre Aufgaben laufen komplett
/// lokal, ohne externen Server.
class IservTasksView extends StatefulWidget {
  const IservTasksView({super.key, this.session});

  /// Nur für Tests injizierbare Session (Standard: echte IServ-Session).
  final IservSession? session;

  @override
  State<IservTasksView> createState() => _IservTasksViewState();
}

class _IservTasksViewState extends State<IservTasksView> {
  late final IservSession _session;
  late final IservMappingEngine _mapping = IservMappingEngine();
  late final TempAssignmentStore _store = TempAssignmentStore();

  List<Map<String, dynamic>>? _tasks;
  bool _loading = true;
  String? _error;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _loginError;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? IservSession();
    _init();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _session.restore();
    await _mapping.restore();
    await _refresh();
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
      final authenticated = await _session.isAuthenticated();
      if (!mounted) return;
      if (authenticated) {
        final iservTasks = await fetchTasks(_session);
        final tempTasks = await _store.load();
        final merged = mergeTasks(
          iservTasks: iservTasks,
          tempTasks: tempTasks,
          engine: _mapping,
        );
        if (!mounted) return;
        setState(() {
          _tasks = merged;
          _loading = false;
        });
      } else {
        setState(() {
          _tasks = null;
          _loading = false;
        });
      }
    } on IservException catch (exc) {
      if (!mounted) return;
      setState(() {
        _tasks = null;
        _error = exc.message;
        _loading = false;
      });
      await _copyErrorToClipboard(exc.message);
    }
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

  Future<void> _addTempAssignment() async {
    final task = await showDialog<TempAssignment>(
      context: context,
      builder: (context) => const _TempAssignmentDialog(),
    );
    if (task == null || !mounted) return;
    await _store.add(
      title: task.title,
      subject: task.subject,
      teacher: task.teacher,
      dueDate: task.dueDate,
      description: task.description,
      links: task.links,
    );
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
    );
    final result = await showDialog<TempAssignment>(
      context: context,
      builder: (context) => _TempAssignmentDialog(initial: current),
    );
    if (result == null || !mounted) return;
    await _store.update(result);
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
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
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
    if (_tasks == null) {
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
                  'Aufgaben (${tasks.length})',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Temporäre Aufgabe',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _addTempAssignment,
              ),
              IconButton(
                tooltip: 'Abmelden',
                icon: const Icon(Icons.logout),
                onPressed: _logout,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: tasks.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 240,
                        child: Center(
                          child: Text(
                            'Keine Aufgaben',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _TaskCard(
                        task: task,
                        onEdit: task['source'] == 'temp'
                            ? () => _editTempAssignment(task)
                            : null,
                        onDelete: task['source'] == 'temp'
                            ? () => _deleteTempAssignment(task)
                            : null,
                      );
                    },
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

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, this.onEdit, this.onDelete});

  final Map<String, dynamic> task;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTemp = task['source'] == 'temp';
    final dueDate = task['due_date'] != null
        ? DateFormat('EEE, dd.MM. HH:mm', 'de_DE').format(
            DateTime.parse(task['due_date'] as String),
          )
        : 'Ohne Termin';

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
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (isTemp)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Chip(
                        label: Text('TEMP'),
                        visualDensity: VisualDensity.compact,
                        labelStyle: TextStyle(fontSize: 10),
                        padding: EdgeInsets.zero,
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
                  if ((task['subject'] as String).isNotEmpty)
                    _MetaRow(icon: Icons.menu_book, text: task['subject'] as String),
                  if ((task['teacher'] as String).isNotEmpty)
                    _MetaRow(
                      icon: Icons.person_outline,
                      text: task['teacher'] as String,
                    ),
                  _MetaRow(icon: Icons.event, text: dueDate),
                  if (task['slot'] != null)
                    _MetaRow(icon: Icons.schedule, text: 'Slot ${task['slot']}'),
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

/// Dialog zum Anlegen/Bearbeiten einer temporären Aufgabe.
class _TempAssignmentDialog extends StatefulWidget {
  const _TempAssignmentDialog({this.initial});

  final TempAssignment? initial;

  @override
  State<_TempAssignmentDialog> createState() => _TempAssignmentDialogState();
}

class _TempAssignmentDialogState extends State<_TempAssignmentDialog> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _subject = TextEditingController(text: widget.initial?.subject ?? '');
  late final _teacher = TextEditingController(text: widget.initial?.teacher ?? '');
  late final _due = TextEditingController(text: widget.initial?.dueDate ?? '');
  late final _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _teacher.dispose();
    _due.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Temporäre Aufgabe' : 'Aufgabe bearbeiten',
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
              controller: _subject,
              decoration: const InputDecoration(
                labelText: 'Fach',
                hintText: 'z. B. Mathematik',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _teacher,
              decoration: const InputDecoration(labelText: 'Lehrkraft'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _due,
              decoration: const InputDecoration(
                labelText: 'Abgabetermin',
                hintText: 'z. B. 2026-08-21 oder 21.08.2026 08:00',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            final due = _due.text.trim().isEmpty ? null : _due.text.trim();
            Navigator.pop(
              context,
              TempAssignment(
                id: widget.initial?.id ?? 0,
                title: title,
                subject: _subject.text.trim(),
                teacher: _teacher.text.trim(),
                dueDate: due,
                description: _description.text.trim(),
                links: widget.initial?.links ?? const [],
              ),
            );
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
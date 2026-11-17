import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/iserv_session.dart';
import '../services/iserv_task_detail.dart';
import 'iserv_web_page.dart';

/// Eigene Detailseite einer IServ-Aufgabe: Titel, Lehrkraft, Termine,
/// Beschreibung, Dateien und Abgabestatus – im Stil der App statt der
/// IServ-Weboberfläche.
class IservTaskPage extends StatefulWidget {
  const IservTaskPage({
    super.key,
    required this.url,
    required this.session,
    this.title = 'Aufgabe',
    this.loader,
  });

  final String url;
  final IservSession session;

  /// Titel, bis die Details geladen sind.
  final String title;

  /// Nur für Tests: liefert die Details ohne Netzwerk.
  final Future<IservTaskDetail> Function()? loader;

  @override
  State<IservTaskPage> createState() => _IservTaskPageState();
}

class _IservTaskPageState extends State<IservTaskPage> {
  late Future<IservTaskDetail> _detail = _load();
  String? _downloading;

  Future<IservTaskDetail> _load() =>
      widget.loader?.call() ?? fetchTaskDetail(widget.session, widget.url);

  void _openInIserv() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IservWebPage(
          url: widget.url,
          session: widget.session,
          title: widget.title,
        ),
      ),
    );
  }

  Future<void> _openAttachment(IservAttachment attachment) async {
    setState(() => _downloading = attachment.url);
    try {
      final file = await downloadAttachment(widget.session, attachment);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        _showMessage('Keine App zum Öffnen gefunden: ${result.message}');
      }
    } catch (error) {
      if (mounted) _showMessage('Datei konnte nicht geladen werden: $error');
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  void _showMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgabe'),
        actions: [
          IconButton(
            tooltip: 'In IServ öffnen',
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInIserv,
          ),
        ],
      ),
      body: FutureBuilder<IservTaskDetail>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Aufgabe konnte nicht geladen werden.'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => setState(() => _detail = _load()),
                      child: const Text('Erneut versuchen'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _buildDetail(context, snapshot.data!);
        },
      ),
    );
  }

  Widget _buildDetail(BuildContext context, IservTaskDetail detail) {
    final theme = Theme.of(context);
    final finished = detail.status.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          detail.title.isEmpty ? widget.title : detail.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (finished) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(detail.status),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              if (detail.author.isNotEmpty)
                _InfoRow(
                  icon: Icons.person_outline,
                  label: 'Erstellt von',
                  value: detail.author,
                ),
              if (detail.start.isNotEmpty)
                _InfoRow(
                  icon: Icons.play_circle_outline,
                  label: 'Start',
                  value: detail.start,
                ),
              if (detail.due.isNotEmpty)
                _InfoRow(
                  icon: Icons.event,
                  label: 'Abgabe',
                  value: detail.due,
                  extra: _remaining(detail.dueDate),
                  highlight: !finished,
                ),
            ],
          ),
        ),
        if (detail.description.isNotEmpty) ...[
          const _Heading('Beschreibung'),
          SelectableText(detail.description, style: theme.textTheme.bodyLarge),
        ],
        if (detail.attachments.isNotEmpty) ...[
          _Heading('Dateien (${detail.attachments.length})'),
          for (final attachment in detail.attachments)
            _AttachmentTile(
              attachment: attachment,
              loading: _downloading == attachment.url,
              onTap: _downloading == null
                  ? () => _openAttachment(attachment)
                  : null,
            ),
        ],
        const _Heading('Abgabe'),
        if (detail.submittedFiles.isNotEmpty)
          for (final file in detail.submittedFiles)
            _AttachmentTile(
              attachment: file,
              loading: _downloading == file.url,
              onTap: _downloading == null ? () => _openAttachment(file) : null,
            )
        else
          Text(
            detail.submissionStatus.isEmpty
                ? (finished
                      ? 'Keine Abgabe-Informationen.'
                      : 'Noch nichts abgegeben.')
                : detail.submissionStatus,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (!finished) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openInIserv,
            icon: const Icon(Icons.upload_file),
            label: const Text('In IServ abgeben'),
          ),
        ],
      ],
    );
  }

  /// "in 29 Tagen" / "heute" / "vor 3 Tagen".
  static String? _remaining(DateTime? due) {
    if (due == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    final days = dueDay.difference(today).inDays;
    if (days == 0) return 'heute';
    if (days == 1) return 'morgen';
    if (days > 1) return 'in $days Tagen';
    if (days == -1) return 'gestern';
    return 'vor ${-days} Tagen';
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.extra,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? extra;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: theme.textTheme.bodySmall),
      subtitle: Text(
        extra == null ? value : '$value · $extra',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: highlight ? FontWeight.bold : null,
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.loading,
    this.onTap,
  });

  final IservAttachment attachment;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isPdf = attachment.name.toLowerCase().endsWith('.pdf');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(
          isPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined,
        ),
        title: Text(attachment.name),
        subtitle: attachment.size.isEmpty ? null : Text(attachment.size),
        trailing: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_outlined),
        onTap: onTap,
      ),
    );
  }
}

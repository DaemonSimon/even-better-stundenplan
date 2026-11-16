import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../components/homework_image_viewer.dart';
import '../services/homework_attachments.dart';
import '../services/iserv_mapping.dart';

class LocalHomeworkPage extends StatefulWidget {
  const LocalHomeworkPage({
    super.key,
    required this.subject,
    required this.lessonDate,
    required this.periods,
    this.onChanged,
  });

  final String subject;
  final DateTime lessonDate;
  final List<int> periods;
  final VoidCallback? onChanged;

  @override
  State<LocalHomeworkPage> createState() => _LocalHomeworkPageState();
}

class _LocalHomeworkPageState extends State<LocalHomeworkPage> {
  final _store = TempAssignmentStore();
  List<TempAssignment> _homework = [];
  bool _loading = true;
  String? _error;
  Timer? _cleanupTimer;

  String get _lessonDate =>
      DateFormat('yyyy-MM-dd').format(widget.lessonDate);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final expired = await _store.purgeCompleted();
      for (final task in expired) {
        await HomeworkAttachments.deleteOwned(task.imagePaths);
      }
      final tasks = await _store.load();
      _scheduleCleanup(tasks);
      final matching = tasks.where(
        (task) =>
            task.completedAt == null &&
            task.subject.trim().toLowerCase() ==
                widget.subject.trim().toLowerCase() &&
            task.lessonDate == _lessonDate &&
            task.periods.any(widget.periods.contains),
      );
      if (!mounted) return;
      setState(() {
        _homework = matching.toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Hausaufgaben konnten nicht geladen werden: $error';
        _loading = false;
      });
    }
  }

  void _scheduleCleanup(List<TempAssignment> tasks) {
    _cleanupTimer?.cancel();
    final nextCleanup = TempAssignmentStore.nextCleanupAt(tasks);
    if (nextCleanup == null) return;
    _cleanupTimer = Timer(nextCleanup.difference(DateTime.now()), () {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _addHomework() async {
    final entry = await showDialog<_HomeworkDraft>(
      context: context,
      builder: (context) => const _HomeworkDialog(),
    );
    if (entry == null || !mounted) return;

    List<String> imagePaths = [];
    try {
      imagePaths = await HomeworkAttachments.copyPicked(entry.images);
      await _store.add(
        title: entry.title,
        subject: widget.subject,
        dueDate: _lessonDate,
        description: entry.description,
        imagePaths: imagePaths,
        lessonDate: _lessonDate,
        hour: widget.periods.join('+'),
      );
      widget.onChanged?.call();
      await _load();
    } catch (error) {
      await HomeworkAttachments.deleteOwned(imagePaths);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hausaufgabe konnte nicht gespeichert werden: $error')),
      );
    }
  }

  Future<void> _delete(TempAssignment task) async {
    try {
      await _store.remove(task.id);
      await HomeworkAttachments.deleteOwned(task.imagePaths);
      widget.onChanged?.call();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hausaufgabe konnte nicht gelöscht werden: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.subject} · ${widget.periods.join('+')}. Stunde',
        ),
        actions: [
          IconButton(
            tooltip: 'Hausaufgabe hinzufügen',
            onPressed: _addHomework,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : _homework.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Für diese Stunde gibt es noch keine Hausaufgaben.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _addHomework,
                    icon: const Icon(Icons.add),
                    label: const Text('Hausaufgabe eintragen'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final task in _homework)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  task.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        decoration: task.completedAt == null
                                            ? null
                                            : TextDecoration.lineThrough,
                                      ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Löschen',
                                onPressed: () => _delete(task),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          if (task.description.isNotEmpty)
                            Text(task.description),
                          if (task.imagePaths.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 100,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: task.imagePaths.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) => GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      fullscreenDialog: true,
                                      builder: (_) => HomeworkImageViewer(
                                        path: task.imagePaths[index],
                                      ),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(task.imagePaths[index]),
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox(
                                            width: 100,
                                            child: Icon(
                                              Icons.broken_image_outlined,
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _HomeworkDraft {
  const _HomeworkDraft({
    required this.title,
    required this.description,
    required this.images,
  });

  final String title;
  final String description;
  final List<XFile> images;
}

class _HomeworkDialog extends StatefulWidget {
  const _HomeworkDialog();

  @override
  State<_HomeworkDialog> createState() => _HomeworkDialogState();
}

class _HomeworkDialogState extends State<_HomeworkDialog> {
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final List<XFile> _images = [];
  bool _picking = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (mounted) setState(() => _images.addAll(picked));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotos konnten nicht geöffnet werden: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Hausaufgabe eingeben')),
      );
      return;
    }
    Navigator.pop(
      context,
      _HomeworkDraft(
        title: title,
        description: _description.text.trim(),
        images: List<XFile>.of(_images),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hausaufgabe eintragen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Hausaufgabe *'),
            ),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _picking ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_picking ? 'Fotos werden geöffnet' : 'Bilder hinzufügen'),
              ),
            ),
            if (_images.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final image in _images)
                    Image.file(
                      File(image.path),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                ],
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
          onPressed: _save,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

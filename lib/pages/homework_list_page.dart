import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/klassenbuch_api.dart';
import '../services/klassenbuch_parser.dart';

const _channel = MethodChannel('in.eike.better_stundenplan/homework');

class HomeworkListPage extends StatefulWidget {
  const HomeworkListPage({
    super.key,
    required this.subject,
    this.sessionId,
    this.klassenbuchApi,
  });

  final String subject;
  final String? sessionId;
  final KlassenbuchApi? klassenbuchApi;

  @override
  State<HomeworkListPage> createState() => _HomeworkListPageState();
}

class _HomeworkListPageState extends State<HomeworkListPage> {
  late final KlassenbuchApi _klassenbuchApi =
      widget.klassenbuchApi ?? KlassenbuchApi();
  late final KlassenbuchParser _parser = KlassenbuchParser();

  List<Map<String, dynamic>> _homework = [];
  List<Map<String, dynamic>> _klassenbuch = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _klassenbuchApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _loadUserHomework(),
        _loadKlassenbuchHomework(),
      ]);
      if (!mounted) return;
      setState(() {
        _homework = results[0];
        _klassenbuch = results[1];
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Fehler beim Laden');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadUserHomework() async {
    try {
      final result = await _channel.invokeMethod('getHomework', {
        'subject': widget.subject,
      });
      if (result == null) return [];
      final items = result as List;
      return [
        for (final item in items)
          if (item is Map)
            {
              for (final entry in item.entries) entry.key.toString(): entry.value,
            },
      ];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadKlassenbuchHomework() async {
    final sessionId = widget.sessionId;
    if (sessionId == null || sessionId.isEmpty) return [];
    try {
      final response = await _klassenbuchApi.fetchKlassenbuch(sessionId);
      if (response.statusCode != 200 || response.isRedirect) return [];
      final entries = _parser.parseHomework(response.body);
      final subject = widget.subject.trim().toLowerCase();
      if (subject.isEmpty) return [];
      return [
        for (final entry in entries)
          if (entry.subject.trim().toLowerCase() == subject) entry.toMap(),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(theme, scheme),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme scheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _load,
                child: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }
    final total = _klassenbuch.length + _homework.length;
    if (total == 0) {
      return Center(
        child: Text(
          'keine eingetragenen Hausaufgaben',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: total,
        itemBuilder: (context, index) {
          if (index < _klassenbuch.length) {
            return _KlassenbuchCard(homework: _klassenbuch[index]);
          }
          return _UserHomeworkCard(homework: _homework[index - _klassenbuch.length]);
        },
      ),
    );
  }
}

class _KlassenbuchCard extends StatelessWidget {
  const _KlassenbuchCard({required this.homework});
  final Map<String, dynamic> homework;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = homework['content'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          content,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _UserHomeworkCard extends StatelessWidget {
  const _UserHomeworkCard({required this.homework});
  final Map<String, dynamic> homework;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = homework['content'] as String? ?? '';
    final author = homework['author_id'] as String? ?? '';
    final imagePath = homework['image_path'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(content, style: theme.textTheme.bodyMedium),
            ),
          if (author.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                author,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (imagePath != null && imagePath.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _openImage(context, imagePath),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imagePath,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openImage(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ZoomableImagePage(url: url),
      ),
    );
  }
}

class _ZoomableImagePage extends StatelessWidget {
  const _ZoomableImagePage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 5.0,
          child: SizedBox(
            width: screenSize.width,
            child: Image.network(
              url,
              fit: BoxFit.fitWidth,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image,
                size: 64,
                color: Colors.white38,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

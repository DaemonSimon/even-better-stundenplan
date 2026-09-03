import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('in.eike.better_stundenplan/homework');

class AddHomeworkPage extends StatefulWidget {
  const AddHomeworkPage({
    super.key,
    required this.subject,
    required this.authorId,
  });

  final String subject;
  final String authorId;

  @override
  State<AddHomeworkPage> createState() => _AddHomeworkPageState();
}

class _AddHomeworkPageState extends State<AddHomeworkPage> {
  final _controller = TextEditingController();
  String? _imagePath;
  bool _isSubmitting = false;
  bool _isTakingPicture = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    setState(() => _isTakingPicture = true);
    try {
      final path = await _channel.invokeMethod<String>('takePicture');
      if (path != null && mounted) {
        setState(() => _imagePath = path);
      }
    } on PlatformException {
      // User denied or camera error — stay on page.
    } catch (_) {
      // MethodChannel not available (e.g. in tests).
    } finally {
      if (mounted) setState(() => _isTakingPicture = false);
    }
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Beschreibung eingeben')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await _channel.invokeMethod('submitHomework', {
        'subject': widget.subject,
        'author_id': widget.authorId,
        'content': content,
        'image_path': _imagePath,
      });
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hausaufgabe geteilt')),
        );
        Navigator.of(context).pop(true);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            maxLines: 5,
            minLines: 3,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'Was ist die Hausaufgabe?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Image.file(
                    File(_imagePath!),
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      onPressed: () => setState(() => _imagePath = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isTakingPicture ? null : _takePicture,
                icon: _isTakingPicture
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt, size: 18),
                label: const Text('Foto'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 18),
                label: const Text('Absenden'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

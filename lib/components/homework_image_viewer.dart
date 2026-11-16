import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeworkImageViewer extends StatefulWidget {
  const HomeworkImageViewer({super.key, required this.path});

  final String path;

  @override
  State<HomeworkImageViewer> createState() => _HomeworkImageViewerState();
}

class _HomeworkImageViewerState extends State<HomeworkImageViewer> {
  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
  }

  @override
  void dispose() {
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.file(
            File(widget.path),
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              size: 64,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

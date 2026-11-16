import 'package:flutter/material.dart';

import '../services/subject_names.dart';

class SubjectNameLabel extends StatefulWidget {
  const SubjectNameLabel({
    super.key,
    required this.raw,
    this.stripGroup = false,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String raw;
  final bool stripGroup;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<SubjectNameLabel> createState() => _SubjectNameLabelState();
}

class _SubjectNameLabelState extends State<SubjectNameLabel> {
  late Future<String> _name;

  @override
  void initState() {
    super.initState();
    _name = _loadName();
    SubjectNames.revision.addListener(_reloadName);
  }

  @override
  void didUpdateWidget(SubjectNameLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raw != widget.raw ||
        oldWidget.stripGroup != widget.stripGroup) {
      _name = _loadName();
    }
  }

  @override
  void dispose() {
    SubjectNames.revision.removeListener(_reloadName);
    super.dispose();
  }

  Future<String> _loadName() =>
      SubjectNames.displayName(widget.raw, stripGroup: widget.stripGroup);

  void _reloadName() {
    if (!mounted) return;
    setState(() => _name = _loadName());
  }

  @override
  Widget build(BuildContext context) {
    final fallback = SubjectNames.fallbackDisplayName(
      widget.raw,
      stripGroup: widget.stripGroup,
    );
    return FutureBuilder<String>(
      future: _name,
      initialData: fallback,
      builder: (context, snapshot) => Text(
        snapshot.data ?? fallback,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        style: widget.style,
      ),
    );
  }
}

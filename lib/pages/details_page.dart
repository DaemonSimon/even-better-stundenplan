import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/subject_colors.dart';

class DetailsPage extends StatefulWidget {
  const DetailsPage({
    super.key,
    required this.lesson,
    required this.teacher,
    required this.room,
    required this.date,
    required this.hour,
  });

  final String lesson;
  final String teacher;
  final String room;
  final String date;
  final String hour;

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  late final TextEditingController _fachController;
  late final TextEditingController _lehrerController;
  late final TextEditingController _raumController;

  bool _editingFach = false;
  bool _editingLehrer = false;
  bool _editingRaum = false;

  @override
  void initState() {
    super.initState();
    _fachController = TextEditingController(text: widget.lesson);
    _lehrerController = TextEditingController(text: widget.teacher);
    _raumController = TextEditingController(text: widget.room);
    _loadEditedNames();
  }

  @override
  void dispose() {
    _fachController.dispose();
    _lehrerController.dispose();
    _raumController.dispose();
    super.dispose();
  }

  /// Baut den Alias-Schlüssel für ein Feld (Fach/Lehrer/Raum) auf, damit
  /// gleiche Originalwerte verschiedener Felder sich nicht überschreiben.
  String _aliasKey(String field, String original) => 'alias:$field:$original';

  Future<void> _loadEditedNames() async {
    final results = await Future.wait([
      getEditedName('fach', widget.lesson),
      getEditedName('lehrer', widget.teacher),
      getEditedName('raum', widget.room),
    ]);
    if (!mounted) return;
    setState(() {
      _fachController.text = results[0];
      _lehrerController.text = results[1];
      _raumController.text = results[2];
    });
  }

  Future<String> getEditedName(String field, String original) async {
    final prefs = await SharedPreferences.getInstance();
    final prefixed = prefs.getString(_aliasKey(field, original));
    if (prefixed != null) return prefixed;

    // Migration alter, nicht-namespaced Aliase
    final legacy = prefs.getString(original);
    if (legacy != null) {
      await prefs.setString(_aliasKey(field, original), legacy);
      return legacy;
    }
    return original;
  }

  Future<void> _toggleEdit(
    String field,
    bool isEditing,
    TextEditingController controller,
    String original,
  ) async {
    if (isEditing) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_aliasKey(field, original), controller.text);
    }
    setState(() {
      switch (field) {
        case 'fach':
          _editingFach = !_editingFach;
        case 'lehrer':
          _editingLehrer = !_editingLehrer;
        case 'raum':
          _editingRaum = !_editingRaum;
      }
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Kopiert: $text')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text("Details"),
      ),
      body: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Column(
              children: [
                _buildFieldRow(
                  icon: Icons.book,
                  label: 'Fach',
                  controller: _fachController,
                  isEditing: _editingFach,
                  iconColor: SubjectColors.forSubject(widget.lesson),
                  onToggle: () => _toggleEdit(
                    'fach',
                    _editingFach,
                    _fachController,
                    widget.lesson,
                  ),
                ),
                _buildFieldRow(
                  icon: Icons.person,
                  label: 'Lehrkraft',
                  controller: _lehrerController,
                  isEditing: _editingLehrer,
                  onToggle: () => _toggleEdit(
                    'lehrer',
                    _editingLehrer,
                    _lehrerController,
                    widget.teacher,
                  ),
                ),
                _buildFieldRow(
                  icon: Icons.meeting_room,
                  label: 'Raum',
                  controller: _raumController,
                  isEditing: _editingRaum,
                  onToggle: () => _toggleEdit(
                    'raum',
                    _editingRaum,
                    _raumController,
                    widget.room,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${widget.hour}. Stunde - ${widget.date}"),
                IconButton(
                  tooltip: 'Stunde kopieren',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyToClipboard(
                    '${widget.hour}. Stunde - ${widget.date}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required bool isEditing,
    required VoidCallback onToggle,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Icon(icon, size: 30, color: iconColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16)),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        enabled: isEditing,
                        controller: controller,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(width: 1),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(width: 2),
                          ),
                          disabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(width: 1),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: isEditing ? 'Speichern' : 'Bearbeiten',
                      icon: Icon(isEditing ? Icons.save : Icons.edit, size: 20),
                      onPressed: onToggle,
                    ),
                    IconButton(
                      tooltip: 'Wert kopieren',
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () =>
                          _copyToClipboard(controller.text.trim()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
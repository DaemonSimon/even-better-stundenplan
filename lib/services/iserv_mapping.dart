import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'iserv_tasks.dart';

/// Mapping von Aufgaben auf Stundenplan-Blöcke ("Mo.1" … "Fr.4").
///
/// Auflösungsreihenfolge pro Aufgabe:
/// 1. manuelles Override nach Task-Key
/// 2. manuelles Override nach Fach (`subject:<name>`)
/// 3. Default-Fach-Map
/// 4. kein Slot (unzugeordnet)
class IservMappingEngine {
  IservMappingEngine();

  static const String _prefsKey = 'iserv_mappings';

  /// Persistierte Overrides: task_key -> slot.
  Map<String, String> _overrides = {};

  static const List<String> days = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
  static const List<int> blocks = [1, 2, 3, 4];

  static List<String> availableSlots() => [
    for (final day in days)
      for (final block in blocks) '$day.$block',
  ];

  // Fach-Kürzel -> kanonischer Fachname (für die Normalisierung).
  static const Map<String, String> _subjectAliases = {
    'ma': 'mathematik', 'math': 'mathematik', 'mathe': 'mathematik',
    'de': 'deutsch', 'deu': 'deutsch',
    'en': 'englisch', 'eng': 'englisch',
    'fr': 'französisch', 'frz': 'französisch',
    'sp': 'spanisch', 'span': 'spanisch',
    'lat': 'latein',
    'bio': 'biologie',
    'phy': 'physik', 'phys': 'physik',
    'che': 'chemie', 'chem': 'chemie',
    'inf': 'informatik', 'info': 'informatik',
    'spo': 'sport',
    'kun': 'kunst',
    'mus': 'musik',
    'rel': 'religion', 'evr': 'religion',
    'eth': 'ethik',
    'pae': 'pädagogik', 'ped': 'pädagogik',
    'sow': 'sozialwissenschaften',
    'pol': 'politik', 'po': 'politik', 'pkw': 'politik',
    'ge': 'geschichte', 'ges': 'geschichte',
    'er': 'erdkunde', 'ek': 'erdkunde', 'geo': 'erdkunde',
    'wi': 'wirtschaft', 'bwl': 'wirtschaft', 'vwl': 'wirtschaft',
    'nw': 'naturwissenschaften',
    'wp': 'wahlpflicht', 'wpo': 'wahlpflicht',
  };

  /// Sinnvolle Defaults: Fach -> bevorzugter Block-Slot.
  static const Map<String, String> _defaultSubjectSlots = {
    'mathematik': 'Mo.1',
    'religion': 'Mo.2',
    'deutsch': 'Mo.3',
    'naturwissenschaften': 'Mo.4',
    'englisch': 'Di.1',
    'pädagogik': 'Di.2',
    'biologie': 'Di.3',
    'sozialwissenschaften': 'Di.4',
    'physik': 'Mi.1',
    'kunst': 'Mi.2',
    'chemie': 'Mi.3',
    'wirtschaft': 'Mi.4',
    'informatik': 'Do.1',
    'sport': 'Do.2',
    'geschichte': 'Do.3',
    'französisch': 'Do.4',
    'erdkunde': 'Fr.1',
    'musik': 'Fr.2',
    'politik': 'Fr.3',
    'wahlpflicht': 'Fr.4',
    'spanisch': 'Fr.4',
    'latein': 'Fr.4',
    'ethik': 'Do.2',
  };

  /// Normalisiert einen Fachnamen ("Mathe GK" -> "mathematik") oder "".
  static String normalizeSubject(String subject) {
    var name = subject
        .trim()
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return '';
    final first = name.split(' ').first;
    return _subjectAliases[first] ?? first;
  }

  static String? defaultSlotFor(String subject) {
    final normalized = normalizeSubject(subject);
    return normalized.isEmpty ? null : _defaultSubjectSlots[normalized];
  }

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _overrides =
            (jsonDecode(raw) as Map<String, dynamic>)
                .map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {
      _overrides = {};
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_overrides));
    } catch (_) {}
  }

  /// Slot für eine Aufgabe: Override nach Key, dann nach Fach, dann Default.
  String? slotFor(String taskKey, String subject) {
    final byKey = _overrides[taskKey];
    if (byKey != null) return byKey;
    final normalized = normalizeSubject(subject);
    if (normalized.isNotEmpty) {
      final bySubject = _overrides['subject:$normalized'];
      if (bySubject != null) return bySubject;
      return _defaultSubjectSlots[normalized];
    }
    return null;
  }

  Future<void> setOverride(String taskKey, String slot) async {
    if (!availableSlots().contains(slot)) {
      throw ArgumentError.value(slot, 'slot', 'Ungültiger Slot');
    }
    _overrides[taskKey] = slot;
    await _persist();
  }

  Future<void> clearOverride(String taskKey) async {
    _overrides.remove(taskKey);
    await _persist();
  }
}

/// Eine lokale, temporäre Aufgabe (existiert nicht auf IServ).
class TempAssignment {
  const TempAssignment({
    required this.id,
    required this.title,
    this.subject = '',
    this.teacher = '',
    this.dueDate,
    this.description = '',
    this.links = const [],
  });

  final int id;
  final String title;
  final String subject;
  final String teacher;
  final String? dueDate;
  final String description;
  final List<String> links;

  TempAssignment copyWith({
    String? title,
    String? subject,
    String? teacher,
    String? dueDate,
    String? description,
    List<String>? links,
  }) => TempAssignment(
    id: id,
    title: title ?? this.title,
    subject: subject ?? this.subject,
    teacher: teacher ?? this.teacher,
    dueDate: dueDate ?? this.dueDate,
    description: description ?? this.description,
    links: links ?? this.links,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subject': subject,
    'teacher': teacher,
    'due_date': dueDate,
    'description': description,
    'links': links,
  };

  factory TempAssignment.fromJson(Map<String, dynamic> json) =>
      TempAssignment(
        id: json['id'] as int,
        title: json['title'] as String,
        subject: json['subject'] as String? ?? '',
        teacher: json['teacher'] as String? ?? '',
        dueDate: json['due_date'] as String?,
        description: json['description'] as String? ?? '',
        links: [
          for (final link in (json['links'] as List? ?? const []))
            if (link is String) link,
        ],
      );
}

/// Speichert temporäre Aufgaben in SharedPreferences (JSON-Liste).
class TempAssignmentStore {
  TempAssignmentStore();

  static const String _prefsKey = 'iserv_temp_assignments';

  Future<List<TempAssignment>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      return [
        for (final item in jsonDecode(raw) as List)
          if (item is Map<String, dynamic>) TempAssignment.fromJson(item),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<List<TempAssignment>> _save(List<TempAssignment> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode([for (final t in tasks) t.toJson()]),
      );
    } catch (_) {}
    return tasks;
  }

  Future<TempAssignment> add({
    required String title,
    String subject = '',
    String teacher = '',
    String? dueDate,
    String description = '',
    List<String> links = const [],
  }) async {
    final tasks = await load();
    final id = tasks.isEmpty
        ? 1
        : tasks.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
    final task = TempAssignment(
      id: id,
      title: title,
      subject: subject,
      teacher: teacher,
      dueDate: dueDate,
      description: description,
      links: links,
    );
    await _save([...tasks, task]);
    return task;
  }

  Future<List<TempAssignment>> update(TempAssignment task) async {
    final tasks = await load();
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index < 0) return tasks;
    tasks[index] = task;
    return _save(tasks);
  }

  Future<List<TempAssignment>> remove(int id) async {
    final tasks = await load();
    return _save([for (final t in tasks) if (t.id != id) t]);
  }
}

/// Vereinigt IServ- und temporäre Aufgaben zu einem Stream, sortiert
/// nach Abgabedatum (ohne Datum zuletzt), und mappt sie auf Slots.
List<Map<String, dynamic>> mergeTasks({
  required List<IservTask> iservTasks,
  required List<TempAssignment> tempTasks,
  required IservMappingEngine engine,
}) {
  final merged = <Map<String, dynamic>>[];

  for (final task in iservTasks) {
    merged.add({
      'source': 'iserv',
      'key': task.key,
      'title': task.title,
      'subject': task.subject,
      'teacher': task.teacher,
      'due_date': task.dueDate,
      'description': task.description,
      'links': task.links,
      'slot': engine.slotFor(task.key, task.subject),
    });
  }
  for (final task in tempTasks) {
    final key = 'temp:${task.id}';
    merged.add({
      'source': 'temp',
      'key': key,
      'id': task.id,
      'title': task.title,
      'subject': task.subject,
      'teacher': task.teacher,
      'due_date': task.dueDate,
      'description': task.description,
      'links': task.links,
      'slot': engine.slotFor(key, task.subject),
    });
  }

  merged.sort(
    (a, b) => (a['due_date'] as String? ?? '9999-12-31T23:59')
        .compareTo(b['due_date'] as String? ?? '9999-12-31T23:59'),
  );
  return merged;
}
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/timetable.dart';

/// Cache für wöchentliche Stundenpläne: In-Memory mit TTL für schnellen
/// Zugriff und eine JSON-Datei auf der Platte als Offline-Fallback.
///
/// Schlüssel ist der Wochenstart (`dd.MM.yyyy` des Montags); gespeichert
/// wird die gesamte Woche (Mo–Fr).
class TimetableCache {
  TimetableCache({TimetableDiskCache? disk})
    : _disk = disk ?? TimetableDiskCache();

  static const Duration ttl = Duration(minutes: 15);
  static const int maxEntries = 30;

  final Map<String, _CacheEntry> _memory = {};
  final TimetableDiskCache _disk;

  WeeklyTimetable? getFresh(String weekKey) {
    final entry = _memory[weekKey];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > ttl) return null;
    return entry.value;
  }

  WeeklyTimetable? getStale(String weekKey) => _memory[weekKey]?.value;

  Future<WeeklyTimetable?> getFromDisk(String weekKey) => _disk.load(weekKey);

  Future<void> put(String weekKey, WeeklyTimetable value) async {
    _memory[weekKey] = _CacheEntry(value: value, fetchedAt: DateTime.now());

    // Älteste Einträge entfernen, falls die Obergrenze überschritten wird.
    while (_memory.length > maxEntries) {
      _memory.remove(_memory.keys.first);
    }

    await _disk.save(weekKey, value);
  }

  void clear() {
    _memory.clear();
  }
}

class _CacheEntry {
  const _CacheEntry({required this.value, required this.fetchedAt});

  final WeeklyTimetable value;
  final DateTime fetchedAt;
}

/// Plattenbasierter Cache als JSON-Datei mit begrenzter Anzahl Wochen.
class TimetableDiskCache {
  static const int _maxWeeks = 14;
  static const int _dayCount = 5;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/timetable_cache.json');
  }

  Future<void> save(String weekKey, WeeklyTimetable value) async {
    try {
      final file = await _file();
      final data = <String, dynamic>{};
      if (await file.exists()) {
        final existing = jsonDecode(await file.readAsString());
        if (existing is Map<String, dynamic>) {
          data.addAll(existing);
        }
      }
      data[weekKey] = _weekToJson(value);

      // Nur die neuesten Wochen behalten.
      final keys = data.keys.toList();
      while (keys.length > _maxWeeks) {
        data.remove(keys.removeAt(0));
      }

      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // Cache ist optional; Fehler ignorieren.
    }
  }

  Future<WeeklyTimetable?> load(String weekKey) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return null;
      final entry = data[weekKey];
      if (entry is! Map<String, dynamic>) return null;
      return _weekFromJson(entry);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _weekToJson(WeeklyTimetable value) => {
    'weekStart': value.weekStart.toIso8601String(),
    'days': [
      for (int i = 0; i < value.days.length && i < _dayCount; i++)
        value.days[i].toJson(),
    ],
  };

  WeeklyTimetable _weekFromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List<dynamic>? ?? [];
    return WeeklyTimetable(
      weekStart:
          json['weekStart'] is String
              ? DateTime.parse(json['weekStart'] as String)
              : DateTime.now(),
      days: rawDays
          .whereType<Map<String, dynamic>>()
          .map(DailyTimetable.fromJson)
          .toList(),
    );
  }
}

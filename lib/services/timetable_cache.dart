import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/timetable.dart';

/// Cache für tägliche Stundenpläne: In-Memory mit TTL für schnellen Zugriff
/// und eine JSON-Datei auf der Platte als Offline-Fallback.
class TimetableCache {
  TimetableCache({TimetableDiskCache? disk})
    : _disk = disk ?? TimetableDiskCache();

  static const Duration ttl = Duration(minutes: 15);
  static const int maxEntries = 30;

  final Map<String, _CacheEntry> _memory = {};
  final TimetableDiskCache _disk;

  DailyTimetable? getFresh(String dateKey) {
    final entry = _memory[dateKey];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > ttl) return null;
    return entry.value;
  }

  DailyTimetable? getStale(String dateKey) => _memory[dateKey]?.value;

  Future<DailyTimetable?> getFromDisk(String dateKey) => _disk.load(dateKey);

  Future<void> put(String dateKey, DailyTimetable value) async {
    _memory[dateKey] = _CacheEntry(value: value, fetchedAt: DateTime.now());

    // Älteste Einträge entfernen, falls die Obergrenze überschritten wird.
    while (_memory.length > maxEntries) {
      _memory.remove(_memory.keys.first);
    }

    await _disk.save(dateKey, value);
  }

  void clear() {
    _memory.clear();
  }
}

class _CacheEntry {
  const _CacheEntry({required this.value, required this.fetchedAt});

  final DailyTimetable value;
  final DateTime fetchedAt;
}

/// Plattenbasierter Cache als JSON-Datei mit begrenzter Anzahl Tagen.
class TimetableDiskCache {
  static const int _maxDays = 14;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/timetable_cache.json');
  }

  Future<void> save(String dateKey, DailyTimetable value) async {
    try {
      final file = await _file();
      final data = <String, dynamic>{};
      if (await file.exists()) {
        final existing = jsonDecode(await file.readAsString());
        if (existing is Map<String, dynamic>) {
          data.addAll(existing);
        }
      }
      data[dateKey] = value.toJson();

      // Nur die neuesten Tage behalten.
      final keys = data.keys.toList();
      while (keys.length > _maxDays) {
        data.remove(keys.removeAt(0));
      }

      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // Cache ist optional; Fehler ignorieren.
    }
  }

  Future<DailyTimetable?> load(String dateKey) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return null;
      final entry = data[dateKey];
      if (entry is! Map<String, dynamic>) return null;
      return DailyTimetable.fromJson(entry);
    } catch (_) {
      return null;
    }
  }
}
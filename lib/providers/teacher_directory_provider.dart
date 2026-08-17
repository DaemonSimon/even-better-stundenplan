import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/teacher_directory.dart';

/// Stellt das Kollegiums-Verzeichnis (Kürzel -> voller Name, E-Mail)
/// für die UI bereit.
///
/// Lädt zuerst einen evtl. vorhandenen Platten-Cache (offline-tauglich)
/// und aktualisiert dann vom Netz. Solange das Verzeichnis leer ist,
/// gibt [resolve] einfach das Kürzel zurück.
class TeacherDirectoryProvider extends ChangeNotifier {
  TeacherDirectoryProvider({
    TeacherDirectory? directory,
    Map<String, TeacherEntry>? initialEntries,
  }) : _directory = directory ?? TeacherDirectory(),
       _entries = {
         if (initialEntries != null)
           for (final entry in initialEntries.entries)
             entry.key.trim().toUpperCase(): entry.value,
       };

  static const String _prefsKey = 'teacher_directory_cache';

  final TeacherDirectory _directory;

  Map<String, TeacherEntry> _entries;
  Future<void>? _inFlight;

  /// Liefert den Eintrag zu einem Kürzel (case-insensitive) – sonst null.
  /// Einträge mit Präfix ("A:KREP") werden über den Teil nach dem
  /// Doppelpunkt aufgelöst.
  TeacherEntry? lookup(String kuerzel) {
    final normalized = kuerzel.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    final direct = _entries[normalized];
    if (direct != null) return direct;
    final split = splitTeacherPrefix(kuerzel);
    if (split.prefix != null) {
      return _entries[split.kuerzel.toUpperCase()];
    }
    return null;
  }

  /// Anzeigename zum Rohtext; ein Präfix ("A:KREP") bleibt erhalten
  /// ("A: Helga Müller"). Fallback ist der Rohtext selbst.
  String resolve(String kuerzel) {
    final entry = lookup(kuerzel);
    if (entry == null) return kuerzel;
    final split = splitTeacherPrefix(kuerzel);
    return split.prefix == null
        ? entry.fullName
        : '${split.prefix}: ${entry.fullName}';
  }

  /// Lädt das Verzeichnis (Platten-Cache, dann Netz). Idempotent.
  Future<void> load() => _inFlight ??= _doLoad();

  Future<void> _doLoad() async {
    final cached = await _loadFromDisk();
    if (cached != null && cached.isNotEmpty) {
      _entries = cached;
      notifyListeners();
    }

    try {
      final fresh = await _directory.fetch();
      _entries = fresh;
      await _saveToDisk(fresh);
      notifyListeners();
    } catch (_) {
      // Offline oder Serverfehler: Cache-Einträge behalten.
    }
  }

  Future<Map<String, TeacherEntry>?> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final entries = <String, TeacherEntry>{};
      for (final item in list.cast<Map<String, dynamic>>()) {
        final entry = TeacherEntry.fromJson(item);
        entries[entry.kuerzel.trim().toUpperCase()] = entry;
      }
      return entries;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToDisk(Map<String, TeacherEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final entry in entries.values) entry.toJson()]),
    );
  }
}
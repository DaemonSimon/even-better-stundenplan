import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubjectNames {
  SubjectNames._();

  static const Map<String, String> _defaultNames = {
    'DE': 'Deutsch',
    'DEU': 'Deutsch',
    'SP': 'Sport',
    'SPO': 'Sport',
    'EN': 'Englisch',
    'ENG': 'Englisch',
    'MA': 'Mathe',
    'MAT': 'Mathe',
    'MATHE': 'Mathe',
    'PO': 'Politik',
    'POL': 'Politik',
    'PH': 'Physik',
    'PHY': 'Physik',
    'PHYS': 'Physik',
  };

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static String _baseSubject(String raw) {
    final trimmed = raw.trim();
    final colon = trimmed.indexOf(':');
    if (colon == 1 && RegExp(r'^[A-Za-z]$').hasMatch(trimmed[0])) {
      return trimmed.substring(colon + 1).trim();
    }
    return trimmed;
  }

  static String _groupPrefix(String raw) {
    final trimmed = raw.trim();
    final colon = trimmed.indexOf(':');
    if (colon == 1 && RegExp(r'^[A-Za-z]$').hasMatch(trimmed[0])) {
      return '${trimmed[0].toUpperCase()}:';
    }
    return '';
  }

  static String subjectKey(String raw) => _baseSubject(raw).toUpperCase();

  static String defaultName(String raw) {
    final subject = _baseSubject(raw);
    final match = RegExp(r'^([A-Za-z]+)(.*)$').firstMatch(subject);
    if (match == null) return subject;
    final name = _defaultNames[match.group(1)!.toUpperCase()];
    if (name == null) return subject;
    return '$name${match.group(2)}';
  }

  static String fallbackDisplayName(String raw, {bool stripGroup = false}) {
    final name = defaultName(raw);
    final prefix = stripGroup ? '' : _groupPrefix(raw);
    return '$prefix$name';
  }

  static Future<String> displayName(
    String raw, {
    bool stripGroup = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'alias:fach:${subjectKey(raw)}';
    var name = prefs.getString(key);

    // Read aliases saved by older versions, which included the group prefix.
    final oldKey = 'alias:fach:${raw.trim()}';
    if (name == null && oldKey != key) {
      name = prefs.getString(oldKey);
    }
    if (name == null) {
      name = prefs.getString(raw.trim());
      if (name != null) await prefs.setString(key, name);
    }

    final resolved = name == null || name.trim().isEmpty
        ? defaultName(raw)
        : name.trim();
    final prefix = stripGroup ? '' : _groupPrefix(raw);
    return '$prefix$resolved';
  }

  static Future<void> saveAlias(String raw, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'alias:fach:${subjectKey(raw)}';
    final alias = value.trim();
    if (alias.isEmpty || alias == defaultName(raw)) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, alias);
    }
    revision.value++;
  }
}

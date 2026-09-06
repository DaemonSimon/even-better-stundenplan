import 'package:shared_preferences/shared_preferences.dart';

/// Ablage der Kursgruppe des Nutzers (z. B. "A"/"B"), damit die Tests eine
/// In-Memory-Implementierung verwenden können (Regel 5).
abstract class GroupPreferenceStore {
  Future<String?> getGroup();
  Future<void> saveGroup(String? group);
}

/// Persistiert die Kursgruppe als normale (nicht-sensible) Einstellung in
/// SharedPreferences.
class SharedPreferencesGroupStore implements GroupPreferenceStore {
  static const String _key = 'timetable.group';

  @override
  Future<String?> getGroup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> saveGroup(String? group) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = group?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, normalized);
    }
  }
}
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Schnittstelle für die Ablage der Zugangsdaten, damit der SessionManager
/// in Tests mit einer In-Memory-Implementierung verwendet werden kann.
abstract class CredentialStorage {
  Future<String?> getSessionId();
  Future<String?> getEmail();
  Future<String?> getPassword();
  Future<void> saveSessionId(String sessionId);
  Future<void> saveCredentials({
    required String email,
    required String password,
  });
  Future<void> clear();
}

/// Verschlüsselte Ablage für Zugangsdaten (Android Keystore / iOS Keychain)
/// inklusive Migration aus der alten, unverschlüsselten SharedPreferences-Ablage.
class SecureCredentialStorage implements CredentialStorage {
  SecureCredentialStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'sessionId';
  static const String _emailKey = 'email';
  static const String _passwordKey = 'password';

  // Schlüssel der alten SharedPreferences-Ablage (inkl. Tippfehler-Variante)
  static const List<String> _legacyPrefsKeys = [
    'sessionId',
    'email',
    'password',
    'passowrd',
  ];

  @override
  Future<String?> getSessionId() => _storage.read(key: _sessionKey);

  @override
  Future<String?> getEmail() => _storage.read(key: _emailKey);

  @override
  Future<String?> getPassword() => _storage.read(key: _passwordKey);

  @override
  Future<void> saveSessionId(String sessionId) =>
      _storage.write(key: _sessionKey, value: sessionId);

  @override
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }

  /// Übernimmt vorhandene Zugangsdaten aus SharedPreferences in die
  /// verschlüsselte Ablage und löscht sie anschließend dort.
  Future<void> migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _legacyPrefsKeys) {
        final value = prefs.getString(key);
        if (value != null && value.isNotEmpty) {
          await _storage.write(key: key, value: value);
          await prefs.remove(key);
        }
      }
    } catch (_) {
      // Migration ist optional; im Fehlerfall nicht blockieren.
    }
  }
}

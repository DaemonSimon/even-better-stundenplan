import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'secure_storage.dart';

/// Verwaltet Anmeldung, Sitzung und Abmeldung gegenüber virtueller-stundenplan.org.
class SessionManager extends ChangeNotifier {
  SessionManager({required CredentialStorage storage, http.Client? client})
    : _storage = storage,
      _client = client ?? http.Client();

  final CredentialStorage _storage;
  final http.Client _client;

  static const String _baseLoginUrl =
      'https://virtueller-stundenplan.org/index.php';
  static const String _userAgent =
      'BetterStundenplan/1.3.1 (+https://github.com/LarvenStein/better-stundenplan)';

  bool _isLoggedIn = false;
  String? _sessionId;

  bool get isLoggedIn => _isLoggedIn;

  String? get sessionId => _sessionId;

  /// Prüft, ob die gespeicherte Sitzung noch gültig ist.
  /// Eine gültige Sitzung liefert die Stundenplan-Seite; abgelaufene
  /// Sitzungen werden per Redirect zur Login-Seite geschickt.
  Future<bool> checkAuthentication() async {
    final storedSessionId = await _storage.getSessionId();
    if (storedSessionId == null || storedSessionId.isEmpty) {
      _setLoggedIn(false);
      _sessionId = null;
      return false;
    }

    // Beliebiges Datum: entscheidend ist nur, ob ein Redirect kommt.
    final checkUrl =
        'https://virtueller-stundenplan.org/page2/index.php'
        '?KlaBuDatum=${DateFormat('dd.MM.yyyy').format(DateTime.now())}&RES=';

    try {
      final request = http.Request('GET', Uri.parse(checkUrl));
      request.followRedirects = false;
      request.headers['Cookie'] = 'PHPSESSID=$storedSessionId';
      request.headers['User-Agent'] = _userAgent;
      final response = await _client.send(request);

      final valid = !response.isRedirect;
      _sessionId = valid ? storedSessionId : null;
      _setLoggedIn(valid);
      return valid;
    } catch (_) {
      _setLoggedIn(false);
      _sessionId = null;
      return false;
    }
  }

  /// Meldet mit E-Mail und Passwort an.
  /// Zugangsdaten werden optional gespeichert, damit eine erneute Anmeldung
  /// ohne erneute Eingabe möglich ist.
  Future<bool> login({
    required String email,
    required String password,
    bool saveCredentials = true,
  }) async {
    try {
      final newSessionId = await _authenticate(email, password);
      if (newSessionId == null) {
        _setLoggedIn(false);
        return false;
      }

      await _storage.saveSessionId(newSessionId);
      if (saveCredentials) {
        await _storage.saveCredentials(email: email, password: password);
      }
      _sessionId = newSessionId;
      _setLoggedIn(true);
      return true;
    } catch (_) {
      _setLoggedIn(false);
      return false;
    }
  }

  /// Versucht, sich mit den gespeicherten Zugangsdaten erneut anzumelden.
  Future<bool> tryReAuthenticate() async {
    final email = await _storage.getEmail();
    final password = await _storage.getPassword();
    if (email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty) {
      return false;
    }
    return login(email: email, password: password, saveCredentials: false);
  }

  /// Meldet ab und entfernt alle gespeicherten Zugangsdaten.
  Future<void> logout() async {
    await _storage.clear();
    _sessionId = null;
    _setLoggedIn(false);
  }

  /// Führt den Login-Request aus und extrahiert die Sitzungs-ID.
  Future<String?> _authenticate(String email, String password) async {
    final request = http.Request('POST', Uri.parse(_baseLoginUrl));
    request.followRedirects = true;

    final encodedBody = {
      'MAIL': Uri.encodeComponent(email),
      'SCHUELERCODE': Uri.encodeComponent(password),
      'formAction': 'login',
      'formName': 'stacks_in_368_page1',
    };
    request.body = encodedBody.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    request.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    request.headers['User-Agent'] = _userAgent;

    final response = await _client.send(request);

    // Bei falschen Zugangsdaten liefert der Server einen Redirect auf die
    // Basis-URL; dann ist kein Set-Cookie zu erwarten.
    if (response.headers.containsValue(
      'https://virtueller-stundenplan.org:443/',
    )) {
      return null;
    }

    // Sitzungs-ID aus dem Set-Cookie-Header extrahieren
    final setCookieHeader = response.headers['set-cookie'];
    if (setCookieHeader == null) return null;
    final cookies = setCookieHeader.split(',');
    for (final cookie in cookies) {
      if (cookie.trim().startsWith('PHPSESSID=')) {
        return cookie.split(';')[0].split('=')[1];
      }
    }
    return null;
  }

  void _setLoggedIn(bool value) {
    if (_isLoggedIn != value) {
      _isLoggedIn = value;
      notifyListeners();
    }
  }
}
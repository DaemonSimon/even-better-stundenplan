import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Fehler bei der Kommunikation mit IServ.
class IservException implements Exception {
  const IservException(this.message);

  final String message;

  @override
  String toString() => message;
}

class IservLoginException extends IservException {
  const IservLoginException(super.message);
}

/// Cookie-basierte IServ-Session direkt in der App.
///
/// Der Login folgt den Redirects manuell, sammelt dabei die Session-Cookies
/// (Set-Cookie-Header) und schickt sie bei jedem Folge-Request mit.
/// Die Cookies werden in SharedPreferences gespeichert, damit die Session
/// einen App-Neustart überlebt.
///
/// Unterstützt sowohl ältere IServ-Versionen mit CSRF-`_token` als auch
/// neuere (OAuth2-/`/iserv/auth/login`-basiert) ohne Token.
class IservSession {
  IservSession({
    http.Client? client,
    this.baseUrl = 'https://bbs-papenburg.eu/iserv',
  }) : _client = client ?? http.Client();

  static const String _prefsKey = 'iserv_cookies';

  final http.Client _client;
  final String baseUrl;

  final Map<String, String> _cookies = {};

  /// Debug-Log der letzten HTTP-Hops (für Fehleranzeige in der App).
  final List<String> requestLog = [];

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _cookies
          ..clear()
          ..addAll(
            Map.fromEntries(
              data.entries
                  .map((e) => MapEntry(e.key, e.value.toString()))
                  .where(
                    (e) =>
                        e.value.isNotEmpty &&
                        !e.key.contains(';') &&
                        !e.key.contains(',') &&
                        !e.key.contains(' ') &&
                        !e.key.contains('='),
                  ),
            ),
          );
      }
    } catch (_) {
      // Ohne SharedPreferences (Tests) startet die Session leer.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_cookies));
    } catch (_) {
      // Ohne SharedPreferences (Tests) wird nichts gespeichert.
    }
  }

  Future<void> clear() async {
    _cookies.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  String _cookieHeader() => _cookies.entries
      .map((e) => '${e.key}=${e.value}')
      .join('; ');

  Uri _resolve(String path) =>
      path.startsWith('/') ? Uri.parse('$baseUrl$path') : Uri.parse(path);

  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Map<String, String>? form,
  }) async {
    var current = uri;
    var requestMethod = method;
    var requestForm = form;
    for (var i = 0; i < 10; i++) {
      final request = http.Request(requestMethod, current);
      // IServ weist Anfragen ohne Browser-Header mit HTTP 401 ab.
      request.headers['user-agent'] =
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
      request.headers['accept'] =
          'text/html,application/xhtml+xml,application/xml;q=0.9,'
          'image/avif,image/webp,*/*;q=0.8';
      request.headers.addAll(headers ?? const {});
      if (_cookies.isNotEmpty) {
        request.headers['cookie'] = _cookieHeader();
      }
      if (requestForm != null) {
        request.headers['content-type'] =
            'application/x-www-form-urlencoded';
        request.body = requestForm.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}='
                  '${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&');
      }

      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      _captureCookies(response.headers['set-cookie']);

      requestLog.add(
        '[$i] $requestMethod ${response.statusCode} '
        '${current.host}${current.path}'
        '${current.query.isNotEmpty ? '?${current.query.length > 60 ? '${current.query.substring(0, 60)}…' : current.query}' : ''}'
        ' | cookie: ${_cookies.keys.join(',')}'
        '${response.headers['set-cookie'] != null ? ' | set-cookie: ${response.headers['set-cookie']!.split(';').first}' : ''}',
      );
      if (requestLog.length > 20) {
        requestLog.removeAt(0);
      }

      if (_isRedirect(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) return response;
        current = current.resolve(location);
        // IServ schleppt beim Login POST + Formular durch die 302-Kette
        // innerhalb von /iserv/auth/ (auth/auth -> auth/login -> auth/auth).
        // Außerhalb davon gilt wie im Browser: 301/302/303 -> GET,
        // 307/308 behalten Methode und Formular.
        final targetIsAuth = current.path.contains('/auth/');
        if ((targetIsAuth && requestMethod == 'POST') ||
            response.statusCode == 307 ||
            response.statusCode == 308) {
          requestMethod = method;
          requestForm = form;
        } else {
          requestMethod = 'GET';
          requestForm = null;
        }
        continue;
      }
      // Neuere IServ-Versionen liefern statt HTTP-Redirects eine Seite
      // mit Meta-Refresh (OIDC-Code-Austausch, z. B. auf
      // /iserv/app/authentication/redirect?…&code=…). Der Code-Austausch
      // auf /iserv/app/authentication/redirect funktioniert nur per POST –
      // GET liefert eine Seite, die endlos auf dieselbe URL weiterleitet.
      if (response.statusCode == 200) {
        final metaRefresh = _metaRefreshUrl(response.body);
        if (metaRefresh != null) {
          current = current.resolve(metaRefresh);
          if (current.path.contains('/authentication/redirect')) {
            requestMethod = 'POST';
          } else {
            requestMethod = 'GET';
            requestForm = null;
          }
          continue;
        }
      }
      return response;
    }
    throw const IservException('Zu viele Redirects beim IServ-Abruf');
  }

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  /// Liest die Ziel-URL aus einem Meta-Refresh
  /// (`<meta http-equiv="refresh" content="0;url=…">`). HTML-Entities
  /// (z. B. `&amp;`) werden aufgelöst.
  static String? _metaRefreshUrl(String body) {
    final match = RegExp(
      r'''<meta[^>]*http-equiv=["']?refresh["']?[^>]*>''',
      caseSensitive: false,
    ).firstMatch(body);
    if (match == null) return null;
    final url = RegExp(
      r'''url\s*=\s*["']?([^"'>\s]+)''',
      caseSensitive: false,
    ).firstMatch(match.group(0)!);
    if (url == null) return null;
    final decoded = url.group(1)!.replaceAll('&amp;', '&');
    return decoded.isEmpty ? null : decoded;
  }

  void _captureCookies(String? header) {
    if (header == null || header.isEmpty) return;
    for (final block in _splitCookieBlocks(header)) {
      final eq = block.indexOf('=');
      if (eq <= 0) continue;
      final name = block.substring(0, eq).trim();
      if (_cookieAttributes.contains(name.toLowerCase())) continue;
      var value = block.substring(eq + 1).split(';').first.trim();
      if (value.length >= 2 &&
          value.startsWith('"') &&
          value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isEmpty) continue;
      if (value == 'deleted') {
        _cookies.remove(name);
        continue;
      }
      _cookies[name] = value;
    }
  }

  /// Zerlegt einen Set-Cookie-Header in einzelne Cookie-Blöcke
  /// ("name=value; Attr=…"). Kommas trennen Blöcke, außer innerhalb
  /// eines Expires-Werts ("expires=Fri, 15 Aug 2026 …") oder innerhalb
  /// von Anführungszeichen.
  static List<String> _splitCookieBlocks(String header) {
    final blocks = <String>[];
    var start = 0;
    var inExpiresValue = false;
    var inQuotes = false;
    for (var i = 0; i < header.length; i++) {
      final c = header[i];
      if (inQuotes) {
        if (c == '"') inQuotes = false;
        continue;
      }
      if (c == '"') {
        inQuotes = true;
        continue;
      }
      if (c == ';') {
        inExpiresValue = false;
        continue;
      }
      if (c == ',') {
        if (!inExpiresValue) {
          blocks.add(header.substring(start, i));
          start = i + 1;
        }
        continue;
      }
      if (c == '=') {
        final name = header.substring(start, i).trim().toLowerCase();
        if (name.endsWith('expires') || name.endsWith('max-age')) {
          inExpiresValue = true;
        }
      }
    }
    blocks.add(header.substring(start));
    return blocks;
  }

  static const _cookieAttributes = {
    'path',
    'domain',
    'expires',
    'max-age',
    'secure',
    'httponly',
    'samesite',
    'priority',
  };

  /// Prüft, ob die Session gültig ist: Die IServ-Startseite liefert ohne
  /// gültige Session das Login-Formular, mit gültiger Session die
  /// Dashboard-Seite. Wirft [IservException] bei Netzwerkfehlern.
  Future<bool> isAuthenticated() async {
    try {
      final response = await _request('GET', _resolve('/'));
      final ok = response.statusCode == 200 &&
          !_hasLoginForm(response.body);
      return ok;
    } on IservException {
      rethrow;
    } catch (exc) {
      throw IservException('IServ nicht erreichbar: $exc');
    }
  }

  Future<bool> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw const IservLoginException(
        'Benutzername und Passwort erforderlich',
      );
    }

    final http.Response page;
    try {
      page = await _request('GET', _resolve('/login'));
    } catch (exc) {
      throw IservException('Login-Seite nicht erreichbar: $exc');
    }
    if (page.statusCode >= 400) {
      throw IservException(
        'Login-Seite lieferte HTTP ${page.statusCode}',
      );
    }

    final doc = html.parse(page.body);
    final tokenInput = doc.querySelector('input[name="_token"]');
    final hasForm = doc.querySelector('input[name="_username"]') != null;
    if (tokenInput == null && !hasForm) {
      throw const IservLoginException(
        'Kein Login-Formular gefunden – Basis-URL prüfen',
      );
    }

    final data = <String, String>{
      '_username': username.trim(),
      '_password': password,
      '_remember_me': 'on',
    };
    final token = tokenInput?.attributes['value'];
    if (token != null && token.isNotEmpty) {
      data['_token'] = token;
    }

    // Neuere IServ-Versionen: das Formular postet auf die (finale) URL
    // der Login-Seite, z. B. /iserv/auth/login?_target_path=…
    final loginUrl = page.request?.url ?? _resolve('/login');

    final http.Response response;
    try {
      response = await _request('POST', loginUrl, form: data);
    } on IservLoginException {
      rethrow;
    } catch (exc) {
      // IServ leitet bei falschen Zugangsdaten in eine Endlos-Redirect-
      // Schleife (OIDC: auth/login -> auth/login mit frischem state).
      if (exc.toString().contains('Zu viele Redirects')) {
        throw const IservLoginException(
          'Anmeldung abgelehnt – Zugangsdaten prüfen',
        );
      }
      throw IservException('Anmeldung fehlgeschlagen: $exc');
    }
    if (response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      throw const IservLoginException(
        'Anmeldung abgelehnt – Zugangsdaten prüfen',
      );
    }
    if (response.statusCode == 200 && _hasLoginForm(response.body)) {
      throw const IservLoginException(
        'Anmeldung abgelehnt – Zugangsdaten prüfen',
      );
    }
    if (response.statusCode >= 400) {
      throw IservException(
        'Anmeldung fehlgeschlagen: HTTP ${response.statusCode}',
      );
    }

    // Erfolgreich, sobald wir auf einer Seite ohne Login-Formular
    // gelandet sind – NICHT über /tasks prüfen (existiert auf manchen
    // IServ-Versionen nicht und würde einen Erfolg als Fehler melden).
    await _persist();
    return true;
  }

  Future<void> logout() async {
    try {
      await _request('GET', _resolve('/logout'));
    } catch (_) {
      // Server nicht erreichbar – lokale Cookies trotzdem löschen.
    }
    await clear();
  }

  Future<http.Response> get(String path) =>
      _request('GET', _resolve(path));

  /// Sammelt alle absoluten Modul-Links der Dashboard-Seite (für
  /// Modul-Suche und Debug-Ausgaben). Leer, wenn die Navigation per JS
  /// gerendert wird.
  Future<List<String>> discoverModuleLinks() async {
    try {
      final response = await _request('GET', _resolve('/'));
      if (response.statusCode != 200) return const [];
      final doc = html.parse(response.body);
      final base = Uri.parse(baseUrl);
      final links = <String>[];
      for (final anchor in doc.querySelectorAll('a[href]')) {
        final href = (anchor.attributes['href'] ?? '').trim();
        if (href.isEmpty ||
            href.startsWith('#') ||
            href.startsWith('javascript:')) {
          continue;
        }
        final resolved = base.resolve(href).toString();
        if (!links.contains(resolved)) links.add(resolved);
        if (links.length >= 20) break;
      }
      return links;
    } catch (_) {
      return const [];
    }
  }

  /// Findet den Pfad eines Moduls (z. B. Aufgaben) über die
  /// Links auf der Dashboard-Seite. IServ-Instanzen verwenden
  /// unterschiedliche Modul-URLs – die Navigation verrät die echten.
  Future<String?> discoverModulePath(List<String> keywords) async {
    final links = await discoverModuleLinks();
    final matches = <String>[];
    for (final link in links) {
      final lower = link.toLowerCase();
      if (keywords.any((k) => lower.contains(k))) {
        matches.add(link);
      }
    }
    if (matches.isEmpty) return null;
    // Pfade, die exakt auf ein Keyword enden (z. B. /iserv/tasks),
    // zuerst probieren.
    matches.sort((a, b) {
      bool exact(String url) {
        final path = Uri.parse(url).path.toLowerCase();
        return keywords.any((k) =>
            path.endsWith('/$k') || path.endsWith('/$k/'));
      }

      final ea = exact(a) ? 0 : 1;
      final eb = exact(b) ? 0 : 1;
      return ea - eb;
    });
    return matches.first;
  }

  static bool _hasLoginForm(String body) =>
      html.parse(body).querySelector('input[name="_username"]') != null;
}
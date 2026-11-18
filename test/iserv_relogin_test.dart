import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/services/iserv_session.dart';

const _base = 'https://schule.example.de/iserv';

const _loginPage = '''
<html><body><form method="post">
<input type="hidden" name="_token" value="T">
<input type="text" name="_username"><input type="password" name="_password">
</form></body></html>
''';

/// Kleiner IServ-Server: gültig ist immer nur die zuletzt ausgegebene
/// Session-ID. Mit [rotate] gibt die Startseite bei jedem Aufruf eine neue
/// ID aus (wie IServ bei der Erneuerung).
class _FakeIserv {
  String password = 'geheim';
  String? validSid;
  bool rotate = false;
  int logins = 0;
  int _counter = 0;

  String _newSid() => validSid = 'sid${++_counter}';

  late final MockClient client = MockClient((request) async {
    final path = request.url.path;
    final cookie = request.headers['cookie'] ?? '';
    final authed = validSid != null && cookie.contains('SID=$validSid');
    if (path.endsWith('/login') && request.method == 'GET') {
      return http.Response(_loginPage, 200, request: request);
    }
    if (path.endsWith('/login') && request.method == 'POST') {
      final fields = Uri.splitQueryString(request.body);
      if (fields['_password'] != password) {
        return http.Response('denied', 403);
      }
      logins++;
      return http.Response(
        '',
        302,
        headers: {'location': '/iserv/', 'set-cookie': 'SID=${_newSid()}'},
      );
    }
    if (path.endsWith('/iserv/')) {
      if (!authed) return http.Response(_loginPage, 200, request: request);
      return http.Response(
        '<html><body>Dashboard</body></html>',
        200,
        headers: rotate ? {'set-cookie': 'SID=${_newSid()}'} : const {},
        request: request,
      );
    }
    return http.Response('', 404);
  });
}

void main() {
  late _FakeIserv server;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    server = _FakeIserv();
  });

  Future<IservSession> restored() async {
    final session = IservSession(client: server.client, baseUrl: _base);
    await session.restore();
    return session;
  }

  test('renewed cookies survive an app restart', () async {
    final first = await restored();
    await first.login('schueler', 'geheim');
    server.rotate = true;
    expect(await first.isAuthenticated(), isTrue); // erneuert die ID
    server.rotate = false;

    // "App-Neustart": neue Instanz, liest den gespeicherten Stand.
    final second = await restored();
    expect(await second.isAuthenticated(), isTrue);
  });

  test('two sessions do not overwrite each other with old cookies', () async {
    final calendar = await restored();
    await calendar.login('schueler', 'geheim');
    final tasks = await restored();

    server.rotate = true;
    expect(await tasks.isAuthenticated(), isTrue); // erneuert die ID
    server.rotate = false;

    // Der Kalender nutzt jetzt die erneuerte ID statt seiner alten.
    expect(await calendar.isAuthenticated(), isTrue);
  });

  test('expired session logs in again silently', () async {
    final session = await restored();
    await session.login('schueler', 'geheim');
    server.validSid = 'expired-on-server';

    expect(await session.ensureAuthenticated(), isTrue);
    expect(server.logins, 2);
    expect(await session.isAuthenticated(), isTrue);
  });

  test('changed password stops the silent login', () async {
    final session = await restored();
    await session.login('schueler', 'geheim');
    server.validSid = 'expired-on-server';
    server.password = 'neu';

    expect(await session.ensureAuthenticated(), isFalse);
    // Zugangsdaten wurden verworfen: kein weiterer Versuch.
    expect(await session.ensureAuthenticated(), isFalse);
    expect(server.logins, 1);
  });

  test('logout forgets the saved login', () async {
    final session = await restored();
    await session.login('schueler', 'geheim');
    await session.logout();
    server.validSid = 'expired-on-server';

    final fresh = await restored();
    expect(await fresh.ensureAuthenticated(), isFalse);
  });
}

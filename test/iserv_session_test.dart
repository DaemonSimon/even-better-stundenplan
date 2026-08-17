import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:better_stundenplan/services/iserv_session.dart';
import 'package:better_stundenplan/services/iserv_tasks.dart';

const _username = 'schueler';
const _password = 'geheim123';
const _sessionId = 'abc123xyz';

const _loginPage = '''
<html><body><form action="/login" method="post">
<input type="hidden" name="_token" value="TOKEN123">
<input type="text" name="_username">
<input type="password" name="_password">
</form></body></html>
''';

String _fixtureHtml() => File('test/fixtures/aufgaben_page.html').readAsStringSync();

/// Klassische IServ-Variante: Login-Formular mit CSRF-_token.
MockClient _classicIserv() {
  return MockClient((request) async {
    expect(request.headers['user-agent'], contains('Mozilla/5.0'));
    expect(request.headers['accept'], contains('text/html'));
    if (request.url.path.endsWith('/login') && request.method == 'GET') {
      return http.Response(_loginPage, 200, request: request);
    }
    if (request.url.path.endsWith('/login') && request.method == 'POST') {
      final fields = Uri.splitQueryString(request.body);
      if (fields['_token'] == 'TOKEN123' &&
          fields['_username'] == _username &&
          fields['_password'] == _password) {
        return http.Response(
          '',
          302,
          headers: {
            'location': '/dashboard',
            'set-cookie': 'JSESSIONID=$_sessionId; Path=/',
          },
        );
      }
      return http.Response('denied', 403);
    }
    if (request.url.path.endsWith('/dashboard')) {
      // 302 nach POST muss als GET gefolgt werden.
      expect(request.method, 'GET');
      if (request.headers['cookie']?.contains(_sessionId) ?? false) {
        return http.Response(
          '<html><body>Dashboard</body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
          request: request,
        );
      }
      return http.Response(_loginPage, 200, request: request);
    }
    if (request.url.path.endsWith('/iserv/')) {
      // isAuthenticated() prüft die Startseite.
      if (request.headers['cookie']?.contains(_sessionId) ?? false) {
        return http.Response(
          '<html><body>Dashboard</body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
          request: request,
        );
      }
      return http.Response(_loginPage, 200, request: request);
    }
    if (request.url.path.endsWith('/tasks')) {
      if (request.headers['cookie']?.contains(_sessionId) ?? false) {
        return http.Response(_fixtureHtml(), 200,
          headers: {'content-type': 'text/html; charset=utf-8'});
      }
      return http.Response(
        '',
        302,
        headers: {'location': '/login'},
      );
    }
    if (request.url.path.endsWith('/logout')) {
      return http.Response('', 302, headers: {'location': '/login'});
    }
    return http.Response('not found', 404);
  });
}

/// Neuere IServ-Variante (OAuth2): GET /login redirectet auf
/// /iserv/auth/login, kein _token, POST geht an die finale URL.
MockClient _oauthIserv() {
  return MockClient((request) async {
    // Wichtig: /iserv/auth/login prüfen, BEVOR das endsWith('/login')
    // greift (sonst Endlos-Redirect).
    if (request.url.path == '/iserv/auth/login' &&
        request.method == 'GET') {
      final page = _loginPage.replaceFirst(
        '<input type="hidden" name="_token" value="TOKEN123">\n',
        '',
      );
      return http.Response(page, 200, request: request);
    }
    if (request.url.path == '/iserv/auth/login' &&
        request.method == 'POST') {
      final fields = Uri.splitQueryString(request.body);
      if (fields['_username'] == _username &&
          fields['_password'] == _password &&
          !fields.containsKey('_token')) {
        return http.Response(
          '',
          302,
          headers: {
            'location': '/dashboard',
            'set-cookie': 'ISERVSESSIONID=$_sessionId; Path=/',
          },
        );
      }
      return http.Response('denied', 403);
    }
    if (request.url.path.endsWith('/login') && request.method == 'GET') {
      return http.Response(
        '',
        302,
        headers: {'location': '/iserv/auth/login?nonce=abc'},
      );
    }
    if (request.url.path.endsWith('/dashboard')) {
      // 302 nach POST muss als GET gefolgt werden.
      expect(request.method, 'GET');
      if (request.headers['cookie']?.contains(_sessionId) ?? false) {
        return http.Response(
          '<html><body>Dashboard</body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
          request: request,
        );
      }
      return http.Response(_loginPage, 200, request: request);
    }
    if (request.url.path.endsWith('/iserv/')) {
      // isAuthenticated() prüft die Startseite.
      if (request.headers['cookie']?.contains(_sessionId) ?? false) {
        return http.Response(
          '<html><body>Dashboard</body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
          request: request,
        );
      }
      return http.Response(_loginPage, 200, request: request);
    }
    if (request.url.path.endsWith('/tasks')) {
      if (request.headers['cookie']?.contains(_sessionId) ?? false) {
        return http.Response(_fixtureHtml(), 200,
          headers: {'content-type': 'text/html; charset=utf-8'});
      }
      return http.Response(
        '',
        302,
        headers: {'location': '/iserv/auth/login'},
      );
    }
    return http.Response('not found', 404);
  });
}

IservSession _session(MockClient client) => IservSession(
  client: client,
  baseUrl: 'https://schule.example.de/iserv',
);

void main() {
  group('IservSession (klassisch mit CSRF-Token)', () {
    test('nicht angemeldet, Login, Aufgaben-Abruf', () async {
      final session = _session(_classicIserv());

      expect(await session.isAuthenticated(), isFalse);

      expect(await session.login(_username, _password), isTrue);
      expect(await session.isAuthenticated(), isTrue);

      final tasks = await fetchTasks(session);
      expect(tasks, hasLength(4));
      expect(tasks.first.title, contains('Quadratische'));
      expect(tasks.first.subject, 'Mathematik');
    });

    test('falsche Zugangsdaten werfen IservLoginException', () async {
      final session = _session(_classicIserv());
      await expectLater(
        session.login(_username, 'falsch'),
        throwsA(isA<IservLoginException>()),
      );
    });

    test('Logout löscht die Session-Cookies', () async {
      final session = _session(_classicIserv());
      await session.login(_username, _password);
      await session.logout();
      expect(await session.isAuthenticated(), isFalse);
    });
  });

  group('IservSession (neu, OAuth2 ohne Token)', () {
    test('Login über Redirect-URL ohne CSRF-Token', () async {
      final session = _session(_oauthIserv());

      expect(await session.login(_username, _password), isTrue);
      expect(await session.isAuthenticated(), isTrue);

      final tasks = await fetchTasks(session);
      expect(tasks, hasLength(4));
    });

    test('falsche Zugangsdaten werden abgelehnt', () async {
      final session = _session(_oauthIserv());
      await expectLater(
        session.login(_username, 'falsch'),
        throwsA(isA<IservLoginException>()),
      );
    });
  });

  group('Set-Cookie-Parsing', () {
    test('POST + Formular werden durch die auth-302-Kette getragen',
        () async {
      final session = _session(MockClient((request) async {
        if (request.url.path == '/iserv/login' &&
            request.method == 'GET') {
          return http.Response(_loginPage, 200, request: request);
        }
        if (request.url.path == '/iserv/login' &&
            request.method == 'POST') {
          final fields = Uri.splitQueryString(request.body);
          if (fields['_username'] == _username &&
              fields['_password'] == _password) {
            return http.Response(
              '',
              302,
              headers: {'location': '/iserv/auth/auth?state=abc'},
            );
          }
          return http.Response('denied', 403);
        }
        if (request.url.path.contains('/iserv/auth/')) {
          // POST + Zugangsdaten müssen durch die auth-Kette getragen werden.
          expect(request.method, 'POST');
          final fields = Uri.splitQueryString(request.body);
          expect(fields['_username'], _username);
          expect(fields['_password'], _password);
          if (request.url.path.endsWith('/auth/auth') &&
              request.url.queryParameters['state'] == 'abc') {
            return http.Response(
              '',
              302,
              headers: {'location': '/iserv/auth/login?_target_path=/iserv'},
            );
          }
          if (request.url.path.endsWith('/auth/login')) {
            return http.Response(
              '',
              302,
              headers: {'location': '/iserv/auth/auth?state=frisch'},
            );
          }
          if (request.url.path.endsWith('/auth/auth') &&
              request.url.queryParameters['state'] == 'frisch') {
            return http.Response(
              '<html><body>Dashboard</body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
              request: request,
            );
          }
        }
        return http.Response('not found', 404);
      }));

      expect(await session.login(_username, _password), isTrue);
    });

    test('Expires-Kommas und gelöschte Cookies werden korrekt behandelt',
        () async {
      var first = true;
      final session = _session(MockClient((request) async {
        if (first) {
          first = false;
          return http.Response('', 302, headers: {
            'location': '/landing',
            'set-cookie':
                'IServAuthRemember=deleted; expires=Fri, 15 Aug 2026 07:11:28 GMT; Max-Age=0; path=/, '
                'IServSession=PFmvNjVypBoSszBXRNPZMC; Path=/; Secure; HttpOnly',
          });
        }
        if (request.url.path.endsWith('/landing')) {
          expect(
            request.headers['cookie'],
            contains('IServSession=PFmvNjVypBoSszBXRNPZMC'),
          );
          expect(request.headers['cookie'], isNot(contains('deleted')));
          expect(request.headers['cookie'], isNot(contains('Max-Age')));
          expect(request.headers['cookie'], isNot(contains('expires')));
          expect(request.headers['cookie'], isNot(contains('IServAuthRemember,')));
          return http.Response('ok', 200, request: request);
        }
        return http.Response('not found', 404);
      }));

      final response = await session.get('/x');
      expect(response.statusCode, 200);
    });
  });

  group('Meta-Refresh-Weiterleitung', () {
    test('folgt einer Meta-Refresh-Seite mit OIDC-code', () async {
      final session = _session(MockClient((request) async {
        final hasSession =
            request.headers['cookie']?.contains('JSESSIONID=neu123') ?? false;
        if (request.url.path.endsWith('/messages') && !hasSession) {
          return http.Response(
            '''
            <html><head>
            <meta http-equiv="refresh" content="0;url=https://bbs-papenburg.eu/iserv/app/authentication/redirect?state=abc&amp;code=xyz%3Aabc">
            </head></html>''',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/authentication/redirect')) {
          // Der Code-Austausch läuft per POST, sonst liefert IServ eine
          // Endlos-Refresh-Schleife auf dieselbe URL.
          expect(request.method, 'POST');
          expect(request.url.queryParameters['code'], 'xyz:abc');
          expect(request.url.queryParameters['state'], 'abc');
          return http.Response(
            '',
            302,
            headers: {
              'location': '/messages',
              'set-cookie': 'JSESSIONID=neu123; Path=/',
            },
          );
        }
        if (request.url.path.endsWith('/messages') && hasSession) {
          return http.Response(
            '<html><body><div class="inbox">Postfach</div></body></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
            request: request,
          );
        }
        return http.Response('not found', 404);
      }));

      final response = await session.get('/messages');
      expect(response.statusCode, 200);
      expect(response.body, contains('Postfach'));
      // Cookie aus dem Code-Austausch wurde übernommen.
      expect(response.request!.headers['cookie'], contains('JSESSIONID=neu123'));
    });

    test('Meta-Refresh ohne url wird ignoriert', () async {
      final session = _session(MockClient((request) async {
        return http.Response(
          '<html><head><meta http-equiv="refresh" content="0"></head></html>',
          200,
        );
      }));

      final response = await session.get('/tasks');
      expect(response.statusCode, 200);
    });

    test('Login: Code-Austausch per POST, kein Endlos-Refresh', () async {
      final session = _session(MockClient((request) async {
        final hasSession =
            request.headers['cookie']?.contains('IServSession=ok') ?? false;
        if (request.url.path == '/iserv/login' && request.method == 'GET') {
          return http.Response(_loginPage, 200, request: request);
        }
        if (request.url.path == '/iserv/login' && request.method == 'POST') {
          final fields = Uri.splitQueryString(request.body);
          if (fields['_username'] == _username &&
              fields['_password'] == _password) {
            return http.Response(
              '',
              302,
              headers: {'location': '/iserv/auth/auth?state=abc'},
            );
          }
          return http.Response('denied', 403);
        }
        if (request.url.path.contains('/iserv/auth/')) {
          if (request.url.path.endsWith('/auth/auth') &&
              request.method == 'POST') {
            // Nach dem Login: Meta-Refresh-Seite mit OIDC-code.
            return http.Response(
              '''
              <html><head>
              <meta http-equiv="refresh" content="0;url=/iserv/app/authentication/redirect?state=abc&amp;code=code123">
              </head></html>''',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          return http.Response(
            '',
            302,
            headers: {'location': '/iserv/auth/login?_target_path=/iserv'},
          );
        }
        if (request.url.path.endsWith('/authentication/redirect')) {
          expect(request.method, 'POST');
          return http.Response(
            '',
            302,
            headers: {
              'location': '/iserv/',
              'set-cookie': 'IServSession=ok; Path=/',
            },
          );
        }
        if (request.url.path == '/iserv/' && hasSession) {
          return http.Response(
            '<html><body>Dashboard</body></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
            request: request,
          );
        }
        return http.Response('not found', 404);
      }));

      expect(await session.login(_username, _password), isTrue);
      expect(await session.isAuthenticated(), isTrue);
    });
  });
}
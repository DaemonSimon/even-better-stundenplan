import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:better_stundenplan/services/secure_storage.dart';
import 'package:better_stundenplan/services/session_manager.dart';

class InMemoryCredentialStorage implements CredentialStorage {
  String? sessionId;
  String? email;
  String? password;

  @override
  Future<String?> getSessionId() async => sessionId;

  @override
  Future<String?> getEmail() async => email;

  @override
  Future<String?> getPassword() async => password;

  @override
  Future<void> saveSessionId(String sessionId) async {
    this.sessionId = sessionId;
  }

  @override
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    this.email = email;
    this.password = password;
  }

  @override
  Future<void> clear() async {
    sessionId = null;
    email = null;
    password = null;
  }
}

void main() {
  group('SessionManager', () {
    test('login succeeds and stores session id + credentials', () async {
      final storage = InMemoryCredentialStorage();
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://virtueller-stundenplan.org/index.php',
        );
        expect(request.method, 'POST');
        expect(request.body, contains('MAIL=user%40example.com'));
        expect(request.body, contains('SCHUELERCODE=secret'));
        expect(request.body, contains('formAction=login'));
        return http.Response(
          '',
          200,
          headers: {'set-cookie': 'PHPSESSID=abc123; path=/; HttpOnly'},
        );
      });
      final manager = SessionManager(storage: storage, client: client);

      final ok = await manager.login(
        email: 'user@example.com',
        password: 'secret',
      );

      expect(ok, isTrue);
      expect(manager.isLoggedIn, isTrue);
      expect(manager.sessionId, 'abc123');
      expect(storage.sessionId, 'abc123');
      expect(storage.email, 'user@example.com');
      expect(storage.password, 'secret');
    });

    test('login fails when the response has no session cookie', () async {
      final storage = InMemoryCredentialStorage();
      final client = MockClient((request) async => http.Response('', 200));
      final manager = SessionManager(storage: storage, client: client);

      final ok = await manager.login(email: 'a@b.de', password: 'x');

      expect(ok, isFalse);
      expect(manager.isLoggedIn, isFalse);
      expect(manager.sessionId, isNull);
      expect(storage.sessionId, isNull);
    });

    test('checkAuthentication succeeds for a non-redirect response', () async {
      final storage = InMemoryCredentialStorage()..sessionId = 'abc123';
      final client = MockClient((request) async {
        expect(request.headers['Cookie'], 'PHPSESSID=abc123');
        expect(request.headers['User-Agent'], isNotNull);
        return http.Response('', 200);
      });
      final manager = SessionManager(storage: storage, client: client);

      final valid = await manager.checkAuthentication();

      expect(valid, isTrue);
      expect(manager.isLoggedIn, isTrue);
      expect(manager.sessionId, 'abc123');
    });

    test('checkAuthentication fails on redirect (expired session)', () async {
      final storage = InMemoryCredentialStorage()..sessionId = 'expired';
      final client = MockClient((request) async => http.Response(
            '',
            302,
            headers: {'location': '/'},
            isRedirect: true,
          ));
      final manager = SessionManager(storage: storage, client: client);

      final valid = await manager.checkAuthentication();

      expect(valid, isFalse);
      expect(manager.isLoggedIn, isFalse);
      expect(manager.sessionId, isNull);
    });

    test('checkAuthentication fails without stored session', () async {
      final storage = InMemoryCredentialStorage();
      final manager = SessionManager(
        storage: storage,
        client: MockClient((_) async => http.Response('', 200)),
      );

      final valid = await manager.checkAuthentication();

      expect(valid, isFalse);
      expect(manager.isLoggedIn, isFalse);
    });

    test('tryReAuthenticate logs in with stored credentials', () async {
      final storage = InMemoryCredentialStorage()
        ..email = 'user@example.com'
        ..password = 'secret';
      final client = MockClient(
        (request) async => http.Response(
          '',
          200,
          headers: {'set-cookie': 'PHPSESSID=xyz; path=/'},
        ),
      );
      final manager = SessionManager(storage: storage, client: client);

      final ok = await manager.tryReAuthenticate();

      expect(ok, isTrue);
      expect(manager.sessionId, 'xyz');
      // Gespeicherte Zugangsdaten bleiben unverändert
      expect(storage.password, 'secret');
    });

    test('tryReAuthenticate fails without stored credentials', () async {
      final storage = InMemoryCredentialStorage();
      final manager = SessionManager(
        storage: storage,
        client: MockClient((_) async => http.Response('', 200)),
      );

      final ok = await manager.tryReAuthenticate();

      expect(ok, isFalse);
    });

    test('logout clears all stored data', () async {
      final storage = InMemoryCredentialStorage()
        ..sessionId = 'abc'
        ..email = 'user@example.com'
        ..password = 'secret';
      final manager = SessionManager(
        storage: storage,
        client: MockClient((_) async => http.Response('', 200)),
      );

      await manager.logout();

      expect(manager.isLoggedIn, isFalse);
      expect(manager.sessionId, isNull);
      expect(storage.sessionId, isNull);
      expect(storage.email, isNull);
      expect(storage.password, isNull);
    });

    test('notifies listeners on state changes', () async {
      final storage = InMemoryCredentialStorage();
      final manager = SessionManager(
        storage: storage,
        client: MockClient(
          (request) async => http.Response(
            '',
            200,
            headers: {'set-cookie': 'PHPSESSID=a; path=/'},
          ),
        ),
      );
      var notifications = 0;
      manager.addListener(() => notifications++);

      await manager.login(email: 'a@b.de', password: 'x');
      await manager.logout();

      expect(notifications, greaterThanOrEqualTo(2));
    });
  });
}

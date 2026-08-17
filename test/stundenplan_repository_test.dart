import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:better_stundenplan/models/timetable_result.dart';
import 'package:better_stundenplan/services/secure_storage.dart';
import 'package:better_stundenplan/services/session_manager.dart';
import 'package:better_stundenplan/services/stundenplan_api.dart';
import 'package:better_stundenplan/services/stundenplan_repository.dart';
import 'package:better_stundenplan/services/timetable_cache.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

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
  late SessionManager sessionManager;

  setUp(() async {
    final storage = InMemoryCredentialStorage()..sessionId = 'valid-session';
    sessionManager = SessionManager(
      storage: storage,
      client: MockClient((request) async => http.Response('', 200)),
    );
    await sessionManager.checkAuthentication();
  });

  group('StundenplanRepository', () {
    test('returns parsed lessons for a single day', () async {
      final client = MockClient((request) async {
        expect(request.headers['Cookie'], 'PHPSESSID=valid-session');
        expect(request.headers['User-Agent'], isNotNull);
        expect(request.url.queryParameters['KlaBuDatum'], '14.08.2026');
        return http.Response(fixture('day_with_lessons.html'), 200);
      });
      final repository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: client),
      );

      final result = await repository.getTimetable(
        '14.08.2026',
        weeklyMode: false,
      );

      expect(result, isA<TimetableSuccess>());
      final week = (result as TimetableSuccess).timetable;
      expect(week.days, hasLength(1));
      expect(week.days.single.timeSlots, hasLength(3));
    });

    test('returns AuthExpired on redirect', () async {
      final client = MockClient(
        (request) async =>
            http.Response('', 302, headers: {'location': '/index.php'}),
      );
      final repository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: client),
      );

      final result = await repository.getTimetable(
        '14.08.2026',
        weeklyMode: false,
      );

      expect(result, isA<TimetableAuthExpired>());
    });

    test(
      'returns AuthExpired when the login page is served with 200',
      () async {
        final client = MockClient(
          (request) async => http.Response(fixture('login_page.html'), 200),
        );
        final repository = StundenplanRepository(
          sessionManager: sessionManager,
          api: StundenplanApi(client: client),
        );

        final result = await repository.getTimetable(
          '14.08.2026',
          weeklyMode: false,
        );

        expect(result, isA<TimetableAuthExpired>());
      },
    );

    test('returns NetworkError without cache fallback', () async {
      final client = MockClient(
        (request) async => throw http.ClientException('connection refused'),
      );
      final repository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: client),
      );

      final result = await repository.getTimetable(
        '14.08.2026',
        weeklyMode: false,
      );

      expect(result, isA<TimetableNetworkError>());
    });

    test('serves a day from the fresh memory cache without network', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response(fixture('day_with_lessons.html'), 200);
      });
      final repository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: client),
      );

      await repository.getTimetable('14.08.2026', weeklyMode: false);
      final cachedResult = await repository.getTimetable(
        '14.08.2026',
        weeklyMode: false,
      );

      expect(cachedResult, isA<TimetableSuccess>());
      expect(requests, 1);
    });

    test('falls back to cache when the network fails', () async {
      // Beide Repositories teilen sich denselben Speicher-Cache
      final sharedCache = TimetableCache();
      final okClient = MockClient(
        (request) async => http.Response(fixture('day_with_lessons.html'), 200),
      );
      final repository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: okClient),
        cache: sharedCache,
      );
      await repository.getTimetable('14.08.2026', weeklyMode: false);

      // Zweites Repository mit kaputtem Netz -> Fallback auf den Speicher-Cache
      final brokenRepository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
        cache: sharedCache,
      );

      final result = await brokenRepository.getTimetable(
        '14.08.2026',
        weeklyMode: false,
      );

      expect(result, isA<TimetableSuccess>());
    });

    test('weekly view fetches all seven days from Monday to Sunday', () async {
      final requestedDates = <String>[];
      final client = MockClient((request) async {
        requestedDates.add(request.url.queryParameters['KlaBuDatum']!);
        return http.Response(fixture('day_empty.html'), 200);
      });
      final repository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: client),
      );

      final result = await repository.getTimetable(
        '14.08.2026',
        weeklyMode: true,
      );

      expect(result, isA<TimetableSuccess>());
      expect(requestedDates, [
        '10.08.2026',
        '11.08.2026',
        '12.08.2026',
        '13.08.2026',
        '14.08.2026',
        '15.08.2026',
        '16.08.2026',
      ]);
      final week = (result as TimetableSuccess).timetable;
      expect(week.days, hasLength(7));
      expect(week.days.every((d) => d.isEmpty), isTrue);
    });

    test(
      'weekly view returns AuthExpired if any day fails with a redirect',
      () async {
        final client = MockClient((request) async {
          final date = request.url.queryParameters['KlaBuDatum'];
          if (date == '14.08.2026') {
            return http.Response('', 302, headers: {'location': '/'});
          }
          return http.Response(fixture('day_empty.html'), 200);
        });
        final repository = StundenplanRepository(
          sessionManager: sessionManager,
          api: StundenplanApi(client: client),
        );

        final result = await repository.getTimetable(
          '14.08.2026',
          weeklyMode: true,
        );

        expect(result, isA<TimetableAuthExpired>());
      },
    );
  });
}

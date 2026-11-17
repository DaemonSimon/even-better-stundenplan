import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:better_stundenplan/models/timetable_result.dart';
import 'package:better_stundenplan/models/timetable.dart';
import 'package:better_stundenplan/services/connectivity_monitor.dart';
import 'package:better_stundenplan/services/secure_storage.dart';
import 'package:better_stundenplan/services/session_manager.dart';
import 'package:better_stundenplan/services/stundenplan_api.dart';
import 'package:better_stundenplan/services/stundenplan_parser.dart';
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

class _NoopDiskCache extends TimetableDiskCache {
  @override
  Future<void> save(String weekKey, WeeklyTimetable value) async {}

  @override
  Future<WeeklyTimetable?> load(String weekKey) async => null;
}

/// Simuliert einen Parse-Fehler (z. B. geändertes HTML-Layout).
class _ThrowingParser extends StundenplanParser {
  @override
  List<List<TimeSlot>> parseWeeklyTimetable(String htmlString) =>
      throw const FormatException('kaputt');
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
    test('fetches the whole week in a single page-5 request', () async {
      final requestedDates = <String>[];
      final client = MockClient((request) async {
        requestedDates.add(request.url.toString());
        return http.Response(fixture('week_page5_real.html'), 200);
      });
      final repository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: client),
        cache: TimetableCache(disk: _NoopDiskCache()),
      );

      final result = await repository.getTimetable(
        '10.08.2026',
        weeklyMode: true,
      );

      expect(result, isA<TimetableSuccess>());
      final week = (result as TimetableSuccess).timetable;
      expect(week.days, hasLength(5)); // Mo–Fr
      expect(requestedDates, hasLength(1));
      expect(requestedDates.single, contains('page-5/index.php'));
      expect(requestedDates.single, contains('KlaBuDatum=10.08.2026'));
    });

    test('returns AuthExpired on redirect', () async {
      final client = MockClient(
        (request) async =>
            http.Response('', 302, headers: {'location': '/index.php'}),
      );
      final repository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: client),
        cache: TimetableCache(disk: _NoopDiskCache()),
      );

      final result = await repository.getTimetable(
        '10.08.2026',
        weeklyMode: true,
      );

      expect(result, isA<TimetableAuthExpired>());
    });

    test('returns NetworkError on connection failure without cache', () async {
      final client = MockClient(
        (request) async => throw http.ClientException('connection refused'),
      );
      final repository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: client),
        cache: TimetableCache(disk: _NoopDiskCache()),
      );

      final result = await repository.getTimetable(
        '10.08.2026',
        weeklyMode: true,
      );

      expect(result, isA<TimetableNetworkError>());
    });

    test('serves the cached week when the network fails', () async {
      final sharedCache = TimetableCache(disk: _NoopDiskCache());
      final okClient = MockClient(
        (request) async => http.Response(fixture('week_page5_real.html'), 200),
      );
      final okRepository = StundenplanRepository(
        sessionManager: sessionManager,
        api: StundenplanApi(client: okClient),
        cache: sharedCache,
      );
      await okRepository.getTimetable('10.08.2026', weeklyMode: true);

      // Zweites Repository mit kaputtem Netz -> Fallback auf den Cache.
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
        '10.08.2026',
        weeklyMode: true,
      );

      expect(result, isA<TimetableSuccess>());
    });

    test(
      'a parse failure keeps the cached week instead of caching an empty one',
      () async {
        final sharedCache = TimetableCache(disk: _NoopDiskCache());
        final client = MockClient(
          (request) async =>
              http.Response(fixture('week_page5_real.html'), 200),
        );
        await StundenplanRepository(
          sessionManager: sessionManager,
          api: StundenplanApi(client: client),
          cache: sharedCache,
        ).getTimetable('10.08.2026', weeklyMode: true);
        final goodWeek = sharedCache.getStale('10.08.2026')!;
        expect(goodWeek.days.any((d) => d.timeSlots.isNotEmpty), isTrue);

        final result = await StundenplanRepository(
          sessionManager: sessionManager,
          api: StundenplanApi(client: client),
          parser: _ThrowingParser(),
          cache: sharedCache,
        ).getTimetable('10.08.2026', weeklyMode: true);

        expect(result, isA<TimetableSuccess>());
        final week = (result as TimetableSuccess).timetable;
        expect(week.days.any((d) => d.timeSlots.isNotEmpty), isTrue);
        expect(sharedCache.getStale('10.08.2026'), same(goodWeek));
      },
    );

    test(
      'single day mode returns only the requested day from the week',
      () async {
        final client = MockClient(
          (request) async =>
              http.Response(fixture('week_page5_real.html'), 200),
        );
        final repository = StundenplanRepository(
          sessionManager: sessionManager,
          api: StundenplanApi(client: client),
          cache: TimetableCache(disk: _NoopDiskCache()),
        );

        // Donnerstag, 13.08.2026 (Index 3 in der Woche).
        final result = await repository.getTimetable(
          '13.08.2026',
          weeklyMode: false,
        );

        expect(result, isA<TimetableSuccess>());
        final week = (result as TimetableSuccess).timetable;
        expect(week.days, hasLength(1));
        expect(week.days.single.date.day, 13);
      },
    );

    group('offline-first', () {
      late ConnectivityMonitor connectivity;
      late TimetableCache cache;

      setUp(() async {
        connectivity = ConnectivityMonitor(pollingEnabled: false);
        cache = TimetableCache(disk: _NoopDiskCache());
        // Woche einmal laden, damit sie gespeichert ist.
        await StundenplanRepository(
          sessionManager: sessionManager,
          api: StundenplanApi(
            client: MockClient(
              (_) async => http.Response(fixture('week_page5_real.html'), 200),
            ),
          ),
          cache: cache,
          connectivity: connectivity,
        ).getTimetable('10.08.2026', weeklyMode: true);
      });

      test('a fresh week is served without any request', () async {
        var requests = 0;
        final repository = StundenplanRepository(
          sessionManager: sessionManager,
          api: StundenplanApi(
            client: MockClient((_) async {
              requests++;
              return http.Response('', 500);
            }),
          ),
          cache: cache,
          connectivity: connectivity,
        );

        final result = await repository.getTimetable(
          '10.08.2026',
          weeklyMode: true,
        );

        expect(result, isA<TimetableSuccess>());
        expect(requests, 0);
      });

      test(
        'a stale week is shown at once and updated in the background',
        () async {
          cache.markAllStale();
          final oldWeek = cache.getStale('10.08.2026')!;
          final repository = StundenplanRepository(
            sessionManager: sessionManager,
            api: StundenplanApi(
              client: MockClient(
                (_) async =>
                    http.Response(fixture('week_with_double_hours.html'), 200),
              ),
            ),
            cache: cache,
            connectivity: connectivity,
          );
          var notified = 0;
          repository.addListener(() => notified++);

          final first = await repository.getTimetable(
            '10.08.2026',
            weeklyMode: true,
          );
          expect((first as TimetableSuccess).timetable, same(oldWeek));

          await pumpEventQueue();
          expect(notified, 1);
          final updated = cache.getFresh('10.08.2026');
          expect(updated, isNotNull);
          expect(updated, isNot(same(oldWeek)));
        },
      );

      test('offline keeps the stored week and does not notify', () async {
        cache.markAllStale();
        final oldWeek = cache.getStale('10.08.2026')!;
        final repository = StundenplanRepository(
          sessionManager: sessionManager,
          api: StundenplanApi(
            client: MockClient(
              (_) async => throw http.ClientException('offline'),
            ),
          ),
          cache: cache,
          connectivity: connectivity,
        );
        var notified = 0;
        repository.addListener(() => notified++);

        final result = await repository.getTimetable(
          '10.08.2026',
          weeklyMode: true,
        );
        await pumpEventQueue();

        expect((result as TimetableSuccess).timetable, same(oldWeek));
        expect(notified, 0);
        expect(connectivity.isOnline, isFalse);
      });

      test('reloads when the connection comes back', () async {
        final repository = StundenplanRepository(
          sessionManager: sessionManager,
          cache: cache,
          connectivity: connectivity,
        );
        var notified = 0;
        repository.addListener(() => notified++);

        connectivity.reportFailure();
        expect(notified, 0);
        connectivity.reportSuccess();

        expect(notified, 1);
        expect(cache.getFresh('10.08.2026'), isNull);
        expect(cache.getStale('10.08.2026'), isNotNull);
        repository.dispose();
      });
    });
  });
}

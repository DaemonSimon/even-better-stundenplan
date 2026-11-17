import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:better_stundenplan/pages/iserv_task_page.dart';
import 'package:better_stundenplan/services/iserv_offline_store.dart';
import 'package:better_stundenplan/services/iserv_session.dart';
import 'package:better_stundenplan/services/iserv_task_detail.dart';
import 'package:better_stundenplan/services/iserv_tasks.dart';

const _base = 'https://schule.example.de/iserv';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  late Directory root;
  late IservOfflineStore store;
  late List<String> requested;
  late IservSession session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('iserv_offline_test');
    store = IservOfflineStore(rootDir: () async => root);
    requested = [];
    session = IservSession(
      baseUrl: _base,
      client: MockClient((request) async {
        requested.add(request.url.path);
        if (request.url.path.contains('/exercise/show/')) {
          return http.Response(_fixture('iserv_exercise_show.html'), 200);
        }
        if (request.url.path.contains('/fs/download/')) {
          return http.Response.bytes([1, 2, 3], 200);
        }
        return http.Response('', 404);
      }),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  IservTask task(String id, {DateTime? due}) => IservTask(
    title: 'Aufgabe $id',
    dueDate: due?.toIso8601String(),
    links: ['$_base/exercise/show/$id'],
  );

  final future = DateTime.now().add(const Duration(days: 3));
  final past = DateTime.now().subtract(const Duration(days: 1));

  test('downloads details and attachments of running tasks', () async {
    await store.sync(session, [task('101', due: future)]);

    final dir = Directory('${root.path}/101');
    expect(File('${dir.path}/detail.html').existsSync(), isTrue);

    final detail = parseTaskDetail(
      _fixture('iserv_exercise_show.html'),
      baseUrl: _base,
    );
    expect(detail.attachments, isNotEmpty);
    for (final attachment in detail.attachments) {
      final file = await store.cachedAttachment(attachment);
      expect(file, isNotNull, reason: attachment.name);
      expect(file!.readAsBytesSync(), [1, 2, 3]);
    }
  });

  test('does not download again when everything is stored', () async {
    await store.sync(session, [task('101', due: future)]);
    requested.clear();

    await store.sync(session, [task('101', due: future)]);

    expect(requested, isEmpty);
  });

  test('deletes tasks that are over or no longer open', () async {
    await store.sync(session, [task('101', due: future), task('102')]);
    expect(Directory('${root.path}/101').existsSync(), isTrue);
    expect(Directory('${root.path}/102').existsSync(), isTrue);

    // 101: Abgabe vorbei; 102: nicht mehr in der Liste.
    await store.sync(session, [task('101', due: past)]);

    expect(Directory('${root.path}/101').existsSync(), isFalse);
    expect(Directory('${root.path}/102').existsSync(), isFalse);
  });

  test('serves the stored detail page when offline', () async {
    await store.sync(session, [task('101', due: future)]);
    final offline = IservSession(
      baseUrl: _base,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );

    final detail = await fetchTaskDetail(
      offline,
      '$_base/exercise/show/101',
      offlineStore: store,
    );

    expect(detail.attachments, isNotEmpty);
  });

  testWidgets('only stored files show the green Cached pill', (tester) async {
    final detail = parseTaskDetail(
      _fixture('iserv_exercise_show.html'),
      baseUrl: _base,
    );
    expect(detail.attachments.length, greaterThan(1));
    // Hoher Bildschirm, damit die Dateiliste sichtbar gebaut wird.
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Nur der erste Anhang liegt offline vor.
    await tester.runAsync(() async {
      final dir = Directory('${root.path}/101')..createSync(recursive: true);
      File(
        '${dir.path}/${IservOfflineStore.fileNameFor(detail.attachments.first)}',
      ).writeAsBytesSync([1]);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: IservTaskPage(
          url: '$_base/exercise/show/101',
          session: session,
          loader: () async => detail,
          offlineStore: store,
        ),
      ),
    );
    // Datei-Zugriffe laufen echt asynchron: schrittweise warten.
    for (var i = 0; i < 40 && find.text('Cached').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }

    expect(find.text('Cached'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/services/iserv_mapping.dart';
import 'package:better_stundenplan/services/iserv_tasks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('normalizeSubject', () {
    test('Kürzel und Umlaute', () {
      expect(IservMappingEngine.normalizeSubject('Mathematik'), 'mathematik');
      expect(IservMappingEngine.normalizeSubject('MATHE'), 'mathematik');
      expect(IservMappingEngine.normalizeSubject('Ma'), 'mathematik');
      expect(IservMappingEngine.normalizeSubject('PO'), 'politik');
      expect(IservMappingEngine.normalizeSubject('Deutsch A'), 'deutsch');
      expect(IservMappingEngine.normalizeSubject('Pädagogik'), 'paedagogik');
      expect(IservMappingEngine.normalizeSubject('  '), '');
    });
  });

  group('IservMappingEngine', () {
    test('Slots sind 20 Doppelstunden-Blöcke', () {
      expect(IservMappingEngine.availableSlots().first, 'Mo.1');
      expect(IservMappingEngine.availableSlots().last, 'Fr.4');
      expect(IservMappingEngine.availableSlots(), hasLength(20));
    });

    test('Default-Mapping nach Fach', () {
      final engine = IservMappingEngine();
      expect(engine.slotFor('iserv:x', 'Mathematik'), 'Mo.1');
      expect(engine.slotFor('iserv:x', 'MA'), 'Mo.1');
      expect(engine.slotFor('iserv:x', 'Kunst'), 'Mi.2');
      expect(engine.slotFor('iserv:x', ''), isNull);
      expect(engine.slotFor('iserv:x', 'Astronomie'), isNull);
    });

    test('Task-Override schlägt Fach-Default, überlebt Neustart', () async {
      final engine = IservMappingEngine();
      await engine.setOverride('iserv:abc', 'Di.2');
      expect(engine.slotFor('iserv:abc', 'Mathematik'), 'Di.2');
      expect(engine.slotFor('iserv:other', 'Mathematik'), 'Mo.1');

      final revived = IservMappingEngine();
      await revived.restore();
      expect(revived.slotFor('iserv:abc', 'Mathematik'), 'Di.2');

      await revived.clearOverride('iserv:abc');
      expect(revived.slotFor('iserv:abc', 'Mathematik'), 'Mo.1');
    });

    test('ungültige Slots werden abgelehnt', () async {
      final engine = IservMappingEngine();
      await expectLater(
        engine.setOverride('iserv:x', 'Montag'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        engine.setOverride('iserv:x', 'Mo.5'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TempAssignmentStore', () {
    test('Fotoanhänge überleben das Speichern und erneute Laden', () async {
      final store = TempAssignmentStore();
      await store.add(
        title: 'Arbeitsblatt',
        imagePaths: const ['/local/homework/photo.jpg'],
      );

      final reloaded = await TempAssignmentStore().load();
      expect(reloaded.single.imagePaths, ['/local/homework/photo.jpg']);
    });

    test('add/update/remove-Roundtrip', () async {
      final store = TempAssignmentStore();
      final added = await store.add(
        title: 'Testat lernen',
        subject: 'Physik',
        dueDate: '2026-08-19T09:00',
      );
      expect(added.id, 1);

      var tasks = await store.load();
      expect(tasks, hasLength(1));
      expect(tasks.first.title, 'Testat lernen');

      final updated = added.copyWith(description: 'Kap. 3 + 4');
      tasks = await store.update(updated);
      expect(tasks.first.description, 'Kap. 3 + 4');
      expect(tasks.first.title, 'Testat lernen');

      tasks = await store.remove(added.id);
      expect(tasks, isEmpty);

      final reloaded = await TempAssignmentStore().load();
      expect(reloaded, isEmpty);
    });

    test('IDs steigen weiter', () async {
      final store = TempAssignmentStore();
      final first = await store.add(title: 'A');
      final second = await store.add(title: 'B');
      expect(first.id, 1);
      expect(second.id, 2);
    });

    test(
      'Unterrichtsbezug und Erledigt-Status bleiben lokal gespeichert',
      () async {
        final store = TempAssignmentStore();
        await store.add(
          title: 'Arbeitsblatt',
          subject: 'Mathematik',
          dueDate: '2026-11-12',
          lessonDate: '2026-11-12',
          hour: '3',
        );
        final task = (await store.load()).single;
        await store.update(
          task.copyWith(completedAt: DateTime(2026, 11, 11).toIso8601String()),
        );

        final restored = (await TempAssignmentStore().load()).single;
        expect(restored.subject, 'Mathematik');
        expect(restored.lessonDate, '2026-11-12');
        expect(restored.hour, '3');
        expect(restored.completedAt, '2026-11-11T00:00:00.000');
      },
    );

    test('löscht erledigte Aufgaben erst nach 24 Stunden', () async {
      final now = DateTime(2026, 11, 11, 12);
      final store = TempAssignmentStore();
      final old = await store.add(title: 'Schon lange erledigt');
      final recent = await store.add(title: 'Gerade erledigt');
      final open = await store.add(title: 'Noch offen');
      await store.update(
        old.copyWith(
          completedAt: now
              .subtract(const Duration(hours: 24))
              .toIso8601String(),
        ),
      );
      await store.update(
        recent.copyWith(
          completedAt: now
              .subtract(const Duration(hours: 23))
              .toIso8601String(),
        ),
      );

      final removed = await store.purgeCompleted(now: now);
      expect(removed.map((task) => task.id), [old.id]);
      expect((await store.load()).map((task) => task.id), [recent.id, open.id]);
    });
  });

  group('mergeTasks', () {
    test('einheitlicher Stream, sortiert nach Abgabedatum', () async {
      final engine = IservMappingEngine();
      final store = TempAssignmentStore();
      await store.add(
        title: 'Referat vorbereiten',
        subject: 'Politik',
        dueDate: '2026-08-18T10:00',
      );

      final merged = mergeTasks(
        iservTasks: [
          IservTask(
            title: 'Alt',
            subject: 'Mathematik',
            dueDate: '2026-08-20T08:00',
          ),
          IservTask(
            title: 'Dringend',
            subject: 'Deutsch',
            dueDate: '2026-08-14T08:00',
          ),
        ],
        tempTasks: await store.load(),
        engine: engine,
      );

      expect(
        [for (final t in merged) t['title']],
        ['Dringend', 'Referat vorbereiten', 'Alt'],
      );
      expect(merged[0]['slot'], 'Mo.3'); // Deutsch-Default
      expect(merged[1]['source'], 'temp');
      expect(merged[1]['slot'], 'Fr.3'); // Politik-Default
      expect(merged[2]['slot'], 'Mo.1');
    });

    test('ohne Abgabedatum zuletzt', () {
      final merged = mergeTasks(
        iservTasks: [IservTask(title: 'Kein Datum', subject: 'Kunst')],
        tempTasks: const [],
        engine: IservMappingEngine(),
      );
      expect(merged.single['due_date'], isNull);
      expect(merged.single['slot'], 'Mi.2');
    });

    test('erledigte lokale Aufgaben werden sofort ausgeblendet', () {
      final merged = mergeTasks(
        iservTasks: const [],
        tempTasks: [
          TempAssignment(
            id: 1,
            title: 'Erledigt',
            completedAt: DateTime.now().toIso8601String(),
          ),
          const TempAssignment(id: 2, title: 'Offen'),
        ],
        engine: IservMappingEngine(),
      );

      expect(merged.map((task) => task['title']), ['Offen']);
    });
  });
}

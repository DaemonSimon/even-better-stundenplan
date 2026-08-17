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
          IservTask(title: 'Alt', subject: 'Mathematik', dueDate: '2026-08-20T08:00'),
          IservTask(title: 'Dringend', subject: 'Deutsch', dueDate: '2026-08-14T08:00'),
        ],
        tempTasks: await store.load(),
        engine: engine,
      );

      expect([for (final t in merged) t['title']], [
        'Dringend',
        'Referat vorbereiten',
        'Alt',
      ]);
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
  });
}
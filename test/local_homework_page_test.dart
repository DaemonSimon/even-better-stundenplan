import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/pages/local_homework_page.dart';
import 'package:better_stundenplan/services/iserv_mapping.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Hausaufgabe wird ohne Anmeldung lokal zur Stunde gespeichert', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalHomeworkPage(
          subject: 'Mathematik',
          lessonDate: DateTime(2026, 11, 12),
          periods: const [3],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hausaufgabe eintragen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Arbeitsblatt S. 12');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('Arbeitsblatt S. 12'), findsOneWidget);
    final stored = (await TempAssignmentStore().load()).single;
    expect(stored.subject, 'Mathematik');
    expect(stored.dueDate, '2026-11-12');
    expect(stored.lessonDate, '2026-11-12');
    expect(stored.hour, '3');

  });

  test('Doppelstunden-Hausaufgabe wird auf beiden Perioden gespeichert', () async {
    final store = TempAssignmentStore();
    await store.add(
      title: 'Doppelstunde',
      subject: 'Mathematik',
      lessonDate: '2026-11-12',
      hour: '1+2',
    );

    final task = (await store.load()).single;
    expect(task.periods, [1, 2]);
    expect(task.periods.any(const [1].contains), isTrue);
    expect(task.periods.any(const [2].contains), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/services/subject_names.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('zeigt die gewünschten Namen für Fachkürzel', () async {
    expect(await SubjectNames.displayName('DE'), 'Deutsch');
    expect(await SubjectNames.displayName('SP'), 'Sport');
    expect(await SubjectNames.displayName('EN'), 'Englisch');
    expect(await SubjectNames.displayName('MA'), 'Mathe');
    expect(await SubjectNames.displayName('PO'), 'Politik');
    expect(await SubjectNames.displayName('PH'), 'Physik');
  });

  test('erhält Zusätze hinter einem Fachkürzel', () async {
    expect(await SubjectNames.displayName('PO [Kl. 10]'), 'Politik [Kl. 10]');
  });

  test('Alias gilt für dasselbe Fach mit und ohne Gruppenzusatz', () async {
    await SubjectNames.saveAlias('A:DE', 'Deutsch erweitert');

    expect(await SubjectNames.displayName('DE'), 'Deutsch erweitert');
    expect(await SubjectNames.displayName('B:DE'), 'B:Deutsch erweitert');
    expect(
      await SubjectNames.displayName('A:DE', stripGroup: true),
      'Deutsch erweitert',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('alias:fach:DE'), 'Deutsch erweitert');
    expect(prefs.getString('alias:fach:EN'), isNull);
  });

  test('unveränderter Standardname wird nicht als Alias gespeichert', () async {
    await SubjectNames.saveAlias('DE', 'Deutsch');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('alias:fach:DE'), isNull);
  });
}

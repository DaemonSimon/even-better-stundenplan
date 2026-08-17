import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/providers/teacher_directory_provider.dart';
import 'package:better_stundenplan/services/teacher_directory.dart';

void main() {
  group('parse', () {
    late String kollegiumHtml;

    setUpAll(() {
      kollegiumHtml = File('test/fixtures/kollegium.html').readAsStringSync();
    });

    test('liest Namen, Kürzel und Foto-URL aus den lehrer-cards', () {
      final entries = TeacherDirectory.parse(
        kollegiumHtml,
        origin: 'https://start.bbs-papenburg.de',
      );

      expect(entries, hasLength(4));
      final abbes = entries['ATWT'];
      expect(abbes?.fullName, 'Thomas Abbes');
      expect(
        abbes?.photoUrl,
        'https://start.bbs-papenburg.de/images/Organisation_Dateien/kollegium/Abbes_Thomas.jpg',
      );

      final ahrens = entries['ITHC'];
      expect(ahrens?.fullName, 'Hermann-Josef Ahrens');
      expect(
        ahrens?.photoUrl,
        'https://start.bbs-papenburg.de/images/Organisation_Dateien/kollegium/Ahrens_Hermann-Josef.jpg',
      );

      final albers = entries['AKWT'];
      expect(
        albers?.photoUrl,
        'https://start.bbs-papenburg.de/images/Organisation_Dateien/kollegium/Albers Katharina.jpg',
      );

      final antons = entries['ANMT'];
      expect(antons?.photoUrl, 'https://cdn.example.org/extern.jpg');
    });

    test('ignoriert Karten ohne Kürzel', () {
      final entries = TeacherDirectory.parse(kollegiumHtml);
      expect(entries.containsKey('ATWT'), isTrue);
      expect(entries.values.where((e) => e.fullName.contains('Ameln')), isEmpty);
    });

    test('leere Kürzel ergeben keinen Eintrag', () {
      final entries = TeacherDirectory.parse(
        '<div class="lehrer-card"><h3>X</h3><p>Kürzel: <strong></strong></p></div>',
      );
      expect(entries, isEmpty);
    });
  });

  group('TeacherDirectoryProvider', () {
    test('resolve liefert vollen Namen bzw. Fallback-Kürzel', () {
      final provider = TeacherDirectoryProvider(
        initialEntries: const {
          'ATWT': TeacherEntry(
            kuerzel: 'ATWT',
            fullName: 'Thomas Abbes',
            photoUrl: 'https://start.bbs-papenburg.de/abbes.jpg',
          ),
          'KREP': TeacherEntry(
            kuerzel: 'KREP',
            fullName: 'Maren Krep',
          ),
        },
      );

      expect(provider.resolve('ATWT'), 'Thomas Abbes');
      expect(provider.resolve('atwt'), 'Thomas Abbes');
      expect(provider.resolve('ATWT '), 'Thomas Abbes');
      expect(provider.resolve('UNBEKANNT'), 'UNBEKANNT');
      expect(
        provider.lookup('ATWT')?.photoUrl,
        'https://start.bbs-papenburg.de/abbes.jpg',
      );
      expect(provider.lookup(''), isNull);
    });

    test('resolve erhält ein Präfix und löst das Kürzel dahinter auf', () {
      final provider = TeacherDirectoryProvider(
        initialEntries: const {
          'KREP': TeacherEntry(
            kuerzel: 'KREP',
            fullName: 'Maren Krep',
            photoUrl: 'https://start.bbs-papenburg.de/krep.jpg',
          ),
        },
      );

      expect(provider.resolve('A:KREP'), 'A: Maren Krep');
      expect(provider.lookup('A:KREP')?.fullName, 'Maren Krep');
      expect(provider.lookup('A:KREP')?.photoUrl,
          'https://start.bbs-papenburg.de/krep.jpg');
      expect(provider.resolve('A:UNBEKANNT'), 'A:UNBEKANNT');
      expect(provider.resolve('KREP:'), 'KREP:');
      expect(provider.resolve(':KREP'), ':KREP');
    });

    test('lädt vom Netz und schreibt den Platten-Cache', () async {
      SharedPreferences.setMockInitialValues({});
      final html = File('test/fixtures/kollegium.html').readAsStringSync();
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://start.bbs-papenburg.de/kollegium.php');
        return http.Response(html, 200);
      });

      final provider = TeacherDirectoryProvider(
        directory: TeacherDirectory(client: client),
      );
      await provider.load();

      expect(provider.resolve('ITHC'), 'Hermann-Josef Ahrens');

      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('teacher_directory_cache');
      expect(cached, isNotNull);
      expect(cached, contains('Hermann-Josef Ahrens'));
      expect(cached, contains('Abbes_Thomas.jpg'));
    });

    test('fällt bei Netzwerkfehler auf den Platten-Cache zurück', () async {
      SharedPreferences.setMockInitialValues({
        'teacher_directory_cache':
            '[{"k":"ATWT","n":"Thomas Abbes","p":"https://start.bbs-papenburg.de/abbes.jpg"}]',
      });
      final client = MockClient((request) async {
        throw http.ClientException('offline');
      });

      final provider = TeacherDirectoryProvider(
        directory: TeacherDirectory(client: client),
      );
      await provider.load();

      expect(provider.resolve('ATWT'), 'Thomas Abbes');
      expect(
        provider.lookup('ATWT')?.photoUrl,
        'https://start.bbs-papenburg.de/abbes.jpg',
      );
    });
  });
}
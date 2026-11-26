import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/pages/legal_page.dart';
import 'package:better_stundenplan/services/iserv_session.dart';

const _base = 'https://schule.example.de/iserv';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('alte Klartext-Cookies werden verschlüsselt umgezogen', () async {
    final stored = jsonEncode({'IServSession': 'abc'});
    SharedPreferences.setMockInitialValues({'iserv_cookies': stored});

    final session = IservSession(baseUrl: _base);
    await session.restore();

    expect(session.cookies, {'IServSession': 'abc'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('iserv_cookies'), isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'iserv_cookies'),
      stored,
    );

    await session.clear();
    expect(
      await const FlutterSecureStorage().read(key: 'iserv_cookies'),
      isNull,
    );
  });

  for (final target in [
    'https://fremd.example.com/auth/login',
    'http://schule.example.de/iserv/auth/login',
  ]) {
    test('Passwort geht nicht an $target', () async {
      final requested = <Uri>[];
      final session = IservSession(
        baseUrl: _base,
        client: MockClient((request) async {
          requested.add(request.url);
          if (request.method == 'POST') {
            return http.Response('', 307, headers: {'location': target});
          }
          return http.Response(
            '<form><input name="_username"></form>',
            200,
            request: request,
          );
        }),
      );

      await expectLater(
        session.login('schueler', 'geheim'),
        throwsA(isA<IservException>()),
      );
      expect(requested, isNot(contains(Uri.parse(target))));
    });
  }

  testWidgets('Datenschutzerklärung ist in der App lesbar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Datenschutzerklärung'), findsWidgets);
    expect(find.text('Wer ist verantwortlich?'), findsOneWidget);
  });
}

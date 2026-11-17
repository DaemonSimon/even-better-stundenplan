import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:better_stundenplan/services/http_timeout.dart';

void main() {
  test('sendWithTimeout bricht hängende Requests ab', () async {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(seconds: 5));
      return http.Response('zu spät', 200);
    });

    await expectLater(
      sendWithTimeout(
        client,
        http.Request('GET', Uri.parse('https://example.de/')),
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('sendWithTimeout liefert schnelle Antworten normal', () async {
    final client = MockClient((request) async => http.Response('ok', 200));

    final response = await sendWithTimeout(
      client,
      http.Request('GET', Uri.parse('https://example.de/')),
    );

    expect(response.statusCode, 200);
    expect(response.body, 'ok');
  });

  test('Standard-Timeout ist kurz genug für schlechte Verbindungen', () {
    expect(kHttpTimeout, lessThanOrEqualTo(const Duration(seconds: 30)));
  });
}

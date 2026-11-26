import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/components/iserv_tasks_view.dart';
import 'package:better_stundenplan/pages/authentication_page.dart';
import 'package:better_stundenplan/pages/welcome_page.dart';
import 'package:better_stundenplan/services/iserv_session.dart';
import 'package:better_stundenplan/services/secure_storage.dart';
import 'package:better_stundenplan/services/session_manager.dart';

class _NoStorage implements CredentialStorage {
  @override
  Future<String?> getSessionId() async => null;
  @override
  Future<String?> getEmail() async => null;
  @override
  Future<String?> getPassword() async => null;
  @override
  Future<void> saveSessionId(String sessionId) async {}
  @override
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> clear() async {}
}

/// Autofill-Hinweise aller Textfelder im Baum.
List<Iterable<String>?> _hints(WidgetTester tester) => [
  for (final field in tester.widgetList<TextField>(find.byType(TextField)))
    field.autofillHints,
];

void main() {
  testWidgets('Willkommensbildschirm führt zur Anmeldung und merkt sich das', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    expect(await WelcomePage.isDone(), isFalse);

    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, __) => const WelcomePage()),
        GoRoute(
          path: '/authenticate',
          builder: (_, __) => const Text('Login-Seite'),
        ),
        GoRoute(path: '/', builder: (_, __) => const Text('Start')),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('Willkommen bei Better Stundenplan'), findsOneWidget);
    await tester.ensureVisible(find.text("Los geht's – anmelden"));
    await tester.tap(find.text("Los geht's – anmelden"));
    await tester.pumpAndSettle();

    expect(find.text('Login-Seite'), findsOneWidget);
    expect(await WelcomePage.isDone(), isTrue);
  });

  testWidgets('Stundenplan-Login meldet E-Mail und Passwort an Autofill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationPage(
          sessionManager: SessionManager(
            storage: _NoStorage(),
            client: MockClient((_) async => http.Response('', 200)),
          ),
        ),
      ),
    );

    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(_hints(tester), [
      [AutofillHints.email, AutofillHints.username],
      [AutofillHints.password],
    ]);
  });

  testWidgets('IServ-Login meldet Benutzername und Passwort an Autofill', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final session = IservSession(
      client: MockClient(
        (_) async => http.Response(
          '<html><body><input name="_username"></body></html>',
          200,
        ),
      ),
      baseUrl: 'https://schule.example.de/iserv',
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: IservTasksView(session: session))),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(TextButton, 'Anmelden'));
    await tester.pump();

    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(_hints(tester), [
      [AutofillHints.username],
      [AutofillHints.password],
    ]);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:better_stundenplan/main.dart';
import 'package:better_stundenplan/providers/teacher_directory_provider.dart';
import 'package:better_stundenplan/services/secure_storage.dart';
import 'package:better_stundenplan/services/session_manager.dart';
import 'package:better_stundenplan/services/teacher_directory.dart';

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

void main() {
  testWidgets('der Router bleibt über Rebuilds von MyApp derselbe', (
    tester,
  ) async {
    final sessionManager = SessionManager(storage: _NoStorage());
    final teacherDirectory = TeacherDirectoryProvider(
      directory: TeacherDirectory(),
    );
    Widget app() => MyApp(
      sessionManager: sessionManager,
      teacherDirectory: teacherDirectory,
    );

    // Login-Seite als Startpunkt, damit keine Netzwerk-Abrufe nötig sind.
    await tester.pumpWidget(app());
    final router = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .routerConfig as GoRouter;
    router.go('/authenticate');
    await tester.pump();

    await tester.pumpWidget(app());
    await tester.pump();

    final after = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .routerConfig as GoRouter;
    expect(after, same(router));
    expect(
      after.routerDelegate.currentConfiguration.uri.path,
      '/authenticate',
    );
  });

  testWidgets('Material-Texte sind deutsch', (tester) async {
    final sessionManager = SessionManager(storage: _NoStorage());
    await tester.pumpWidget(
      MyApp(
        sessionManager: sessionManager,
        teacherDirectory: TeacherDirectoryProvider(
          directory: TeacherDirectory(),
        ),
      ),
    );

    final context = tester.element(find.byType(Navigator).first);
    expect(Localizations.localeOf(context).languageCode, 'de');
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Abbrechen');
  });
}

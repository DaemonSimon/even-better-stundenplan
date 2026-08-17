import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'pages/home_page.dart';
import 'pages/authentication_page.dart';
import 'providers/teacher_directory_provider.dart';
import 'services/session_manager.dart';
import 'services/secure_storage.dart';
import 'services/teacher_directory.dart';
import 'routes.dart';

const Color _seedColor = Color(0xFFC59B31);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'de_DE';
  await initializeDateFormatting('de_DE');
  final storage = SecureCredentialStorage();
  await storage.migrateFromSharedPreferences();
  final sessionManager = SessionManager(storage: storage);
  await sessionManager.checkAuthentication();

  // Kollegiums-Verzeichnis (Kürzel -> volle Namen) im Hintergrund laden.
  final teacherDirectory = TeacherDirectoryProvider(
    directory: TeacherDirectory(),
  );
  unawaited(teacherDirectory.load());

  runApp(
    MyApp(sessionManager: sessionManager, teacherDirectory: teacherDirectory),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.sessionManager,
    required this.teacherDirectory,
  });

  final SessionManager sessionManager;
  final TeacherDirectoryProvider teacherDirectory;

  static final _defaultLightColorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.light,
  );

  static final _defaultDarkColorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    // Router hier definieren, damit wir auf authenticationStatus zugreifen können
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => HomePage(
            title: "Stundenplan",
            sessionManager: sessionManager,
            teacherDirectory: teacherDirectory,
          ),
        ),
        GoRoute(
          path: '/authenticate',
          builder: (context, state) =>
              AuthenticationPage(sessionManager: sessionManager),
        ),
        GoRouteData.$route(path: '/details', factory: DetailsRoute.fromState),
      ],
    );

    return DynamicColorBuilder(
      builder: (lightColorScheme, darkColorScheme) {
        return MaterialApp.router(
          routerConfig: router,
          title: "Better Stundenplan",
          theme: ThemeData(
            colorScheme: lightColorScheme ?? _defaultLightColorScheme,
            brightness: Brightness.light,
            useMaterial3: true,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
              },
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: darkColorScheme ?? _defaultDarkColorScheme,
            brightness: Brightness.dark,
            useMaterial3: true,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
              },
            ),
          ),
        );
      },
    );
  }
}
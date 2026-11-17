import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'pages/home_page.dart';
import 'pages/authentication_page.dart';
import 'pages/welcome_page.dart';
import 'providers/teacher_directory_provider.dart';
import 'services/session_manager.dart';
import 'services/secure_storage.dart';
import 'services/teacher_directory.dart';
import 'routes.dart';
import 'components/class_card.dart';
import 'services/homework_attachments.dart';
import 'services/iserv_mapping.dart';

const Color _seedColor = Color(0xFFC59B31);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  Intl.defaultLocale = 'de_DE';
  await initializeDateFormatting('de_DE');
  await _purgeExpiredHomework();
  final storage = SecureCredentialStorage();
  await storage.migrateFromSharedPreferences();
  final sessionManager = SessionManager(storage: storage);
  await sessionManager.checkAuthentication();

  // Kollegiums-Verzeichnis (Kürzel -> volle Namen) im Hintergrund laden.
  final teacherDirectory = TeacherDirectoryProvider(
    directory: TeacherDirectory(),
  );
  unawaited(teacherDirectory.load());

  // Willkommensbildschirm nur beim allerersten Start – wer schon
  // angemeldet ist (z. B. nach einem Update), bekommt ihn nicht.
  final showWelcome =
      !sessionManager.isLoggedIn && !await WelcomePage.isDone();

  runApp(
    MyApp(
      sessionManager: sessionManager,
      teacherDirectory: teacherDirectory,
      showWelcome: showWelcome,
    ),
  );
}

Future<void> _purgeExpiredHomework() async {
  try {
    final expired = await TempAssignmentStore().purgeCompleted();
    for (final task in expired) {
      await HomeworkAttachments.deleteOwned(task.imagePaths);
    }
  } catch (error) {
    debugPrint(
      'Abgelaufene Hausaufgaben konnten nicht gelöscht werden: $error',
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.sessionManager,
    required this.teacherDirectory,
    this.showWelcome = false,
  });

  final SessionManager sessionManager;
  final TeacherDirectoryProvider teacherDirectory;

  /// Mit dem Willkommensbildschirm starten (erster App-Start).
  final bool showWelcome;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static final _defaultLightColorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.light,
  );

  static final _defaultDarkColorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.dark,
  );

  // Router nur einmal anlegen: Ein neuer GoRouter bei jedem Rebuild
  // (z. B. durch DynamicColorBuilder) würde den Navigationsstand verwerfen.
  late final GoRouter _router = GoRouter(
    initialLocation: widget.showWelcome ? '/welcome' : '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomePage(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => HomePage(
          title: "Stundenplan",
          sessionManager: widget.sessionManager,
          teacherDirectory: widget.teacherDirectory,
        ),
      ),
      GoRoute(
        path: '/authenticate',
        builder: (context, state) =>
            AuthenticationPage(sessionManager: widget.sessionManager),
      ),
      GoRouteData.$route(path: '/details', factory: DetailsRoute.fromState),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightColorScheme, darkColorScheme) {
        return MaterialApp.router(
          routerConfig: _router,
          title: "Better Stundenplan",
          // Material-Texte (Datumsauswahl, Tooltips, "Abbrechen" …) auf
          // Deutsch statt Englisch.
          locale: const Locale('de', 'DE'),
          supportedLocales: const [Locale('de', 'DE')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
            scaffoldBackgroundColor: appBackground,
            canvasColor: appBackground,
            cardColor: cardBackground,
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

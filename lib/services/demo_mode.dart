import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo_data.dart';
import 'iserv_logout.dart';

/// Testkonto ("demo" / "demo"), z. B. für die Prüfung durch Google Play.
///
/// Solange der Demo-Modus aktiv ist, beantwortet die App alle Anfragen
/// selbst mit erfundenen Daten ([demoResponse]) und kontaktiert keine
/// Schulseite. Parser und Oberfläche sind dieselben wie sonst.
class DemoMode {
  DemoMode._();

  static const String user = 'demo';
  static const String password = 'demo';
  static const String _prefsKey = 'demo_mode';

  static final ValueNotifier<bool> active = ValueNotifier(false);

  static bool isDemoLogin(String name, String secret) =>
      name.trim().toLowerCase() == user && secret == password;

  /// Beim App-Start den gespeicherten Zustand laden.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      active.value = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      // Ohne Einstellungen normal starten.
    }
  }

  static Future<void> enter() async {
    if (active.value) return;
    // Zuerst umschalten, damit beim Aufräumen nichts ins Netz geht.
    active.value = true;
    await (await SharedPreferences.getInstance()).setBool(_prefsKey, true);
    await _clearSchoolData();
  }

  static Future<void> leave() async {
    if (!active.value) return;
    await _clearSchoolData();
    await (await SharedPreferences.getInstance()).remove(_prefsKey);
    active.value = false;
  }

  /// Entfernt alles, was von den Schulseiten (oder der Demo) stammt, damit
  /// sich echte und erfundene Daten nicht mischen. Eigene Hausaufgaben,
  /// Aliasse und Einstellungen bleiben.
  static Future<void> _clearSchoolData() async {
    Future<void> step(Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        // Ein fehlgeschlagener Schritt soll die übrigen nicht verhindern.
      }
    }

    await step(logoutFromIserv);
    await step(() => FlutterLocalNotificationsPlugin().cancelAll());
    await step(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('iserv_calendar_events');
      await prefs.remove('teacher_directory_cache');
    });
    await step(() async {
      final support = await getApplicationSupportDirectory();
      final file = File('${support.path}/timetable_cache.json');
      if (await file.exists()) await file.delete();
    });
  }
}

/// Leitet Anfragen im Demo-Modus an die erfundenen Daten um.
class DemoAwareClient extends http.BaseClient {
  DemoAwareClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      DemoMode.active.value ? demoResponse(request) : _inner.send(request);

  @override
  void close() => _inner.close();
}

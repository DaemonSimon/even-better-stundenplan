import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'iserv_logout.dart';
import 'session_manager.dart';

/// Löscht alles, was die App auf dem Gerät gespeichert hat: Zugangsdaten,
/// Cookies, Caches, Hausaufgaben samt Fotos, Einstellungen und geplante
/// Benachrichtigungen.
///
/// Jeder Schritt läuft für sich, damit ein Fehler die übrigen nicht
/// verhindert. Liefert `false`, wenn mindestens ein Schritt scheiterte.
Future<bool> deleteAllAppData(SessionManager sessionManager) async {
  var complete = true;
  Future<void> step(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      complete = false;
    }
  }

  await step(logoutFromIserv);
  await step(sessionManager.logout);
  await step(() => const FlutterSecureStorage().deleteAll());
  await step(() => FlutterLocalNotificationsPlugin().cancelAll());
  await step(() async {
    await (await SharedPreferences.getInstance()).clear();
  });
  await step(() async {
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    final cache = File('${support.path}/timetable_cache.json');
    if (await cache.exists()) await cache.delete();
    final images = Directory('${documents.path}/homework_images');
    if (await images.exists()) await images.delete(recursive: true);
  });
  // Temporäre Dateien: geöffnete Anhänge und Kopien aus Kamera/Galerie.
  await step(() async {
    final temporary = await getTemporaryDirectory();
    await for (final entry in temporary.list()) {
      await entry.delete(recursive: true);
    }
  });
  return complete;
}

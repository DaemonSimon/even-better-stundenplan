import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'connectivity_monitor.dart';
import 'iserv_session.dart';
import 'iserv_task_detail.dart';
import 'iserv_tasks.dart';

/// Hält laufende IServ-Aufgaben offline bereit: Detailseite und alle
/// Anhänge werden nach jedem erfolgreichen Laden der Aufgabenliste im
/// Hintergrund heruntergeladen. Ist eine Aufgabe vorbei (Abgabetermin
/// verstrichen oder nicht mehr in der Liste der offenen Aufgaben), wird
/// ihr Ordner wieder gelöscht.
///
/// Ablage: `<App-Support>/iserv_offline/<Aufgaben-ID>/` mit `detail.html`
/// und den Anhängen.
class IservOfflineStore {
  IservOfflineStore({Future<Directory> Function()? rootDir})
    : _rootDir = rootDir ?? _defaultRoot;

  static final IservOfflineStore instance = IservOfflineStore();

  /// Größere Dateien werden nicht vorab geladen (nur beim Antippen).
  static const int maxFileBytes = 50 * 1024 * 1024;

  /// So lange gilt eine gespeicherte Detailseite als aktuell; danach wird
  /// sie neu geladen, falls Lehrkräfte Anhänge nachgereicht haben.
  static const Duration detailMaxAge = Duration(hours: 6);

  final Future<Directory> Function() _rootDir;
  bool _syncing = false;

  static Future<Directory> _defaultRoot() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/iserv_offline',
  );

  /// Aufgaben-ID aus einer Detail-URL (`…/exercise/show/123`).
  static String? taskIdOf(String url) => RegExp(
    r'/exercise/(?:past/exercise/)?show/(\d+)',
  ).firstMatch(url)?.group(1);

  /// Stabiler Dateiname je Anhang (URL-Hash + lesbarer Name).
  static String fileNameFor(IservAttachment attachment) {
    final safe = attachment.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '${_fnv1a(attachment.url)}_$safe';
  }

  static String _fnv1a(String text) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(text)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<Directory> _taskDir(String id) async =>
      Directory('${(await _rootDir()).path}/$id');

  /// Gespeicherte Detailseite einer Aufgabe, falls vorhanden.
  Future<String?> loadDetailHtml(String id) async {
    try {
      final file = File('${(await _taskDir(id)).path}/detail.html');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Aktualisiert die gespeicherte Detailseite, aber nur für Aufgaben,
  /// die bereits offline vorgehalten werden.
  Future<void> updateDetailHtmlIfKept(String id, String html) async {
    try {
      final dir = await _taskDir(id);
      if (!await dir.exists()) return;
      await File('${dir.path}/detail.html').writeAsString(html);
    } catch (_) {
      // Offline-Kopie ist optional.
    }
  }

  /// Gespeicherte Kopie eines Anhangs, falls vorhanden.
  Future<File?> cachedAttachment(IservAttachment attachment) async {
    try {
      final root = await _rootDir();
      if (!await root.exists()) return null;
      final name = fileNameFor(attachment);
      await for (final entry in root.list()) {
        if (entry is! Directory) continue;
        final file = File('${entry.path}/$name');
        if (await file.exists()) return file;
      }
    } catch (_) {
      // z. B. in Tests ohne path_provider.
    }
    return null;
  }

  /// Gleicht die Offline-Kopien mit den offenen Aufgaben ab: neue Aufgaben
  /// samt Anhängen herunterladen, vorbei Aufgaben löschen.
  Future<void> sync(IservSession session, List<IservTask> openTasks) async {
    if (_syncing) return;
    _syncing = true;
    try {
      final keep = _runningTaskUrls(openTasks, DateTime.now());
      final root = await _rootDir();
      await root.create(recursive: true);

      // Vorbei: Ordner löschen.
      await for (final entry in root.list()) {
        final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (entry is Directory && !keep.containsKey(id)) {
          await entry.delete(recursive: true);
        }
      }

      // Laufend: Details + Anhänge laden.
      for (final MapEntry(key: id, value: url) in keep.entries) {
        try {
          await _syncTask(session, id, url);
        } catch (error) {
          if (isNetworkError(error)) {
            ConnectivityMonitor.instance.reportFailure();
            return; // Ohne Netz bringen weitere Versuche nichts.
          }
          debugPrint('Offline-Kopie für Aufgabe $id fehlgeschlagen: $error');
        }
      }
    } catch (error) {
      debugPrint('IServ-Offline-Abgleich fehlgeschlagen: $error');
    } finally {
      _syncing = false;
    }
  }

  /// ID → Detail-URL aller Aufgaben, deren Abgabe noch nicht vorbei ist.
  static Map<String, String> _runningTaskUrls(
    List<IservTask> tasks,
    DateTime now,
  ) {
    final result = <String, String>{};
    for (final task in tasks) {
      final due = task.dueDate == null
          ? null
          : DateTime.tryParse(task.dueDate!);
      if (due != null && due.isBefore(now)) continue;
      for (final link in task.links) {
        final id = isTaskDetailUrl(link) ? taskIdOf(link) : null;
        if (id != null) {
          result[id] = link;
          break;
        }
      }
    }
    return result;
  }

  Future<void> _syncTask(IservSession session, String id, String url) async {
    final dir = await _taskDir(id);
    await dir.create(recursive: true);
    final detailFile = File('${dir.path}/detail.html');

    // Detailseite nur neu laden, wenn sie fehlt oder alt ist.
    String html;
    final exists = await detailFile.exists();
    final fresh =
        exists &&
        DateTime.now().difference(await detailFile.lastModified()) <
            detailMaxAge;
    if (fresh) {
      html = await detailFile.readAsString();
    } else {
      final response = await session.get(url);
      if (response.statusCode != 200) return;
      html = response.body;
      await detailFile.writeAsString(html);
    }

    final detail = parseTaskDetail(html, baseUrl: session.baseUrl);
    final wanted = <String>{'detail.html'};
    for (final attachment in detail.attachments) {
      final name = fileNameFor(attachment);
      wanted.add(name);
      final file = File('${dir.path}/$name');
      if (await file.exists()) continue;
      if (_parseSize(attachment.size) > maxFileBytes) continue;

      final response = await session.get(attachment.downloadUrl);
      if (response.statusCode != 200) continue;
      // Erst vollständig schreiben, dann umbenennen: keine halben Dateien.
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(response.bodyBytes);
      await tmp.rename(file.path);
    }

    // Von der Lehrkraft entfernte Anhänge auch lokal löschen.
    await for (final entry in dir.list()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File && !wanted.contains(name)) await entry.delete();
    }
  }

  /// "58.36 KB" / "1,2 MB" → Bytes (0, wenn unbekannt).
  static int _parseSize(String text) {
    final match = RegExp(
      r'([\d.,]+)\s*(B|KB|MB|GB)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return 0;
    final value = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 0;
    final factor = switch (match.group(2)!.toUpperCase()) {
      'KB' => 1024,
      'MB' => 1024 * 1024,
      'GB' => 1024 * 1024 * 1024,
      _ => 1,
    };
    return (value * factor).round();
  }

  /// Alles löschen (z. B. beim IServ-Abmelden).
  Future<void> clear() async {
    try {
      final root = await _rootDir();
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Merkt sich, ob der letzte Netzwerkzugriff geklappt hat, und erkennt,
/// wann wieder Internet da ist.
///
/// Solange alles funktioniert, passiert hier nichts. Schlägt ein Abruf
/// fehl ([reportFailure]), gilt die App als offline und prüft im
/// Hintergrund in kurzen Abständen, ob der Server wieder erreichbar ist.
/// Sobald das klappt, werden die Listener benachrichtigt, damit Ansichten
/// ihre gespeicherten Daten aktualisieren.
class ConnectivityMonitor extends ChangeNotifier {
  ConnectivityMonitor({
    Future<bool> Function()? probe,
    this.pollInterval = const Duration(seconds: 15),
    bool? pollingEnabled,
  }) : _probe = probe ?? _defaultProbe,
       // In Tests keine echten Sockets/Timer starten.
       _pollingEnabled =
           pollingEnabled ?? !Platform.environment.containsKey('FLUTTER_TEST');

  /// Gemeinsame Instanz für die ganze App.
  static final ConnectivityMonitor instance = ConnectivityMonitor();

  final Future<bool> Function() _probe;
  final Duration pollInterval;
  final bool _pollingEnabled;

  bool _online = true;
  Timer? _timer;
  bool _probing = false;

  /// `false`, solange der letzte Abruf fehlgeschlagen ist.
  bool get isOnline => _online;

  /// Ein Abruf hat geklappt: wieder online.
  void reportSuccess() {
    _timer?.cancel();
    _timer = null;
    if (!_online) {
      _online = true;
      notifyListeners();
    }
  }

  /// Ein Abruf ist am Netzwerk gescheitert: offline, regelmäßig prüfen.
  void reportFailure() {
    if (_online) {
      _online = false;
      notifyListeners();
    }
    if (_pollingEnabled) {
      _timer ??= Timer.periodic(pollInterval, (_) => _check());
    }
  }

  /// Prüft sofort, ob wieder Internet da ist (z. B. beim Zurückkehren
  /// in die App). Ohne Wirkung, solange die App als online gilt.
  Future<void> checkNow() => _online ? Future.value() : _check();

  Future<void> _check() async {
    if (_probing) return;
    _probing = true;
    try {
      if (await _probe()) reportSuccess();
    } finally {
      _probing = false;
    }
  }

  static Future<bool> _defaultProbe() async {
    try {
      final socket = await Socket.connect(
        'virtueller-stundenplan.org',
        443,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// `true` für Fehler, die nach fehlender Verbindung aussehen (kein
/// Server-/Parse-Fehler).
bool isNetworkError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HttpException ||
    error is http.ClientException ||
    error.toString().contains('nicht erreichbar');

import 'package:flutter/foundation.dart';

/// Debug-Uhr: simuliert die aktuelle Zeit und eine Ablaufgeschwindigkeit,
/// damit die Live-Effekte (JETZT-Badge, rote "Jetzt"-Linie,
/// Fortschrittsbalken) ohne Warten sichtbar sind.
class SimulatedClock extends ChangeNotifier {
  SimulatedClock({DateTime? start}) {
    _anchorReal = DateTime.now();
    _anchorSim = start ?? DateTime.now();
  }

  /// Geschwindigkeitsstufen für den Debug-Slider (x1 … x3600).
  static const List<double> speedSteps = [
    1, 2, 5, 10, 30, 60, 120, 300, 600, 1800, 3600,
  ];

  late DateTime _anchorReal;
  late DateTime _anchorSim;

  double _speed = 1;

  /// Simulierte aktuelle Zeit.
  DateTime now() {
    final elapsedMs = DateTime.now().difference(_anchorReal).inMilliseconds;
    return _anchorSim.add(
      Duration(milliseconds: (elapsedMs * _speed).round()),
    );
  }

  double get speed => _speed;

  /// Weicht die Simulation von der echten Zeit ab?
  bool get isCustomized =>
      _speed != 1 ||
      now().difference(DateTime.now()).abs() > const Duration(seconds: 30);

  /// Takt für Live-UI-Updates: die simulierte Zeit rückt pro Tick ~30
  /// Sekunden vor (min. 100 ms, max. 30 s).
  Duration get tickInterval {
    if (_speed <= 1) return const Duration(seconds: 30);
    final ms = (30000 / _speed).round().clamp(100, 30000);
    return Duration(milliseconds: ms);
  }

  /// Setzt die simulierte Zeit absolut (Datum + Uhrzeit).
  void setTime(DateTime value) {
    _anchorReal = DateTime.now();
    _anchorSim = value;
    notifyListeners();
  }

  /// Setzt die Geschwindigkeit, ohne die simulierte Zeit springen zu lassen.
  void setSpeed(double value) {
    _anchorReal = DateTime.now();
    _anchorSim = now();
    _speed = value;
    notifyListeners();
  }

  /// Zurück zur echten Zeit (x1, keine Abweichung).
  void reset() {
    _anchorReal = DateTime.now();
    _anchorSim = DateTime.now();
    _speed = 1;
    notifyListeners();
  }
}
import 'package:flutter/material.dart';

/// Zeitfenster einer Unterrichtsstunde bzw. eines Blocks.
class BlockTime {
  const BlockTime(this.start, this.end);

  final TimeOfDay start;
  final TimeOfDay end;

  int get startInMinutes => start.hour * 60 + start.minute;
  int get endInMinutes => end.hour * 60 + end.minute;
  int get durationInMinutes => endInMinutes - startInMinutes;
}

/// Stunden-Raster der Schule: 8 Einzelstunden à 45 Minuten.
/// Je zwei aufeinanderfolgende Stunden bilden eine Doppelstunde
/// (Block): (1,2), (3,4), (5,6) und (7,8). Die Mittagspause liegt
/// zwischen der 6. und der 7. Stunde.
class BlockSchedule {
  BlockSchedule._();

  /// Mittagspause: 13:15 – 13:45 (zwischen 6. und 7. Stunde).
  static const TimeOfDay lunchStart = TimeOfDay(hour: 13, minute: 15);
  static const TimeOfDay lunchEnd = TimeOfDay(hour: 13, minute: 45);

  /// Zeitfenster vor Unterrichtsbeginn, in dem eine Klasse als
  /// "urgent" (Beginnt gleich) hervorgehoben wird.
  static const int urgencyWindowMinutes = 5;

  /// Die acht 45-Minuten-Stunden des Schultags.
  static const Map<int, BlockTime> periodTimes = {
    1: BlockTime(
      TimeOfDay(hour: 8, minute: 10),
      TimeOfDay(hour: 8, minute: 55),
    ),
    2: BlockTime(
      TimeOfDay(hour: 8, minute: 55),
      TimeOfDay(hour: 9, minute: 40),
    ),
    3: BlockTime(
      TimeOfDay(hour: 10, minute: 0),
      TimeOfDay(hour: 10, minute: 45),
    ),
    4: BlockTime(
      TimeOfDay(hour: 10, minute: 45),
      TimeOfDay(hour: 11, minute: 30),
    ),
    5: BlockTime(
      TimeOfDay(hour: 11, minute: 45),
      TimeOfDay(hour: 12, minute: 30),
    ),
    6: BlockTime(
      TimeOfDay(hour: 12, minute: 30),
      TimeOfDay(hour: 13, minute: 15),
    ),
    7: BlockTime(
      TimeOfDay(hour: 13, minute: 45),
      TimeOfDay(hour: 14, minute: 30),
    ),
    8: BlockTime(
      TimeOfDay(hour: 14, minute: 30),
      TimeOfDay(hour: 15, minute: 15),
    ),
  };

  static const int _firstPeriodStartMinute = 8 * 60 + 10;
  static const int _periodDuration = 45;
  static const int _periodStride = 55;

  /// Zeitfenster einer Einzelstunde (1–8), sonst null.
  static BlockTime? periodTimeFor(int period) => periodTimes[period];

  /// Fallback-Zeiten für Stunden außerhalb des 1–8-Rasters.
  static BlockTime fallbackPeriodTimeFor(int period) {
    final start = _firstPeriodStartMinute + (period - 1) * _periodStride;
    return BlockTime(
      TimeOfDay(hour: start ~/ 60, minute: start % 60),
      TimeOfDay(
        hour: (start + _periodDuration) ~/ 60,
        minute: (start + _periodDuration) % 60,
      ),
    );
  }

  /// Block (1–4), zu dem eine Stunde gehört: (1,2), (3,4), (5,6), (7,8).
  static int blockForPeriod(int period) => (period + 1) ~/ 2;

  /// Erste Stunde eines Blocks (Block 1 -> Stunde 1, Block 4 -> Stunde 7).
  static int firstPeriodOfBlock(int block) => block * 2 - 1;

  /// Zeitfenster eines 90-Minuten-Blocks (Doppelstunde aus zwei Stunden).
  static BlockTime? timeFor(int block) {
    final first = periodTimes[block * 2 - 1];
    final last = periodTimes[block * 2];
    if (first == null || last == null) return null;
    return BlockTime(first.start, last.end);
  }

  /// Fallback-Zeiten für Blöcke außerhalb des 1–4-Rasters.
  static BlockTime fallbackTimeFor(int block) {
    final first = fallbackPeriodTimeFor(block * 2 - 1);
    final last = fallbackPeriodTimeFor(block * 2);
    return BlockTime(first.start, last.end);
  }

  /// Liegt [now] innerhalb des Zeitfensters?
  static bool isWithin(BlockTime time, DateTime now) {
    final m = now.hour * 60 + now.minute;
    return m >= time.startInMinutes && m < time.endInMinutes;
  }
}
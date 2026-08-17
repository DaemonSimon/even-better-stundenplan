import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/utils/block_schedule.dart';

void main() {
  group('BlockSchedule', () {
    test('period times are 45 minutes each', () {
      expect(
        BlockSchedule.periodTimeFor(1)!.start,
        const TimeOfDay(hour: 8, minute: 10),
      );
      expect(
        BlockSchedule.periodTimeFor(1)!.end,
        const TimeOfDay(hour: 8, minute: 55),
      );
      expect(
        BlockSchedule.periodTimeFor(2)!.start,
        const TimeOfDay(hour: 8, minute: 55),
      );
      expect(
        BlockSchedule.periodTimeFor(6)!.end,
        const TimeOfDay(hour: 13, minute: 15),
      );
      expect(
        BlockSchedule.periodTimeFor(7)!.start,
        const TimeOfDay(hour: 13, minute: 45),
      );
      expect(
        BlockSchedule.periodTimeFor(8)!.end,
        const TimeOfDay(hour: 15, minute: 15),
      );
      expect(BlockSchedule.periodTimeFor(9), isNull);
    });

    test('blocks span two periods each (double hours)', () {
      expect(
        BlockSchedule.timeFor(1)!.start,
        const TimeOfDay(hour: 8, minute: 10),
      );
      expect(
        BlockSchedule.timeFor(1)!.end,
        const TimeOfDay(hour: 9, minute: 40),
      );
      expect(
        BlockSchedule.timeFor(2)!.start,
        const TimeOfDay(hour: 10, minute: 0),
      );
      expect(
        BlockSchedule.timeFor(3)!.start,
        const TimeOfDay(hour: 11, minute: 45),
      );
      expect(
        BlockSchedule.timeFor(4)!.start,
        const TimeOfDay(hour: 13, minute: 45),
      );
      expect(
        BlockSchedule.timeFor(4)!.end,
        const TimeOfDay(hour: 15, minute: 15),
      );
      expect(BlockSchedule.timeFor(5), isNull);
    });

    test('Mittagspause liegt zwischen 6. und 7. Stunde', () {
      expect(BlockSchedule.lunchStart, const TimeOfDay(hour: 13, minute: 15));
      expect(BlockSchedule.lunchEnd, const TimeOfDay(hour: 13, minute: 45));
      expect(BlockSchedule.periodTimeFor(6)!.end, BlockSchedule.lunchStart);
      expect(BlockSchedule.periodTimeFor(7)!.start, BlockSchedule.lunchEnd);
    });

    test('blockForPeriod pairs consecutive periods', () {
      expect(BlockSchedule.blockForPeriod(1), 1);
      expect(BlockSchedule.blockForPeriod(2), 1);
      expect(BlockSchedule.blockForPeriod(3), 2);
      expect(BlockSchedule.blockForPeriod(4), 2);
      expect(BlockSchedule.blockForPeriod(5), 3);
      expect(BlockSchedule.blockForPeriod(6), 3);
      expect(BlockSchedule.blockForPeriod(7), 4);
      expect(BlockSchedule.blockForPeriod(8), 4);
      expect(BlockSchedule.blockForPeriod(9), 5);
    });

    test('firstPeriodOfBlock returns the opening period', () {
      expect(BlockSchedule.firstPeriodOfBlock(1), 1);
      expect(BlockSchedule.firstPeriodOfBlock(2), 3);
      expect(BlockSchedule.firstPeriodOfBlock(3), 5);
      expect(BlockSchedule.firstPeriodOfBlock(4), 7);
    });

    test('unknown periods and blocks get fallback times', () {
      final fallbackPeriod = BlockSchedule.fallbackPeriodTimeFor(9);
      expect(fallbackPeriod.start, const TimeOfDay(hour: 15, minute: 30));
      expect(fallbackPeriod.end, const TimeOfDay(hour: 16, minute: 15));

      final fallbackBlock = BlockSchedule.fallbackTimeFor(5);
      expect(fallbackBlock.start, const TimeOfDay(hour: 15, minute: 30));
    });

    test('isWithin checks a single time window', () {
      final block = BlockSchedule.timeFor(1)!;
      expect(BlockSchedule.isWithin(block, DateTime(2026, 8, 14, 8, 10)), true);
      expect(BlockSchedule.isWithin(block, DateTime(2026, 8, 14, 9, 39)), true);
      expect(BlockSchedule.isWithin(block, DateTime(2026, 8, 14, 9, 40)), false);
      expect(BlockSchedule.isWithin(block, DateTime(2026, 8, 14, 7, 59)), false);
    });
  });
}
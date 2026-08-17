import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/utils/simulated_clock.dart';

void main() {
  group('SimulatedClock', () {
    test('startet bei der echten Zeit (x1)', () {
      final clock = SimulatedClock();
      final diff = clock.now().difference(DateTime.now()).abs();
      expect(diff.inSeconds, lessThan(2));
      expect(clock.speed, 1);
      expect(clock.isCustomized, isFalse);
      expect(clock.tickInterval, const Duration(seconds: 30));
    });

    test('setTime setzt die simulierte Zeit absolut', () {
      final clock = SimulatedClock();
      final target = DateTime(2026, 8, 14, 9, 10);
      clock.setTime(target);
      final diff = clock.now().difference(target).abs();
      expect(diff.inSeconds, lessThan(2));
      expect(clock.isCustomized, isTrue);
    });

    test('setSpeed lässt die simulierte Zeit nicht springen', () {
      final clock = SimulatedClock(start: DateTime(2026, 8, 14, 9, 10));
      clock.setSpeed(600);
      final diff = clock.now().difference(DateTime(2026, 8, 14, 9, 10)).abs();
      expect(diff.inSeconds, lessThan(2));
      expect(clock.isCustomized, isTrue);
    });

    test('reset kehrt zur Echtzeit zurück', () {
      final clock = SimulatedClock();
      clock.setTime(DateTime(2026, 8, 14, 9, 10));
      clock.setSpeed(600);
      clock.reset();
      expect(clock.speed, 1);
      expect(clock.isCustomized, isFalse);
      expect(clock.now().difference(DateTime.now()).abs().inSeconds,
          lessThan(2));
    });

    test('tickInterval skaliert mit der Geschwindigkeit (gekappt)', () {
      final clock = SimulatedClock();
      clock.setSpeed(2);
      expect(clock.tickInterval, const Duration(milliseconds: 15000));
      clock.setSpeed(60);
      expect(clock.tickInterval, const Duration(milliseconds: 500));
      clock.setSpeed(3600);
      expect(clock.tickInterval, const Duration(milliseconds: 100));
    });

    test('hohe Geschwindigkeit lässt die Zeit schneller vergehen', () async {
      final clock = SimulatedClock(start: DateTime(2026, 8, 14, 8, 0));
      clock.setSpeed(600);
      final start = clock.now();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final elapsed = clock.now().difference(start);
      // 600x über ~150 ms -> ~90 s simuliert (Toleranz für Scheduling).
      expect(elapsed.inSeconds, inInclusiveRange(30, 200));
    });
  });
}
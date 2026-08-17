import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/components/debug_clock_sheet.dart';
import 'package:better_stundenplan/utils/simulated_clock.dart';

Widget _wrap(SimulatedClock clock) => MaterialApp(
  home: Scaffold(body: DebugClockSheet(clock: clock)),
);

void main() {
  testWidgets('Preset-Chips setzen die simulierte Uhrzeit', (tester) async {
    final clock = SimulatedClock();
    await tester.pumpWidget(_wrap(clock));
    await tester.pump();

    await tester.tap(find.widgetWithText(ActionChip, '08:10'));
    await tester.pump();

    final now = clock.now();
    expect(now.hour, 8);
    expect(now.minute, 10);
    expect(clock.isCustomized, isTrue);

    // Timer des Sheets beenden, sonst schlägt der Test fehl.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zurücksetzen bringt die Uhr in die Echtzeit', (tester) async {
    final clock = SimulatedClock();
    clock.setTime(DateTime(2026, 8, 14, 9, 10));
    clock.setSpeed(600);

    await tester.pumpWidget(_wrap(clock));
    await tester.pump();

    await tester.tap(find.text('Auf Echtzeit zurücksetzen'));
    await tester.pump();

    expect(clock.speed, 1);
    expect(clock.isCustomized, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Geschwindigkeits-Slider setzt die Stufen', (tester) async {
    final clock = SimulatedClock();
    await tester.pumpWidget(_wrap(clock));
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    // Slider auf x600 (Index 8) ziehen.
    slider.onChanged!(8);
    await tester.pump();

    expect(clock.speed, 600);

    await tester.pumpWidget(const SizedBox());
  });
}
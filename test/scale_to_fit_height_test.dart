import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/components/scale_to_fit_height.dart';

/// Kind mit fester Höhe, das die Breite übernimmt.
Widget _box(double height, {VoidCallback? onTap}) => GestureDetector(
  onTap: onTap,
  behavior: HitTestBehavior.opaque,
  child: SizedBox(key: const Key('child'), height: height),
);

Future<void> _pump(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(400, 300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: ScaleToFitHeight(child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('passt das Kind, bleibt es 1:1', (tester) async {
    await _pump(tester, _box(200));

    final render = tester.renderObject<RenderScaleToFitHeight>(
      find.byType(ScaleToFitHeight),
    );
    expect(render.scale, 1);
    expect(tester.getSize(find.byType(ScaleToFitHeight)), const Size(400, 200));
  });

  testWidgets('zu hohes Kind wird verkleinert und füllt die volle Breite', (
    tester,
  ) async {
    await _pump(tester, _box(600));

    final render = tester.renderObject<RenderScaleToFitHeight>(
      find.byType(ScaleToFitHeight),
    );
    expect(render.scale, 0.5);
    // Sichtbar: volle Breite, genau die verfügbare Höhe.
    expect(tester.getSize(find.byType(ScaleToFitHeight)), const Size(400, 300));
    final childRect = tester.getRect(find.byKey(const Key('child')));
    expect(childRect.left, 0);
    expect(childRect.width, 400); // nicht 200 wie bei FittedBox
    expect(childRect.height, 300);
  });

  testWidgets('Taps landen trotz Verkleinerung beim Kind', (tester) async {
    var taps = 0;
    await _pump(tester, _box(600, onTap: () => taps++));

    await tester.tapAt(const Offset(390, 290));

    expect(taps, 1);
  });
}

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Verkleinert [child] gleichmäßig, bis es in die verfügbare Höhe passt –
/// füllt dabei aber immer die volle Breite.
///
/// Anders als `FittedBox(fit: BoxFit.scaleDown)` wird das Kind dafür
/// breiter gelayoutet (Breite ÷ Faktor): Nach dem Verkleinern ist es
/// genau so breit wie der verfügbare Platz, statt schmaler mit leeren
/// Rändern links und rechts. Passt das Kind ohnehin, bleibt es 1:1.
class ScaleToFitHeight extends SingleChildRenderObjectWidget {
  const ScaleToFitHeight({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderScaleToFitHeight();
}

class RenderScaleToFitHeight extends RenderProxyBox {
  double _scale = 1;

  /// Aktueller Verkleinerungsfaktor (1 = unverändert).
  double get scale => _scale;

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final width = constraints.maxWidth;
    final maxHeight = constraints.maxHeight;

    _scale = 1;
    child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final naturalHeight = child.size.height;

    if (maxHeight.isFinite && naturalHeight > maxHeight) {
      _scale = maxHeight / naturalHeight;
      // Breiter layouten, damit das verkleinerte Ergebnis wieder genau
      // die volle Breite einnimmt. Mehr Breite macht den Inhalt höchstens
      // niedriger (weniger Umbrüche) – er passt also weiterhin.
      child.layout(
        BoxConstraints.tightFor(width: width / _scale),
        parentUsesSize: true,
      );
    }
    size = constraints.constrain(Size(width, child.size.height * _scale));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1) {
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}

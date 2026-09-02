import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nested sequence rect fills remain visible in resolved paint order',
      () async {
    const source = '''
sequenceDiagram
  participant A
  participant B
  rect rgb(200, 220, 100)
    rect rgb(200, 255, 200)
      A->>B: inside child
    end
    A->>B: inside parent
  end
''';
    final scene = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(source);
    final parent = _rectWithFill(scene, 0xffc8dc64);
    final child = _rectWithFill(scene, 0xffc8ffc8);
    final png = await renderSceneToPng(scene, pixelRatio: 2);
    final image = await _decodePng(png);
    addTearDown(image.dispose);

    expect(
      await _pixelAt(image, core.Point(parent.left + 2, parent.top + 2)),
      const ui.Color(0xffc8dc64),
      reason: 'the parent-only area keeps the outer rect fill',
    );
    expect(
      await _pixelAt(
        image,
        core.Point(math.max(parent.left, child.left) + 2, child.top + 2),
      ),
      const ui.Color(0xffc8ffc8),
      reason: 'the child rect paints above its parent across its bounds',
    );
    expect(
      await _pixelAt(image, const core.Point(2, 2)),
      const ui.Color(0xffffffff),
      reason: 'pixels outside both ranges keep the scene background',
    );
  });
}

core.Rect _rectWithFill(core.RenderScene scene, int color) =>
    (scene.nodes.whereType<core.SceneShape>().singleWhere(
              (shape) =>
                  shape.geometry is core.RectGeometry &&
                  shape.fill?.color.value == color,
            ).geometry
            as core.RectGeometry)
        .rect;

Future<ui.Image> _decodePng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<ui.Color> _pixelAt(ui.Image image, core.Point point) async {
  const pixelRatio = 2.0;
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final x = (point.x * pixelRatio).round();
  final y = (point.y * pixelRatio).round();
  final offset = (y * image.width + x) * 4;
  return ui.Color.fromARGB(
    rgba!.getUint8(offset + 3),
    rgba.getUint8(offset),
    rgba.getUint8(offset + 1),
    rgba.getUint8(offset + 2),
  );
}

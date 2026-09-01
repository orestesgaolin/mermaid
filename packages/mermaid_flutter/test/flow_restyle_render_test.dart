import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

const _evidenceDirectory = String.fromEnvironment('MERMAID_EVIDENCE_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paint overrides change rendered pixels without moving nodes', () async {
    const source = '''flowchart LR
  A[Start] -->|advance| B[Current] --> C[Done]''';
    final base = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(source);
    final highlighted = core.applyFlowchartPaintOverrides(
      base,
      nodes: const {
        'B': core.FlowNodePaintOverride(
          fill: core.Color(0xffffcc00),
          stroke: core.Color(0xffcc3300),
          strokeWidth: 5,
          textColor: core.Color(0xff112233),
        ),
      },
      links: const {
        1: core.FlowLinkPaintOverride(
          stroke: core.Color(0xff0066ff),
          strokeWidth: 6,
        ),
      },
    );

    expect(highlighted.size, base.size);
    expect(highlighted.nodeBounds, base.nodeBounds);

    final before = await _render(base);
    final after = await _render(highlighted);
    addTearDown(before.dispose);
    addTearDown(after.dispose);

    expect(after.png, isNot(equals(before.png)));
    final bounds = highlighted.boundsOfNode('B')!;
    final fillPixel = await after.pixelAt(bounds.left + 10, bounds.top + 10);
    expect(fillPixel, const ui.Color(0xffffcc00));
    final edge = _groups(highlighted.nodes).firstWhere(
      (group) =>
          group.role == core.SceneGroupRole.edge && group.edge?.linkIndex == 1,
    );
    final edgeStroke = _shapes(
      edge.children,
    ).firstWhere((shape) => shape.paintRole == core.ScenePaintRole.edgeStroke);
    final edgePoint = _pathInteriorPoint(edgeStroke.geometry);
    final edgePixel = await after.pixelAt(edgePoint.x, edgePoint.y);
    expect(edgePixel, const ui.Color(0xff0066ff));

    if (_evidenceDirectory.isNotEmpty) {
      final directory = Directory(_evidenceDirectory)
        ..createSync(recursive: true);
      File('${directory.path}/before.png').writeAsBytesSync(before.png);
      File('${directory.path}/after.png').writeAsBytesSync(after.png);
    }
  });
}

core.Point _pathInteriorPoint(core.ShapeGeometry geometry) {
  final commands = (geometry as core.PathGeometry).commands;
  core.Point? current;
  core.Point? longestPoint;
  var longestDistanceSquared = -1.0;

  void consider(core.Point start, core.Point end, core.Point midpoint) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final distanceSquared = dx * dx + dy * dy;
    if (distanceSquared > longestDistanceSquared) {
      longestDistanceSquared = distanceSquared;
      longestPoint = midpoint;
    }
  }

  for (final command in commands) {
    switch (command) {
      case core.MoveTo(:final p):
        current = p;
      case core.LineTo(:final p):
        final start = current!;
        consider(
          start,
          p,
          core.Point((start.x + p.x) / 2, (start.y + p.y) / 2),
        );
        current = p;
      case core.QuadTo(:final c, :final p):
        final start = current!;
        consider(
          start,
          p,
          core.Point(
            (start.x + 2 * c.x + p.x) / 4,
            (start.y + 2 * c.y + p.y) / 4,
          ),
        );
        current = p;
      case core.CubicTo(:final c1, :final c2, :final p):
        final start = current!;
        consider(
          start,
          p,
          core.Point(
            (start.x + 3 * c1.x + 3 * c2.x + p.x) / 8,
            (start.y + 3 * c1.y + 3 * c2.y + p.y) / 8,
          ),
        );
        current = p;
      case core.ClosePath():
    }
  }
  return longestPoint ?? (throw StateError('Edge path has no segment'));
}

Iterable<core.SceneGroup> _groups(Iterable<core.SceneNode> nodes) sync* {
  for (final node in nodes) {
    if (node is core.SceneGroup) {
      yield node;
      yield* _groups(node.children);
    }
  }
}

Iterable<core.SceneShape> _shapes(Iterable<core.SceneNode> nodes) sync* {
  for (final node in nodes) {
    switch (node) {
      case core.SceneGroup(:final children):
        yield* _shapes(children);
      case core.SceneShape():
        yield node;
      case core.SceneText():
    }
  }
}

Future<_RenderedScene> _render(core.RenderScene scene) async {
  const pixelRatio = 2.0;
  const padding = 16.0;
  final width = ((scene.size.width + padding * 2) * pixelRatio).ceil();
  final height = ((scene.size.height + padding * 2) * pixelRatio).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xffffffff),
    )
    ..scale(pixelRatio)
    ..translate(padding, padding);
  ScenePainter(
    scene,
  ).paint(canvas, ui.Size(scene.size.width, scene.size.height));
  final image = await recorder.endRecording().toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return _RenderedScene(image, png!.buffer.asUint8List());
}

class _RenderedScene {
  const _RenderedScene(this.image, this.png);

  final ui.Image image;
  final List<int> png;

  Future<ui.Color> pixelAt(double sceneX, double sceneY) async {
    const pixelRatio = 2.0;
    const padding = 16.0;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final x = ((sceneX + padding) * pixelRatio).round();
    final y = ((sceneY + padding) * pixelRatio).round();
    final offset = (y * image.width + x) * 4;
    return ui.Color.fromARGB(
      rgba!.getUint8(offset + 3),
      rgba.getUint8(offset),
      rgba.getUint8(offset + 1),
      rgba.getUint8(offset + 2),
    );
  }

  void dispose() => image.dispose();
}

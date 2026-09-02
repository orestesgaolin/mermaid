import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

void main() {
  test('paint overrides change styles without changing geometry', () {
    const source = '''flowchart LR
  A[Start] -->|go| B{Ready?}
  B -->|yes| C[Finish]
  B -->|no| A''';
    final base = const Mermaid(
      measurer: ApproximateTextMeasurer(),
    ).render(source);
    final restyled = applyFlowchartPaintOverrides(
      base,
      nodes: const {
        'B': FlowNodePaintOverride(
          fill: Color(0xffffcc00),
          stroke: Color(0xffcc3300),
          strokeWidth: 5,
          textColor: Color(0xff112233),
        ),
      },
      links: const {
        2: FlowLinkPaintOverride(
          stroke: Color(0xff0066ff),
          strokeWidth: 6,
          strokeDash: [8, 4],
        ),
      },
    );

    expect(restyled.size, base.size);
    expect(restyled.nodeBounds, base.nodeBounds);
    expect(_geometry(restyled.nodes), _geometry(base.nodes));

    final node = _groups(restyled.nodes).firstWhere((g) => g.id == 'B');
    final body = _shapes(
      node.children,
    ).firstWhere((shape) => shape.paintRole == ScenePaintRole.nodeBody);
    final label = _texts(
      node.children,
    ).firstWhere((text) => text.paintRole == ScenePaintRole.nodeLabel);
    expect(body.fill?.color, const Color(0xffffcc00));
    expect(body.stroke?.color, const Color(0xffcc3300));
    expect(body.stroke?.width, 5);
    expect(label.color, const Color(0xff112233));

    final edge = _groups(restyled.nodes).firstWhere(
      (g) => g.role == SceneGroupRole.edge && g.edge?.linkIndex == 2,
    );
    final stroke = _shapes(edge.children)
        .firstWhere((shape) => shape.paintRole == ScenePaintRole.edgeStroke)
        .stroke!;
    expect(stroke.color, const Color(0xff0066ff));
    expect(stroke.width, 6);
    expect(stroke.dash, [8, 4]);

    expect(
      applyFlowchartPaintOverrides(
        base,
        nodes: const {'unknown': FlowNodePaintOverride(fill: Color.black)},
      ).nodes,
      isNotEmpty,
    );
  });

  test('hand-drawn fill and outline channels stay separate', () {
    const source = '''%%{init: {"look": "handDrawn", "handDrawnSeed": 7}}%%
flowchart LR
  A[Start] --> B[Finish]''';
    final base = const Mermaid(
      measurer: ApproximateTextMeasurer(),
    ).render(source);
    final restyled = applyFlowchartPaintOverrides(
      base,
      nodes: const {
        'A': FlowNodePaintOverride(
          fill: Color(0xffffcc00),
          stroke: Color(0xffcc3300),
          strokeWidth: 5,
        ),
      },
    );

    final node = _groups(restyled.nodes).firstWhere((group) => group.id == 'A');
    final shapes = _shapes(node.children).toList();
    final fillStrokes = shapes.where(
      (shape) => shape.paintRole == ScenePaintRole.nodeFill,
    );
    final outlines = shapes.where(
      (shape) => shape.paintRole == ScenePaintRole.nodeStroke,
    );
    expect(fillStrokes, isNotEmpty);
    expect(outlines, isNotEmpty);
    expect(
      fillStrokes.every(
        (shape) => shape.stroke?.color == const Color(0xffffcc00),
      ),
      isTrue,
    );
    expect(
      outlines.every((shape) => shape.stroke?.color == const Color(0xffcc3300)),
      isTrue,
    );
    expect(outlines.every((shape) => shape.stroke?.width == 5), isTrue);
    expect(shapes.every((shape) => shape.fill == null), isTrue);
  });

  test('paint overrides do not add fills to open primitives', () {
    const base = RenderScene(
      size: Size(20, 20),
      nodes: [
        SceneGroup(
          id: 'A',
          children: [
            SceneShape(
              geometry: PathGeometry([
                MoveTo(Point(0, 0)),
                LineTo(Point(10, 10)),
              ]),
              stroke: Stroke(color: Color.black),
              paintRole: ScenePaintRole.nodeLabel,
            ),
          ],
        ),
      ],
    );

    final restyled = applyFlowchartPaintOverrides(
      base,
      nodes: const {'A': FlowNodePaintOverride(textColor: Color(0xff112233))},
    );
    final shape = _shapes(restyled.nodes).single;
    expect(shape.fill, isNull);
    expect(shape.stroke?.color, const Color(0xff112233));
  });

  test('restyle preserves blend mode and an unchanged stroke gradient', () {
    const gradient = SceneGradient(Point(0, 0), Point(20, 0), [
      Color(0x80ff0000),
      Color(0x800000ff),
    ]);
    const base = RenderScene(
      size: Size(20, 20),
      nodes: [
        SceneGroup(
          edge: SceneEdgeMetadata(fromId: 'A', toId: 'B', linkIndex: 0),
          children: [
            SceneShape(
              geometry: PathGeometry([
                MoveTo(Point(0, 10)),
                LineTo(Point(20, 10)),
              ]),
              stroke: Stroke(
                color: Color(0x80ff0000),
                width: 4,
                gradient: gradient,
              ),
              blendMode: SceneBlendMode.multiply,
              paintRole: ScenePaintRole.edgeStroke,
            ),
          ],
        ),
      ],
    );

    final restyled = applyFlowchartPaintOverrides(
      base,
      links: const {0: FlowLinkPaintOverride(strokeWidth: 6)},
    );
    final shape = _shapes(restyled.nodes).single;
    expect(shape.blendMode, SceneBlendMode.multiply);
    expect(shape.stroke?.width, 6);
    expect(shape.stroke?.gradient, same(gradient));
  });
}

String _geometry(Iterable<SceneNode> nodes) {
  final out = StringBuffer();

  void writeNodes(Iterable<SceneNode> values) {
    for (final node in values) {
      switch (node) {
        case SceneGroup(:final id, :final role, :final children):
          out.write('group($id,$role)[');
          writeNodes(children);
          out.write(']');
        case SceneShape(:final geometry):
          out.write('shape(');
          writeGeometry(geometry, out);
          out.write(')');
        case SceneText(:final text, :final bounds, :final rotation):
          out.write('text($text,$bounds,$rotation)');
      }
    }
  }

  writeNodes(nodes);
  return out.toString();
}

void writeGeometry(ShapeGeometry geometry, StringBuffer out) {
  switch (geometry) {
    case RectGeometry(:final rect, :final rx, :final ry):
      out.write('rect($rect,$rx,$ry)');
    case CircleGeometry(:final center, :final radius):
      out.write('circle($center,$radius)');
    case EllipseGeometry(:final center, :final rx, :final ry):
      out.write('ellipse($center,$rx,$ry)');
    case PolygonGeometry(:final points):
      out.write('polygon($points)');
    case PathGeometry(:final commands):
      out.write('path(');
      for (final command in commands) {
        switch (command) {
          case MoveTo(:final p):
            out.write('M$p');
          case LineTo(:final p):
            out.write('L$p');
          case QuadTo(:final c, :final p):
            out.write('Q$c,$p');
          case CubicTo(:final c1, :final c2, :final p):
            out.write('C$c1,$c2,$p');
          case ClosePath():
            out.write('Z');
        }
      }
      out.write(')');
  }
}

Iterable<SceneGroup> _groups(Iterable<SceneNode> nodes) sync* {
  for (final node in nodes) {
    if (node is SceneGroup) {
      yield node;
      yield* _groups(node.children);
    }
  }
}

Iterable<SceneShape> _shapes(Iterable<SceneNode> nodes) sync* {
  for (final node in nodes) {
    switch (node) {
      case SceneGroup(:final children):
        yield* _shapes(children);
      case SceneShape():
        yield node;
      case SceneText():
    }
  }
}

Iterable<SceneText> _texts(Iterable<SceneNode> nodes) sync* {
  for (final node in nodes) {
    switch (node) {
      case SceneGroup(:final children):
        yield* _texts(children);
      case SceneText():
        yield node;
      case SceneShape():
    }
  }
}

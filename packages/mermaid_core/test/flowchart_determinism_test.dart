import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

const _flowchart = '''flowchart TD
  Start["Start session"] -->|choose| A
  subgraph Branch["Decision branch"]
    A{"Ready?"}
    A -->|yes| B["Continue"]
    A -->|retry| B
  end
  B --> Finish(("Done"))''';

void main() {
  group('flowchart geometry determinism', () {
    for (final engine in ['dagre', 'elk']) {
      test('$engine repeats identical geometry across renderer instances', () {
        final source = "%%{init: {'layout': '$engine'}}%%\n$_flowchart";
        final scenes = [
          for (var i = 0; i < 3; i++)
            const Mermaid(measurer: ApproximateTextMeasurer()).render(source),
        ];
        final expected = _geometryLog(scenes.first);

        for (final scene in scenes.skip(1)) {
          expect(_geometryLog(scene), expected);
          expect(scene.nodeBounds, scenes.first.nodeBounds);
          expect(scene.size, scenes.first.size);
        }
      });
    }

    test('paint-only class and link styles keep geometry unchanged', () {
      const styled = '''$_flowchart
  classDef active fill:#ff0000,stroke:#00ff00,stroke-width:4px
  class A,B active
  linkStyle 0,2 stroke:#0000ff,stroke-width:5px''';
      const renderer = Mermaid(measurer: ApproximateTextMeasurer());
      final plainScene = renderer.render(_flowchart);
      final styledScene = renderer.render(styled);

      expect(_geometryLog(styledScene), _geometryLog(plainScene));
      expect(
        renderSceneToSvg(styledScene),
        isNot(renderSceneToSvg(plainScene)),
        reason: 'paint data must change without changing geometry',
      );

      final changedLabel = renderer.render(
        _flowchart.replaceFirst('Start session', 'A much longer start label'),
      );
      expect(
        _geometryLog(changedLabel),
        isNot(_geometryLog(plainScene)),
        reason: 'the geometry comparator must detect layout changes',
      );
    });

    test('hand-drawn geometry repeats for a fixed seed', () {
      const seed7 =
          "%%{init: {'look':'handDrawn','handDrawnSeed':7}}%%\n"
          '$_flowchart';
      const seed8 =
          "%%{init: {'look':'handDrawn','handDrawnSeed':8}}%%\n"
          '$_flowchart';
      const renderer = Mermaid(measurer: ApproximateTextMeasurer());
      final first = renderer.render(seed7);
      final second = renderer.render(seed7);
      final otherSeed = renderer.render(seed8);

      expect(_geometryLog(second), _geometryLog(first));
      expect(_geometryLog(otherSeed), isNot(_geometryLog(first)));
    });
  });
}

String _geometryLog(RenderScene scene) {
  final out = StringBuffer()
    ..writeln(
      'scene ${_number(scene.size.width)} ${_number(scene.size.height)}',
    );

  void writeNodes(Iterable<SceneNode> nodes, int depth) {
    for (final node in nodes) {
      final prefix = '  ' * depth;
      switch (node) {
        case SceneGroup(:final id, :final role, :final children):
          out.writeln(
            '$prefix group ${role.name} ${id ?? '-'} '
            '${_rect(sceneBounds(children))}',
          );
          writeNodes(children, depth + 1);
        case SceneShape(:final geometry):
          out.writeln('$prefix shape ${_geometry(geometry)}');
        case SceneText(:final text, :final bounds, :final rotation):
          out.writeln(
            '$prefix text ${text.replaceAll('\n', r'\n')} '
            '${_rect(bounds)} rotation=${_number(rotation)}',
          );
      }
    }
  }

  writeNodes(scene.nodes, 0);
  return out.toString();
}

String _geometry(ShapeGeometry geometry) => switch (geometry) {
  RectGeometry(:final rect, :final rx, :final ry) =>
    'rect ${_rect(rect)} rx=${_number(rx)} ry=${_number(ry)}',
  CircleGeometry(:final center, :final radius) =>
    'circle ${_point(center)} r=${_number(radius)}',
  EllipseGeometry(:final center, :final rx, :final ry) =>
    'ellipse ${_point(center)} rx=${_number(rx)} ry=${_number(ry)}',
  PolygonGeometry(:final points) => 'polygon ${points.map(_point).join(' ')}',
  PathGeometry(:final commands) => 'path ${commands.map(_command).join(' ')}',
};

String _command(PathCommand command) => switch (command) {
  MoveTo(:final p) => 'M${_point(p)}',
  LineTo(:final p) => 'L${_point(p)}',
  QuadTo(:final c, :final p) => 'Q${_point(c)},${_point(p)}',
  CubicTo(:final c1, :final c2, :final p) =>
    'C${_point(c1)},${_point(c2)},${_point(p)}',
  ClosePath() => 'Z',
};

String _rect(Rect? rect) => rect == null
    ? '-'
    : '${_number(rect.left)},${_number(rect.top)},'
          '${_number(rect.width)},${_number(rect.height)}';

String _point(Point point) => '${_number(point.x)},${_number(point.y)}';

String _number(double value) {
  if (value == 0) return '0.0';
  return value.toString();
}

/// SVG backend tests: structure, styling attributes, escaping.
library;

import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/render/svg_renderer.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/text/text_style.dart';
import 'package:test/test.dart';

void main() {
  test('serializes all geometry kinds with paint attributes', () {
    const style = TextStyleSpec(fontFamily: 'arial', fontSize: 14);
    final scene = RenderScene(
      size: const Size(200, 100),
      background: const Color(0xffffffff),
      nodes: [
        const SceneShape(
          geometry: RectGeometry(Rect.fromLTWH(0, 0, 10, 10), rx: 3, ry: 3),
          fill: Fill(Color(0xffececff)),
          stroke: Stroke(color: Color(0xff9370db)),
        ),
        const SceneShape(
          geometry: CircleGeometry(Point(50, 50), 8),
          fill: Fill(Color(0xff333333)),
        ),
        const SceneShape(
          geometry: PolygonGeometry([Point(0, 0), Point(10, 0), Point(5, 8)]),
          stroke: Stroke(color: Color(0xff333333), dash: [3, 3]),
        ),
        const SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(0, 0)),
            CubicTo(Point(5, 0), Point(10, 5), Point(10, 10)),
            ClosePath(),
          ]),
          stroke: Stroke(color: Color(0xff333333), width: 2),
        ),
        const SceneGroup(id: 'n1', semanticLabel: 'Node "1"', children: [
          SceneText(
            text: 'line1\nline2',
            bounds: Rect.fromLTWH(20, 20, 60, 36),
            style: style,
            color: Color(0xff111111),
          ),
        ]),
      ],
    );
    final svg = renderSceneToSvg(scene);
    expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
    expect(svg, contains('<rect x="0" y="0" width="10" height="10" rx="3"'));
    expect(svg, contains('fill="#ececff"'));
    expect(svg, contains('stroke="#9370db"'));
    expect(svg, contains('<circle cx="50" cy="50" r="8"'));
    expect(svg, contains('stroke-dasharray="3,3"'));
    expect(svg, contains('<path d="M0 0C5 0 10 5 10 10Z"'));
    expect(svg, contains('<g id="n1" aria-label="Node &quot;1&quot;">'));
    expect(svg, contains('<tspan'));
    expect(svg, contains('line1'));
    expect(svg, contains('line2'));
    expect(svg, endsWith('</svg>'));
  });

  test('escapes XML special characters in text', () {
    const style = TextStyleSpec(fontFamily: 'arial', fontSize: 14);
    final svg = renderSceneToSvg(RenderScene(
      size: const Size(100, 30),
      nodes: const [
        SceneText(
          text: 'a < b & "c"',
          bounds: Rect.fromLTWH(0, 0, 100, 20),
          style: style,
          color: Color(0xff000000),
        ),
      ],
    ));
    expect(svg, contains('a &lt; b &amp; "c"'));
    expect(svg, isNot(contains('a < b')));
  });

  test('end-to-end: every supported diagram type serializes', () {
    const mermaid = Mermaid(measurer: ApproximateTextMeasurer());
    const sources = [
      'graph TD\nA-->B',
      'sequenceDiagram\nA->>B: hi',
      'classDiagram\nA <|-- B',
      'stateDiagram-v2\n[*] --> A',
      'erDiagram\nA ||--o{ B : has',
      'pie\n"X" : 10',
      'gantt\ndateFormat YYYY-MM-DD\nT : 2024-01-01, 1d',
    ];
    for (final src in sources) {
      final svg = renderSceneToSvg(mermaid.render(src));
      expect(svg, startsWith('<svg'), reason: src);
      expect(svg, endsWith('</svg>'), reason: src);
    }
  });
}

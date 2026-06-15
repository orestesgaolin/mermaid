/// Tests for the layout-engine selection and the tidy-tree / elk engines.
library;

import 'package:mermaid_core/src/diagrams/flowchart/flow_layout.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_parser.dart';
import 'package:mermaid_core/src/diagrams/flowchart/layout_engines.dart';
import 'package:mermaid_core/src/directives.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

void main() {
  group('resolveLayout', () {
    test('defaults to dagre', () {
      expect(resolveLayout('flowchart TD\nA-->B'), 'dagre');
    });
    test('reads layout from frontmatter config', () {
      expect(
          resolveLayout('---\nconfig:\n  layout: elk\n---\nflowchart TD\nA-->B'),
          'elk');
    });
    test('reads layout from init directive', () {
      expect(resolveLayout("%%{init: {'layout': 'tidy-tree'}}%%\ngraph TD\nA-->B"),
          'tidy-tree');
    });
    test('flowchart-elk keyword selects elk', () {
      expect(resolveLayout('flowchart-elk TD\nA-->B'), 'elk');
    });
    test('reads layout from a separate init directive alongside look', () {
      // The website emits layout and look as two separate %%{init}%% lines;
      // all init directives must be merged, not just the first.
      const src = "%%{init: {'look': 'handDrawn'}}%%\n"
          "%%{init: {'layout': 'elk'}}%%\ngraph TD\nA-->B";
      expect(resolveLayout(src), 'elk');
      expect(resolveLook(src).isHandDrawn, isTrue);
    });
  });

  group('tidyTreeLayout', () {
    test('parent is centered over its children', () {
      final centers = tidyTreeLayout(
        ['r', 'a', 'b'],
        {
          'r': const Size(40, 30),
          'a': const Size(40, 30),
          'b': const Size(40, 30),
        },
        [('r', 'a'), ('r', 'b')],
        flow: TreeFlow.topBottom,
      );
      // Root sits between its two children on the x axis, above them on y.
      expect(centers['r']!.x, closeTo((centers['a']!.x + centers['b']!.x) / 2, 1));
      expect(centers['r']!.y, lessThan(centers['a']!.y));
    });
  });

  group('engine end-to-end', () {
    final g = parseFlowchart('flowchart TD\nRoot-->A\nRoot-->B\nA-->A1');

    test('every engine produces a valid scene', () {
      for (final engine in ['dagre', 'tidy-tree', 'elk']) {
        final scene = layoutFlowchart(g,
            measurer: measurer, theme: theme, engine: engine);
        expect(scene.nodes, isNotEmpty, reason: engine);
        final texts = _flat(scene.nodes)
            .whereType<SceneText>()
            .map((t) => t.text)
            .toSet();
        expect(texts.containsAll({'Root', 'A', 'B', 'A1'}), isTrue,
            reason: engine);
      }
    });

    test('elk routes edges orthogonally (linear), unlike dagre curves', () {
      final g2 = parseFlowchart('graph TD\n  A-->B\n  A-->C\n  B-->D\n  C-->D');
      bool anyCubic(String engine) {
        final scene = layoutFlowchart(g2,
            measurer: measurer, theme: theme, engine: engine);
        return _flat(scene.nodes)
            .whereType<SceneGroup>()
            .where((g) => (g.id ?? '').startsWith('edge_'))
            .expand((g) => g.children.whereType<SceneShape>())
            .whereType<SceneShape>()
            .map((s) => s.geometry)
            .whereType<PathGeometry>()
            .expand((p) => p.commands)
            .any((c) => c is CubicTo);
      }

      // dagre uses smooth basis curves (CubicTo); elk uses sharp orthogonal
      // segments (no CubicTo on the edge lines).
      expect(anyCubic('dagre'), isTrue);
      expect(anyCubic('elk'), isFalse);
    });

    test('tidy-tree fans antiparallel edges to opposite sides (P15)', () {
      final scene = layoutFlowchart(
        parseFlowchart('graph TD\n  A-->B{Q}\n  B-->D[Debug]\n  D-->B'),
        measurer: measurer,
        theme: theme,
        engine: 'tidy-tree',
      );
      // Centroid of an edge group's path (its bow direction).
      Point centroid(String idPrefix) {
        final group = _flat(scene.nodes).whereType<SceneGroup>().firstWhere(
            (g) => (g.id ?? '').startsWith(idPrefix));
        final geo = group.children.whereType<SceneShape>().first.geometry
            as PathGeometry;
        final pts = <Point>[];
        for (final c in geo.commands) {
          switch (c) {
            case MoveTo():
              pts.add(c.p);
            case LineTo():
              pts.add(c.p);
            case CubicTo():
              pts..add(c.c1)..add(c.c2)..add(c.p);
            case QuadTo():
              pts..add(c.c)..add(c.p);
            case ClosePath():
              break;
          }
        }
        var sx = 0.0, sy = 0.0;
        for (final p in pts) {
          sx += p.x;
          sy += p.y;
        }
        return Point(sx / pts.length, sy / pts.length);
      }

      final bd = centroid('edge_B_D');
      final db = centroid('edge_D_B');
      // The two curves bow to opposite sides — their centroids are well apart
      // (the bug routed both on the same line → near-identical centroids).
      final dx = bd.x - db.x, dy = bd.y - db.y;
      expect(dx * dx + dy * dy, greaterThan(15 * 15));
    });
  });
}

List<SceneNode> _flat(List<SceneNode> n) => [
      for (final x in n) ...[
        x,
        if (x is SceneGroup) ..._flat(x.children),
      ],
    ];

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
  });
}

List<SceneNode> _flat(List<SceneNode> n) => [
      for (final x in n) ...[
        x,
        if (x is SceneGroup) ..._flat(x.children),
      ],
    ];

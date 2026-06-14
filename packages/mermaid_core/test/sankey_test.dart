/// Tests for the sankey diagram.
library;

import 'package:mermaid_core/src/detect.dart';
import 'package:mermaid_core/src/diagrams/sankey/sankey.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

List<SceneNode> flatten(List<SceneNode> nodes) => [
      for (final n in nodes) ...[
        n,
        if (n is SceneGroup) ...flatten(n.children),
      ],
    ];

void main() {
  test('detects sankey / sankey-beta', () {
    expect(detectDiagramType('sankey-beta\na,b,1'), DiagramType.sankey);
    expect(detectDiagramType('sankey\na,b,1'), DiagramType.sankey);
  });

  group('parse', () {
    test('collects links and unique nodes in order', () {
      final s = parseSankey('''
sankey-beta
A,B,5
B,C,3
A,C,2
''');
      expect(s.nodes, ['A', 'B', 'C']);
      expect(s.links.length, 3);
      expect(s.links.first.value, 5);
    });

    test('honors quoted fields with commas', () {
      final s = parseSankey('sankey-beta\n"a, b",C,1');
      expect(s.nodes.first, 'a, b');
    });

    test('rejects a non-numeric value', () {
      expect(() => parseSankey('sankey-beta\nA,B,x'),
          throwsA(isA<MermaidParseException>()));
    });
  });

  group('layout', () {
    test('places nodes in columns by longest path; widths track flow', () {
      final scene = layoutSankey(
        parseSankey('sankey-beta\nA,B,10\nB,C,10'),
        measurer: measurer,
        theme: theme,
      );
      final rects = flatten(scene.nodes)
          .whereType<SceneShape>()
          .where((s) => s.geometry is RectGeometry)
          .toList();
      // Three node bars at three distinct x columns.
      final xs = rects
          .map((s) => (s.geometry as RectGeometry).rect.left)
          .toSet();
      expect(xs.length, 3);
      // Ribbons are filled bezier paths.
      final ribbons = flatten(scene.nodes)
          .whereType<SceneShape>()
          .where((s) => s.geometry is PathGeometry && s.fill != null);
      expect(ribbons.length, 2);
      // Labels present. showValues defaults true upstream, so each node label
      // is "<name>\n<value>"; check the name on the first line.
      final names = flatten(scene.nodes)
          .whereType<SceneText>()
          .map((t) => t.text.split('\n').first);
      expect(names, containsAll(['A', 'B', 'C']));
    });
  });
}

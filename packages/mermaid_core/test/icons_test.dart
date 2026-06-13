/// Tests for SVG-path parsing, the icon registry, and flowchart `@{ icon: }`.
library;

import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_layout.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_parser.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/icons/icon_registry.dart';
import 'package:mermaid_core/src/icons/svg_path.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

List<SceneNode> flatten(List<SceneNode> nodes) => [
      for (final n in nodes) ...[
        n,
        if (n is SceneGroup) ...flatten(n.children),
      ],
    ];

void main() {
  group('parseSvgPath', () {
    test('parses move/line/cubic/close', () {
      final cmds = parseSvgPath('M0 0 L10 0 C10 5 5 10 0 10 Z');
      expect(cmds.first, isA<MoveTo>());
      expect(cmds.any((c) => c is LineTo), isTrue);
      expect(cmds.any((c) => c is CubicTo), isTrue);
      expect(cmds.last, isA<ClosePath>());
    });

    test('normalizes arcs to cubics (no crash)', () {
      final cmds = parseSvgPath('M10 10 A5 5 0 0 1 20 10');
      expect(cmds, isNotEmpty);
      expect(cmds.every((c) => c is! QuadTo), isTrue);
    });

    test('blank/invalid input yields empty', () {
      expect(parseSvgPath(null), isEmpty);
      expect(parseSvgPath('   '), isEmpty);
    });
  });

  group('icon registry', () {
    test('built-in pack resolves and renders glyph shapes', () {
      ensureBuiltinIconPacks();
      expect(lookupIcon('icon:cog'), isNotNull);
      expect(lookupIcon('icon:nope'), isNull);
      expect(lookupIcon('bogus:cog'), isNull);
      final shapes = renderIcon('icon:cog',
          const Rect.fromLTWH(0, 0, 40, 40), const Color(0xff000000));
      expect(shapes, isNotEmpty);
      expect(shapes.whereType<SceneShape>().every((s) => s.fill != null), isTrue);
    });

    test('custom pack registration', () {
      registerIconPack(const IconPack(prefix: 'demo', icons: {
        'box': IconDef('<path d="M0 0 H10 V10 H0 Z"/>'),
      }));
      final shapes = renderIcon('demo:box',
          const Rect.fromLTWH(0, 0, 20, 20), const Color(0xff112233));
      expect(shapes, isNotEmpty);
    });
  });

  group('flowchart @{ icon: }', () {
    test('parses icon attribute onto the node', () {
      final g = parseFlowchart(
          'flowchart LR\n  A@{ icon: "icon:cloud", label: "Cloud" } --> B');
      expect(g.nodes['A']!.icon, 'icon:cloud');
      expect(g.nodes['A']!.label, 'Cloud');
    });

    test('renders icon glyph + label inside the node', () {
      final scene = layoutFlowchart(
        parseFlowchart('flowchart LR\n  A@{ icon: "icon:star", label: "Win" }'),
        measurer: const ApproximateTextMeasurer(),
        theme: MermaidTheme.defaultTheme,
      );
      final texts =
          flatten(scene.nodes).whereType<SceneText>().map((t) => t.text);
      expect(texts, contains('Win'));
      // The star glyph contributes filled path shapes beyond the node body.
      final filledPaths = flatten(scene.nodes)
          .whereType<SceneShape>()
          .where((s) => s.geometry is PathGeometry && s.fill != null);
      expect(filledPaths, isNotEmpty);
    });
  });
}

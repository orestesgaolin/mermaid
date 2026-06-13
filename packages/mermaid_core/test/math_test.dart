/// Tests for the TeX-subset math layout (low-level scene primitives).
library;

import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_layout.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_parser.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/math/tex_math.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/text/text_style.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const style = TextStyleSpec(fontFamily: 'arial', fontSize: 16);
const black = Color(0xff000000);

List<SceneNode> flatten(List<SceneNode> nodes) => [
      for (final n in nodes) ...[
        n,
        if (n is SceneGroup) ...flatten(n.children),
      ],
    ];

void main() {
  group('detection', () {
    test('hasMath / wholeMath', () {
      expect(hasMath(r'area $$x^2$$ here'), isTrue);
      expect(hasMath('plain'), isFalse);
      expect(wholeMath(r'$$\frac{1}{2}$$'), r'\frac{1}{2}');
      expect(wholeMath(r'mixed $$x$$ text'), isNull);
    });
  });

  group('layoutMath', () {
    test('superscript raises and shrinks the script', () {
      final base = layoutMath('x', style, measurer, black);
      final sup = layoutMath('x^2', style, measurer, black);
      // Superscript adds width and extra height above the base.
      expect(sup.size.width, greaterThan(base.size.width));
      expect(sup.size.height, greaterThan(base.size.height));
    });

    test(r'\frac emits a rule line (a stroked path)', () {
      final ml = layoutMath(r'\frac{1}{2}', style, measurer, black);
      final nodes = ml.render(const Point(0, 0));
      final rules = flatten(nodes)
          .whereType<SceneShape>()
          .where((s) => s.geometry is PathGeometry && s.stroke != null);
      expect(rules, isNotEmpty);
      // Numerator and denominator glyphs both present.
      final texts = flatten(nodes).whereType<SceneText>().map((t) => t.text);
      expect(texts, containsAll(['1', '2']));
    });

    test(r'\sqrt renders the radical symbol + overline', () {
      final ml = layoutMath(r'\sqrt{x}', style, measurer, black);
      final nodes = ml.render(const Point(0, 0));
      final texts = flatten(nodes).whereType<SceneText>().map((t) => t.text);
      expect(texts, contains('√'));
      expect(
          flatten(nodes).whereType<SceneShape>().where((s) => s.stroke != null),
          isNotEmpty);
    });

    test('symbol macros map to unicode', () {
      final ml = layoutMath(r'\pi r', style, measurer, black);
      final texts = flatten(ml.render(const Point(0, 0)))
          .whereType<SceneText>()
          .map((t) => t.text)
          .join();
      expect(texts.contains('π'), isTrue);
    });
  });

  group('flowchart integration', () {
    test(r'a math node label renders as math, not literal text', () {
      final scene = layoutFlowchart(
        parseFlowchart(r'graph LR' '\n' r'  A["$$x^2$$"]'),
        measurer: measurer,
        theme: MermaidTheme.defaultTheme,
      );
      final texts =
          flatten(scene.nodes).whereType<SceneText>().map((t) => t.text);
      // The raw delimiters never reach the scene; 'x' and '2' do.
      expect(texts.any((t) => t.contains(r'$$')), isFalse);
      expect(texts, containsAll(['x', '2']));
    });
  });
}

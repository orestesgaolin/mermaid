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

    test(r'\text keeps literal spaces', () {
      final ml = layoutMath(r'\text{if x}', style, measurer, black);
      final texts =
          flatten(ml.render(const Point(0, 0))).whereType<SceneText>();
      expect(texts.map((t) => t.text), contains('if x'));
    });

    test(r'\begin{cases} renders rows, columns and a brace', () {
      final ml = layoutMath(
          r'\begin{cases} a &x \\ b &y \end{cases}', style, measurer, black);
      final nodes = ml.render(const Point(0, 0));
      final texts =
          flatten(nodes).whereType<SceneText>().map((t) => t.text).toSet();
      expect(texts.containsAll({'a', 'x', 'b', 'y'}), isTrue);
      // The brace is a stroked path.
      expect(
          flatten(nodes).whereType<SceneShape>().where((s) => s.stroke != null),
          isNotEmpty);
    });

    test(r'\begin{bmatrix} renders all cells', () {
      final ml = layoutMath(
          r'\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}', style, measurer, black);
      final texts = flatten(ml.render(const Point(0, 0)))
          .whereType<SceneText>()
          .map((t) => t.text)
          .toSet();
      expect(texts.containsAll({'1', '2', '3', '4'}), isTrue);
    });

    test(r'\left( ... \right) sizes delimiters (stroked paths)', () {
      final ml =
          layoutMath(r'\left(\frac{a}{b}\right)', style, measurer, black);
      final nodes = ml.render(const Point(0, 0));
      // Two delimiter paths (left paren + right paren) plus the frac rule.
      final strokes =
          flatten(nodes).whereType<SceneShape>().where((s) => s.stroke != null);
      expect(strokes.length, greaterThanOrEqualTo(3));
    });

    test('function names render upright', () {
      final ml = layoutMath(r'\sin t', style, measurer, black);
      final texts =
          flatten(ml.render(const Point(0, 0))).whereType<SceneText>();
      // 'sin' is one upright (non-italic) run; 't' is italic.
      final sin = texts.firstWhere((t) => t.text == 'sin');
      expect(sin.style.italic, isFalse);
      expect(texts.any((t) => t.text == 't' && t.style.italic), isTrue);
    });

    test(r'\overbrace composes with a ^ label', () {
      final ml = layoutMath(
          r'\overbrace{a+b}^{\text{sum}}', style, measurer, black);
      final texts = flatten(ml.render(const Point(0, 0)))
          .whereType<SceneText>()
          .map((t) => t.text);
      expect(texts, contains('sum'));
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

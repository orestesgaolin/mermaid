/// Tests for math layout. Math is laid out by the `katex` package and adapted
/// into mermaid's scene IR (glyphs as filled outline paths, rules as filled
/// rects). KaTeX-level correctness is verified in katex's own oracle suite;
/// here we check the adaptation + the flowchart integration.
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

List<SceneShape> shapes(MathLayout ml) =>
    flatten(ml.render(const Point(0, 0))).whereType<SceneShape>().toList();

void main() {
  group('detection', () {
    test('hasMath / wholeMath', () {
      expect(hasMath(r'area $$x^2$$ here'), isTrue);
      expect(hasMath('plain'), isFalse);
      expect(wholeMath(r'$$\frac{1}{2}$$'), r'\frac{1}{2}');
      expect(wholeMath(r'mixed $$x$$ text'), isNull);
    });
  });

  group('layoutMath (katex adapter)', () {
    test('emits filled outline paths, not text glyphs', () {
      final ml = layoutMath('x', style, measurer, black);
      final s = shapes(ml);
      expect(s, isNotEmpty);
      // Glyphs are filled paths; nothing relies on a math font being present.
      expect(s.every((n) => n.fill != null), isTrue);
      expect(s.any((n) => n.geometry is PathGeometry), isTrue);
      expect(
          flatten(ml.render(const Point(0, 0))).whereType<SceneText>(), isEmpty);
    });

    test('superscript raises and widens vs the base', () {
      final base = layoutMath('x', style, measurer, black);
      final sup = layoutMath('x^2', style, measurer, black);
      expect(sup.size.width, greaterThan(base.size.width));
      expect(sup.size.height, greaterThan(base.size.height));
    });

    test(r'\frac emits a filled rule rect (the bar)', () {
      final ml = layoutMath(r'\frac{1}{2}', style, measurer, black);
      final rects =
          shapes(ml).where((s) => s.geometry is RectGeometry && s.fill != null);
      expect(rects, isNotEmpty);
    });

    test('renders a range of constructs without error', () {
      for (final tex in [
        r'\sqrt{x+3}',
        r'\sum_{i=1}^{n} i',
        r'\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}',
        r'\begin{cases} a &x \\ b &y \end{cases}',
        r'\left(\frac{a}{b}\right)',
        r'\nabla \hbar \Psi \partial',
        r'e^{i\pi} + 1 = 0',
        r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
      ]) {
        final ml = layoutMath(tex, style, measurer, black);
        expect(ml.size.width, greaterThan(0), reason: tex);
        expect(ml.size.height, greaterThan(0), reason: tex);
        expect(shapes(ml), isNotEmpty, reason: tex);
      }
    });

    test('a bigger expression produces more shapes than a single glyph', () {
      expect(shapes(layoutMath(r'\frac{a+b}{c+d}', style, measurer, black)).length,
          greaterThan(shapes(layoutMath('a', style, measurer, black)).length));
    });
  });

  group('flowchart integration', () {
    test('a math node label renders as math shapes, not literal text', () {
      final scene = layoutFlowchart(
        parseFlowchart(r'graph LR' '\n' r'  A["$$x^2$$"]'),
        measurer: measurer,
        theme: MermaidTheme.defaultTheme,
      );
      final texts =
          flatten(scene.nodes).whereType<SceneText>().map((t) => t.text);
      // The math is rendered (as paths) — the raw source never reaches the
      // scene as literal text.
      expect(texts.any((t) => t.contains(r'$$')), isFalse);
      expect(texts.any((t) => t.contains('x^2')), isFalse);
      // Filled outline paths from the math are present.
      expect(flatten(scene.nodes).whereType<SceneShape>(), isNotEmpty);
    });
  });
}

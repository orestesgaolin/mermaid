/// Tests for hand-drawn (`look: 'handDrawn'`) rendering and look config.
library;

import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/directives.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/render/rough.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/text/text_style.dart';
import 'package:test/test.dart';

List<SceneNode> flatten(List<SceneNode> nodes) => [
      for (final n in nodes) ...[
        n,
        if (n is SceneGroup) ...flatten(n.children),
      ],
    ];

void main() {
  group('resolveLook', () {
    test('defaults to classic', () {
      final l = resolveLook('graph TD\nA-->B');
      expect(l.look, 'classic');
      expect(l.isHandDrawn, isFalse);
    });

    test('reads look + seed from init directive', () {
      final l = resolveLook(
          "%%{init: {'look': 'handDrawn', 'handDrawnSeed': 42}}%%\n"
          'graph TD\nA-->B');
      expect(l.isHandDrawn, isTrue);
      expect(l.handDrawnSeed, 42);
    });

    test('reads look from frontmatter config', () {
      final l = resolveLook('---\nlook: handDrawn\n---\ngraph TD\nA-->B');
      expect(l.isHandDrawn, isTrue);
    });
  });

  group('roughenScene', () {
    final base = RenderScene(
      size: const Size(100, 60),
      nodes: [
        const SceneShape(
          geometry: RectGeometry(Rect.fromLTWH(10, 10, 80, 40)),
          fill: Fill(Color(0xffeeeeff)),
          stroke: Stroke(color: Color(0xff333366)),
        ),
        const SceneText(
          text: 'A',
          bounds: Rect.fromLTWH(20, 20, 20, 20),
          style: TextStyleSpec(fontFamily: 'arial', fontSize: 12),
          color: Color(0xff000000),
        ),
      ],
    );

    test('keeps text untouched and expands the shape into strokes', () {
      final r = roughenScene(base, seed: 1);
      final flat = flatten(r.nodes);
      // Text survives verbatim.
      expect(flat.whereType<SceneText>().map((t) => t.text), contains('A'));
      // The single rect became multiple sketchy stroked paths (hachure + 2
      // outline passes).
      final paths = flat
          .whereType<SceneShape>()
          .where((s) => s.geometry is PathGeometry)
          .toList();
      expect(paths.length, greaterThan(2));
      expect(paths.every((s) => s.stroke != null), isTrue);
    });

    test('is deterministic for a given seed', () {
      String dump(RenderScene s) => flatten(s.nodes)
          .whereType<SceneShape>()
          .whereType<SceneShape>()
          .map((s) => (s.geometry as PathGeometry?)?.commands.length ?? 0)
          .join(',');
      expect(dump(roughenScene(base, seed: 7)),
          dump(roughenScene(base, seed: 7)));
    });
  });

  group('end to end', () {
    test('handDrawn directive routes render through the rough pass', () {
      const m = Mermaid(measurer: ApproximateTextMeasurer());
      final classic = m.render('graph TD\nA[Hi]-->B[Yo]');
      final hand =
          m.render("%%{init: {'look':'handDrawn'}}%%\ngraph TD\nA[Hi]-->B[Yo]");
      // Hand-drawn explodes each shape into many sketchy strokes, so the node
      // count is strictly higher than the classic render.
      expect(flatten(hand.nodes).length,
          greaterThan(flatten(classic.nodes).length));
    });
  });
}

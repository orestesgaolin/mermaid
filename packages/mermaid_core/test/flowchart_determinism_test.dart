import 'support/scene.dart';
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
        final expected = sceneGeometry(scenes.first);

        for (final scene in scenes.skip(1)) {
          expect(sceneGeometry(scene), expected);
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

      expect(sceneGeometry(styledScene), sceneGeometry(plainScene));
      expect(
        renderSceneToSvg(styledScene),
        isNot(renderSceneToSvg(plainScene)),
        reason: 'paint data must change without changing geometry',
      );

      final changedLabel = renderer.render(
        _flowchart.replaceFirst('Start session', 'A much longer start label'),
      );
      expect(
        sceneGeometry(changedLabel),
        isNot(sceneGeometry(plainScene)),
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

      expect(sceneGeometry(second), sceneGeometry(first));
      expect(sceneGeometry(otherSeed), isNot(sceneGeometry(first)));
    });
  });
}

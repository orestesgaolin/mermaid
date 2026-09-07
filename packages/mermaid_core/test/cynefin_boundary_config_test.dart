import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

void main() {
  const renderer = Mermaid(measurer: ApproximateTextMeasurer());
  for (final seed in [0, 1, 42, 2147483648]) {
    test(
      'Cynefin seed $seed keeps boundaries within their configured amplitude',
      () {
        final scene = renderer.render('''
%%{init: {"cynefin": {"width": 800, "height": 600, "padding": 40, "boundaryAmplitude": 12, "seed": $seed}}}%%
cynefin-beta
clear
  Restart
''');
        final boundaries = scene.nodes
            .whereType<SceneShape>()
            .where(
              (shape) =>
                  shape.geometry is PathGeometry &&
                  shape.stroke?.dash?.join(',') == '6.0,3.0',
            )
            .toList();
        expect(boundaries, hasLength(2));
        for (var i = 0; i < boundaries.length; i++) {
          final path = boundaries[i].geometry as PathGeometry;
          final points = <Point>[
            for (final command in path.commands)
              ...switch (command) {
                MoveTo(:final p) || LineTo(:final p) => [p],
                CubicTo(:final c1, :final c2, :final p) => [c1, c2, p],
                QuadTo(:final c, :final p) => [c, p],
                ClosePath() => <Point>[],
              },
          ];
          // Wavy control points have at most jitter + 1.5*amplitude offset.
          for (final point in points) {
            expect(
              i == 0 ? point.x : point.y,
              inInclusiveRange(
                (i == 0 ? 440 : 340) - 30,
                (i == 0 ? 440 : 340) + 30,
              ),
            );
          }
        }
      },
    );
  }
}

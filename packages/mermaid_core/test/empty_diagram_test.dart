/// Trivial and degenerate sources must still render.
///
/// Each case below threw out of `Mermaid.render` before: the vendored dagre
/// pipeline dereferenced `min(<empty>)`, the sequence layout anchored an empty
/// block on a participant that did not exist, the sankey value formatter
/// rounded a non-finite product, and the quadrant layout raised an
/// `ArgumentError` — none of which are part of `render`'s documented contract
/// (`MermaidParseException` or `UnsupportedError`).
library;

import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:test/test.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());

void _expectRenderable(String label, String source) {
  late final RenderScene scene;
  expect(
    () => scene = _renderer.render(source),
    returnsNormally,
    reason: '$label must render instead of throwing',
  );
  expect(scene.size.width, isNot(isNaN), reason: label);
  expect(scene.size.height, isNot(isNaN), reason: label);
  expect(scene.size.width.isFinite, isTrue, reason: label);
  expect(scene.size.height.isFinite, isTrue, reason: label);
  expect(scene.size.width, greaterThanOrEqualTo(0), reason: label);
  expect(scene.size.height, greaterThanOrEqualTo(0), reason: label);
}

void main() {
  group('header-only sources render an empty scene', () {
    // These all reach the vendored dagre layout with zero nodes.
    const cases = {
      'flowchart': 'flowchart TB\n',
      'class diagram': 'classDiagram\n',
      'er diagram': 'erDiagram\n',
      'requirement diagram': 'requirementDiagram\n',
      'state diagram': 'stateDiagram-v2\n',
    };
    cases.forEach((label, source) {
      test(label, () {
        _expectRenderable(label, source);
        expect(
          _renderer.render(source).nodes,
          isEmpty,
          reason: 'nothing was declared, so nothing should be painted',
        );
      });
    });
  });

  test('a sequence block with no participants keeps its frame', () {
    const source = 'sequenceDiagram\n loop x\n end\n';
    _expectRenderable('participant-less loop', source);

    final scene = _renderer.render(source);
    final frames = scene.nodes.whereType<SceneGroup>().where(
      (group) => group.id == 'frame_loop',
    );
    expect(frames, hasLength(1));
    // The empty block falls back to a ±20 nominal extent around the origin.
    final rect = frames.single.children
        .whereType<SceneShape>()
        .map((shape) => shape.geometry)
        .whereType<RectGeometry>()
        .single
        .rect;
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
  });

  group('sankey values', () {
    test('a value too large to scale by 100 still renders', () {
      // `(1e308 * 100).round()` overflowed to Infinity and threw.
      _expectRenderable('huge sankey value', 'sankey-beta\nA,B,1e308\n');
      final labels = _renderer
          .render('sankey-beta\nA,B,1e308\n')
          .nodes
          .whereType<SceneText>()
          .map((text) => text.text)
          .toList();
      expect(labels.any((text) => text.contains('1e+308')), isTrue);
    });

    for (final literal in ['NaN', 'Infinity', '-Infinity']) {
      test('$literal is rejected as a parse error', () {
        expect(
          () => _renderer.render('sankey-beta\nA,B,$literal\n'),
          throwsA(
            isA<MermaidParseException>().having(
              (error) => error.message,
              'message',
              contains('finite'),
            ),
          ),
        );
      });
    }
  });

  test('a quadrant chart smaller than its reserved bands renders', () {
    const source = '''
---
config:
  quadrantChart:
    chartWidth: 1
    chartHeight: 1
---
quadrantChart
  title Too small
  x-axis Left --> Right
  y-axis Bottom --> Top
  A: [0.5, 0.5]
''';
    _expectRenderable('1x1 quadrant chart', source);
    expect(_renderer.render(source).size, const Size(1, 1));
  });
}

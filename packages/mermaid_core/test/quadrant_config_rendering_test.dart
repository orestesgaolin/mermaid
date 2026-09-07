import 'support/scene.dart';
import 'dart:convert';

import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());
const _body = '''quadrantChart
title Priorities
x-axis Low --> High
y-axis Low effort --> High effort
quadrant-1 Plan
quadrant-2 Research
quadrant-3 Skip
quadrant-4 Do
Item: [0.25, 0.75]
''';

Iterable<String> _sources(Map<String, Object?> values, String body) sync* {
  yield '%%{init: ${jsonEncode({'quadrantChart': values})}}%%\n$body';
  yield '---\nconfig:\n  quadrantChart:\n${values.entries.map((e) => '    ${e.key}: ${jsonEncode(e.value)}').join('\n')}\n---\n$body';
}

void main() {
  for (final entry in <String, Object?>{
    'chartWidth': 720,
    'chartHeight': 600,
    'quadrantPadding': 15,
    'titleFontSize': 30,
    'titlePadding': 18,
    'xAxisLabelPadding': 12,
    'yAxisLabelPadding': 12,
    'xAxisLabelFontSize': 24,
    'yAxisLabelFontSize': 24,
    'quadrantLabelFontSize': 22,
    'quadrantTextTopPadding': 15,
    'pointTextPadding': 15,
    'pointLabelFontSize': 20,
    'pointRadius': 12,
    'quadrantInternalBorderStrokeWidth': 4,
    'quadrantExternalBorderStrokeWidth': 6,
    'xAxisPosition': 'bottom',
    'yAxisPosition': 'right',
  }.entries) {
    test('${entry.key} changes rendered output through both config forms', () {
      // Upstream always moves X labels to the bottom when points exist.
      final body = entry.key == 'xAxisPosition'
          ? _body.replaceAll('Item: [0.25, 0.75]\n', '')
          : _body;
      final baseline = renderSceneToSvg(_renderer.render(body));
      final scenes = [
        for (final s in _sources({entry.key: entry.value}, body))
          _renderer.render(s),
      ];
      expect(renderSceneToSvg(scenes.first), isNot(baseline));
      expect(renderSceneToSvg(scenes.last), renderSceneToSvg(scenes.first));
    });
  }

  test(
    'right Y axis reserves space and point styles override config radius',
    () {
      for (final source in _sources({
        'yAxisPosition': 'right',
        'pointRadius': 12,
      }, _body)) {
        final scene = _renderer.render(source);
        final nodes = flattenScene(scene.nodes).toList();
        final axis = nodes.whereType<SceneText>().firstWhere(
          (n) => n.text == 'High effort',
        );
        expect(axis.bounds.center.x, greaterThan(scene.size.width / 2));
        expect(
          nodes
              .whereType<SceneShape>()
              .map((n) => n.geometry)
              .whereType<CircleGeometry>()
              .single
              .radius,
          12,
        );
      }
    },
  );
}

import 'support/scene.dart';
import 'dart:convert';

import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());

Iterable<String> _configuredSources(
  String diagramKey,
  Map<String, Object?> values,
  String body,
) sync* {
  yield '%%{init: ${jsonEncode({diagramKey: values})}}%%\n$body';
  final yaml = values.entries
      .map((entry) => '    ${entry.key}: ${jsonEncode(entry.value)}')
      .join('\n');
  yield '---\nconfig:\n  $diagramKey:\n$yaml\n---\n$body';
}

void main() {
  group(
    'remaining per-diagram config renders through init and frontmatter',
    () {
      test('wardley controls canvas, geometry, text, and grid', () {
        const body = '''
wardley-beta
component Kettle [0.43, 0.35]
component Power [0.10, 0.70]
Kettle -> Power
''';
        for (final source in _configuredSources('wardley-beta', {
          'width': 720,
          'height': 480,
          'padding': 60,
          'nodeRadius': 11,
          'nodeLabelOffset': 17,
          'axisFontSize': 18,
          'labelFontSize': 15,
          'showGrid': true,
        }, body)) {
          final scene = _renderer.render(source);
          final nodes = flattenScene(scene.nodes);
          expect(scene.size, const Size(720, 480));
          expect(
            nodes
                .whereType<SceneShape>()
                .map((shape) => shape.geometry)
                .whereType<CircleGeometry>()
                .map((circle) => circle.radius),
            contains(11),
          );
          expect(
            nodes
                .whereType<SceneText>()
                .singleWhere((text) => text.text == 'Kettle')
                .style
                .fontSize,
            15,
          );
          expect(
            nodes.whereType<SceneShape>().where(
              (shape) => shape.stroke?.dash?.join(',') == '3.0,3.0',
            ),
            hasLength(3),
          );
        }
      });

      test('cynefin controls canvas, descriptions, and boundary geometry', () {
        const body = '''
cynefin-beta
  clear
    "Restart"
''';
        final baseline = _renderer.render(body);
        for (final source in _configuredSources('cynefin', {
          'width': 640,
          'height': 420,
          'padding': 12,
          'showDomainDescriptions': false,
          'boundaryAmplitude': 0,
          'seed': 42,
        }, body)) {
          final scene = _renderer.render(source);
          final texts = flattenScene(scene.nodes).whereType<SceneText>();
          expect(scene.size, const Size(664, 444));
          expect(
            texts.map((text) => text.text),
            isNot(contains('Best Practices')),
          );
          final fold = flattenScene(scene.nodes)
              .whereType<SceneShape>()
              .where((shape) => shape.stroke?.dash?.join(',') == '6.0,3.0')
              .map((shape) => shape.geometry)
              .whereType<PathGeometry>()
              .first;
          final foldXs = <double>[
            for (final command in fold.commands)
              ...switch (command) {
                MoveTo(:final p) => [p.x],
                LineTo(:final p) => [p.x],
                CubicTo(:final c1, :final c2, :final p) => [c1.x, c2.x, p.x],
                QuadTo(:final c, :final p) => [c.x, p.x],
                ClosePath() => const [],
              },
          ];
          expect(foldXs, everyElement(closeTo(332, 0.001)));
          expect(scene.size, isNot(baseline.size));
        }
      });

      test('ishikawa controls diagram padding', () {
        const body = '''
ishikawa-beta
  Slow website
    Technology
      Old servers
''';
        final baseline = _renderer.render(body);
        for (final source in _configuredSources('ishikawa', {
          'diagramPadding': 55,
        }, body)) {
          final scene = _renderer.render(source);
          expect(scene.size.width, closeTo(baseline.size.width + 70, 0.001));
          expect(scene.size.height, closeTo(baseline.size.height + 70, 0.001));
        }
      });

      test('event modeling controls outer padding and minimum row height', () {
        const body = '''
eventmodeling
tf 01 ui CartUI
tf 02 cmd AddItem
tf 03 evt ItemAdded
''';
        final baseline = _renderer.render(body);
        for (final source in _configuredSources('eventmodeling', {
          'padding': 60,
          'rowHeight': 140,
        }, body)) {
          final scene = _renderer.render(source);
          expect(scene.size.width, greaterThan(baseline.size.width));
          expect(scene.size.height, greaterThan(baseline.size.height + 100));
        }
      });
    },
  );
}

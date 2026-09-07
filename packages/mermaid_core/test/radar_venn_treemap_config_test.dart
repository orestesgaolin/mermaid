import 'support/scene.dart';
import 'dart:convert';

import 'package:mermaid_core/src/diagrams/radar/radar.dart';
import 'package:mermaid_core/src/diagrams/treemap/treemap.dart';
import 'package:mermaid_core/src/diagrams/venn/venn.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const _measurer = ApproximateTextMeasurer();
const _theme = MermaidTheme.defaultTheme;

Iterable<({String form, String source})> _configuredSources(
  String diagramKey,
  Map<String, Object?> values,
  String body,
) sync* {
  yield (
    form: 'init',
    source: '%%{init: ${jsonEncode({diagramKey: values})}}%%\n$body',
  );
  final yaml = values.entries
      .map((entry) => '    ${entry.key}: ${jsonEncode(entry.value)}')
      .join('\n');
  yield (
    form: 'frontmatter',
    source: '---\nconfig:\n  $diagramKey:\n$yaml\n---\n$body',
  );
}

void main() {
  group('radar config', () {
    const body = '''
radar-beta
  axis a["A"], b["B"], c["C"]
  curve x["X"]{10, 10, 10}
  max 10
  showLegend false
''';

    test('source config changes radius, axes, labels, and curve tension', () {
      const values = <String, Object?>{
        'width': 400,
        'height': 300,
        'marginTop': 20,
        'marginRight': 30,
        'marginBottom': 40,
        'marginLeft': 10,
        'axisScaleFactor': 0.5,
        'axisLabelFactor': 0.75,
        'curveTension': 0,
      };

      for (final configured in _configuredSources('radar', values, body)) {
        final config = RadarConfig.fromSource(configured.source);
        final scene = layoutRadar(
          parseRadar(configured.source),
          measurer: _measurer,
          theme: _theme,
          config: config,
        );
        final shapes = flattenScene(
          scene.nodes,
        ).whereType<SceneShape>().toList();
        final graticules = shapes
            .map((shape) => shape.geometry)
            .whereType<CircleGeometry>()
            .toList();
        expect(
          graticules
              .map((circle) => circle.radius)
              .reduce((a, b) => a > b ? a : b),
          closeTo(150, 0.001),
          reason: configured.form,
        );

        final axisPaths = shapes
            .map((shape) => shape.geometry)
            .whereType<PathGeometry>()
            .where((path) => path.commands.length == 2)
            .toList();
        expect(axisPaths, hasLength(3), reason: configured.form);
        final firstAxis = axisPaths.first.commands.last as LineTo;
        final firstStart = axisPaths.first.commands.first as MoveTo;
        expect(
          firstAxis.p.distanceTo(firstStart.p),
          closeTo(75, 0.001),
          reason: configured.form,
        );

        final curve = shapes
            .map((shape) => shape.geometry)
            .whereType<PathGeometry>()
            .singleWhere((path) => path.commands.any((c) => c is CubicTo));
        final move = curve.commands.first as MoveTo;
        final firstSegment = curve.commands[1] as CubicTo;
        expect(firstSegment.c1, move.p, reason: configured.form);
        expect(firstSegment.c2, firstSegment.p, reason: configured.form);
      }
    });

    test('invalid dimensions and tension retain finite default geometry', () {
      final source = _configuredSources('radar', const {
        'width': 0,
        'height': -1,
        'axisScaleFactor': -2,
        'curveTension': 2,
      }, body).first.source;
      final scene = layoutRadar(
        parseRadar(source),
        measurer: _measurer,
        theme: _theme,
        config: RadarConfig.fromSource(source),
      );
      final outer = flattenScene(scene.nodes)
          .whereType<SceneShape>()
          .map((shape) => shape.geometry)
          .whereType<CircleGeometry>()
          .map((circle) => circle.radius)
          .reduce((a, b) => a > b ? a : b);
      expect(outer, 300);
      expect(scene.size.width.isFinite && scene.size.height.isFinite, isTrue);
    });
  });

  group('venn config', () {
    const body = '''
venn-beta
  set A
    text item["Inside A"]
  set B
  union A,B["Both"]
''';

    test(
      'source config sets viewport, fitting padding, and debug geometry',
      () {
        const values = <String, Object?>{
          'width': 400,
          'height': 300,
          'padding': 30,
          'useDebugLayout': true,
        };
        for (final configured in _configuredSources('venn', values, body)) {
          final scene = layoutVenn(
            parseVenn(configured.source),
            measurer: _measurer,
            theme: _theme,
            config: VennConfig.fromSource(configured.source),
          );
          expect(scene.size, const Size(400, 300), reason: configured.form);

          final shapes = flattenScene(
            scene.nodes,
          ).whereType<SceneShape>().toList();
          final setCircles = shapes
              .where(
                (shape) =>
                    shape.geometry is CircleGeometry && shape.fill != null,
              )
              .map((shape) => shape.geometry as CircleGeometry)
              .toList();
          expect(setCircles, hasLength(2), reason: configured.form);
          for (final circle in setCircles) {
            expect(circle.center.x - circle.radius, greaterThanOrEqualTo(30));
            expect(circle.center.x + circle.radius, lessThanOrEqualTo(370));
            expect(circle.center.y - circle.radius, greaterThanOrEqualTo(30));
            expect(circle.center.y + circle.radius, lessThanOrEqualTo(270));
          }
          expect(
            shapes.where((shape) => shape.stroke?.dash != null),
            hasLength(2),
            reason: configured.form,
          );
        }
      },
    );

    test('invalid canvas and padding use schema defaults', () {
      final source = _configuredSources('venn', const {
        'width': 0,
        'height': 'large',
        'padding': -1,
      }, body).first.source;
      final scene = layoutVenn(
        parseVenn(source),
        measurer: _measurer,
        theme: _theme,
        config: VennConfig.fromSource(source),
      );
      expect(scene.size, const Size(800, 450));
    });
  });

  group('treemap config', () {
    const body = '''
treemap-beta
  "Products"
    "Editor": 1200
    "Viewer": 800
''';

    test('source config changes canvas, padding, values, and formatting', () {
      const values = <String, Object?>{
        'padding': 4,
        'diagramPadding': 20,
        'showValues': true,
        'nodeWidth': 60,
        'nodeHeight': 30,
        'valueFormat': r'$0,0',
      };
      for (final configured in _configuredSources('treemap', values, body)) {
        final scene = layoutTreemap(
          parseTreemap(configured.source),
          measurer: _measurer,
          theme: _theme,
          config: TreemapConfig.fromSource(configured.source),
        );
        expect(scene.size, const Size(640, 340), reason: configured.form);
        final texts = flattenScene(
          scene.nodes,
        ).whereType<SceneText>().map((node) => node.text).toList();
        expect(texts, contains(r'$1,200'), reason: configured.form);

        final rectangles = flattenScene(scene.nodes)
            .whereType<SceneShape>()
            .map((shape) => shape.geometry)
            .whereType<RectGeometry>()
            .map((geometry) => geometry.rect)
            .toList();
        expect(rectangles, isNotEmpty, reason: configured.form);
        expect(
          rectangles.every((rect) => rect.left >= 20 && rect.top >= 20),
          isTrue,
        );
      }
    });

    test('showValues false removes values but retains labels', () {
      final source = _configuredSources('treemap', const {
        'showValues': false,
      }, body).first.source;
      final scene = layoutTreemap(
        parseTreemap(source),
        measurer: _measurer,
        theme: _theme,
        config: TreemapConfig.fromSource(source),
      );
      final texts = flattenScene(
        scene.nodes,
      ).whereType<SceneText>().map((node) => node.text).toList();
      expect(texts, containsAll(['Products', 'Editor', 'Viewer']));
      expect(
        texts.where((text) => RegExp(r'^[$0-9,]+$').hasMatch(text)),
        isEmpty,
      );
    });

    test('grouping preserves percent suffix and general-format exponent', () {
      RenderScene render(String valueFormat) {
        final source = _configuredSources(
          'treemap',
          {'showValues': true, 'valueFormat': valueFormat},
          '''
treemap-beta
  "Products"
    "Editor": 1234
    "Viewer": 1234567
''',
        ).first.source;
        return layoutTreemap(
          parseTreemap(source),
          measurer: _measurer,
          theme: _theme,
          config: TreemapConfig.fromSource(source),
        );
      }

      List<String> labels(RenderScene scene) => flattenScene(
        scene.nodes,
      ).whereType<SceneText>().map((node) => node.text).toList();

      expect(labels(render(',.0%')), contains('123,456,700%'));
      expect(labels(render(',.3g')), contains('1.23e+6'));
    });

    test('invalid dimensions and padding retain existing default canvas', () {
      final source = _configuredSources('treemap', const {
        'nodeWidth': 0,
        'nodeHeight': -4,
        'padding': -1,
        'diagramPadding': -2,
      }, body).first.source;
      final scene = layoutTreemap(
        parseTreemap(source),
        measurer: _measurer,
        theme: _theme,
        config: TreemapConfig.fromSource(source),
      );
      expect(scene.size, const Size(1016, 416));
    });
  });
}

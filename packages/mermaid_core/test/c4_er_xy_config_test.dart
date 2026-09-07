import 'dart:convert';
import 'dart:math' as math;

import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/diagrams/c4/c4.dart';
import 'package:mermaid_core/src/diagrams/er/er_layout.dart';
import 'package:mermaid_core/src/diagrams/xychart/xychart.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const _measurer = ApproximateTextMeasurer();
const _theme = MermaidTheme.defaultTheme;
const _renderer = Mermaid(measurer: _measurer, theme: _theme);

List<SceneNode> _flatten(Iterable<SceneNode> nodes) => [
  for (final node in nodes) ...[
    node,
    if (node is SceneGroup) ..._flatten(node.children),
  ],
];

Rect _largestRect(SceneGroup group) => group.children
    .whereType<SceneShape>()
    .map((shape) => shape.geometry)
    .whereType<RectGeometry>()
    .map((geometry) => geometry.rect)
    .reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);

Iterable<({String form, String source})> _configuredC4Sources(
  Map<String, Object?> values,
  String body,
) sync* {
  yield (
    form: 'init',
    source: '%%{init: ${jsonEncode({'c4': values})}}%%\n$body',
  );
  final yaml = values.entries
      .map((entry) => '    ${entry.key}: ${jsonEncode(entry.value)}')
      .join('\n');
  yield (form: 'frontmatter', source: '---\nconfig:\n  c4:\n$yaml\n---\n$body');
}

void main() {
  group('C4 config', () {
    const body = '''
C4Context
Person(a, "A")
Person(b, "B")
Person(c, "C")
''';

    test('frontmatter resolves geometric values', () {
      const source = '''
---
config:
  c4:
    diagramMarginX: 7
    c4ShapeMargin: 11
    c4ShapePadding: 3
    width: 90
    height: 40
    c4ShapeInRow: 2
    nextLinePaddingX: 13
    c4BoundaryInRow: 1
---
$body''';
      final config = C4Config.fromSource(source);
      expect(config.diagramMarginX, 7);
      expect(config.c4ShapeMargin, 11);
      expect(config.c4ShapePadding, 3);
      expect(config.width, 90);
      expect(config.height, 40);
      expect(config.c4ShapeInRow, 2);
      expect(config.nextLinePaddingX, 13);
      expect(config.c4BoundaryInRow, 1);
    });

    test('init config changes wrapping and box geometry', () {
      const source = '%%{init: {"c4":{"width":300,"c4ShapeInRow":2}}}%%\n$body';
      final scene = _renderer.render(source);
      final groups = scene.nodes.whereType<SceneGroup>().where(
        (group) => const {'a', 'b', 'c'}.contains(group.id),
      );
      final rects = {
        for (final group in groups) group.id!: _largestRect(group),
      };
      expect(rects['a']!.width, 300);
      expect(rects['a']!.top, rects['b']!.top);
      expect(rects['c']!.top, greaterThan(rects['a']!.bottom));
    });

    test(
      'variant colors and typography reach rendered nodes and relations',
      () {
        const source = '''
%%{init: {"c4":{"system_db_bg_color":"#123456","system_db_border_color":"#654321","system_dbFontSize":22,"system_dbFontFamily":"DB Font","system_dbFontWeight":600,"external_container_db_bg_color":"#abcdef","boundaryFontSize":18,"messageFontSize":17}}}%%
C4Container
System_Boundary(boundary, "Boundary") {
  SystemDb(db, "Database")
  ContainerDb_Ext(external, "External", "SQL")
}
Rel(db, external, "reads")
''';
        final scene = _renderer.render(source);
        final db = scene.nodes.whereType<SceneGroup>().singleWhere(
          (group) => group.id == 'db',
        );
        final dbShape = db.children.whereType<SceneShape>().first;
        expect(dbShape.fill!.color, const Color(0xff123456));
        expect(dbShape.stroke!.color, const Color(0xff654321));
        final dbLabel = db.children.whereType<SceneText>().singleWhere(
          (text) => text.text == 'Database',
        );
        expect(dbLabel.style.fontFamily, 'DB Font');
        expect(dbLabel.style.fontSize, 24);
        final external = scene.nodes.whereType<SceneGroup>().singleWhere(
          (group) => group.id == 'external',
        );
        expect(
          external.children.whereType<SceneShape>().first.fill!.color,
          const Color(0xffabcdef),
        );
        expect(
          _flatten(scene.nodes)
              .whereType<SceneText>()
              .singleWhere((text) => text.text == 'Boundary')
              .style
              .fontSize,
          20,
        );
        expect(
          _flatten(scene.nodes)
              .whereType<SceneText>()
              .singleWhere((text) => text.text == 'reads')
              .style
              .fontSize,
          17,
        );
      },
    );

    const variants = <String, String>{
      'Person': 'person',
      'Person_Ext': 'external_person',
      'System': 'system',
      'System_Ext': 'external_system',
      'SystemDb': 'system_db',
      'SystemDb_Ext': 'external_system_db',
      'SystemQueue': 'system_queue',
      'SystemQueue_Ext': 'external_system_queue',
      'Container': 'container',
      'Container_Ext': 'external_container',
      'ContainerDb': 'container_db',
      'ContainerDb_Ext': 'external_container_db',
      'ContainerQueue': 'container_queue',
      'ContainerQueue_Ext': 'external_container_queue',
      'Component': 'component',
      'Component_Ext': 'external_component',
      'ComponentDb': 'component_db',
      'ComponentDb_Ext': 'external_component_db',
      'ComponentQueue': 'component_queue',
      'ComponentQueue_Ext': 'external_component_queue',
    };
    for (final entry in variants.entries) {
      test('${entry.key} resolves ${entry.value} style keys', () {
        final values = <String, Object?>{
          '${entry.value}_bg_color': '#123456',
          '${entry.value}_border_color': '#654321',
          '${entry.value}FontSize': 19,
          '${entry.value}FontFamily': 'Variant Font',
          '${entry.value}FontWeight': 600,
        };
        for (final configured in _configuredC4Sources(
          values,
          'C4Context\n${entry.key}(node, "Label")',
        )) {
          final node = _renderer
              .render(configured.source)
              .nodes
              .whereType<SceneGroup>()
              .singleWhere((group) => group.id == 'node');
          final shape = node.children.whereType<SceneShape>().first;
          expect(
            shape.fill!.color,
            const Color(0xff123456),
            reason: configured.form,
          );
          expect(
            shape.stroke!.color,
            const Color(0xff654321),
            reason: configured.form,
          );
          final label = node.children.whereType<SceneText>().singleWhere(
            (text) => text.text == 'Label',
          );
          expect(
            label.style.fontFamily,
            'Variant Font',
            reason: configured.form,
          );
          expect(label.style.fontSize, 21, reason: configured.form);
          final stereotype = node.children.whereType<SceneText>().singleWhere(
            (text) => text.text.startsWith('<<'),
          );
          expect(stereotype.style.fontWeight, 600, reason: configured.form);
        }
      });
    }
  });

  group('ER config', () {
    const body = '''
erDiagram
  CUSTOMER {
    string name
  }
''';

    test('frontmatter diagramPadding controls horizontal cell padding', () {
      const source = '''
---
config:
  er:
    diagramPadding: 32
---
$body''';
      final scene = _renderer.render(source);
      final entity = scene.nodes.whereType<SceneGroup>().singleWhere(
        (group) => group.id == 'CUSTOMER',
      );
      expect(_largestRect(entity).width, greaterThanOrEqualTo(100));
      final type = entity.children.whereType<SceneText>().singleWhere(
        (text) => text.text == 'string',
      );
      final name = entity.children.whereType<SceneText>().singleWhere(
        (text) => text.text == 'name',
      );
      expect(name.bounds.left - type.bounds.right, greaterThan(20));
    });

    test('init config merges both padding values', () {
      const source =
          '%%{init: {"er":{"diagramPadding":24,"entityPadding":9}}}%%\n$body';
      final config = ErConfig.fromSource(source);
      expect(config.diagramPadding, 24);
      expect(config.entityPadding, 9);
    });

    test('frontmatter minimum entity size changes rendered boxes', () {
      const source = '''
---
config:
  er:
    minEntityWidth: 260
    minEntityHeight: 180
---
erDiagram
  CUSTOMER
''';
      final entity = _renderer
          .render(source)
          .nodes
          .whereType<SceneGroup>()
          .singleWhere((group) => group.id == 'CUSTOMER');
      final rect = _largestRect(entity);
      expect(rect.width, greaterThanOrEqualTo(260));
      expect(rect.height, greaterThanOrEqualTo(180));
    });

    test('init spacing and title margin change scene geometry', () {
      const diagram = '''
erDiagram
  title Accounts
  CUSTOMER ||--o{ ORDER : places
''';
      final normal = _renderer.render(diagram);
      final spaced = _renderer.render('''
%%{init: {"er":{"nodeSpacing":260,"rankSpacing":190,"titleTopMargin":70}}}%%
$diagram''');
      expect(spaced.size.height, greaterThan(normal.size.height));
      final normalTitle = _flatten(
        normal.nodes,
      ).whereType<SceneText>().singleWhere((text) => text.text == 'Accounts');
      final spacedTitle = _flatten(
        spaced.nodes,
      ).whereType<SceneText>().singleWhere((text) => text.text == 'Accounts');
      final normalEntityTop = _flatten(normal.nodes)
          .whereType<SceneGroup>()
          .where((group) => group.id == 'CUSTOMER' || group.id == 'ORDER')
          .map((group) => _largestRect(group).top)
          .reduce(math.min);
      final spacedEntityTop = _flatten(spaced.nodes)
          .whereType<SceneGroup>()
          .where((group) => group.id == 'CUSTOMER' || group.id == 'ORDER')
          .map((group) => _largestRect(group).top)
          .reduce(math.min);
      expect(
        spacedEntityTop - spacedTitle.bounds.bottom,
        greaterThan(normalEntityTop - normalTitle.bounds.bottom),
      );
    });
  });

  group('XY chart visibility and rotation config', () {
    const body = '''
xychart-beta
  title "Sales"
  x-axis "Quarter" [Q1, Q2, Q3]
  y-axis "Revenue" 0 --> 10
  bar [2, 5, 8]
''';

    for (final configured in <String, String>{
      'init':
          '%%{init: {"xyChart":{"showTitle":false,"xAxis":{"showLabel":false,"showTick":false,"showAxisLine":false,"showTitle":false},"yAxis":{"labelRotation":45}}}}%%\n$body',
      'frontmatter': '''
---
config:
  xyChart:
    showTitle: false
    xAxis:
      showLabel: false
      showTick: false
      showAxisLine: false
      showTitle: false
    yAxis:
      labelRotation: 45
---
$body''',
    }.entries) {
      test('${configured.key} controls visible parts end to end', () {
        final scene = layoutXyChart(
          parseXyChart(configured.value),
          measurer: _measurer,
          theme: _theme,
        );
        final nodes = _flatten(scene.nodes);
        final texts = nodes.whereType<SceneText>().toList();
        expect(texts.map((text) => text.text), isNot(contains('Sales')));
        expect(texts.map((text) => text.text), isNot(contains('Quarter')));
        expect(texts.map((text) => text.text), isNot(contains('Q1')));
        expect(
          texts.where((text) => text.text == '0').single.rotation,
          0,
          reason: 'labelRotation applies only to the bottom axis upstream',
        );
      });
    }

    test('bottom-axis labels rotate and invalid angles fall back to zero', () {
      String source(num rotation) =>
          '%%{init: {"xyChart":{"xAxis":{"labelRotation":$rotation}}}}%%\n$body';
      RenderScene render(num rotation) => layoutXyChart(
        parseXyChart(source(rotation)),
        measurer: _measurer,
        theme: _theme,
      );
      SceneText q1(RenderScene scene) => _flatten(
        scene.nodes,
      ).whereType<SceneText>().singleWhere((text) => text.text == 'Q1');
      expect(q1(render(-45)).rotation, -45);
      expect(q1(render(100)).rotation, 0);
    });
  });
}

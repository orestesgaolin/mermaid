/// Per-diagram configuration tests for journey and timeline.
library;

import 'support/scene.dart';

import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/diagrams/journey/journey.dart';
import 'package:mermaid_core/src/diagrams/timeline/timeline.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const _measurer = ApproximateTextMeasurer();
const _theme = MermaidTheme.defaultTheme;

SceneGroup _group(RenderScene scene, String id) =>
    scene.nodes.whereType<SceneGroup>().singleWhere((node) => node.id == id);

Rect _box(SceneGroup group) =>
    (group.children
                .whereType<SceneShape>()
                .firstWhere((shape) => shape.geometry is RectGeometry)
                .geometry
            as RectGeometry)
        .rect;

SceneGroup _timelineNode(RenderScene scene, String label) =>
    flattenScene(scene.nodes).whereType<SceneGroup>().singleWhere(
      (group) => group.children.whereType<SceneText>().any(
        (text) => text.text == label,
      ),
    );

void main() {
  group('JourneyConfig', () {
    test('init config changes task geometry, typography, and actor color', () {
      const source = '''
%%{init: {"journey": {"diagramMarginX": 20, "diagramMarginY": 6, "leftMargin": 80, "maxLabelWidth": 100, "width": 120, "height": 40, "taskMargin": 30, "taskFontSize": "18px", "taskFontFamily": "Config Sans", "actorColours": ["#123456"], "sectionFills": ["#abcdef"], "sectionColours": ["#102030"]}}}%%
journey
  section Work
    First: 5: Dev
    Second: 3: Dev
''';
      final config = JourneyConfig.fromSource(source);
      final scene = layoutJourney(
        parseJourney(source),
        measurer: _measurer,
        theme: _theme,
        config: config,
      );

      final first = _box(_group(scene, 'task_First'));
      final second = _box(_group(scene, 'task_Second'));
      final section = _box(_group(scene, 'section_0'));
      expect(first.size, const Size(120, 40));
      expect(second.left - first.left, 150);
      expect(section.width, 260);

      final firstLabel = _group(
        scene,
        'task_First',
      ).children.whereType<SceneText>().single;
      expect(firstLabel.style.fontSize, 18);
      expect(firstLabel.style.fontFamily, 'Config Sans');
      expect(
        _group(scene, 'task_First').children
            .whereType<SceneShape>()
            .firstWhere((shape) => shape.geometry is RectGeometry)
            .fill!
            .color,
        const Color(0xffabcdef),
      );
      expect(firstLabel.color, const Color(0xff102030));
      expect(
        flattenScene(scene.nodes)
            .whereType<SceneShape>()
            .where((shape) => shape.geometry is CircleGeometry)
            .map((shape) => shape.fill?.color),
        contains(const Color(0xff123456)),
      );
    });

    test('frontmatter config changes title styling and outer margin', () {
      const source = '''
---
config:
  journey:
    diagramMarginY: 24
    titleColor: "#654321"
    titleFontFamily: "Title Sans"
    titleFontSize: "3ex"
---
journey
  title Configured
  Task: 4: Dev
''';
      final config = JourneyConfig.fromSource(source);
      final scene = layoutJourney(
        parseJourney(source),
        measurer: _measurer,
        theme: _theme,
        config: config,
      );
      final title = scene.nodes.whereType<SceneText>().singleWhere(
        (text) => text.text == 'Configured',
      );

      expect(title.color, const Color(0xff654321));
      expect(title.style.fontFamily, 'Title Sans');
      expect(title.style.fontSize, 21);
      expect(scene.size.height, greaterThan(450));
    });
  });

  group('TimelineConfig', () {
    test('init padding changes the intrinsic scene extent', () {
      const source = '''
%%{init: {"timeline": {"padding": 40}}}%%
timeline
  2000 : Start
''';
      final diagram = parseTimeline(source);
      final defaultScene = layoutTimeline(
        diagram,
        measurer: _measurer,
        theme: _theme,
      );
      final configuredScene = layoutTimeline(
        diagram,
        measurer: _measurer,
        theme: _theme,
        config: TimelineConfig.fromSource(source),
      );

      expect(configuredScene.size.width - defaultScene.size.width, 56);
      expect(configuredScene.size.height - defaultScene.size.height, 56);
    });

    test('frontmatter can disable per-period colors', () {
      const source = '''
---
config:
  timeline:
    leftMargin: 90
    disableMulticolor: true
---
timeline
  First : A
  Second : B
''';
      final config = TimelineConfig.fromSource(source);
      final scene = layoutTimeline(
        parseTimeline(source),
        measurer: _measurer,
        theme: _theme,
        config: config,
      );
      final defaultScene = layoutTimeline(
        parseTimeline(source),
        measurer: _measurer,
        theme: _theme,
      );

      Color fill(String label) => _timelineNode(
        scene,
        label,
      ).children.whereType<SceneShape>().first.fill!.color;
      expect(config.leftMargin, 90);
      expect(scene.size.width, greaterThan(defaultScene.size.width));
      expect(fill('First'), fill('Second'));
    });
  });
}

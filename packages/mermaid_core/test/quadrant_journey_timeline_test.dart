/// Tests for quadrant, journey and timeline diagrams plus frontmatter
/// indentation tolerance.
library;

import 'package:mermaid_core/src/detect.dart';
import 'package:mermaid_core/src/diagrams/journey/journey.dart';
import 'package:mermaid_core/src/diagrams/quadrant/quadrant.dart';
import 'package:mermaid_core/src/diagrams/timeline/timeline.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

List<SceneNode> flatten(List<SceneNode> nodes) => [
      for (final n in nodes) ...[
        n,
        if (n is SceneGroup) ...flatten(n.children),
      ],
    ];

Iterable<String> texts(RenderScene s) =>
    flatten(s.nodes).whereType<SceneText>().map((t) => t.text);

void main() {
  group('quadrant', () {
    test('parses axes, quadrant labels and points', () {
      final q = parseQuadrantChart('''
quadrantChart
    title Reach
    x-axis Low Reach --> High Reach
    y-axis Low Engagement --> High Engagement
    quadrant-1 Expand
    quadrant-2 Promote
    Campaign A: [0.3, 0.6]
    Campaign B: [0.45, 0.23]
''');
      expect(q.title, 'Reach');
      expect(q.xAxisLeft, 'Low Reach');
      expect(q.xAxisRight, 'High Reach');
      expect(q.quadrantLabels[0], 'Expand');
      expect(q.quadrantLabels[2], isNull);
      expect(q.points.length, 2);
      expect(q.points[0].x, 0.3);
      expect(q.points[0].y, 0.6);
    });
    test('layout places points by coordinates (y up)', () {
      final s = layoutQuadrantChart(
        parseQuadrantChart(
            'quadrantChart\nLow: [0.1, 0.1]\nHigh: [0.9, 0.9]'),
        measurer: measurer,
        theme: theme,
      );
      CircleGeometry dot(String id) => flatten(s.nodes)
          .whereType<SceneGroup>()
          .firstWhere((g) => g.id == 'point_$id')
          .children
          .whereType<SceneShape>()
          .map((n) => n.geometry)
          .whereType<CircleGeometry>()
          .single;
      expect(dot('High').center.x, greaterThan(dot('Low').center.x));
      expect(dot('High').center.y, lessThan(dot('Low').center.y));
    });
    test('garbage throws', () {
      expect(() => parseQuadrantChart('quadrantChart\n???'),
          throwsA(isA<MermaidParseException>()));
    });
  });

  group('journey', () {
    test('parses sections, scores and actors', () {
      final j = parseJourney('''
journey
    title My day
    section Go to work
      Make tea: 5: Me
      Do work: 1: Me, Cat
    section Go home
      Sit down: 5: Me
''');
      expect(j.title, 'My day');
      expect(j.sections.length, 2);
      final work = j.sections[0].tasks[1];
      expect(work.score, 1);
      expect(work.actors, ['Me', 'Cat']);
    });
    test('layout renders faces, actor legend and section bands', () {
      final s = layoutJourney(
        parseJourney('journey\nsection S\nA: 5: Me\nB: 1: Me, Cat'),
        measurer: measurer,
        theme: theme,
      );
      expect(texts(s), containsAll(['S', 'A', 'B', 'Me', 'Cat']));
      // Upstream draws every smiley face with a uniform cornsilk fill
      // (#FFF8DC); the score is conveyed by the mouth shape, not the fill.
      final fills = flatten(s.nodes)
          .whereType<SceneShape>()
          .where((n) => n.geometry is CircleGeometry && n.fill != null)
          .map((n) => n.fill!.color.value)
          .toSet();
      expect(fills, contains(0xffFFF8DC));
    });
    test('invalid score throws', () {
      expect(() => parseJourney('journey\nA: nope: Me'),
          throwsA(isA<MermaidParseException>()));
    });
  });

  group('timeline', () {
    test('parses periods, inline and continuation events', () {
      final t = parseTimeline('''
timeline
    title History
    section 2000s
    2002 : LinkedIn
    2004 : Facebook : Google
         : Orkut
    2005 : YouTube
''');
      expect(t.title, 'History');
      final periods = t.sections.single.periods;
      expect(periods.length, 3);
      expect(periods[1].label, '2004');
      expect(periods[1].events, ['Facebook', 'Google', 'Orkut']);
    });
    test('layout renders period boxes and stacked events', () {
      final s = layoutTimeline(
        parseTimeline('timeline\n2002 : LinkedIn\n2004 : Facebook : Google'),
        measurer: measurer,
        theme: theme,
      );
      expect(texts(s),
          containsAll(['2002', 'LinkedIn', '2004', 'Facebook', 'Google']));
      // Google stacks below Facebook in the same column.
      final all = flatten(s.nodes).whereType<SceneText>().toList();
      final fb = all.firstWhere((t) => t.text == 'Facebook');
      final gg = all.firstWhere((t) => t.text == 'Google');
      expect((fb.bounds.center.x - gg.bounds.center.x).abs(), lessThan(2));
      expect(gg.bounds.top, greaterThan(fb.bounds.bottom));
    });
  });

  group('frontmatter tolerance', () {
    test('indented frontmatter fences are stripped and detected', () {
      const src = '  ---\n  title: My day\n  ---\n  journey\n  A: 3: Me\n';
      expect(detectDiagramType(src), DiagramType.journey);
      expect(frontmatterTitle(src), 'My day');
      expect(parseJourney(src).title, 'My day');
    });
  });
}

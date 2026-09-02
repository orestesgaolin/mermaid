/// Tests for xychart, mindmap, requirement and C4 diagrams.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:mermaid_core/src/diagrams/c4/c4.dart';
import 'package:mermaid_core/src/diagrams/mindmap/mindmap.dart';
import 'package:mermaid_core/src/diagrams/requirement/requirement.dart';
import 'package:mermaid_core/src/diagrams/xychart/xychart.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
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
  group('xychart', () {
    test('parses axes, bar and line series', () {
      final c = parseXyChart('''
xychart-beta
    title "Sales"
    x-axis [jan, feb, mar]
    y-axis "Revenue" 0 --> 100
    bar [10, 20, 30]
    line [15, 25, 35]
''');
      expect(c.title, 'Sales');
      expect(c.categories, ['jan', 'feb', 'mar']);
      expect(c.yRange, (0, 100));
      expect(c.yAxisTitle, 'Revenue');
      expect(c.series.length, 2);
      expect(c.series[0].kind, XySeriesKind.bar);
      expect(c.series[1].values, [15, 25, 35]);
    });
    test('values may carry labels', () {
      final c = parseXyChart('xychart\nline [540 "PaLM", 65 "LLaMA"]');
      expect(c.series.single.values, [540, 65]);
    });
    test('layout renders bars scaled by value', () {
      final s = layoutXyChart(
        parseXyChart('xychart-beta\nx-axis [a, b]\nbar [10, 100]'),
        measurer: measurer,
        theme: theme,
      );
      final bars = flatten(s.nodes)
          .whereType<SceneShape>()
          .where((n) => n.geometry is RectGeometry && n.fill != null)
          .map((n) => (n.geometry as RectGeometry).rect)
          .toList();
      expect(bars, hasLength(2));
      expect(bars[1].height, greaterThan(bars[0].height * 5));
      expect(texts(s), containsAll(['a', 'b']));
    });
    test('layout centers titles on the final left-axis range', () {
      void expectCenteredOnEndTicks(
          RenderScene scene, String title, String firstTick, String lastTick) {
        final allText = flatten(scene.nodes).whereType<SceneText>();
        final titleNode = allText.singleWhere((text) => text.text == title);
        final first =
            allText.singleWhere((text) => text.text == firstTick).bounds.center;
        final last =
            allText.singleWhere((text) => text.text == lastTick).bounds.center;

        expect(titleNode.rotation, 270);
        expect(titleNode.bounds.center.y,
            closeTo(first.y + (last.y - first.y) / 2, 0.001));
        expect(titleNode.bounds.center.x,
            lessThan(math.min(first.x, last.x)));
      }

      final vertical = layoutXyChart(
        parseXyChart('''
xychart-beta
    title "Sales Revenue"
    x-axis [jan, feb, mar, apr, may, jun]
    y-axis "Revenue (thousands)" 4000 --> 11000
    bar [5000, 6000, 7500, 8200, 9500, 10500]
    line [5000, 6000, 7500, 8200, 9500, 10500]
'''),
        measurer: measurer,
        theme: theme,
      );
      expectCenteredOnEndTicks(
          vertical, 'Revenue (thousands)', '4000', '11000');

      final horizontal = layoutXyChart(
        parseXyChart('''
xychart-beta horizontal
    x-axis "Quarter" [jan, feb, mar]
    y-axis 0 --> 100
    bar [10, 50, 100]
'''),
        measurer: measurer,
        theme: theme,
      );
      expectCenteredOnEndTicks(horizontal, 'Quarter', 'jan', 'mar');
    });
    test('fixture frontmatter controls theme, size and orientation', () {
      final source = File(
          'test/fixtures/upstream_xychart/18.mmd')
          .readAsStringSync();
      final chart = parseXyChart(source);
      final scene = const Mermaid(measurer: ApproximateTextMeasurer())
          .render(source);
      expect(chart.horizontal, isTrue);
      expect(scene.size, const Size(1000, 600));
      expect(chart.config.xAxis.labelFontSize, 20);
      final nodes = flatten(scene.nodes);
      final bars = nodes.whereType<SceneShape>().where((shape) =>
          shape.fill?.color.value == 0xffcde498 &&
          shape.geometry is RectGeometry).toList();
      expect(bars, hasLength(12));
      expect(nodes.whereType<SceneShape>().any(
          (shape) => shape.stroke?.color.value == 0xffff6b6b), isTrue);
      SceneText text(String value) => nodes.whereType<SceneText>()
          .singleWhere((node) => node.text == value);
      expect(text('Sales Revenue').style.fontSize, 10);
      expect(text('Months').style.fontSize, 30);
      expect(text('jan').style.fontSize, 20);
    });
  });

  group('mindmap', () {
    test('parses indentation hierarchy and shapes', () {
      final m = parseMindmap('''
mindmap
  root((Center))
    A topic
      Deeper
    [Square topic]
''');
      expect(m.root.label, 'Center');
      expect(m.root.shape, MindmapShape.circle);
      expect(m.root.children.length, 2);
      expect(m.root.children[0].label, 'A topic');
      expect(m.root.children[0].children.single.label, 'Deeper');
      expect(m.root.children[1].shape, MindmapShape.rect);
    });
    test('icon decorations are tolerated', () {
      final m = parseMindmap('mindmap\n  root\n    A\n    ::icon(fa fa-book)\n    B');
      expect(m.root.children.map((c) => c.label), ['A', 'B']);
    });
    test('layout splits branches around the root', () {
      final s = layoutMindmap(
        parseMindmap('mindmap\n  root((R))\n    A\n    B\n    C\n    D'),
        measurer: measurer,
        theme: theme,
      );
      final groups = flatten(s.nodes)
          .whereType<SceneGroup>()
          .where((g) => (g.id ?? '').startsWith('mind_'))
          .toList();
      expect(groups, hasLength(5));
      expect(texts(s), containsAll(['R', 'A', 'B', 'C', 'D']));
    });
    test('layout: elk relayouts as a top-down tree (P10)', () {
      final src = 'mindmap\n  root((R))\n    A\n    B\n    C\n    D';
      double yOf(RenderScene s, String label) => flatten(s.nodes)
          .whereType<SceneText>()
          .firstWhere((t) => t.text == label)
          .bounds
          .center
          .y;
      final radial =
          layoutMindmap(parseMindmap(src), measurer: measurer, theme: theme);
      final elk = layoutMindmap(parseMindmap(src),
          measurer: measurer, theme: theme, engine: 'elk');
      // Under elk the root sits on top and every child is on the row below it
      // (a hierarchical tree), unlike the radial spread.
      final rootY = yOf(elk, 'R');
      for (final c in ['A', 'B', 'C', 'D']) {
        expect(yOf(elk, c), greaterThan(rootY));
      }
      // Radial places at least one child above the root; the tree never does.
      expect(['A', 'B', 'C', 'D'].any((c) => yOf(radial, c) < yOf(radial, 'R')),
          isTrue);
    });
  });

  group('requirement', () {
    test('parses requirements, elements and relations', () {
      final d = parseRequirementDiagram('''
requirementDiagram
    requirement test_req {
      id: 1
      text: the test text.
      risk: high
      verifymethod: test
    }
    element test_entity {
      type: simulation
    }
    test_entity - satisfies -> test_req
''');
      expect(d.nodes['test_req']!.kind, 'requirement');
      expect(d.nodes['test_req']!.fields,
          contains(('verifyMethod', 'test')));
      expect(d.nodes['test_entity']!.kind, 'element');
      final r = d.relations.single;
      expect(r.from, 'test_entity');
      expect(r.label, 'satisfies');
    });
    test('reversed arrow form and spaced names', () {
      final d = parseRequirementDiagram('requirementDiagram\n'
          'requirement Some Req {\nid: 2\n}\n'
          'Some Req <- copies - other');
      expect(d.relations.single.from, 'other');
      expect(d.relations.single.to, 'Some Req');
    });
    test('layout renders kind line, id and dashed labeled relation', () {
      final s = layoutRequirementDiagram(
        parseRequirementDiagram('requirementDiagram\n'
            'requirement r1 {\nid: 1\n}\nelement e1 {\ntype: sim\n}\n'
            'e1 - satisfies -> r1'),
        measurer: measurer,
        theme: theme,
      );
      // Upstream shows the kind as its display name («Requirement»), not the
      // raw keyword; relation labels stay lowercase («satisfies»).
      expect(texts(s),
          containsAll(['«Requirement»', 'r1', '«satisfies»', 'e1']));
      expect(
        flatten(s.nodes).whereType<SceneShape>().any(
            (n) => n.geometry is PathGeometry && n.stroke?.dash != null),
        isTrue,
      );
    });
  });

  group('C4', () {
    test('parses persons, systems, boundaries and rels', () {
      final d = parseC4Diagram('''
C4Context
  title System Context
  Person(customer, "Customer", "A bank customer")
  Enterprise_Boundary(b0, "Bank") {
    System(banking, "Internet Banking")
    SystemDb_Ext(mainframe, "Mainframe")
  }
  Rel(customer, banking, "Uses")
  BiRel(banking, mainframe, "Reads/Writes")
''');
      expect(d.title, 'System Context');
      expect(d.nodes['customer']!.kind, C4Kind.person);
      expect(d.nodes['customer']!.description, 'A bank customer');
      expect(d.nodes['banking']!.boundary, 'b0');
      expect(d.boundaries.single.label, 'Bank');
      expect(d.rels[0].label, 'Uses');
      expect(d.rels[1].bidirectional, isTrue);
    });
    test('layout renders boundary, person head and rel label', () {
      final s = layoutC4Diagram(
        parseC4Diagram('C4Context\nPerson(p, "User")\n'
            'Enterprise_Boundary(b, "Org") {\nSystem(sys, "System")\n}\n'
            'Rel(p, sys, "Uses")'),
        measurer: measurer,
        theme: theme,
      );
      expect(texts(s), containsAll(['User', 'System', 'Uses', 'Org']));
      // Person head circle present.
      expect(
        flatten(s.nodes)
            .whereType<SceneShape>()
            .any((n) => n.geometry is CircleGeometry),
        isTrue,
      );
      // Dashed boundary rect.
      expect(
        flatten(s.nodes).whereType<SceneShape>().any((n) =>
            n.geometry is RectGeometry && n.stroke?.dash != null),
        isTrue,
      );
    });
    test('database cap is filled by the body and stroked separately', () {
      final s = layoutC4Diagram(
        parseC4Diagram('''
C4Context
  Enterprise_Boundary(b0, "Bank") {
    SystemDb_Ext(mainframe, "Mainframe", "Stores core banking records")
  }
'''),
        measurer: measurer,
        theme: theme,
      );
      final database = flatten(s.nodes)
          .whereType<SceneGroup>()
          .singleWhere((group) => group.id == 'mainframe');
      final paths = database.children
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is PathGeometry)
          .toList();

      expect(paths, hasLength(2));
      final body = paths.singleWhere((shape) => shape.fill != null);
      final seam = paths.singleWhere((shape) => shape.fill == null);
      expect((body.geometry as PathGeometry).commands.last, isA<ClosePath>());
      expect(seam.stroke, isNotNull);
    });
    test('deployment nodes reserve their header and use solid borders', () {
      final s = layoutC4Diagram(
        parseC4Diagram('''
C4Deployment
  Deployment_Node(mob, "Customer's mobile device", "Apple IOS or Android") {
    Container(mobile, "Mobile App", "Xamarin", "Customer application")
  }
'''),
        measurer: measurer,
        theme: theme,
      );
      final boundary = flatten(s.nodes)
          .whereType<SceneGroup>()
          .singleWhere((group) => group.id == 'boundary_mob');
      final mobile = flatten(s.nodes)
          .whereType<SceneGroup>()
          .singleWhere((group) => group.id == 'mobile');
      final boundaryRect = (boundary.children
              .whereType<SceneShape>()
              .single
              .geometry as RectGeometry)
          .rect;
      final mobileRect = (mobile.children
              .whereType<SceneShape>()
              .first
              .geometry as RectGeometry)
          .rect;
      final type = boundary.children
          .whereType<SceneText>()
          .singleWhere((text) => text.text == '[Apple IOS or Android]');

      expect(boundary.children.whereType<SceneShape>().single.stroke?.dash,
          isNull);
      expect(type.bounds.bottom, lessThan(mobileRect.top));
      expect(boundaryRect.contains(mobileRect.center), isTrue);
    });
    test('UpdateRelStyle offsets move the complete relation annotation', () {
      const base = '''
C4Context
  Person(a, "User")
  System(b, "System")
  Rel(a, b, "Uses", "HTTPS")
''';
      final updated = '$base\n'
          'UpdateRelStyle(a, b, \$offsetX="-40", \$offsetY="-20")';
      final parsed = parseC4Diagram(updated).rels.single;
      expect(parsed.offsetX, -40);
      expect(parsed.offsetY, -20);

      RenderScene render(String source) => layoutC4Diagram(
            parseC4Diagram(source),
            measurer: measurer,
            theme: theme,
          );
      Point center(RenderScene scene, String value) => flatten(scene.nodes)
          .whereType<SceneText>()
          .singleWhere((text) => text.text == value)
          .bounds
          .center;
      final original = render(base);
      final shifted = render(updated);
      for (final value in ['Uses', '[HTTPS]']) {
        final delta = center(shifted, value) - center(original, value);
        expect(delta.x, closeTo(-40, 0.001));
        expect(delta.y, closeTo(-20, 0.001));
      }
    });
    test('garbage throws', () {
      expect(() => parseC4Diagram('C4Context\nnonsense here'),
          throwsA(isA<MermaidParseException>()));
    });
  });
}

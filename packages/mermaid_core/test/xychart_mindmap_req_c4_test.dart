/// Tests for xychart, mindmap, requirement and C4 diagrams.
library;

import 'package:mermaid_core/src/diagrams/c4/c4.dart';
import 'package:mermaid_core/src/diagrams/mindmap/mindmap.dart';
import 'package:mermaid_core/src/diagrams/requirement/requirement.dart';
import 'package:mermaid_core/src/diagrams/xychart/xychart.dart';
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
      expect(texts(s),
          containsAll(['«requirement»', 'r1', '«satisfies»', 'e1']));
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
    test('garbage throws', () {
      expect(() => parseC4Diagram('C4Context\nnonsense here'),
          throwsA(isA<MermaidParseException>()));
    });
  });
}

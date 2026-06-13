/// Flowchart parser tests. Cases are ported from upstream mermaid's
/// flow.spec.js / flow-text.spec.js / flow-edges.spec.js /
/// flow-singlenode.spec.js / flow-arrows.spec.js / subgraph.spec.js /
/// flow-style.spec.js suites (expectations adapted from flowDb's
/// vertices/edges to FlowGraph).
library;

import 'package:mermaid_core/src/diagrams/flowchart/flow_model.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_parser.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:test/test.dart';

void main() {
  group('header and direction', () {
    test('graph TD', () {
      expect(parseFlowchart('graph TD;A-->B;').direction, FlowDirection.tb);
    });
    test('graph TB', () {
      expect(parseFlowchart('graph TB\nA-->B').direction, FlowDirection.tb);
    });
    test('graph BT', () {
      expect(parseFlowchart('graph BT\nA-->B').direction, FlowDirection.bt);
    });
    test('graph LR', () {
      expect(parseFlowchart('graph LR\nA-->B').direction, FlowDirection.lr);
    });
    test('graph RL', () {
      expect(parseFlowchart('graph RL\nA-->B').direction, FlowDirection.rl);
    });
    test('flowchart keyword', () {
      expect(parseFlowchart('flowchart LR\nA-->B').direction, FlowDirection.lr);
    });
    test('flowchart-elk keyword', () {
      expect(
          parseFlowchart('flowchart-elk TD\nA-->B').direction, FlowDirection.tb);
    });
    test('legacy direction >', () {
      expect(parseFlowchart('graph >;A-->B;').direction, FlowDirection.lr);
    });
    test('legacy direction <', () {
      expect(parseFlowchart('graph <;A-->B;').direction, FlowDirection.rl);
    });
    test('legacy direction ^', () {
      expect(parseFlowchart('graph ^;A-->B;').direction, FlowDirection.bt);
    });
    test('legacy direction v', () {
      expect(parseFlowchart('graph v;A-->B;').direction, FlowDirection.tb);
    });
    test('default direction is TB', () {
      expect(parseFlowchart('graph\nA-->B').direction, FlowDirection.tb);
    });
    test('statements on header line', () {
      final g = parseFlowchart('graph TD;A-->B;B-->C;');
      expect(g.nodes.keys, ['A', 'B', 'C']);
      expect(g.edges.length, 2);
    });
    test('non-flowchart header throws', () {
      expect(() => parseFlowchart('sequenceDiagram\nA->>B: hi'),
          throwsA(isA<MermaidParseException>()));
    });
  });

  group('basic nodes and edges', () {
    test('A-->B creates both nodes and a point edge', () {
      final g = parseFlowchart('graph TD;A-->B;');
      expect(g.nodes.keys, ['A', 'B']);
      final e = g.edges.single;
      expect(e.from, 'A');
      expect(e.to, 'B');
      expect(e.headTo, ArrowHead.point);
      expect(e.headFrom, ArrowHead.none);
      expect(e.stroke, EdgeStroke.normal);
      expect(e.minLen, 1);
      expect(e.label, isNull);
    });
    test('single node statement', () {
      final g = parseFlowchart('graph TD;A;');
      expect(g.nodes.keys, ['A']);
      expect(g.edges, isEmpty);
      expect(g.nodes['A']!.label, 'A');
      expect(g.nodes['A']!.shape, FlowNodeShape.plain);
    });
    test('numeric node id', () {
      final g = parseFlowchart('graph TD;1-->2;');
      expect(g.nodes.keys, ['1', '2']);
    });
    test('node ids with dashes and dots', () {
      final g = parseFlowchart('graph TD;a-b-->c.d;');
      expect(g.nodes.keys, ['a-b', 'c.d']);
    });
    test('node id containing "end" substring', () {
      final g = parseFlowchart('graph TD;endpoint --> sender;');
      expect(g.nodes.keys, ['endpoint', 'sender']);
    });
    test('unicode node text', () {
      final g = parseFlowchart('graph TD;A[Detta är ett exempel]-->B;');
      expect(g.nodes['A']!.label, 'Detta är ett exempel');
    });
    test('chained edges', () {
      final g = parseFlowchart('graph TD;A-->B-->C;');
      expect(g.edges.length, 2);
      expect(g.edges[0].from, 'A');
      expect(g.edges[0].to, 'B');
      expect(g.edges[1].from, 'B');
      expect(g.edges[1].to, 'C');
    });
    test('ampersand groups produce cartesian product', () {
      final g = parseFlowchart('graph TD;A & B --> C & D;');
      expect(g.edges.length, 4);
      expect(
        g.edges.map((e) => '${e.from}${e.to}').toList(),
        ['AC', 'AD', 'BC', 'BD'],
      );
    });
    test('no whitespace around edge', () {
      final g = parseFlowchart('graph TD;A-->B;');
      expect(g.edges.single.from, 'A');
    });
    test('whitespace and tabs tolerated', () {
      final g = parseFlowchart('graph TD\n\tA --> B\n  B -->\tC');
      expect(g.edges.length, 2);
    });
    test('statement garbage throws with line info', () {
      expect(
        () => parseFlowchart('graph TD\nA --> B\nA -> B'),
        throwsA(isA<MermaidParseException>()
            .having((e) => e.line, 'line', isNotNull)),
      );
    });
  });

  group('node shapes', () {
    FlowNode parseNode(String decl) =>
        parseFlowchart('graph TD;$decl;').nodes.values.first;

    test('square', () {
      final n = parseNode('A[square text]');
      expect(n.shape, FlowNodeShape.rect);
      expect(n.label, 'square text');
    });
    test('rounded', () {
      final n = parseNode('A(round text)');
      expect(n.shape, FlowNodeShape.rounded);
      expect(n.label, 'round text');
    });
    test('stadium', () {
      final n = parseNode('A([stadium text])');
      expect(n.shape, FlowNodeShape.stadium);
      expect(n.label, 'stadium text');
    });
    test('subroutine', () {
      final n = parseNode('A[[subroutine text]]');
      expect(n.shape, FlowNodeShape.subroutine);
      expect(n.label, 'subroutine text');
    });
    test('cylinder', () {
      final n = parseNode('A[(cylinder text)]');
      expect(n.shape, FlowNodeShape.cylinder);
      expect(n.label, 'cylinder text');
    });
    test('circle', () {
      final n = parseNode('A((circle text))');
      expect(n.shape, FlowNodeShape.circle);
      expect(n.label, 'circle text');
    });
    test('double circle', () {
      final n = parseNode('A(((double text)))');
      expect(n.shape, FlowNodeShape.doubleCircle);
      expect(n.label, 'double text');
    });
    test('asymmetric', () {
      final n = parseNode('A>odd text]');
      expect(n.shape, FlowNodeShape.asymmetric);
      expect(n.label, 'odd text');
    });
    test('diamond', () {
      final n = parseNode('A{diamond text}');
      expect(n.shape, FlowNodeShape.diamond);
      expect(n.label, 'diamond text');
    });
    test('hexagon', () {
      final n = parseNode('A{{hexagon text}}');
      expect(n.shape, FlowNodeShape.hexagon);
      expect(n.label, 'hexagon text');
    });
    test('lean right', () {
      final n = parseNode('A[/lean right/]');
      expect(n.shape, FlowNodeShape.leanRight);
      expect(n.label, 'lean right');
    });
    test('lean left', () {
      final n = parseNode(r'A[\lean left\]');
      expect(n.shape, FlowNodeShape.leanLeft);
      expect(n.label, 'lean left');
    });
    test('trapezoid', () {
      final n = parseNode(r'A[/trapezoid\]');
      expect(n.shape, FlowNodeShape.trapezoid);
      expect(n.label, 'trapezoid');
    });
    test('inverted trapezoid', () {
      final n = parseNode(r'A[\inv trapezoid/]');
      expect(n.shape, FlowNodeShape.invTrapezoid);
      expect(n.label, 'inv trapezoid');
    });
    test('ellipse', () {
      final n = parseNode('A(-ellipse text-)');
      expect(n.shape, FlowNodeShape.ellipse);
      expect(n.label, 'ellipse text');
    });
    test('shape in edge chain', () {
      final g = parseFlowchart('graph TD;A[start]-->B{decide};');
      expect(g.nodes['A']!.shape, FlowNodeShape.rect);
      expect(g.nodes['B']!.shape, FlowNodeShape.diamond);
    });
    test('quoted label with special characters', () {
      final n = parseNode('A["quoted; text (with) [brackets]"]');
      expect(n.label, 'quoted; text (with) [brackets]');
      expect(n.shape, FlowNodeShape.rect);
    });
    test('br tag becomes newline', () {
      final n = parseNode('A[first<br/>second<br >third]');
      expect(n.label, 'first\nsecond\nthird');
    });
    test('markdown string label', () {
      final n = parseNode('A["`bold text`"]');
      expect(n.label, 'bold text');
    });
    test('bare reference keeps earlier declaration', () {
      final g = parseFlowchart('graph TD;A[The text];A-->B;');
      expect(g.nodes['A']!.label, 'The text');
      expect(g.nodes['A']!.shape, FlowNodeShape.rect);
    });
  });

  group('edge variants', () {
    FlowEdge parseEdge(String stmt) =>
        parseFlowchart('graph TD;$stmt;').edges.single;

    test('open link ---', () {
      final e = parseEdge('A---B');
      expect(e.headTo, ArrowHead.none);
      expect(e.stroke, EdgeStroke.normal);
      expect(e.minLen, 1);
    });
    test('cross arrow', () {
      final e = parseEdge('A--xB');
      expect(e.headTo, ArrowHead.cross);
    });
    test('circle arrow', () {
      final e = parseEdge('A--oB');
      expect(e.headTo, ArrowHead.circle);
    });
    test('bidirectional point', () {
      final e = parseEdge('A<-->B');
      expect(e.headFrom, ArrowHead.point);
      expect(e.headTo, ArrowHead.point);
    });
    test('bidirectional cross', () {
      final e = parseEdge('A x--x B');
      expect(e.headFrom, ArrowHead.cross);
      expect(e.headTo, ArrowHead.cross);
    });
    test('bidirectional circle', () {
      final e = parseEdge('A o--o B');
      expect(e.headFrom, ArrowHead.circle);
      expect(e.headTo, ArrowHead.circle);
    });
    test('dotted arrow', () {
      final e = parseEdge('A-.->B');
      expect(e.stroke, EdgeStroke.dotted);
      expect(e.headTo, ArrowHead.point);
      expect(e.minLen, 1);
    });
    test('dotted open', () {
      final e = parseEdge('A-.-B');
      expect(e.stroke, EdgeStroke.dotted);
      expect(e.headTo, ArrowHead.none);
    });
    test('thick arrow', () {
      final e = parseEdge('A==>B');
      expect(e.stroke, EdgeStroke.thick);
      expect(e.headTo, ArrowHead.point);
      expect(e.minLen, 1);
    });
    test('thick open', () {
      final e = parseEdge('A===B');
      expect(e.stroke, EdgeStroke.thick);
      expect(e.headTo, ArrowHead.none);
    });
    test('invisible link', () {
      final e = parseEdge('A~~~B');
      expect(e.stroke, EdgeStroke.invisible);
      expect(e.headTo, ArrowHead.none);
      expect(e.minLen, 1);
    });
    test('pipe label', () {
      final e = parseEdge('A-->|the label|B');
      expect(e.label, 'the label');
    });
    test('pipe label on open link', () {
      final e = parseEdge('A---|This is the 123 s text|B');
      expect(e.label, 'This is the 123 s text');
      expect(e.headTo, ArrowHead.none);
      expect(e.minLen, 1);
    });
    test('text-form label normal', () {
      final e = parseEdge('A-- the text -->B');
      expect(e.label, 'the text');
      expect(e.headTo, ArrowHead.point);
      expect(e.stroke, EdgeStroke.normal);
    });
    test('text-form label dotted', () {
      final e = parseEdge('A-. the text .->B');
      expect(e.label, 'the text');
      expect(e.stroke, EdgeStroke.dotted);
      expect(e.headTo, ArrowHead.point);
    });
    test('text-form label thick', () {
      final e = parseEdge('A== the text ==>B');
      expect(e.label, 'the text');
      expect(e.stroke, EdgeStroke.thick);
      expect(e.headTo, ArrowHead.point);
    });
    test('text-form open link', () {
      final e = parseEdge('A-- the text ---B');
      expect(e.label, 'the text');
      expect(e.headTo, ArrowHead.none);
    });
    test('quoted pipe label', () {
      final e = parseEdge('A-->|"quoted label"|B');
      expect(e.label, 'quoted label');
    });
    test('bidirectional with text form', () {
      final e = parseEdge('A<-- text -->B');
      expect(e.headFrom, ArrowHead.point);
      expect(e.headTo, ArrowHead.point);
      expect(e.label, 'text');
    });

    for (var length = 1; length <= 3; length++) {
      final dashes = '-' * length;
      test('normal open edge length $length', () {
        expect(parseEdge('A -$dashes- B').minLen, length);
      });
      test('normal arrow edge length $length', () {
        expect(parseEdge('A $dashes-> B').minLen, length);
      });
      test('dotted edge length $length', () {
        expect(parseEdge('A -${'.' * length}- B').minLen, length);
      });
      test('thick arrow edge length $length', () {
        expect(parseEdge('A ${'=' * (length + 1)}> B').minLen, length);
      });
    }
  });

  group('subgraphs', () {
    test('basic subgraph membership', () {
      final g = parseFlowchart(
          'graph TB\nsubgraph one\na1-->a2\nend');
      final sg = g.subgraphs.single;
      expect(sg.id, 'one');
      expect(sg.title, 'one');
      expect(sg.nodeIds, ['a1', 'a2']);
    });
    test('multiple subgraphs', () {
      final g = parseFlowchart(
          'graph TB\nsubgraph one\na1-->a2\nend\nsubgraph two\nb1-->b2\nend');
      expect(g.subgraphs.length, 2);
      expect(g.subgraphs[1].nodeIds, ['b1', 'b2']);
    });
    test('quoted title', () {
      final g = parseFlowchart('graph TB\nsubgraph "Some Title"\na-->b\nend');
      expect(g.subgraphs.single.title, 'Some Title');
    });
    test('id with bracket title', () {
      final g = parseFlowchart('graph TB\nsubgraph sg1[Nice Title]\na-->b\nend');
      expect(g.subgraphs.single.id, 'sg1');
      expect(g.subgraphs.single.title, 'Nice Title');
    });
    test('id with quoted bracket title', () {
      final g =
          parseFlowchart('graph TB\nsubgraph sg1["Quoted Title"]\na-->b\nend');
      expect(g.subgraphs.single.title, 'Quoted Title');
    });
    test('multi-word title without brackets', () {
      final g = parseFlowchart('graph TB\nsubgraph A long title\na-->b\nend');
      expect(g.subgraphs.single.title, 'A long title');
    });
    test('nested subgraphs and parentIndex', () {
      final g = parseFlowchart('''
flowchart TB
subgraph outer
  o1
  subgraph inner
    i1 --> i2
  end
end
''');
      expect(g.subgraphs.length, 2);
      final outer = g.subgraphs[0];
      final inner = g.subgraphs[1];
      expect(outer.id, 'outer');
      expect(inner.id, 'inner');
      expect(inner.parentIndex, 0);
      expect(outer.parentIndex, isNull);
      expect(outer.nodeIds, ['o1']);
      expect(inner.nodeIds, ['i1', 'i2']);
    });
    test('direction inside subgraph', () {
      final g = parseFlowchart(
          'flowchart TB\nsubgraph s1\ndirection LR\na-->b\nend');
      expect(g.subgraphs.single.direction, FlowDirection.lr);
    });
    test('unclosed subgraph throws', () {
      expect(() => parseFlowchart('graph TB\nsubgraph one\na-->b'),
          throwsA(isA<MermaidParseException>()));
    });
    test('edges may cross subgraph boundary', () {
      final g = parseFlowchart(
          'graph TB\nsubgraph one\na1\nend\nb1-->a1');
      expect(g.edges.single.from, 'b1');
      expect(g.edges.single.to, 'a1');
    });
  });

  group('styling', () {
    test('classDef single', () {
      final g = parseFlowchart(
          'graph TD;A-->B;classDef exClass background:#bbb,border:1px solid red;');
      expect(g.classDefs['exClass'],
          {'background': '#bbb', 'border': '1px solid red'});
    });
    test('classDef multiple names', () {
      final g = parseFlowchart('graph TD;A;classDef firstClass,secondClass background:#bbb;');
      expect(g.classDefs.keys, containsAll(['firstClass', 'secondClass']));
    });
    test('classDef default', () {
      final g = parseFlowchart('graph TD;A;classDef default fill:#f9f;');
      expect(g.classDefs['default'], {'fill': '#f9f'});
    });
    test('class statement', () {
      final g = parseFlowchart(
          'graph TD;A-->B;classDef exClass fill:#f9f;class A exClass;');
      expect(g.nodes['A']!.classes, ['exClass']);
      expect(g.nodes['B']!.classes, isEmpty);
    });
    test('class statement multiple nodes', () {
      final g = parseFlowchart(
          'graph TD;A-->B;classDef c fill:#f9f;class A,B c;');
      expect(g.nodes['A']!.classes, ['c']);
      expect(g.nodes['B']!.classes, ['c']);
    });
    test('shorthand :::', () {
      final g = parseFlowchart(
          'graph TD;A[label]:::exClass-->B;classDef exClass fill:#f9f;');
      expect(g.nodes['A']!.classes, ['exClass']);
      expect(g.nodes['A']!.label, 'label');
    });
    test('shorthand ::: without shape', () {
      final g = parseFlowchart('graph TD;A:::exClass-->B;');
      expect(g.nodes['A']!.classes, ['exClass']);
    });
    test('style statement', () {
      final g = parseFlowchart(
          'graph TD;A-->B;style A fill:#f9f,stroke:#333,stroke-width:4px;');
      expect(g.nodes['A']!.styles,
          {'fill': '#f9f', 'stroke': '#333', 'stroke-width': '4px'});
    });
    test('style with rgb value keeps commas inside parens', () {
      final g = parseFlowchart('graph TD;A;style A fill:rgb(1,2,3),stroke:#333;');
      expect(g.nodes['A']!.styles['fill'], 'rgb(1,2,3)');
    });
    test('linkStyle by index', () {
      final g = parseFlowchart(
          'graph TD;A-->B;A-->C;linkStyle 1 stroke:#ff3,stroke-width:4px;');
      expect(g.edges[0].styles, isEmpty);
      expect(g.edges[1].styles, {'stroke': '#ff3', 'stroke-width': '4px'});
    });
    test('linkStyle with interpolate is tolerated', () {
      final g = parseFlowchart(
          'graph TD;A-->B;linkStyle 0 interpolate basis stroke:#ff3;');
      expect(g.edges[0].styles, {'stroke': '#ff3'});
    });
    test('linkStyle out of range throws', () {
      expect(() => parseFlowchart('graph TD;A-->B;linkStyle 5 stroke:#ff3;'),
          throwsA(isA<MermaidParseException>()));
    });
    test('click with url and tooltip', () {
      final g = parseFlowchart(
          'graph TD;A-->B;click A "https://example.com" "the tip";');
      expect(g.nodes['A']!.link, 'https://example.com');
      expect(g.nodes['A']!.tooltip, 'the tip');
    });
    test('click href form', () {
      final g =
          parseFlowchart('graph TD;A;click A href "https://example.com";');
      expect(g.nodes['A']!.link, 'https://example.com');
    });
    test('click callback is ignored gracefully', () {
      final g = parseFlowchart('graph TD;A;click A someCallback;');
      expect(g.nodes['A']!.link, isNull);
    });
  });

  group('v11 @{} attribute syntax', () {
    test('shape and label attributes', () {
      final g = parseFlowchart(
          'flowchart LR\nA@{ shape: datastore, label: "Datastore" } --> B');
      expect(g.nodes['A']!.shape, FlowNodeShape.cylinder);
      expect(g.nodes['A']!.label, 'Datastore');
    });
    test('decision alias maps to diamond', () {
      final g = parseFlowchart('flowchart TD\nq@{ shape: decision }');
      expect(g.nodes['q']!.shape, FlowNodeShape.diamond);
    });
    test('label only keeps shape', () {
      final g = parseFlowchart('flowchart TD\nA[old]\nA@{ label: "new" }');
      expect(g.nodes['A']!.shape, FlowNodeShape.rect);
      expect(g.nodes['A']!.label, 'new');
    });
    test('v11 geometries map to their shape', () {
      expect(parseFlowchart('flowchart TD\nA@{ shape: hourglass }')
          .nodes['A']!.shape, FlowNodeShape.hourglass);
      expect(parseFlowchart('flowchart TD\nA@{ shape: doc }')
          .nodes['A']!.shape, FlowNodeShape.document);
    });
    test('valid-but-unported shape (image) falls back to rect', () {
      final g = parseFlowchart('flowchart TD\nA@{ shape: image }');
      expect(g.nodes['A']!.shape, FlowNodeShape.rect);
    });
    test('unknown shape throws', () {
      expect(() => parseFlowchart('flowchart TD\nA@{ shape: zigzag }'),
          throwsA(isA<MermaidParseException>()));
    });
    test('unrecognized attributes are ignored', () {
      final g = parseFlowchart(
          'flowchart TD\nA@{ shape: rounded, w: 200, icon: "gear" } --> B');
      expect(g.nodes['A']!.shape, FlowNodeShape.rounded);
      expect(g.edges.single.to, 'B');
    });
    test('quoted label may contain commas and braces', () {
      final g =
          parseFlowchart('flowchart TD\nA@{ label: "a, b } c", shape: stadium }');
      expect(g.nodes['A']!.label, 'a, b } c');
      expect(g.nodes['A']!.shape, FlowNodeShape.stadium);
    });
    test('fixture 60 style: attributes mid-chain', () {
      final g = parseFlowchart(
          'flowchart LR\nDataStore@{shape: datastore, label: "Datastore"} '
          '-->|input| Process((System)) -->|output| Entity[Customer];');
      expect(g.nodes['DataStore']!.shape, FlowNodeShape.cylinder);
      expect(g.nodes['Process']!.shape, FlowNodeShape.circle);
      expect(g.edges.length, 2);
      expect(g.edges[0].label, 'input');
    });
  });

  group('linkStyle default', () {
    test('applies to every edge', () {
      final g = parseFlowchart(
          'graph TD;A-->B;B-->C;linkStyle default stroke:#999,stroke-width:2px;');
      expect(g.edges[0].styles['stroke'], '#999');
      expect(g.edges[1].styles['stroke'], '#999');
    });
    test('per-index linkStyle overrides default', () {
      final g = parseFlowchart('graph TD;A-->B;B-->C;'
          'linkStyle default stroke:#999;linkStyle 1 stroke:#f00;');
      expect(g.edges[0].styles['stroke'], '#999');
      expect(g.edges[1].styles['stroke'], '#f00');
    });
    test('default declared before later edges still applies to them', () {
      final g = parseFlowchart(
          'graph TD;A-->B;linkStyle default stroke:#999;B-->C;');
      expect(g.edges[1].styles['stroke'], '#999');
    });
  });

  group('comments, directives, frontmatter', () {
    test('comment lines are ignored', () {
      final g = parseFlowchart('graph TD\n%% this is a comment\nA-->B');
      expect(g.nodes.keys, ['A', 'B']);
    });
    test('inline trailing comments are ignored', () {
      final g = parseFlowchart('graph TD\nA-->B %% trailing words');
      expect(g.nodes.keys, ['A', 'B']);
    });
    test('init directive is ignored', () {
      final g = parseFlowchart(
          '%%{init: {"theme": "dark"}}%%\ngraph TD\nA-->B');
      expect(g.edges.length, 1);
    });
    test('frontmatter title is captured', () {
      final g = parseFlowchart('---\ntitle: My Chart\n---\nflowchart LR\nA-->B');
      expect(g.title, 'My Chart');
      expect(g.direction, FlowDirection.lr);
    });
    test('accTitle and accDescr are tolerated', () {
      final g = parseFlowchart(
          'graph TD\naccTitle: Big chart\naccDescr: A description\nA-->B');
      expect(g.edges.length, 1);
    });
    test('multiline accDescr block is tolerated', () {
      final g = parseFlowchart(
          'graph TD\naccDescr {\nA long description\nspanning lines\n}\nA-->B');
      expect(g.edges.length, 1);
    });
    test('empty source throws', () {
      expect(() => parseFlowchart(''), throwsA(isA<MermaidParseException>()));
    });
  });
}

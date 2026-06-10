/// State diagram parser + layout tests; parser cases ported from upstream
/// stateDiagram.spec.js.
library;

import 'package:mermaid_core/src/diagrams/flowchart/flow_model.dart'
    show FlowDirection;
import 'package:mermaid_core/src/diagrams/state/state_layout.dart';
import 'package:mermaid_core/src/diagrams/state/state_model.dart';
import 'package:mermaid_core/src/diagrams/state/state_parser.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/ir/scene_utils.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

StateDiagram parse(String body) =>
    parseStateDiagram('stateDiagram-v2\n$body');

RenderScene layout(String body) => layoutStateDiagram(
      parse(body),
      measurer: const ApproximateTextMeasurer(),
      theme: MermaidTheme.defaultTheme,
    );

List<SceneNode> flatten(List<SceneNode> nodes) => [
      for (final n in nodes) ...[
        n,
        if (n is SceneGroup) ...flatten(n.children),
      ],
    ];

SceneGroup sceneGroup(RenderScene s, String id) => flatten(s.nodes)
    .whereType<SceneGroup>()
    .firstWhere((g) => g.id == id);

void main() {
  group('parser', () {
    test('simple transition with label', () {
      final d = parse('Still --> Moving : push');
      expect(d.states.keys, containsAll(['Still', 'Moving']));
      final t = d.transitions.single;
      expect(t.from, 'Still');
      expect(t.to, 'Moving');
      expect(t.label, 'push');
    });
    test('[*] as source becomes a start state', () {
      final d = parse('[*] --> Still');
      expect(d.states['__start_']!.kind, StateKind.start);
      expect(d.transitions.single.from, '__start_');
    });
    test('[*] as target becomes an end state', () {
      final d = parse('Still --> [*]');
      expect(d.states['__end_']!.kind, StateKind.end);
    });
    test('start and end are distinct states', () {
      final d = parse('[*] --> A\nA --> [*]');
      expect(d.states['__start_']!.kind, StateKind.start);
      expect(d.states['__end_']!.kind, StateKind.end);
    });
    test('state with description via as', () {
      final d = parse('state "This is a state" as s1\ns1 --> s2');
      expect(d.states['s1']!.label, 'This is a state');
    });
    test('colon description', () {
      final d = parse('s1 : Some description');
      expect(d.states['s1']!.label, 'Some description');
    });
    test('repeat colon descriptions append', () {
      final d = parse('s1 : line one\ns1 : line two');
      expect(d.states['s1']!.label, 'line one\nline two');
    });
    test('composite state membership and kind', () {
      final d = parse('state Active {\nIdle --> Busy\n}');
      expect(d.states['Active']!.kind, StateKind.composite);
      expect(d.states['Active']!.children, containsAll(['Idle', 'Busy']));
      expect(d.states['Idle']!.parent, 'Active');
    });
    test('nested composites', () {
      final d = parse('state A {\nstate B {\nC\n}\n}');
      expect(d.states['B']!.parent, 'A');
      expect(d.states['C']!.parent, 'B');
    });
    test('[*] inside composite is scoped', () {
      final d = parse('state A {\n[*] --> X\n}\n[*] --> A');
      expect(d.states.keys, containsAll(['__start_A', '__start_']));
      expect(d.states['__start_A']!.parent, 'A');
    });
    test('choice, fork and join', () {
      final d = parse('state c <<choice>>\nstate f <<fork>>\nstate j <<join>>');
      expect(d.states['c']!.kind, StateKind.choice);
      expect(d.states['f']!.kind, StateKind.fork);
      expect(d.states['j']!.kind, StateKind.join);
    });
    test('note right of inline', () {
      final d = parse('A\nnote right of A : hello');
      expect(d.notes.single.position, StateNotePosition.rightOf);
      expect(d.notes.single.text, 'hello');
    });
    test('multiline note block', () {
      final d = parse('A\nnote left of A\nline one\nline two\nend note');
      expect(d.notes.single.text, 'line one\nline two');
      expect(d.notes.single.position, StateNotePosition.leftOf);
    });
    test('direction statement', () {
      expect(parse('direction LR\nA --> B').direction, FlowDirection.lr);
    });
    test('concurrency separator tolerated', () {
      final d = parse('state A {\nx\n--\ny\n}');
      expect(d.states['A']!.children, containsAll(['x', 'y']));
    });
    test('classDef and class', () {
      final d = parse('A\nclassDef hot fill:#f96\nclass A hot');
      expect(d.classDefs['hot'], {'fill': '#f96'});
      expect(d.states['A']!.cssClasses, ['hot']);
    });
    test('stateDiagram v1 header accepted', () {
      final d = parseStateDiagram('stateDiagram\nA --> B');
      expect(d.transitions.length, 1);
    });
    test('hide empty description tolerated', () {
      expect(parse('hide empty description\nA --> B').transitions.length, 1);
    });
    test('frontmatter title', () {
      final d = parseStateDiagram(
          '---\ntitle: Machine\n---\nstateDiagram-v2\nA --> B');
      expect(d.title, 'Machine');
    });
    test('garbage throws with line number', () {
      expect(
        () => parse('A --> B\n!!!nope'),
        throwsA(isA<MermaidParseException>()
            .having((e) => e.line, 'line', isNotNull)),
      );
    });
  });

  group('layout', () {
    test('start is filled circle, end is double circle', () {
      final s = layout('[*] --> A\nA --> [*]');
      final start = flatten(sceneGroup(s, '__start_').children)
          .whereType<SceneShape>()
          .toList();
      expect(start.single.geometry, isA<CircleGeometry>());
      expect(start.single.fill, isNotNull);
      final end = flatten(sceneGroup(s, '__end_').children)
          .whereType<SceneShape>()
          .toList();
      expect(end.length, 2);
    });
    test('transition direction follows statement', () {
      final s = layout('[*] --> A\nA --> B');
      final a = sceneNodeBounds(sceneGroup(s, 'A'))!;
      final b = sceneNodeBounds(sceneGroup(s, 'B'))!;
      expect(b.center.y, greaterThan(a.center.y));
    });
    test('choice renders a diamond', () {
      final s = layout('state c <<choice>>\nA --> c\nc --> B : yes');
      final shapes =
          flatten(sceneGroup(s, 'c').children).whereType<SceneShape>();
      expect(shapes.single.geometry, isA<PolygonGeometry>());
    });
    test('fork renders a filled bar', () {
      final s = layout('state f <<fork>>\n[*] --> f\nf --> A\nf --> B');
      final bar = flatten(sceneGroup(s, 'f').children)
          .whereType<SceneShape>()
          .single;
      final rect = (bar.geometry as RectGeometry).rect;
      expect(rect.width, greaterThan(rect.height));
      expect(bar.fill, isNotNull);
    });
    test('composite cluster contains members with title', () {
      final s = layout('state Active {\nIdle --> Busy\n}\n[*] --> Active');
      final cluster = sceneNodeBounds(sceneGroup(s, 'Active'))!;
      for (final id in ['Idle', 'Busy']) {
        expect(cluster.contains(sceneNodeBounds(sceneGroup(s, id))!.center),
            isTrue);
      }
      expect(
        flatten(s.nodes).whereType<SceneText>().any((t) => t.text == 'Active'),
        isTrue,
      );
    });
    test('self-transition on composite renders a loop', () {
      final s = layout('state Active {\nIdle\n}\nActive --> Active : LOG');
      final loop = sceneGroup(s, 'trans_Active_Active_0');
      expect(flatten(loop.children).whereType<SceneShape>(), isNotEmpty);
      expect(
        flatten(s.nodes).whereType<SceneText>().any((t) => t.text == 'LOG'),
        isTrue,
      );
    });
    test('transition label has background', () {
      final s = layout('A --> B : go');
      expect(
        flatten(s.nodes).whereType<SceneText>().any((t) => t.text == 'go'),
        isTrue,
      );
    });
    test('note renders beside the state with dashed connector', () {
      final s = layout('A --> B\nnote right of A : check this');
      expect(
        flatten(s.nodes)
            .whereType<SceneText>()
            .any((t) => t.text == 'check this'),
        isTrue,
      );
      expect(
        flatten(s.nodes).whereType<SceneShape>().any((n) =>
            n.geometry is PathGeometry && n.stroke?.dash != null),
        isTrue,
      );
    });
    test('scene bounds enclose everything', () {
      final s = layout('[*] --> A\nstate A {\nx --> y\n}\nA --> A : again\n'
          'note right of A : hi');
      for (final n in flatten(s.nodes)) {
        final b = sceneNodeBounds(n);
        if (b == null) continue;
        expect(b.left, greaterThanOrEqualTo(-0.5));
        expect(b.top, greaterThanOrEqualTo(-0.5));
        expect(b.right, lessThanOrEqualTo(s.size.width + 0.5));
        expect(b.bottom, lessThanOrEqualTo(s.size.height + 0.5));
      }
    });
  });
}

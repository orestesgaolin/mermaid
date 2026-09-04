/// State diagram parser + layout tests; parser cases ported from upstream
/// stateDiagram.spec.js.
library;

import 'support/fixtures.dart';

import 'package:mermaid_core/src/diagrams/flowchart/flow_model.dart'
    show FlowDirection;
import 'package:mermaid_core/src/diagrams/state/state_layout.dart';
import 'package:mermaid_core/src/diagrams/state/state_model.dart';
import 'package:mermaid_core/src/diagrams/state/state_parser.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/ir/scene_utils.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

StateDiagram parse(String body) => parseStateDiagram('stateDiagram-v2\n$body');

RenderScene layout(String body) => layoutStateDiagram(
  parse(body),
  measurer: const ApproximateTextMeasurer(),
  theme: MermaidTheme.defaultTheme,
);

String stateFixture(String name) => readFixture('upstream_state/$name.mmd');

List<SceneNode> flatten(List<SceneNode> nodes) => [
  for (final n in nodes) ...[n, if (n is SceneGroup) ...flatten(n.children)],
];

SceneGroup sceneGroup(RenderScene s, String id) =>
    flatten(s.nodes).whereType<SceneGroup>().firstWhere((g) => g.id == id);

PathGeometry transitionPath(RenderScene scene, String id) =>
    flatten(sceneGroup(scene, id).children)
        .whereType<SceneShape>()
        .map((shape) => shape.geometry)
        .whereType<PathGeometry>()
        .single;

PolygonGeometry transitionArrow(RenderScene scene, String id) =>
    flatten(sceneGroup(scene, id).children)
        .whereType<SceneShape>()
        .map((shape) => shape.geometry)
        .whereType<PolygonGeometry>()
        .single;

List<Point> transitionPoints(RenderScene scene, String id) =>
    transitionPath(scene, id).commands
        .map(
          (command) => switch (command) {
            MoveTo(:final p) => p,
            LineTo(:final p) => p,
            _ => null,
          },
        )
        .whereType<Point>()
        .toList();

bool segmentIntersectsRectInterior(Point a, Point b, Rect rect) {
  final inner = rect.inflate(-0.01);
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  var minT = 0.0;
  var maxT = 1.0;

  bool clip(double p, double q) {
    if (p == 0) return q >= 0;
    final ratio = q / p;
    if (p < 0) {
      if (ratio > maxT) return false;
      if (ratio > minT) minT = ratio;
    } else {
      if (ratio < minT) return false;
      if (ratio < maxT) maxT = ratio;
    }
    return true;
  }

  return clip(-dx, a.x - inner.left) &&
      clip(dx, inner.right - a.x) &&
      clip(-dy, a.y - inner.top) &&
      clip(dy, inner.bottom - a.y) &&
      minT <= maxT;
}

void expectRouteAvoidsRect(List<Point> route, Rect blocker) {
  expect(route, hasLength(greaterThan(1)));
  for (var i = 1; i < route.length; i++) {
    expect(
      segmentIntersectsRectInterior(route[i - 1], route[i], blocker),
      isFalse,
      reason: 'segment ${route[i - 1]} -> ${route[i]} crosses $blocker',
    );
  }
}

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
    test('later composite adopts an implicitly referenced state', () {
      final d = parseStateDiagram(stateFixture('05'));
      expect(d.states['2nd']!.parent, 'Second');
      expect(d.states['First']!.children, isNot(contains('2nd')));
      expect(
        d.states['Second']!.children.where((id) => id == '2nd'),
        hasLength(1),
      );
      expect(
        d.transitions,
        contains(
          isA<StateTransition>()
              .having((transition) => transition.from, 'from', '2nd')
              .having((transition) => transition.to, 'to', '__end_Second'),
        ),
      );
    });
    test(
      'adoption updates regions without moving declared cross-boundary states',
      () {
        final d = parse('''
state First {
  Declared
  A --> Adopted
  --
  B
}
state Second {
  Adopted --> Declared
  Adopted --> [*]
}
''');
        expect(d.states['Declared']!.parent, 'First');
        expect(d.states['Adopted']!.parent, 'Second');
        expect(d.states['First']!.children, isNot(contains('Adopted')));
        expect(
          d.states['First']!.regions.expand((region) => region),
          isNot(contains('Adopted')),
        );
        expect(
          d.states['Second']!.children.where((id) => id == 'Adopted'),
          hasLength(1),
        );
      },
    );
    test(
      'root references preserve nested ownership and adoption rejects cycles',
      () {
        final d = parse('''
state Parent {
  X --> Nested
  state Child {
    state Parent
  }
}
Nested --> RootTarget
''');
        expect(d.states['Nested']!.parent, 'Parent');
        expect(d.states['Child']!.parent, 'Parent');
        // `state Parent` inside Child would make Parent its own grandchild;
        // the adoption is rejected outright, so Parent keeps the root scope and
        // Child never lists it as a member.
        expect(d.states['Parent']!.parent, isNull);
        expect(d.states['Child']!.children, isNot(contains('Parent')));
      },
    );
    test('a state named in two composites belongs to the last one', () {
      // Upstream resolves this in `dataFetcher`: every mention rebuilds the
      // node and `insertOrUpdateNode` Object.assigns it over the previous one,
      // so the parentId of the last enclosing document wins.
      final d = parse('''
state Outer {
  X --> Y
}
state Other {
  X --> Z
}
''');
      expect(d.states['X']!.parent, 'Other');
      expect(d.states['Outer']!.children, isNot(contains('X')));
      expect(d.states['Outer']!.children, contains('Y'));
      expect(d.states['Other']!.children, containsAll(['X', 'Z']));
      // Both relations survive the move.
      expect(
        d.transitions.map((t) => (t.from, t.to)),
        containsAll([('X', 'Y'), ('X', 'Z')]),
      );
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
        '---\ntitle: Machine\n---\nstateDiagram-v2\nA --> B',
      );
      expect(d.title, 'Machine');
    });
    test('garbage throws with line number', () {
      expect(
        () => parse('A --> B\n!!!nope'),
        throwsA(
          isA<MermaidParseException>().having((e) => e.line, 'line', isNotNull),
        ),
      );
    });
  });

  group('layout', () {
    test('start is filled circle, end is double circle', () {
      final s = layout('[*] --> A\nA --> [*]');
      final start = flatten(
        sceneGroup(s, '__start_').children,
      ).whereType<SceneShape>().toList();
      expect(start.single.geometry, isA<CircleGeometry>());
      expect(start.single.fill, isNotNull);
      final end = flatten(
        sceneGroup(s, '__end_').children,
      ).whereType<SceneShape>().toList();
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
      final shapes = flatten(
        sceneGroup(s, 'c').children,
      ).whereType<SceneShape>();
      expect(shapes.single.geometry, isA<PolygonGeometry>());
    });
    test('fork renders a filled bar', () {
      final s = layout('state f <<fork>>\n[*] --> f\nf --> A\nf --> B');
      final bar = flatten(
        sceneGroup(s, 'f').children,
      ).whereType<SceneShape>().single;
      final rect = (bar.geometry as RectGeometry).rect;
      expect(rect.width, greaterThan(rect.height));
      expect(bar.fill, isNotNull);
    });
    test('composite cluster contains members with title', () {
      final s = layout('state Active {\nIdle --> Busy\n}\n[*] --> Active');
      final cluster = sceneNodeBounds(sceneGroup(s, 'Active'))!;
      for (final id in ['Idle', 'Busy']) {
        expect(
          cluster.contains(sceneNodeBounds(sceneGroup(s, id))!.center),
          isTrue,
        );
      }
      expect(
        flatten(s.nodes).whereType<SceneText>().any((t) => t.text == 'Active'),
        isTrue,
      );
    });
    test('empty composite renders as a box that transitions can target', () {
      final s = layout('A --> B\nstate B {\n}\n');
      final box = sceneNodeBounds(sceneGroup(s, 'B'))!;
      expect(box.width, greaterThan(0));
      expect(box.height, greaterThan(0));
      expect(
        flatten(s.nodes).whereType<SceneText>().map((t) => t.text),
        contains('B'),
      );

      // The transition ends on the box instead of dangling at the origin.
      final route = transitionPath(s, 'trans_A_B_0');
      final end = switch (route.commands.last) {
        LineTo(:final p) => p,
        CubicTo(:final p) => p,
        final other => fail('unexpected terminal command $other'),
      };
      expect(end.x, inInclusiveRange(box.left, box.right));
      expect(end.y, inInclusiveRange(box.top - 12, box.bottom));
      expect(sceneNodeBounds(sceneGroup(s, 'A'))!.bottom, lessThan(box.top));
    });
    test('adopted fixture state renders only inside its final composite', () {
      final diagram = parseStateDiagram(stateFixture('05'));
      final s = layoutStateDiagram(
        diagram,
        measurer: const ApproximateTextMeasurer(),
        theme: MermaidTheme.defaultTheme,
      );
      final first = sceneNodeBounds(sceneGroup(s, 'First'))!;
      final second = sceneNodeBounds(sceneGroup(s, 'Second'))!;
      final adoptedGroups = flatten(
        s.nodes,
      ).whereType<SceneGroup>().where((group) => group.id == '2nd').toList();
      expect(adoptedGroups, hasLength(1));
      final adopted = sceneNodeBounds(adoptedGroups.single)!.center;
      expect(second.contains(adopted), isTrue);
      expect(first.contains(adopted), isFalse);
    });
    test(
      'nested fixture preserves hierarchical placement and straight routes',
      () {
        final diagram = parseStateDiagram(stateFixture('05'));
        final s = layoutStateDiagram(
          diagram,
          measurer: const ApproximateTextMeasurer(),
          theme: MermaidTheme.defaultTheme,
        );

        final first = sceneNodeBounds(sceneGroup(s, 'First'))!;
        final inner = sceneNodeBounds(sceneGroup(s, 'innerFirst'))!;
        final firstState = sceneNodeBounds(sceneGroup(s, '1st'))!;
        final second = sceneNodeBounds(sceneGroup(s, 'Second'))!;
        final third = sceneNodeBounds(sceneGroup(s, 'Third'))!;

        expect(inner.top, greaterThan(firstState.bottom));
        expect((inner.center.x - firstState.center.x).abs(), lessThan(25));
        expect(first.bottom - inner.bottom, greaterThan(5));
        expect(second.top, greaterThan(first.bottom));
        expect(third.left, greaterThan(first.right));

        // Composite bodies alternate with depth: a root composite shows the
        // theme background, a nested one a slight tint of it.
        final background = MermaidTheme.defaultTheme.background;
        List<SceneShape> bodyShapes(String id) => sceneGroup(s, id).children
            .whereType<SceneShape>()
            .where((shape) => shape.geometry is RectGeometry)
            .toList();
        final rootBodyShapes = bodyShapes('First');
        final nestedBodyShapes = bodyShapes('innerFirst');
        expect(rootBodyShapes, hasLength(2));
        expect(nestedBodyShapes, hasLength(2));
        expect(rootBodyShapes.last.fill?.color, background);
        final nestedBody = nestedBodyShapes.last.fill!.color;
        expect(nestedBody, isNot(background));
        expect((nestedBody.red - background.red).abs(), lessThan(32));
        expect(nestedBody.red, nestedBody.green);
        expect(nestedBody.green, nestedBody.blue);

        final rootBranch =
            flatten(sceneGroup(s, 'trans_First_Third_2').children)
                .whereType<SceneShape>()
                .map((shape) => shape.geometry)
                .whereType<PathGeometry>()
                .single;
        final start = (rootBranch.commands.first as MoveTo).p;
        final end = (rootBranch.commands.last as LineTo).p;
        expect(start.x, closeTo(first.right, 0.001));
        expect(third.left - end.x, inInclusiveRange(0, 8.1));

        for (final id in [
          'trans___start_innerFirst_1st1st_4',
          'trans_1st1st_1st2nd_5',
        ]) {
          final path = flatten(sceneGroup(s, id).children)
              .whereType<SceneShape>()
              .map((shape) => shape.geometry)
              .whereType<PathGeometry>()
              .single;
          expect(path.commands.whereType<CubicTo>(), isEmpty);
        }

        final parentRoute = transitionPath(s, 'trans_First_Second_1');
        final nestedRoute = transitionPath(s, 'trans_innerFirst_2nd_7');
        final parentStart = (parentRoute.commands.first as MoveTo).p;
        final nestedStart = (nestedRoute.commands.first as MoveTo).p;
        expect((parentStart.x - nestedStart.x).abs(), greaterThan(5));
      },
    );
    test('fixture pseudo-state arrows use the shared vertical centre line', () {
      final s = layoutStateDiagram(
        parseStateDiagram(stateFixture('05')),
        measurer: const ApproximateTextMeasurer(),
        theme: MermaidTheme.defaultTheme,
      );

      for (final (transitionId, sourceId, targetId) in [
        ('trans___start_Third_3rd_9', '__start_Third', '3rd'),
        ('trans_3rd___end_Third_10', '3rd', '__end_Third'),
      ]) {
        final source = sceneNodeBounds(sceneGroup(s, sourceId))!;
        final target = sceneNodeBounds(sceneGroup(s, targetId))!;
        final path = transitionPath(s, transitionId);
        final start = (path.commands.first as MoveTo).p;
        final tip = transitionArrow(s, transitionId).points.first;

        expect(start.x, closeTo(source.center.x, 0.001));
        expect(start.y, closeTo(source.bottom, 0.001));
        expect(tip.x, closeTo(target.center.x, 0.001));
        expect(tip.y, closeTo(target.top, 0.001));
      }
    });
    test(
      'aligned normal-state shortcut does not cross an intervening state',
      () {
        final s = layout('''
state Root {
  A --> B
  B --> C
  A --> C
}
''');

        expectRouteAvoidsRect(
          transitionPoints(s, 'trans_A_C_2'),
          sceneNodeBounds(sceneGroup(s, 'B'))!,
        );
      },
    );
    test('aligned pseudo-state shortcut requires a clear corridor', () {
      final s = layout('''
state Root {
  A --> B
  B --> [*]
  A --> [*]
}
''');

      expectRouteAvoidsRect(
        transitionPoints(s, 'trans_A___end_Root_2'),
        sceneNodeBounds(sceneGroup(s, 'B'))!,
      );
    });
    test('explicit dagre selection is preserved for nested composites', () {
      final s = layoutStateDiagram(
        parseStateDiagram(stateFixture('05')),
        measurer: const ApproximateTextMeasurer(),
        theme: MermaidTheme.defaultTheme,
        engine: 'dagre',
      );
      final path =
          flatten(sceneGroup(s, 'trans___start_innerFirst_1st1st_4').children)
              .whereType<SceneShape>()
              .map((shape) => shape.geometry)
              .whereType<PathGeometry>()
              .single;
      expect(path.commands.whereType<CubicTo>(), isNotEmpty);
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
        flatten(
          s.nodes,
        ).whereType<SceneText>().any((t) => t.text == 'check this'),
        isTrue,
      );
      expect(
        flatten(s.nodes).whereType<SceneShape>().any(
          (n) => n.geometry is PathGeometry && n.stroke?.dash != null,
        ),
        isTrue,
      );
    });
    test('scene bounds enclose everything', () {
      final s = layout(
        '[*] --> A\nstate A {\nx --> y\n}\nA --> A : again\n'
        'note right of A : hi',
      );
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

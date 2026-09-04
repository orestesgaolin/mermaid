/// Structural tests for the sequence diagram layout.
library;

import 'support/fixtures.dart';

import 'package:mermaid_core/src/diagrams/sequence/sequence_layout.dart';
import 'package:mermaid_core/src/diagrams/sequence/sequence_parser.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/ir/scene_utils.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

RenderScene layout(String body) => layoutSequence(
  parseSequence('sequenceDiagram\n$body'),
  measurer: const ApproximateTextMeasurer(),
  theme: MermaidTheme.defaultTheme,
);

List<SceneNode> flatten(List<SceneNode> nodes) => [
  for (final n in nodes) ...[n, if (n is SceneGroup) ...flatten(n.children)],
];

Iterable<SceneGroup> groups(RenderScene s, String prefix) => flatten(
  s.nodes,
).whereType<SceneGroup>().where((g) => (g.id ?? '').startsWith(prefix));

Rect geometryBounds(ShapeGeometry g) {
  Rect points(List<Point> pts) {
    var r = Rect.fromLTWH(pts.first.x, pts.first.y, 0, 0);
    for (final p in pts) {
      r = r.union(Rect.fromLTWH(p.x, p.y, 0, 0));
    }
    return r;
  }

  return switch (g) {
    RectGeometry(:final rect) => rect,
    CircleGeometry(:final center, :final radius) => Rect.fromCenter(
      center,
      radius * 2,
      radius * 2,
    ),
    EllipseGeometry(:final center, :final rx, :final ry) => Rect.fromCenter(
      center,
      rx * 2,
      ry * 2,
    ),
    PolygonGeometry(points: final pts) => points(pts),
    PathGeometry(:final commands) => points([
      for (final c in commands)
        ...switch (c) {
          MoveTo(:final p) => [p],
          LineTo(:final p) => [p],
          QuadTo(:final c, :final p) => [c, p],
          CubicTo(:final c1, :final c2, :final p) => [c1, c2, p],
          ClosePath() => const <Point>[],
        },
    ]),
  };
}

Rect groupBounds(SceneGroup g) {
  Rect? acc;
  for (final n in flatten(g.children)) {
    final b = switch (n) {
      SceneShape(:final geometry) => geometryBounds(geometry),
      SceneText(:final bounds) => bounds,
      _ => null,
    };
    if (b != null) acc = acc == null ? b : acc.union(b);
  }
  return acc!;
}

void main() {
  test('fixture 01 wraps explicit wrap labels into a compact scene', () {
    final source = readFixture('upstream_sequence/01.mmd');
    final scene = layoutSequence(
      parseSequence(source),
      measurer: const ApproximateTextMeasurer(),
      theme: MermaidTheme.defaultTheme,
    );
    final texts = flatten(scene.nodes).whereType<SceneText>().toList();

    expect(texts.any((text) => text.text.startsWith('wrap:')), isFalse);
    expect(texts.any((text) => text.text.startsWith('nowrap:')), isFalse);
    final wrappedMessage = texts.singleWhere(
      (text) => text.text.startsWith('John! Are you still debating'),
    );
    expect(wrappedMessage.text.split('\n'), hasLength(greaterThan(1)));
    final unwrappedNote = texts.singleWhere(
      (text) => text.text.startsWith("John's trying hard"),
    );
    expect(unwrappedNote.text, isNot(contains('\n')));

    // Wrapping is what keeps the scene compact: a `wrap:` message is laid out
    // inside the gap between its two participants (centre distance plus
    // 2 * wrapPadding), never at its full single-line width.
    double centerX(String id) => groupBounds(
      groups(scene, 'actor_$id').firstWhere((g) => g.id == 'actor_$id'),
    ).center.x;
    const wrapPadding = 10.0;
    final wrapBudget = (centerX('John') - centerX('Bob')).abs() +
        2 * wrapPadding;
    expect(wrappedMessage.bounds.width, lessThanOrEqualTo(wrapBudget));
    final unwrappedWidth = const ApproximateTextMeasurer()
        .measure(
          wrappedMessage.text.replaceAll('\n', ' '),
          wrappedMessage.style,
        )
        .width;
    expect(wrappedMessage.bounds.width, lessThan(unwrappedWidth));
  });

  test('columns ordered left to right, boxes mirrored top and bottom', () {
    final s = layout('participant A\nparticipant B\nparticipant C\nA->>B: x');
    double centerX(String id) => groupBounds(
      groups(s, 'actor_$id').firstWhere((g) => g.id == 'actor_$id'),
    ).center.x;
    expect(centerX('A'), lessThan(centerX('B')));
    expect(centerX('B'), lessThan(centerX('C')));
    // Mirrored bottom boxes exist and sit below the top ones.
    final top = groupBounds(groups(s, 'actor_A').first);
    final bottom = groupBounds(groups(s, 'actor_A_bottom').single);
    expect(bottom.top, greaterThan(top.bottom));
  });

  test('messages are y-ordered by statement order', () {
    final s = layout('A->>B: one\nB->>A: two\nA->>B: three');
    final ys = groups(s, 'msg_').map((g) => groupBounds(g).bottom).toList();
    expect(ys.length, 3);
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
  });

  test('message arrow spans between the two lifelines', () {
    final s = layout('participant A\nparticipant B\nA->>B: hello');
    final ax = groupBounds(groups(s, 'actor_A').first).center.x;
    final bx = groupBounds(groups(s, 'actor_B').first).center.x;
    final msg = groupBounds(groups(s, 'msg_A_B').single);
    expect(msg.left, closeTo(ax, 30));
    expect(msg.right, closeTo(bx, 30));
  });

  test('activation bar spans the +/- pair', () {
    final s = layout('A->>+B: go\nB-->>-A: done');
    // The activation rect is a 10px-wide standalone shape.
    final bars = flatten(s.nodes).whereType<SceneShape>().where(
      (n) =>
          n.geometry is RectGeometry &&
          ((n.geometry as RectGeometry).rect.width - 10).abs() < 0.1,
    );
    expect(bars, hasLength(1));
    final bar = (bars.single.geometry as RectGeometry).rect;
    final msgs = groups(s, 'msg_').map(groupBounds).toList();
    expect(bar.top, lessThanOrEqualTo(msgs[1].top + 1));
    expect(bar.bottom, greaterThanOrEqualTo(msgs[1].bottom - 6));
  });

  test('auth activations align badges and leave side-note clearance', () {
    final s = layout('''
autonumber
actor U as User
participant W as Web App
participant S as Auth Service
U->>+W: Login request
W->>+S: Validate credentials
Note right of S: Check password hash
alt valid
    S-->>W: Token
    W-->>U: Welcome!
else invalid
    S-->>-W: 401
    W-->>-U: Try again
end
''');

    double actorCenter(String id) => groupBounds(
      groups(s, 'actor_$id').firstWhere((group) => group.id == 'actor_$id'),
    ).center.x;

    final bars = flatten(s.nodes)
        .whereType<SceneShape>()
        .map((shape) => shape.geometry)
        .whereType<RectGeometry>()
        .map((geometry) => geometry.rect)
        .where((rect) => (rect.width - 10).abs() < 0.1)
        .toList();
    final webBar = bars.singleWhere(
      (rect) => (rect.center.x - actorCenter('W')).abs() < 0.1,
    );
    final authBar = bars.singleWhere(
      (rect) => (rect.center.x - actorCenter('S')).abs() < 0.1,
    );
    expect(webBar.center.x, closeTo(actorCenter('W'), 1e-9));
    expect(authBar.center.x, closeTo(actorCenter('S'), 1e-9));

    Rect badge(String number) => flatten(
      s.nodes,
    ).whereType<SceneText>().singleWhere((text) => text.text == number).bounds;
    expect(badge('2').center.x, closeTo(webBar.center.x, 1e-9));
    expect(badge('3').center.x, closeTo(authBar.center.x, 1e-9));

    // `Note right of` starts actorMargin/2 right of the lifeline, which clears
    // the half-width of the activation bar drawn on that lifeline.
    const actorMargin = 50.0;
    const activationWidth = 10.0;
    final note = groupBounds(groups(s, 'note').single);
    expect(note.left, closeTo(actorCenter('S') + actorMargin / 2, 1e-9));
    expect(
      note.left - authBar.right,
      closeTo(actorMargin / 2 - activationWidth / 2, 1e-9),
    );
  });

  test('a created participant exposes both its top and bottom box', () {
    final s = layout(
      'participant A\nparticipant B\n'
      'A->>B: hello\n'
      'create participant C\n'
      'B->>C: made you\n',
    );
    final ids = flatten(s.nodes)
        .whereType<SceneGroup>()
        .map((group) => group.id)
        .whereType<String>()
        .toList();
    // Both boxes used to be emitted as `actor_C_bottom`, which dropped
    // `actor_C` from the public hover/tap surface entirely.
    expect(ids.where((id) => id == 'actor_C'), hasLength(1));
    expect(ids.where((id) => id == 'actor_C_bottom'), hasLength(1));
    expect(s.nodeBounds.keys, contains('actor_C'));

    final top = groupBounds(
      groups(s, 'actor_C').firstWhere((group) => group.id == 'actor_C'),
    );
    final bottom = groupBounds(groups(s, 'actor_C_bottom').single);
    expect(bottom.top, greaterThan(top.bottom));
    // The created box starts below the diagram top, unlike a declared one.
    final declared = groupBounds(
      groups(s, 'actor_A').firstWhere((group) => group.id == 'actor_A'),
    );
    expect(top.top, greaterThan(declared.bottom));
  });

  test('an arrow into an active participant stops on its bar', () {
    // Upstream ends a message on the target's activation-bar edge
    // (`stopx = isArrowToRight ? toLeft : toRight`), not on its lifeline, and
    // nested bars step right by half an activation width each. The sending
    // side already did this; the tip ignored it.
    final s = layout(
      'participant A\nparticipant B\n'
      'A->>B: on the lifeline\n'
      'activate B\n'
      'activate B\n'
      'A->>B: on the nested bar\n'
      'deactivate B\n'
      'deactivate B\n',
    );
    final arrows = groups(s, 'msg_').map(groupBounds).toList()
      ..sort((a, b) => a.top.compareTo(b.top));
    expect(arrows, hasLength(2));

    // The nested bar is drawn at [x, x + activationWidth]; the tip moves with
    // its centre, half an activation width right of the bare lifeline.
    const activationWidth = 10.0;
    expect(
      arrows[1].right - arrows[0].right,
      closeTo(activationWidth / 2, 1e-9),
    );
  });

  test('note over two participants spans both lifelines', () {
    final s = layout(
      'participant A\nparticipant B\nA->>B: x\n'
      'Note over A,B: across',
    );
    final ax = groupBounds(groups(s, 'actor_A').first).center.x;
    final bx = groupBounds(groups(s, 'actor_B').first).center.x;
    final note = groupBounds(groups(s, 'note').single);
    expect(note.left, lessThan(ax));
    expect(note.right, greaterThan(bx));
  });

  test('loop frame encloses its messages', () {
    final s = layout('loop forever\nA->>B: ping\nB-->>A: pong\nend');
    final frame = groupBounds(groups(s, 'frame_loop').single);
    for (final m in groups(s, 'msg_')) {
      final b = groupBounds(m);
      expect(frame.top, lessThan(b.top));
      expect(frame.bottom, greaterThan(b.bottom));
    }
    // Keyword tab text present.
    expect(
      flatten(s.nodes).whereType<SceneText>().any((t) => t.text == 'loop'),
      isTrue,
    );
  });

  test('nested rect backgrounds paint parent before child', () {
    final s = layout('''
box rgb(10, 20, 30) Group
participant A
participant B
end
rect rgb(200, 220, 100)
  rect rgb(200, 255, 200)
    A->>B: inside
  end
  A->>B: parent only
end
rect rgb(100, 110, 120)
  A->>B: sibling
end
''');
    const participantColor = 0xff0a141e;
    const parentColor = 0xffc8dc64;
    const childColor = 0xffc8ffc8;
    const siblingColor = 0xff646e78;
    final coloredRects = s.nodes.whereType<SceneShape>().where(
      (shape) => shape.geometry is RectGeometry && shape.fill != null,
    );
    final colors = coloredRects
        .map((shape) => shape.fill!.color.value)
        .toList();
    expect(
      colors,
      containsAllInOrder([
        participantColor,
        parentColor,
        childColor,
        siblingColor,
      ]),
    );

    Rect rectOf(int color) =>
        (coloredRects
                    .singleWhere((shape) => shape.fill!.color.value == color)
                    .geometry
                as RectGeometry)
            .rect;
    final parent = rectOf(parentColor);
    final child = rectOf(childColor);
    final sibling = rectOf(siblingColor);
    expect(child.top, greaterThan(parent.top));
    expect(child.bottom, lessThan(parent.bottom));
    expect(child.left, lessThan(parent.right));
    expect(child.right, greaterThan(parent.left));
    expect(sibling.top, greaterThan(parent.bottom));
  });

  test('alt divider renders bracketed label', () {
    final s = layout('alt ok\nA->>B: a\nelse failed\nA->>B: b\nend');
    expect(
      flatten(s.nodes).whereType<SceneText>().any((t) => t.text == '[failed]'),
      isTrue,
    );
  });

  test('self message stays right of the lifeline', () {
    final s = layout('A->>A: think');
    final ax = groupBounds(groups(s, 'actor_A').first).center.x;
    final msg = groupBounds(groups(s, 'msg_A_A').single);
    expect(msg.right, greaterThan(ax + 20));
  });

  test('autonumber emits number badges', () {
    final s = layout('autonumber\nA->>B: one\nB->>A: two');
    final texts = flatten(s.nodes).whereType<SceneText>().map((t) => t.text);
    expect(texts, containsAll(['1', '2']));
  });

  test('scene bounds enclose everything with margin', () {
    final s = layout(
      'A->>B: x\nNote left of A: way left\nloop l\nA->>B: y\nend',
    );
    for (final n in flatten(s.nodes)) {
      final b = switch (n) {
        SceneShape(geometry: RectGeometry(:final rect)) => rect,
        SceneText(:final bounds) => bounds,
        _ => null,
      };
      if (b == null) continue;
      expect(b.left, greaterThanOrEqualTo(-0.5));
      expect(b.top, greaterThanOrEqualTo(-0.5));
      expect(b.right, lessThanOrEqualTo(s.size.width + 0.5));
      expect(b.bottom, lessThanOrEqualTo(s.size.height + 0.5));
    }
  });

  test('actor keyword draws a stick figure (circle head)', () {
    final s = layout('actor A\nA->>B: x');
    final actorGroup = groups(s, 'actor_A').first;
    expect(
      flatten(
        actorGroup.children,
      ).whereType<SceneShape>().any((n) => n.geometry is CircleGeometry),
      isTrue,
    );
  });
}

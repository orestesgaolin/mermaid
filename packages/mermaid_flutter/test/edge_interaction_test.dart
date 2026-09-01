import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  testWidgets('taps a long curved edge stroke and its label', (tester) async {
    const source = '''flowchart TD
  A[Start] --> B[Middle]
  B --> C[Finish]
  A -->|skip_condition| C''';
    final scene = _render(source);
    final taps = <(String, String, int)>[];
    await _pumpDiagram(tester, source, (a, b, i) => taps.add((a, b, i)));
    final origin = tester.getTopLeft(find.byType(MermaidDiagram));

    final stroke = _distinctStrokePoint(scene, 2);
    await tester.tapAt(origin + Offset(stroke.x, stroke.y));
    await tester.pump();
    expect(taps.removeLast(), ('A', 'C', 2));

    final label = _edgeGroup(scene, core.SceneGroupRole.edgeLabel, 2);
    final labelCenter = core.sceneBounds(label.children)!.center;
    await tester.tapAt(origin + Offset(labelCenter.x, labelCenter.y));
    await tester.pump();
    expect(taps.removeLast(), ('A', 'C', 2));
  });

  testWidgets('parallel and antiparallel strokes keep distinct link indices', (
    tester,
  ) async {
    const source = '''%%{init: {'layout': 'tidy-tree'}}%%
flowchart LR
  from_id --> to_id
  from_id --> to_id
  to_id --> from_id''';
    final scene = _render(source);
    final taps = <(String, String, int)>[];
    await _pumpDiagram(tester, source, (a, b, i) => taps.add((a, b, i)));
    final origin = tester.getTopLeft(find.byType(MermaidDiagram));

    for (final index in [0, 1, 2]) {
      final point = _distinctStrokePoint(scene, index);
      await tester.tapAt(origin + Offset(point.x, point.y));
      await tester.pump();
      expect(taps.last.$3, index);
    }
    expect(taps[0].$1, 'from_id');
    expect(taps[2].$1, 'to_id');
  });

  testWidgets('nodes occlude edges and invisible edges are not targets', (
    tester,
  ) async {
    const source = '''flowchart LR
  A[Start] --> B[Target]
  A ~~~ C[Hidden target]''';
    final scene = _render(source);
    var edgeTaps = 0;
    await _pumpDiagram(tester, source, (_, _, _) => edgeTaps++);
    final origin = tester.getTopLeft(find.byType(MermaidDiagram));

    final targetBounds = scene.boundsOf('B')!;
    final inside = core.Point(targetBounds.left + 1, targetBounds.center.y);
    await tester.tapAt(origin + Offset(inside.x, inside.y));
    await tester.pump();
    expect(edgeTaps, 0, reason: 'the node must occlude the nearby edge');

    final hiddenMid = _midpoint(
      scene.boundsOf('A')!.center,
      scene.boundsOf('C')!.center,
    );
    await tester.tapAt(origin + Offset(hiddenMid.x, hiddenMid.y));
    await tester.pump();
    expect(edgeTaps, 0);
  });

  testWidgets('MermaidView passes edge taps through its viewport transform', (
    tester,
  ) async {
    const source = 'flowchart LR\nA --- B';
    final scene = _render(source);
    final controller = MermaidViewController();
    addTearDown(controller.dispose);
    (String, String, int)? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MermaidView(
              source: source,
              controller: controller,
              showControls: false,
              onEdgeTap: (a, b, i) => tapped = (a, b, i),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final point = _distinctStrokePoint(scene, 0);
    final viewportPoint = MatrixUtils.transformPoint(
      controller.transformation,
      Offset(point.x, point.y),
    );
    final origin = tester.getTopLeft(find.byType(InteractiveViewer));
    await tester.tapAt(origin + viewportPoint);
    await tester.pump();
    expect(tapped, ('A', 'B', 0));
  });
}

core.RenderScene _render(String source) => core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(source);

Future<void> _pumpDiagram(
  WidgetTester tester,
  String source,
  void Function(String, String, int) onEdgeTap,
) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MermaidDiagram(source: source, onEdgeTap: onEdgeTap),
          ),
        ),
      ),
    );

core.SceneGroup _edgeGroup(
  core.RenderScene scene,
  core.SceneGroupRole role,
  int index,
) => _groups(scene.nodes).firstWhere(
      (group) => group.role == role && group.edge?.linkIndex == index,
    );

core.PathGeometry _edgePath(core.RenderScene scene, int index) {
  final group = _edgeGroup(scene, core.SceneGroupRole.edge, index);
  return _paths(group.children).first;
}

core.Point _distinctStrokePoint(core.RenderScene scene, int index) {
  final target = _samplePath(_edgePath(scene, index));
  final other = <core.Point>[
    for (final group in _groups(scene.nodes))
      if (group.role == core.SceneGroupRole.edge &&
          group.edge?.linkIndex != index &&
          group.children.isNotEmpty)
        ..._samplePath(_paths(group.children).first),
  ];
  final obstacles = <core.Rect>[
    ...scene.nodeBounds.values,
    for (final group in _groups(scene.nodes))
      if (group.role == core.SceneGroupRole.edgeLabel)
        core.sceneBounds(group.children)!,
  ];
  var best = target[target.length ~/ 2];
  var bestScore = double.negativeInfinity;
  for (final candidate in target.skip(2).take(target.length - 4)) {
    if (obstacles.any((rect) => rect.contains(candidate))) continue;
    final score = other.isEmpty
        ? 1000.0
        : other
            .map((point) => point.distanceTo(candidate))
            .reduce(math.min);
    if (score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  return best;
}

Iterable<core.SceneGroup> _groups(Iterable<core.SceneNode> nodes) sync* {
  for (final node in nodes) {
    if (node is core.SceneGroup) {
      yield node;
      yield* _groups(node.children);
    }
  }
}

Iterable<core.PathGeometry> _paths(Iterable<core.SceneNode> nodes) sync* {
  for (final node in nodes) {
    switch (node) {
      case core.SceneGroup(:final children):
        yield* _paths(children);
      case core.SceneShape(geometry: final core.PathGeometry path):
        yield path;
      case core.SceneShape():
      case core.SceneText():
    }
  }
}

List<core.Point> _samplePath(core.PathGeometry path) {
  final points = <core.Point>[];
  core.Point? current;
  for (final command in path.commands) {
    switch (command) {
      case core.MoveTo(:final p):
        current = p;
        points.add(p);
      case core.LineTo(:final p):
        final start = current;
        if (start != null) {
          for (var i = 1; i <= 20; i++) {
            points.add(_lerp(start, p, i / 20));
          }
        }
        current = p;
      case core.QuadTo(:final c, :final p):
        final start = current;
        if (start != null) {
          for (var i = 1; i <= 20; i++) {
            final t = i / 20;
            final u = 1 - t;
            points.add(core.Point(
              u * u * start.x + 2 * u * t * c.x + t * t * p.x,
              u * u * start.y + 2 * u * t * c.y + t * t * p.y,
            ));
          }
        }
        current = p;
      case core.CubicTo(:final c1, :final c2, :final p):
        final start = current;
        if (start != null) {
          for (var i = 1; i <= 20; i++) {
            final t = i / 20;
            final u = 1 - t;
            points.add(core.Point(
              u * u * u * start.x +
                  3 * u * u * t * c1.x +
                  3 * u * t * t * c2.x +
                  t * t * t * p.x,
              u * u * u * start.y +
                  3 * u * u * t * c1.y +
                  3 * u * t * t * c2.y +
                  t * t * t * p.y,
            ));
          }
        }
        current = p;
      case core.ClosePath():
    }
  }
  return points;
}

core.Point _lerp(core.Point a, core.Point b, double t) => core.Point(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
    );

core.Point _midpoint(core.Point a, core.Point b) =>
    core.Point((a.x + b.x) / 2, (a.y + b.y) / 2);

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_demo/main.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  testWidgets('demo focuses and highlights tapped flowchart nodes and edges', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MermaidDemoApp());
    await tester.pumpAndSettle();

    var scene = _paintedScene(tester);
    await _tapScenePoint(tester, scene.boundsOfNode('B')!.center);
    await tester.pumpAndSettle();

    expect(find.text('Node: B'), findsOneWidget);
    scene = _paintedScene(tester);
    final colors = Theme.of(
      tester.element(find.byType(MermaidView)),
    ).colorScheme;
    final node = _groups(scene.nodes).firstWhere((group) => group.id == 'B');
    final body = _shapes(
      node.children,
    ).firstWhere((shape) => shape.paintRole == core.ScenePaintRole.nodeBody);
    expect(body.fill?.color.value, colors.primaryContainer.toARGB32());
    expect(body.stroke?.color.value, colors.primary.toARGB32());
    expect(body.stroke?.width, 4);

    final viewport = find.byType(InteractiveViewer);
    final focusedCenter = MatrixUtils.transformPoint(
      tester
          .widget<InteractiveViewer>(viewport)
          .transformationController!
          .value,
      Offset(
        scene.boundsOfNode('B')!.center.x,
        scene.boundsOfNode('B')!.center.y,
      ),
    );
    expect(
      focusedCenter,
      within(
        distance: 0.01,
        from: tester.getSize(viewport).center(Offset.zero),
      ),
    );

    final edgeLabel = _groups(scene.nodes).firstWhere(
      (group) =>
          group.role == core.SceneGroupRole.edgeLabel &&
          group.edge?.linkIndex == 1,
    );
    await _tapScenePoint(tester, core.sceneBounds(edgeLabel.children)!.center);
    await tester.pump();

    expect(find.text('Edge 1: B → C'), findsOneWidget);
    scene = _paintedScene(tester);
    final edge = _groups(scene.nodes).firstWhere(
      (group) =>
          group.role == core.SceneGroupRole.edge && group.edge?.linkIndex == 1,
    );
    final stroke = _shapes(
      edge.children,
    ).firstWhere((shape) => shape.paintRole == core.ScenePaintRole.edgeStroke);
    expect(stroke.stroke?.color.value, colors.primary.toARGB32());
    expect(stroke.stroke?.width, 5);
  });
}

Future<void> _tapScenePoint(WidgetTester tester, core.Point point) async {
  final viewport = find.byType(InteractiveViewer);
  final controller = tester
      .widget<InteractiveViewer>(viewport)
      .transformationController!;
  final transformed = MatrixUtils.transformPoint(
    controller.value,
    Offset(point.x, point.y),
  );
  await tester.tapAt(tester.getTopLeft(viewport) + transformed);
}

core.RenderScene _paintedScene(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(MermaidDiagram),
      matching: find.byType(CustomPaint),
    ),
  );
  final paint = paints.singleWhere((value) => value.painter is ScenePainter);
  return (paint.painter! as ScenePainter).scene;
}

Iterable<core.SceneGroup> _groups(Iterable<core.SceneNode> nodes) sync* {
  for (final node in nodes) {
    if (node is core.SceneGroup) {
      yield node;
      yield* _groups(node.children);
    }
  }
}

Iterable<core.SceneShape> _shapes(Iterable<core.SceneNode> nodes) sync* {
  for (final node in nodes) {
    switch (node) {
      case core.SceneGroup(:final children):
        yield* _shapes(children);
      case core.SceneShape():
        yield node;
      case core.SceneText():
    }
  }
}

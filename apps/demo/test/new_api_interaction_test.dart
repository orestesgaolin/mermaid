import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_demo/main.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  testWidgets('demo focuses and highlights tapped flowchart nodes and edges', (
    tester,
  ) async {
    final previewPng = (await tester.runAsync(
      () =>
          renderToPng('flowchart LR\n  A[Start] --> B[Finish]', pixelRatio: 1),
    ))!;
    Map<String, core.FlowNodePaintOverride>? exportedNodeOverrides;
    Map<int, core.FlowLinkPaintOverride>? exportedLinkOverrides;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MermaidDemoApp(
        pngExporter:
            (
              source, {
              required pixelRatio,
              required theme,
              required nodePaintOverrides,
              required linkPaintOverrides,
            }) {
              expect(pixelRatio, 2);
              exportedNodeOverrides = nodePaintOverrides;
              exportedLinkOverrides = linkPaintOverrides;
              return Future.value(previewPng);
            },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Hover for node ids · tap to focus · tap edges to inspect'),
      findsOneWidget,
    );
    expect(find.textContaining('Viewport '), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full), findsOneWidget);
    expect(find.bySemanticsLabel('Start'), findsOneWidget);
    expect(find.bySemanticsIdentifier('A'), findsOneWidget);

    var scene = _paintedScene(tester);
    final initialViewport = find.byType(InteractiveViewer);
    final initialB = scene.boundsOfNode('B')!.center;
    final initialBViewport = MatrixUtils.transformPoint(
      tester
          .widget<InteractiveViewer>(initialViewport)
          .transformationController!
          .value,
      Offset(initialB.x, initialB.y),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1390, 890));
    await mouse.moveTo(tester.getTopLeft(initialViewport) + initialBViewport);
    await tester.pump();
    expect(find.text('Node id: B'), findsOneWidget);
    await mouse.removePointer();
    await tester.pump();
    expect(find.text('Node id: B'), findsNothing);

    await tester.tap(find.bySemanticsIdentifier('B'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Node: B'), findsOneWidget);
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
    expect(
      _viewportStatusText(tester),
      startsWith('Viewport ${(_viewportScale(tester) * 100).round()}%'),
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

    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    expect(find.byType(MermaidView), findsNWidgets(2));
    expect(find.textContaining('Viewport '), findsNWidgets(2));

    scene = _paintedScene(tester, within: dialog);
    final fullscreenViewport = find.descendant(
      of: dialog,
      matching: find.byType(InteractiveViewer),
    );
    final fullscreenB = scene.boundsOfNode('B')!.center;
    final fullscreenBViewport = MatrixUtils.transformPoint(
      tester
          .widget<InteractiveViewer>(fullscreenViewport)
          .transformationController!
          .value,
      Offset(fullscreenB.x, fullscreenB.y),
    );
    final fullscreenMouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await fullscreenMouse.addPointer(location: const Offset(1390, 890));
    await fullscreenMouse.moveTo(
      tester.getTopLeft(fullscreenViewport) + fullscreenBViewport,
    );
    await tester.pump();
    expect(find.text('Node id: B'), findsOneWidget);
    await fullscreenMouse.removePointer();
    await tester.pump();
    expect(find.text('Node id: B'), findsNothing);

    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.bySemanticsIdentifier('B'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Node: B'), findsNWidgets(2));
    scene = _paintedScene(tester, within: dialog);
    final fullscreenNode = _groups(
      scene.nodes,
    ).firstWhere((group) => group.id == 'B');
    final fullscreenBody = _shapes(
      fullscreenNode.children,
    ).firstWhere((shape) => shape.paintRole == core.ScenePaintRole.nodeBody);
    expect(
      fullscreenBody.fill?.color.value,
      colors.primaryContainer.toARGB32(),
    );
    final fullscreenCenter = MatrixUtils.transformPoint(
      tester
          .widget<InteractiveViewer>(fullscreenViewport)
          .transformationController!
          .value,
      Offset(
        scene.boundsOfNode('B')!.center.x,
        scene.boundsOfNode('B')!.center.y,
      ),
    );
    expect(
      fullscreenCenter,
      within(
        distance: 0.01,
        from: tester.getSize(fullscreenViewport).center(Offset.zero),
      ),
    );
    expect(
      _viewportStatusText(tester, within: dialog),
      startsWith(
        'Viewport ${(_viewportScale(tester, within: dialog) * 100).round()}%',
      ),
    );
    await tester.tap(find.byTooltip('Close fullscreen'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.textContaining('Node: B'), findsOneWidget);

    await tester.tap(find.byTooltip('Preview PNG export'));
    await tester.pumpAndSettle();
    expect(find.text('PNG export (2×)'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(exportedNodeOverrides, contains('B'));
    expect(exportedLinkOverrides, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
  }, semanticsEnabled: true);
}

double _viewportScale(WidgetTester tester, {Finder? within}) {
  final viewport = within == null
      ? find.byType(InteractiveViewer)
      : find.descendant(of: within, matching: find.byType(InteractiveViewer));
  return tester
      .widget<InteractiveViewer>(viewport)
      .transformationController!
      .value
      .getMaxScaleOnAxis();
}

String _viewportStatusText(WidgetTester tester, {Finder? within}) {
  final status = within == null
      ? find.textContaining('Viewport ')
      : find.descendant(of: within, matching: find.textContaining('Viewport '));
  return tester.widget<Text>(status).data!;
}

Future<void> _tapScenePoint(
  WidgetTester tester,
  core.Point point, {
  Finder? within,
}) async {
  final viewport = within == null
      ? find.byType(InteractiveViewer)
      : find.descendant(of: within, matching: find.byType(InteractiveViewer));
  final controller = tester
      .widget<InteractiveViewer>(viewport)
      .transformationController!;
  final transformed = MatrixUtils.transformPoint(
    controller.value,
    Offset(point.x, point.y),
  );
  await tester.tapAt(tester.getTopLeft(viewport) + transformed);
}

core.RenderScene _paintedScene(WidgetTester tester, {Finder? within}) {
  final diagram = within == null
      ? find.byType(MermaidDiagram)
      : find.descendant(of: within, matching: find.byType(MermaidDiagram));
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(of: diagram, matching: find.byType(CustomPaint)),
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

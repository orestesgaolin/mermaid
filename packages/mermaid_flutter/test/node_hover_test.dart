import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  testWidgets('mouse hover deduplicates nodes, cursor, leave, and tooltip', (
    tester,
  ) async {
    const source = 'flowchart LR\n  A[Start] --> B[Finish]';
    final scene = _render(source);
    final hovered = <String?>[];
    String? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MermaidDiagram(
              source: source,
              hoverCursor: SystemMouseCursors.help,
              onNodeHover: hovered.add,
              onNodeTap: (id, _) => tapped = id,
              nodeTooltipBuilder: (context, id) =>
                  Material(child: Text('Tooltip $id')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final diagram = find.byType(MermaidDiagram);
    final originalSize = tester.getSize(diagram);
    final origin = tester.getTopLeft(diagram);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: origin + const Offset(1, 1));
    await tester.pump();
    expect(hovered, isEmpty);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );

    final a = scene.boundsOfNode('A')!.center;
    await mouse.moveTo(origin + Offset(a.x, a.y));
    await tester.pump();
    expect(hovered, ['A']);
    expect(find.text('Tooltip A'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Tooltip A'), matching: find.byType(Overlay)),
      findsWidgets,
    );
    expect(
      find.ancestor(
        of: find.text('Tooltip A'),
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(diagram), originalSize);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.help,
    );

    await mouse.moveTo(origin + Offset(a.x + 1, a.y));
    await tester.pump();
    expect(hovered, ['A'], reason: 'movement inside one node is deduplicated');

    await tester.tapAt(origin + Offset(a.x, a.y));
    await tester.pump();
    expect(tapped, 'A');
    expect(hovered, ['A'], reason: 'touch taps do not emit hover changes');

    final b = scene.boundsOfNode('B')!.center;
    await mouse.moveTo(origin + Offset(b.x, b.y));
    await tester.pump();
    expect(hovered, ['A', 'B']);
    expect(find.text('Tooltip B'), findsOneWidget);

    await mouse.moveTo(origin + const Offset(1, 1));
    await tester.pump();
    expect(hovered, ['A', 'B', null]);
    expect(find.textContaining('Tooltip '), findsNothing);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );
  });

  testWidgets('MermaidView forwards hover through its fitted transform', (
    tester,
  ) async {
    const source = 'flowchart LR\n  A[Start] --> B[Finish]';
    final scene = _render(source);
    final hovered = <String?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              height: 400,
              child: MermaidView(
                source: source,
                showControls: false,
                onNodeHover: hovered.add,
                nodeTooltipBuilder: (context, id) => Text('View tooltip $id'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = find.byType(InteractiveViewer);
    final transformation = tester
        .widget<InteractiveViewer>(viewport)
        .transformationController!
        .value;
    final b = scene.boundsOfNode('B')!.center;
    final transformed = MatrixUtils.transformPoint(
      transformation,
      Offset(b.x, b.y),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(900, 700));
    await mouse.moveTo(tester.getTopLeft(viewport) + transformed);
    await tester.pump();

    expect(hovered, ['B']);
    expect(find.text('View tooltip B'), findsOneWidget);
    final expectedTooltipTopLeft =
        tester.getTopLeft(viewport) +
        MatrixUtils.transformPoint(
          transformation,
          Offset(
            scene.boundsOfNode('B')!.left,
            scene.boundsOfNode('B')!.bottom,
          ),
        ) +
        const Offset(0, 8);
    expect(
      (tester.getTopLeft(find.text('View tooltip B')) - expectedTooltipTopLeft)
          .distance,
      lessThan(0.01),
    );
  });

  testWidgets('built-in fullscreen forwards hover, cursor, and tooltip', (
    tester,
  ) async {
    const source = 'flowchart LR\n  A[Start] --> B[Finish]';
    final scene = _render(source);
    final hovered = <String?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MermaidView(
              source: source,
              onNodeHover: hovered.add,
              hoverCursor: SystemMouseCursors.help,
              nodeTooltipBuilder: (context, id) => Text('Fullscreen $id'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    final viewport = find.descendant(
      of: dialog,
      matching: find.byType(InteractiveViewer),
    );
    final transformation = tester
        .widget<InteractiveViewer>(viewport)
        .transformationController!
        .value;
    final a = scene.boundsOfNode('A')!.center;
    final target = tester.getTopLeft(viewport) +
        MatrixUtils.transformPoint(transformation, Offset(a.x, a.y));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(900, 700));
    await mouse.moveTo(target);
    await tester.pump();

    expect(hovered, ['A']);
    expect(find.text('Fullscreen A'), findsOneWidget);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.help,
    );
  });
}

core.RenderScene _render(String source) =>
    core.Mermaid(measurer: const FlutterTextMeasurer()).render(source);

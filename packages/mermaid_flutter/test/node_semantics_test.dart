import 'dart:ui' as ui show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  testWidgets('semantic nodes are opt-in and exclude decorative groups', (
    tester,
  ) async {
    const source = 'flowchart LR\n  A[Human start] --> B[Finish]';
    final scene = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(source);
    String? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: MermaidDiagram(source: source, onNodeTap: (id, _) => tapped = id),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Human start'), findsNothing);
    expect(find.bySemanticsIdentifier('A'), findsNothing);
    final origin = tester.getTopLeft(find.byType(MermaidDiagram));
    final center = scene.boundsOfNode('A')!.center;
    await tester.tapAt(origin + Offset(center.x, center.y));
    expect(tapped, 'A', reason: 'opt-out keeps canvas interaction unchanged');
  }, semanticsEnabled: true);

  testWidgets('semantic nodes expose labels, ids, order, and tap actions', (
    tester,
  ) async {
    final taps = <(String, String?)>[];
    const source = '''
flowchart LR
  subgraph group[Decorative group]
    A[Human start] --> B[Finish]
  end
  click A "https://example.com/start"
''';

    await tester.pumpWidget(
      MaterialApp(
        home: MermaidDiagram(
          source: source,
          semanticNodes: true,
          onNodeTap: (id, link) => taps.add((id, link)),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Human start'), findsOneWidget);
    expect(find.bySemanticsLabel('Finish'), findsOneWidget);
    expect(find.bySemanticsIdentifier('A'), findsOneWidget);
    expect(find.bySemanticsIdentifier('B'), findsOneWidget);
    expect(find.bySemanticsLabel('Decorative group'), findsNothing);

    final a = find.semantics.byLabel('Human start');
    final data = a.evaluate().single.getSemanticsData();
    expect(data.identifier, 'A');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.bySemanticsLabel('Human start'));
    await tester.pump();
    expect(taps, [('A', 'https://example.com/start')]);

    tester.semantics.tap(a);
    await tester.pump();
    expect(taps, [
      ('A', 'https://example.com/start'),
      ('A', 'https://example.com/start'),
    ]);

    final nodeLabels = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((node) => node.label)
        .where((label) => label == 'Human start' || label == 'Finish');
    expect(nodeLabels, ['Human start', 'Finish']);
  }, semanticsEnabled: true);

  testWidgets('fallback ids are exposed and non-node roles are excluded', (
    tester,
  ) async {
    const bounds = core.Rect.fromLTWH(10, 10, 40, 30);
    const body = core.SceneShape(geometry: core.RectGeometry(bounds));
    const scene = core.RenderScene(
      size: core.Size(200, 100),
      nodes: [
        core.SceneGroup(id: 'fallback', semanticLabel: '  ', children: [body]),
        core.SceneGroup(
          id: 'cluster',
          role: core.SceneGroupRole.cluster,
          semanticLabel: 'Cluster',
          children: [body],
        ),
        core.SceneGroup(
          id: 'edge',
          role: core.SceneGroupRole.edge,
          semanticLabel: 'Edge',
          children: [body],
        ),
        core.SceneGroup(
          id: 'edge-label',
          role: core.SceneGroupRole.edgeLabel,
          semanticLabel: 'Edge label',
          children: [body],
        ),
        core.SceneGroup(
          id: 'annotation',
          role: core.SceneGroupRole.annotation,
          semanticLabel: 'Annotation',
          children: [body],
        ),
        core.SceneGroup(
          id: 'internal',
          role: core.SceneGroupRole.internal,
          semanticLabel: 'Internal',
          children: [body],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MermaidDiagram(
          source: 'ignored',
          semanticNodes: true,
          sceneRenderer: (_, _) => scene,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('fallback'), findsOneWidget);
    expect(find.bySemanticsIdentifier('fallback'), findsOneWidget);
    final fallbackData = find.semantics
        .byLabel('fallback')
        .evaluate()
        .single
        .getSemanticsData();
    expect(fallbackData.flagsCollection.isButton, isFalse);
    expect(fallbackData.flagsCollection.isEnabled, ui.Tristate.none);
    expect(fallbackData.hasAction(SemanticsAction.tap), isFalse);
    for (final label in [
      'Cluster',
      'Edge',
      'Edge label',
      'Annotation',
      'Internal',
    ]) {
      expect(find.bySemanticsLabel(label), findsNothing);
    }
  }, semanticsEnabled: true);

  testWidgets('MermaidView transforms semantic bounds with painted nodes', (
    tester,
  ) async {
    const source = 'flowchart LR\n  A[Start] --> B[Finish]';
    final controller = MermaidViewController();
    addTearDown(controller.dispose);
    String? tapped;
    final scene = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(source);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(left: 40, top: 30),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                height: 400,
                child: MermaidView(
                  source: source,
                  controller: controller,
                  semanticNodes: true,
                  showControls: false,
                  onNodeTap: (id, _) => tapped = id,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = find.byType(InteractiveViewer);
    final viewportOrigin = tester.getTopLeft(viewport);
    final transformation = tester
        .widget<InteractiveViewer>(viewport)
        .transformationController!
        .value;
    final bounds = scene.boundsOfNode('B')!;
    final expected = MatrixUtils.transformRect(
      Matrix4.translationValues(viewportOrigin.dx, viewportOrigin.dy, 0)
        ..multiply(transformation),
      Rect.fromLTRB(bounds.left, bounds.top, bounds.right, bounds.bottom),
    );
    expect(
      tester.getRect(find.bySemanticsIdentifier('B')),
      within(distance: 0.01, from: expected),
    );

    final focus = controller.focusNode('B', zoom: 1.7, animate: false);
    await tester.pump();
    await tester.pump();
    expect(await focus, isTrue);
    await tester.pump();
    final focusedTransform = tester
        .widget<InteractiveViewer>(viewport)
        .transformationController!
        .value;
    final focusedExpected = MatrixUtils.transformRect(
      Matrix4.translationValues(viewportOrigin.dx, viewportOrigin.dy, 0)
        ..multiply(focusedTransform),
      Rect.fromLTRB(bounds.left, bounds.top, bounds.right, bounds.bottom),
    );
    expect(
      tester.getRect(find.bySemanticsIdentifier('B')),
      within(distance: 0.01, from: focusedExpected),
    );
    await tester.tap(find.bySemanticsIdentifier('B'));
    expect(tapped, 'B');
  }, semanticsEnabled: true);
}

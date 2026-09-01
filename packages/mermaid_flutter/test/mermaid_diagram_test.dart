import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  testWidgets('node bounds center targets the matching diagram node', (
    tester,
  ) async {
    const source = 'flowchart TD\n  n1["First"] -->|next| n2["Second"]';
    final scene = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(source);
    String? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MermaidDiagram(
              source: source,
              onNodeTap: (id, link) => tapped = id,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final origin = tester.getTopLeft(find.byType(MermaidDiagram));
    final center = scene.boundsOfNode('n1')!.center;
    await tester.tapAt(origin + Offset(center.x, center.y));
    await tester.pump();

    expect(tapped, 'n1');
  });

  testWidgets('paint overrides reuse a 50-node base scene', (tester) async {
    var source = StringBuffer('flowchart LR\n  N0[Step 0]')
      ..writeAll([
        for (var i = 1; i < 50; i++) ' --> N$i[Step $i]',
      ]);
    var fullRenders = 0;
    var theme = core.MermaidTheme.defaultTheme;
    var nodeOverrides = const <String, core.FlowNodePaintOverride>{};
    var linkOverrides = const <int, core.FlowLinkPaintOverride>{};
    final deliveredScenes = <core.RenderScene>[];
    late StateSetter update;

    core.RenderScene renderer(String value, core.MermaidTheme valueTheme) {
      fullRenders++;
      return core.Mermaid(
        measurer: const FlutterTextMeasurer(),
        theme: valueTheme,
      ).render(value);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MermaidDiagram(
                source: source.toString(),
                theme: theme,
                sceneRenderer: renderer,
                nodePaintOverrides: nodeOverrides,
                linkPaintOverrides: linkOverrides,
                onSceneChanged: deliveredScenes.add,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(fullRenders, 1);
    expect(deliveredScenes, hasLength(1));
    final base = _paintedScene(tester);
    expect(deliveredScenes.single, same(base));

    update(() {
      nodeOverrides = const {
        'N25': core.FlowNodePaintOverride(
          fill: core.Color(0xffffcc00),
          stroke: core.Color(0xffcc3300),
          strokeWidth: 5,
        ),
      };
      linkOverrides = const {
        24: core.FlowLinkPaintOverride(
          stroke: core.Color(0xff0066ff),
          strokeWidth: 6,
        ),
      };
    });
    await tester.pump();
    expect(fullRenders, 1);
    expect(
      deliveredScenes,
      hasLength(1),
      reason: 'paint-only changes do not publish new geometry',
    );
    final highlighted = _paintedScene(tester);
    expect(highlighted, isNot(same(base)));
    expect(highlighted.size, base.size);
    expect(highlighted.nodeBounds, base.nodeBounds);
    final node = _groups(highlighted.nodes).firstWhere((g) => g.id == 'N25');
    final nodeBody = _shapes(node.children).firstWhere(
      (shape) => shape.paintRole == core.ScenePaintRole.nodeBody,
    );
    expect(nodeBody.fill?.color, const core.Color(0xffffcc00));
    expect(nodeBody.stroke?.color, const core.Color(0xffcc3300));
    final edge = _groups(highlighted.nodes).firstWhere(
      (g) =>
          g.role == core.SceneGroupRole.edge && g.edge?.linkIndex == 24,
    );
    final edgeStroke = _shapes(edge.children).firstWhere(
      (shape) => shape.paintRole == core.ScenePaintRole.edgeStroke,
    );
    expect(edgeStroke.stroke?.color, const core.Color(0xff0066ff));
    expect(edgeStroke.stroke?.width, 6);

    update(() {
      nodeOverrides = const {};
      linkOverrides = const {};
    });
    await tester.pump();
    expect(fullRenders, 1);
    expect(deliveredScenes, hasLength(1));
    expect(_paintedScene(tester), same(base));

    update(() {
      theme = core.MermaidTheme.defaultTheme.copyWith(fontSize: 19);
    });
    await tester.pump();
    expect(fullRenders, 2, reason: 'font metrics require a complete render');
    expect(deliveredScenes, hasLength(2));

    update(() {
      source = StringBuffer('${source.toString()} --> N50[Step 50]');
    });
    await tester.pump();
    expect(fullRenders, 3, reason: 'structural source changes require a complete render');
    expect(deliveredScenes, hasLength(3));
  });
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

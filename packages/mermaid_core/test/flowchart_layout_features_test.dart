/// Tests for self-loop edges and per-subgraph direction layout.
library;

import 'package:mermaid_core/src/diagrams/flowchart/flow_layout.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_model.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

RenderScene layout(FlowGraph g) => layoutFlowchart(
      g,
      measurer: const ApproximateTextMeasurer(),
      theme: MermaidTheme.defaultTheme,
    );

FlowNode node(String id) => FlowNode(id: id, label: id);

/// Flattens the scene tree, returning every node with its group path.
List<(List<String?>, SceneNode)> flatten(List<SceneNode> nodes,
    [List<String?> path = const []]) {
  final out = <(List<String?>, SceneNode)>[];
  for (final n in nodes) {
    out.add((path, n));
    if (n is SceneGroup) {
      out.addAll(flatten(n.children, [...path, n.id]));
    }
  }
  return out;
}

SceneGroup groupById(RenderScene scene, String id) => flatten(scene.nodes)
    .map((e) => e.$2)
    .whereType<SceneGroup>()
    .firstWhere((g) => g.id == id);

Rect groupBounds(SceneGroup g) {
  Rect? acc;
  for (final (_, n) in flatten(g.children)) {
    final b = switch (n) {
      SceneShape(geometry: RectGeometry(:final rect)) => rect,
      SceneText(:final bounds) => bounds,
      _ => null,
    };
    if (b != null) acc = acc == null ? b : acc.union(b);
  }
  return acc!;
}

void main() {
  group('self-loops', () {
    test('loop stays right of node center with arrowhead, inside scene', () {
      final g = FlowGraph(
        direction: FlowDirection.tb,
        nodes: {'A': node('A')},
        edges: const [FlowEdge(from: 'A', to: 'A', label: 'again')],
      );
      final scene = layout(g);
      final edgeGroup = groupById(scene, 'edge_A_A_0');
      final path = edgeGroup.children.whereType<SceneShape>().firstWhere(
          (s) => s.geometry is PathGeometry,
          orElse: () => fail('no loop path emitted'));
      final nodeGroup = groupById(scene, 'A');
      final nodeRect = groupBounds(nodeGroup);
      for (final cmd in (path.geometry as PathGeometry).commands) {
        final pts = switch (cmd) {
          MoveTo(:final p) => [p],
          LineTo(:final p) => [p],
          CubicTo(:final c1, :final c2, :final p) => [c1, c2, p],
          QuadTo(:final c, :final p) => [c, p],
          ClosePath() => const <Point>[],
        };
        for (final p in pts) {
          expect(p.x, greaterThanOrEqualTo(nodeRect.center.x),
              reason: 'loop should bulge to the right of the node');
          expect(scene.size.width, greaterThanOrEqualTo(p.x),
              reason: 'loop must stay inside the scene');
        }
      }
      // Arrowhead present (point head = filled triangle polygon).
      expect(
        edgeGroup.children.whereType<SceneShape>().any(
            (s) => s.geometry is PolygonGeometry && s.fill != null),
        isTrue,
      );
      // Label emitted.
      expect(
        flatten(scene.nodes).map((e) => e.$2).whereType<SceneText>().any(
            (t) => t.text == 'again'),
        isTrue,
      );
    });

    test('two self-loops on one node are offset from each other', () {
      final g = FlowGraph(
        direction: FlowDirection.tb,
        nodes: {'A': node('A')},
        edges: const [
          FlowEdge(from: 'A', to: 'A'),
          FlowEdge(from: 'A', to: 'A'),
        ],
      );
      final scene = layout(g);
      double maxX(SceneGroup grp) {
        var x = double.negativeInfinity;
        for (final (_, n) in flatten(grp.children)) {
          if (n is SceneShape && n.geometry is PathGeometry) {
            for (final cmd in (n.geometry as PathGeometry).commands) {
              if (cmd is CubicTo) {
                x = [x, cmd.c1.x, cmd.c2.x].reduce((a, b) => a > b ? a : b);
              }
            }
          }
        }
        return x;
      }

      final x0 = maxX(groupById(scene, 'edge_A_A_0'));
      final x1 = maxX(groupById(scene, 'edge_A_A_1'));
      expect((x1 - x0).abs(), greaterThan(8));
    });
  });

  group('per-subgraph direction', () {
    FlowGraph mixed() => FlowGraph(
          direction: FlowDirection.tb,
          nodes: {
            for (final id in ['req', 'a1', 'a2', 'a3', 'resp']) id: node(id),
          },
          edges: const [
            FlowEdge(from: 'req', to: 'a1'),
            FlowEdge(from: 'a1', to: 'a2'),
            FlowEdge(from: 'a2', to: 'a3'),
            FlowEdge(from: 'a3', to: 'resp'),
          ],
          subgraphs: const [
            FlowSubgraph(
              id: 'mw',
              title: 'Middleware',
              nodeIds: ['a1', 'a2', 'a3'],
              direction: FlowDirection.lr,
            ),
          ],
        );

    test('LR subgraph members form a horizontal row inside a TB graph', () {
      final scene = layout(mixed());
      Rect b(String id) => groupBounds(groupById(scene, id));
      final r1 = b('a1'), r2 = b('a2'), r3 = b('a3');
      expect((r1.center.y - r2.center.y).abs(), lessThan(2));
      expect((r2.center.y - r3.center.y).abs(), lessThan(2));
      expect(r2.center.x, greaterThan(r1.center.x));
      expect(r3.center.x, greaterThan(r2.center.x));
      // Outer nodes remain vertically stacked.
      expect(b('resp').center.y, greaterThan(b('req').center.y));
      // Cluster rect contains all members.
      final cluster = groupBounds(groupById(scene, 'mw'));
      for (final r in [r1, r2, r3]) {
        expect(cluster.contains(r.center), isTrue);
      }
    });

    test('cross-boundary edge ends at the cluster border', () {
      final scene = layout(mixed());
      final edge = groupById(scene, 'edge_req_a1_0');
      final path = edge.children
          .whereType<SceneShape>()
          .firstWhere((s) => s.geometry is PathGeometry);
      final cmds = (path.geometry as PathGeometry).commands;
      final endPoint = switch (cmds.last) {
        LineTo(:final p) => p,
        CubicTo(:final p) => p,
        MoveTo(:final p) => p,
        _ => fail('unexpected trailing command'),
      };
      final cluster = groupBounds(groupById(scene, 'mw'));
      // Arrow tip sits the marker-shorten distance above the cluster top.
      expect((endPoint.y - cluster.top).abs(), lessThan(12),
          reason: 'edge should stop at the cluster boundary, '
              'got $endPoint vs cluster top ${cluster.top}');
      final a1 = groupBounds(groupById(scene, 'a1'));
      expect(endPoint.y, lessThan(a1.top),
          reason: 'edge must not reach into the member node');
    });

    test('nested isolated directions complete and nest correctly', () {
      final g = FlowGraph(
        direction: FlowDirection.tb,
        nodes: {for (final id in ['x', 'i1', 'i2', 'j1', 'j2']) id: node(id)},
        edges: const [
          FlowEdge(from: 'x', to: 'i1'),
          FlowEdge(from: 'i1', to: 'i2'),
          FlowEdge(from: 'j1', to: 'j2'),
        ],
        subgraphs: const [
          FlowSubgraph(
            id: 'outer',
            title: 'Outer',
            nodeIds: ['i1', 'i2'],
            direction: FlowDirection.lr,
          ),
          FlowSubgraph(
            id: 'inner',
            title: 'Inner',
            nodeIds: ['j1', 'j2'],
            direction: FlowDirection.tb,
            parentIndex: 0,
          ),
        ],
      );
      final scene = layout(g);
      final outer = groupBounds(groupById(scene, 'outer'));
      final inner = groupBounds(groupById(scene, 'inner'));
      for (final id in ['i1', 'i2']) {
        expect(outer.contains(groupBounds(groupById(scene, id)).center), isTrue);
      }
      for (final id in ['j1', 'j2']) {
        final c = groupBounds(groupById(scene, id)).center;
        expect(inner.contains(c), isTrue);
        expect(outer.contains(c), isTrue);
      }
      // Inner is TB again: j2 below j1.
      expect(groupBounds(groupById(scene, 'j2')).center.y,
          greaterThan(groupBounds(groupById(scene, 'j1')).center.y));
      // Outer is LR: i2 right of i1.
      expect(groupBounds(groupById(scene, 'i2')).center.x,
          greaterThan(groupBounds(groupById(scene, 'i1')).center.x));
    });
  });
}

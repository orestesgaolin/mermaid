/// Tests for self-loop edges and per-subgraph direction layout.
library;

import 'package:mermaid_core/src/diagrams/flowchart/flow_layout.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_model.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_parser.dart';
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

  group('edges targeting subgraph ids', () {
    FlowGraph clusterTarget({FlowDirection? sgDirection}) => FlowGraph(
          direction: FlowDirection.tb,
          nodes: {
            for (final id in ['x', 'm1', 'm2', 's']) id: node(id),
          },
          edges: const [
            FlowEdge(from: 'x', to: 's'),
            FlowEdge(from: 'm1', to: 'm2'),
          ],
          subgraphs: [
            FlowSubgraph(
              id: 's',
              title: 'Cluster',
              nodeIds: const ['m1', 'm2'],
              direction: sgDirection,
            ),
          ],
        );

    void expectStopsAtBorder(RenderScene scene) {
      final edge = groupById(scene, 'edge_x_s_0');
      final path = edge.children
          .whereType<SceneShape>()
          .firstWhere((s) => s.geometry is PathGeometry);
      final endPoint = switch ((path.geometry as PathGeometry).commands.last) {
        LineTo(:final p) => p,
        CubicTo(:final p) => p,
        MoveTo(:final p) => p,
        _ => fail('unexpected trailing command'),
      };
      final cluster = groupBounds(groupById(scene, 's'));
      expect((endPoint.y - cluster.top).abs(), lessThan(12),
          reason: 'arrow should stop at the cluster border, got $endPoint '
              'vs top ${cluster.top}');
      final m1 = groupBounds(groupById(scene, 'm1'));
      expect(endPoint.y, lessThan(m1.top));
      // The phantom node `s` must not be rendered as a standalone node:
      // every group named `s` is the cluster (contains the title text).
      final sGroups = flatten(scene.nodes)
          .map((e) => e.$2)
          .whereType<SceneGroup>()
          .where((g) => g.id == 's');
      for (final g in sGroups) {
        expect(
          flatten(g.children)
              .map((e) => e.$2)
              .whereType<SceneText>()
              .any((t) => t.text == 'Cluster'),
          isTrue,
          reason: 'group "s" should be the cluster, not a phantom node',
        );
      }
    }

    test('compound cluster endpoint clips at border', () {
      expectStopsAtBorder(layout(clusterTarget()));
    });

    test('isolated-direction cluster endpoint clips at border', () {
      expectStopsAtBorder(
          layout(clusterTarget(sgDirection: FlowDirection.lr)));
    });
  });

  group('edges entering sibling subgraphs', () {
    const source = '''
flowchart TB
  A0["Tela A"] --> A1["dialog de opcoes<br/>settings.name = null"] --> A2["dialog de loading<br/>settings.name = null"]
  A2 --> B1
  A2 --> C1
  subgraph SEM["SEM await — quebrado"]
    direction TB
    B1["push Tela B no topo"] --> B2["cb1 pop → remove Tela B"] --> B3["cb2 pop → remove loading"] --> B4["sobra o dialog de opcoes<br/>Tela B nunca aparece"]
  end
  subgraph COM["COM await — funciona por acidente"]
    direction TB
    C1["cb1 pop → remove loading"] --> C2["cb2 pop → remove dialog de opcoes"] --> C3["push Tela B sobre Tela A"] --> C4["Tela B visivel"]
  end
  B2 -.->|"rota com name null<br/>Logger de rotas grava<br/>'Rota nao encontrada'"| LOG["log: Rota nao encontrada"]
''';

    test('matches Mermaid sibling order', () {
      final scene = layout(parseFlowchart(source));
      final com = groupBounds(groupById(scene, 'COM'));
      final sem = groupBounds(groupById(scene, 'SEM'));
      expect(
        com.center.x,
        lessThan(sem.center.x),
      );
      expect(com.top, closeTo(sem.top, 0.001));

      final firstMember = groupBounds(groupById(scene, 'C1'));
      expect(firstMember.top - com.top, lessThan(30),
          reason: 'the visible cluster top should contain only its title band');
      final comTitle = groupById(scene, 'COM')
          .children
          .whereType<SceneText>()
          .single;
      expect(comTitle.bounds.height, lessThan(25),
          reason: 'the cluster title should remain on one line');
    });

    test('enters each visible cluster after a rounded bend', () {
      final scene = layout(parseFlowchart(source));

      void expectRoundedVerticalEntry(String edgeId, String clusterId) {
        final edge = groupById(scene, edgeId);
        final path = edge.children
            .whereType<SceneShape>()
            .map((shape) => shape.geometry)
            .whereType<PathGeometry>()
            .single;
        final cluster = groupBounds(groupById(scene, clusterId));

        Point? cursor;
        var hasRoundedBendAbove = false;
        var crossesVertically = false;
        for (final command in path.commands) {
          switch (command) {
            case MoveTo(:final p):
              cursor = p;
            case LineTo(:final p):
              final start = cursor!;
              if (start.y <= cluster.top && p.y >= cluster.top) {
                crossesVertically = (start.x - p.x).abs() < 0.001;
              }
              cursor = p;
            case CubicTo(:final c1, :final c2, :final p):
              final start = cursor!;
              final allVertical = [c1.x, c2.x, p.x]
                  .every((x) => (start.x - x).abs() < 0.001);
              if (p.y < cluster.top &&
                  !allVertical &&
                  (p.x - c2.x).abs() < 0.001) {
                hasRoundedBendAbove = true;
              }
              if (start.y <= cluster.top && p.y >= cluster.top) {
                crossesVertically = allVertical;
              }
              cursor = p;
            case QuadTo(:final p):
              cursor = p;
            case ClosePath():
              break;
          }
        }

        expect(hasRoundedBendAbove, isTrue,
            reason: '$edgeId should keep a rounded bend above $clusterId');
        expect(crossesVertically, isTrue,
            reason: '$edgeId should be vertical at the $clusterId border');
      }

      expectRoundedVerticalEntry('edge_A2_B1_2', 'SEM');
      expectRoundedVerticalEntry('edge_A2_C1_3', 'COM');
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

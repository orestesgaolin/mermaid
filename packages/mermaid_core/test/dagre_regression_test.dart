/// Regression tests for porting defects in the vendored dagre
/// (lib/src/vendor/dagre/). Each test reproduces a fixture-derived graph
/// shape that used to crash or hang the layout pipeline:
///
/// 1. position/bk.dart findType1Conflicts read absent `dummy` props with
///    Props.get (which throws) and dropped dagre.js's negation of the
///    inner-segment test — crashed on DAGs with parallel long edges
///    (fixtures 04/06).
/// 2. acyclic.dart dfsFAS's iterative DFS never tracked the on-path stack,
///    so cycles were never broken and ranking crashed on cyclic compound
///    graphs (fixtures 10/11).
/// 3. graph.dart inEdges returned null for nodes with no incoming edges,
///    making nodeEdges drop a source node's out-edges; feasibleTree could
///    then never grow past the nesting root, hanging forever on graphs
///    with several disconnected components (fixture 22).
library;

import 'package:mermaid_core/src/diagrams/flowchart/flow_layout.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_model.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

RenderScene layout(FlowGraph graph) =>
    layoutFlowchart(graph, measurer: measurer, theme: theme);

FlowNode node(String id) => FlowNode(id: id, label: 'Node $id');

void expectSaneScene(RenderScene scene) {
  expect(scene.size.width, greaterThan(0));
  expect(scene.size.height, greaterThan(0));
  expect(scene.size.width.isFinite, isTrue);
  expect(scene.size.height.isFinite, isTrue);
}

void main() {
  group('vendored dagre regressions', () {
    test('bug 1: LR fan-in DAG with rank-spanning edges (fixture 04 shrunk)',
        () {
      // Mirrors the shape of fixture 04: many sources fanning into a hub,
      // with edges that span multiple ranks. The long edges are split into
      // dummy-node chains by normalize, and the Brandes-Koepf type-1
      // conflict scan then mixes dummy and non-dummy predecessors, which
      // used to throw "Unsupported operation: not value" in bk.dart.
      final graph = FlowGraph(
        direction: FlowDirection.lr,
        nodes: {for (final id in ['A', 'B', 'C', 'D', 'E', 'F', 'G']) id: node(id)},
        edges: const [
          FlowEdge(from: 'A', to: 'B'),
          FlowEdge(from: 'B', to: 'C'),
          FlowEdge(from: 'C', to: 'D'),
          // Rank-spanning edges that produce dummy chains next to real nodes.
          FlowEdge(from: 'A', to: 'D'),
          FlowEdge(from: 'A', to: 'C'),
          // Extra sources fanning into the hub D.
          FlowEdge(from: 'E', to: 'D'),
          FlowEdge(from: 'F', to: 'D'),
          FlowEdge(from: 'G', to: 'D'),
          FlowEdge(from: 'E', to: 'B'),
        ],
      );
      expectSaneScene(layout(graph));
    });

    test('bug 2: cyclic compound graph with two subgraphs (fixture 10 shrunk)',
        () {
      // Mirrors fixture 10: two subgraphs plus loose nodes, with cycles
      // (E->A closes A->B->C->D->E; F->D closes D->E->F). The broken
      // iterative dfsFAS in acyclic.dart never reversed any edge, leaving
      // cycles that crashed longestPath with a null rank.
      final graph = FlowGraph(
        direction: FlowDirection.tb,
        nodes: {for (final id in ['A', 'B', 'C', 'D', 'E', 'F', 'G']) id: node(id)},
        edges: const [
          FlowEdge(from: 'A', to: 'B'),
          FlowEdge(from: 'B', to: 'C'),
          FlowEdge(from: 'C', to: 'D'),
          FlowEdge(from: 'B', to: 'D'),
          FlowEdge(from: 'D', to: 'E'),
          FlowEdge(from: 'E', to: 'A'),
          FlowEdge(from: 'E', to: 'F'),
          FlowEdge(from: 'F', to: 'D'),
          FlowEdge(from: 'F', to: 'G'),
          FlowEdge(from: 'B', to: 'G'),
          FlowEdge(from: 'G', to: 'D'),
        ],
        subgraphs: const [
          FlowSubgraph(id: 'foo', title: 'Foo SubGraph', nodeIds: ['C', 'D']),
          FlowSubgraph(id: 'bar', title: 'Bar SubGraph', nodeIds: ['E', 'F']),
        ],
      );
      expectSaneScene(layout(graph));
    });

    test(
        'bug 2b: compound subgraphs whose members have no edges at all '
        'lay out fine', () {
      // Edgeless subgraph members plus isolated roots: every node hangs off
      // the nesting root only, exercising the nesting-edge defaults.
      final graph = FlowGraph(
        direction: FlowDirection.tb,
        nodes: {for (final id in ['A', 'B', 'C', 'D', 'E', 'F', 'G']) id: node(id)},
        edges: const [],
        subgraphs: const [
          FlowSubgraph(id: 'foo', title: 'Foo', nodeIds: ['C', 'D']),
          FlowSubgraph(id: 'bar', title: 'Bar', nodeIds: ['E', 'F']),
        ],
      );
      expectSaneScene(layout(graph));
    });

    test(
        'bug 3: six disconnected labeled-edge pairs terminate '
        '(fixture 22 shape)', () {
      // Six disconnected 2-node components, every edge labeled (creating
      // edge-label dummy nodes), LR. The broken Graph.inEdges returned null
      // for the nesting root (no in-edges), so nodeEdges dropped its
      // out-edges and feasibleTree spun forever trying to bridge components.
      final nodes = <String, FlowNode>{};
      final edges = <FlowEdge>[];
      for (var i = 1; i <= 6; i++) {
        nodes['A$i'] = node('A$i');
        nodes['B$i'] = node('B$i');
        edges.add(FlowEdge(from: 'A$i', to: 'B$i', label: 'Multi Line'));
      }
      final graph =
          FlowGraph(direction: FlowDirection.lr, nodes: nodes, edges: edges);
      expectSaneScene(layout(graph));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

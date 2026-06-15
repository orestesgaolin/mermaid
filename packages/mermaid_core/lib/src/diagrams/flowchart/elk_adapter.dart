/// Adapter between the flowchart pipeline and the standalone `elk_layout`
/// package — the Dart counterpart of upstream `mermaid-layout-elk/render.ts`.
///
/// The flowchart layout already assembles a compound `dagre.DagreGraph` (nodes
/// with sizes + parent links, edges with `e$i` ids). This adapter converts
/// that graph into an [ElkGraph], runs the ELK layered algorithm, and exposes
/// the result in the same coordinate vocabulary the rest of `flow_layout`
/// consumes from dagre: node centers, cluster rects, and edge polylines —
/// keyed by the same ids. Downstream clipping, markers and scene-building are
/// then reused unchanged.
library;

import 'package:elk_layout/elk_layout.dart' as elk;

import '../../geometry.dart';
import '../../vendor/dagre/dart_dagre.dart' as dagre;
import 'flow_model.dart';

/// Result of an ELK layout, in flowchart coordinate space (absolute).
class ElkLayoutResult {
  ElkLayoutResult(this._nodes, this._edges, this.width, this.height);

  final Map<String, Rect> _nodes; // node/cluster id → absolute rect
  final Map<String, List<Point>> _edges; // edge id (e$i) → orthogonal polyline
  final double width;
  final double height;

  /// Absolute center of a node or cluster, or null if it was not laid out.
  Point? center(String id) => _nodes[id]?.center;

  /// Absolute rect of a node or cluster, or null.
  Rect? rect(String id) => _nodes[id];

  /// Orthogonal polyline for an edge id (e.g. `e3`), or null.
  List<Point>? edgePoints(String id) => _edges[id];
}

/// Runs the ELK layered layout over an already-built compound [g].
ElkLayoutResult layoutWithElk(
  dagre.DagreGraph g, {
  required FlowDirection direction,
  required elk.ElkLayoutOptions options,
}) {
  // Build the parent → children map from each node's `parent` link.
  final childrenOf = <String?, List<dagre.DagreNode>>{};
  for (final n in g.nodes) {
    (childrenOf[n.parent] ??= []).add(n);
  }
  final isCompound = {for (final n in g.nodes) n.id: childrenOf.containsKey(n.id)};

  elk.ElkNode toElkNode(dagre.DagreNode n) {
    final kids = childrenOf[n.id];
    if (isCompound[n.id] == true && kids != null) {
      return elk.ElkNode(id: n.id, children: kids.map(toElkNode).toList());
    }
    return elk.ElkNode(id: n.id, width: n.width, height: n.height);
  }

  final roots = childrenOf[null] ?? const <dagre.DagreNode>[];
  final edges = [
    for (final e in g.edges)
      elk.ElkEdge(id: e.id, sources: [e.source], targets: [e.target]),
  ];

  final elkGraph = elk.ElkGraph(
    layoutOptions: options.copyWith(direction: _direction(direction)),
    children: roots.map(toElkNode).toList(),
    edges: edges,
  );

  final result = const elk.ElkLayered().layout(elkGraph);

  // Absolute node/cluster rects.
  final nodes = <String, Rect>{};
  result.nodesById.forEach((id, n) {
    nodes[id] = Rect.fromLTWH(n.x, n.y, n.width, n.height);
  });

  // Edge polylines (already absolute, orthogonal).
  final edgePoints = <String, List<Point>>{};
  for (final e in result.edges) {
    if (e.sections.isEmpty) continue;
    edgePoints[e.id] = [
      for (final p in e.sections.first.points) Point(p.x, p.y),
    ];
  }

  return ElkLayoutResult(nodes, edgePoints, result.width, result.height);
}

elk.ElkDirection _direction(FlowDirection d) => switch (d) {
      FlowDirection.tb => elk.ElkDirection.down,
      FlowDirection.bt => elk.ElkDirection.up,
      FlowDirection.lr => elk.ElkDirection.right,
      FlowDirection.rl => elk.ElkDirection.left,
    };

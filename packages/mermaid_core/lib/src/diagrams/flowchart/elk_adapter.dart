/// Adapter between the flowchart pipeline and the standalone `elk`
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

import 'package:elk/elk.dart' as elk;

import '../../geometry.dart';
import '../../vendor/dagre/dart_dagre.dart' as dagre;
import 'flow_model.dart';

/// Result of an ELK layout, in flowchart coordinate space (absolute).
class ElkLayoutResult {
  ElkLayoutResult(
      this._nodes, this._edges, this._labels, this.width, this.height);

  final Map<String, Rect> _nodes; // node/cluster id → absolute rect
  final Map<String, List<Point>> _edges; // edge id (e$i) → orthogonal polyline
  final Map<String, Point> _labels; // edge id → ELK-placed label center
  final double width;
  final double height;

  /// Absolute center of a node or cluster, or null if it was not laid out.
  Point? center(String id) => _nodes[id]?.center;

  /// Absolute rect of a node or cluster, or null.
  Rect? rect(String id) => _nodes[id];

  /// Orthogonal polyline for an edge id (e.g. `e3`), or null.
  List<Point>? edgePoints(String id) => _edges[id];

  /// ELK-placed label center for an edge, or null (e.g. unlabeled, or a
  /// cross-hierarchy edge whose label isn't positioned yet — caller falls back
  /// to the path midpoint).
  Point? labelCenter(String id) => _labels[id];
}

/// Runs the ELK layered layout over an already-built compound [g].
ElkLayoutResult layoutWithElk(
  dagre.DagreGraph g, {
  required FlowDirection direction,
  required elk.ElkLayoutOptions options,
  Map<String, Size> clusterLabels = const {},
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
      // Pass the subgraph title as a node label so ELK reserves a top band for
      // it (matching upstream mermaid-layout-elk), keeping edges/children off
      // the title.
      final label = clusterLabels[n.id];
      return elk.ElkNode(
        id: n.id,
        children: kids.map(toElkNode).toList(),
        labels: label != null && label.height > 0
            ? [elk.ElkLabel(width: label.width, height: label.height)]
            : const [],
      );
    }
    return elk.ElkNode(id: n.id, width: n.width, height: n.height);
  }

  final roots = childrenOf[null] ?? const <dagre.DagreNode>[];
  // Pass each edge's label dimensions (the DagreEdge carries the measured label
  // size as width/height) so ELK reserves space for the label — inserting a
  // label dummy spreads the edges apart instead of letting their midpoint
  // labels pile up — and returns a placed position we use below.
  final edges = [
    for (final e in g.edges)
      elk.ElkEdge(
        id: e.id,
        sources: [e.source],
        targets: [e.target],
        labels: e.width > 0 && e.height > 0
            ? [elk.ElkLabel(width: e.width, height: e.height)]
            : const [],
      ),
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

  // Edge polylines (already absolute, orthogonal) + ELK-placed label centers.
  final edgePoints = <String, List<Point>>{};
  final labelCenters = <String, Point>{};
  for (final e in result.edges) {
    if (e.sections.isNotEmpty) {
      edgePoints[e.id] = [
        for (final p in e.sections.first.points) Point(p.x, p.y),
      ];
    }
    if (e.labels.isNotEmpty) {
      final l = e.labels.first;
      labelCenters[e.id] = Point(l.x + l.width / 2, l.y + l.height / 2);
    }
  }

  return ElkLayoutResult(
      nodes, edgePoints, labelCenters, result.width, result.height);
}

elk.ElkDirection _direction(FlowDirection d) => switch (d) {
      FlowDirection.tb => elk.ElkDirection.down,
      FlowDirection.bt => elk.ElkDirection.up,
      FlowDirection.lr => elk.ElkDirection.right,
      FlowDirection.rl => elk.ElkDirection.left,
    };

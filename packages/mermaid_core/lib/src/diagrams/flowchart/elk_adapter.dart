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

  // Fan-in ordering: when several edges enter the same node on the same border
  // they must attach in an order that lets their orthogonal feeds nest instead
  // of cross. ELK routes each segment independently, so two edges into one node
  // can swap lanes and cross right before entering. Re-assign their attach lanes
  // here (idempotent: an already-nested fan keeps its lanes).
  final targetOf = {for (final e in edges) e.id: e.targets.first};
  _orderFanIn(edgePoints, targetOf, nodes);

  return ElkLayoutResult(
      nodes, edgePoints, labelCenters, result.width, result.height);
}

/// Reorders the border-attach lanes of edges that enter the *same node* on the
/// *same side* coming from the *same lateral direction*, so their orthogonal
/// feeds nest without crossing. Only such groups are touched, and only their
/// final attach coordinate is moved (the perpendicular drop and its feed bend),
/// so node placement and every other edge are untouched. Already-correct fans
/// are left unchanged (the sort reproduces their lanes).
void _orderFanIn(
  Map<String, List<Point>> edgePoints,
  Map<String, String> targetOf,
  Map<String, Rect> nodes,
) {
  const eps = 1.0;
  // side: 0=top, 1=bottom, 2=left, 3=right.
  final groups = <String, List<String>>{};
  edgePoints.forEach((id, pts) {
    if (pts.length < 3) return;
    final tgt = targetOf[id];
    final r = tgt == null ? null : nodes[tgt];
    if (r == null) return;
    final p = pts.last;
    final onX = p.x > r.left - eps && p.x < r.right + eps;
    final onY = p.y > r.top - eps && p.y < r.bottom + eps;
    int? side;
    if ((p.y - r.top).abs() <= eps && onX) {
      side = 0;
    } else if ((p.y - r.bottom).abs() <= eps && onX) {
      side = 1;
    } else if ((p.x - r.left).abs() <= eps && onY) {
      side = 2;
    } else if ((p.x - r.right).abs() <= eps && onY) {
      side = 3;
    }
    if (side == null) return;
    (groups['$tgt:$side'] ??= []).add(id);
  });

  for (final entry in groups.entries) {
    final ids = entry.value;
    if (ids.length < 2) continue;
    final side = int.parse(entry.key.split(':').last);
    final vertical = side == 0 || side == 1; // drop is vertical → attach is x

    // (id, turn index, attach lane, approach line coord, lateral side).
    final infos = <(String, int, double, double, int)>[];
    int? commonLateral;
    var ok = true;
    for (final id in ids) {
      final pts = edgePoints[id]!;
      final n = pts.length;
      final attach = vertical ? pts[n - 1].x : pts[n - 1].y;
      // Walk back through the (possibly multi-point) perpendicular drop to the
      // turn where the parallel feed meets it.
      var t = n - 1;
      while (t - 1 >= 0 &&
          ((vertical ? pts[t - 1].x : pts[t - 1].y) - attach).abs() <= eps) {
        t--;
      }
      if (t - 1 < 0) { ok = false; break; } // no feed segment
      final turn = pts[t], feed = pts[t - 1];
      double approach;
      int lateral;
      if (vertical) {
        if ((feed.y - turn.y).abs() > eps) { ok = false; break; } // feed not ∥
        approach = turn.y;
        lateral = feed.x < turn.x ? -1 : 1; // -1: feed comes from the left
      } else {
        if ((feed.x - turn.x).abs() > eps) { ok = false; break; }
        approach = turn.x;
        lateral = feed.y < turn.y ? -1 : 1; // -1: feed comes from the top
      }
      commonLateral ??= lateral;
      if (lateral != commonLateral) { ok = false; break; }
      infos.add((id, t, attach, approach, lateral));
    }
    if (!ok || infos.length < 2) continue;

    final lanes = [for (final i in infos) i.$3]..sort();
    // Deepest = feed line closest to the border. top/left: larger coord;
    // bottom/right: smaller coord.
    int cmpDeep((String, int, double, double, int) a,
            (String, int, double, double, int) b) =>
        (side == 0 || side == 2) ? b.$4.compareTo(a.$4) : a.$4.compareTo(b.$4);
    final order = [...infos]..sort(cmpDeep); // deepest first
    // The deepest feed attaches to the lane nearest its lateral source side:
    // from-left (-1) → smallest coord first; from-right (1) → largest first.
    final laneOrder = commonLateral == -1 ? lanes : lanes.reversed.toList();
    for (var k = 0; k < order.length; k++) {
      final (id, t, _, _, _) = order[k];
      final pts = edgePoints[id]!;
      final lane = laneOrder[k];
      // Move the whole perpendicular drop (turn .. attach) onto the new lane.
      for (var j = t; j < pts.length; j++) {
        pts[j] = vertical ? Point(lane, pts[j].y) : Point(pts[j].x, lane);
      }
    }
  }
}

elk.ElkDirection _direction(FlowDirection d) => switch (d) {
      FlowDirection.tb => elk.ElkDirection.down,
      FlowDirection.bt => elk.ElkDirection.up,
      FlowDirection.lr => elk.ElkDirection.right,
      FlowDirection.rl => elk.ElkDirection.left,
    };

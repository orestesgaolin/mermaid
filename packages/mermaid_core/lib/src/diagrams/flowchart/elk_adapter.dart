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

import 'dart:math' as math;

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
/// [straightenEdges] applies [straightenEdgeTerminals] afterwards.
ElkLayoutResult layoutWithElk(
  dagre.DagreGraph g, {
  required FlowDirection direction,
  required elk.ElkLayoutOptions options,
  Map<String, Size> clusterLabels = const {},
  bool straightenEdges = true,
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

  if (straightenEdges) {
    final labelSizes = {
      for (final e in edges)
        if (e.labels.isNotEmpty)
          e.id: Size(e.labels.first.width, e.labels.first.height),
    };
    straightenEdgeTerminals(edgePoints, labelCenters, labelSizes);
  }

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

// Port of mermaid 12.3 `straightenEdgeTerminals` (elk/render.ts).
const double _terminalJogMax = 16;
const double _terminalRunMax = 30;
const double _jogEps = 0.01;

/// A shifted run of an edge, before and after.
typedef _Run = ({Point oldA, Point oldB, Point newA, Point newB});

/// Removes a jog of at most 16 px after an edge's first or before its last
/// segment (at most 30 px), unless that adds a crossing or puts a label over
/// an edge. A moved label follows the run.
void straightenEdgeTerminals(
  Map<String, List<Point>> edgePoints,
  Map<String, Point> labelCenters,
  Map<String, Size> labelSizes,
) {
  final ids = edgePoints.keys.toList();
  Rect? labelBox(String id, [Point? center]) {
    final c = center ?? labelCenters[id];
    final s = labelSizes[id];
    if (c == null || s == null || s.width <= 0 || s.height <= 0) return null;
    return Rect.fromLTWH(
      c.x - s.width / 2,
      c.y - s.height / 2,
      s.width,
      s.height,
    );
  }

  bool covers(List<Point> route, Rect? box) {
    if (box == null) return false;
    for (var i = 0; i < route.length - 1; i++) {
      if (_segmentHitsBox(route[i], route[i + 1], box)) return true;
    }
    return false;
  }

  for (final id in ids) {
    final original = edgePoints[id]!;
    final simplified = _dropStraightThroughPoints(original);
    if (simplified.length < 5) continue;
    final runs = <_Run>[];
    var candidate = simplified;
    final front = _straightenFront(candidate);
    if (front != null) {
      candidate = front.$1;
      runs.add(front.$2);
    }
    final back = _straightenFront(candidate.reversed.toList());
    if (back != null) {
      candidate = back.$1.reversed.toList();
      runs.add(back.$2);
    }
    if (runs.isEmpty) continue;

    final label = labelBox(id);
    final oldCenter = labelCenters[id];
    final moved = label == null || oldCenter == null
        ? null
        : _projectOntoRuns(oldCenter, runs);
    final candidateLabel = moved == null ? label : labelBox(id, moved);
    var before = 0, after = 0, coveredBefore = 0, coveredAfter = 0;
    for (final other in ids) {
      final route = edgePoints[other]!;
      if (other == id || route.length < 2) continue;
      before += _crossingCount(original, route);
      after += _crossingCount(candidate, route);
      final otherLabel = labelBox(other);
      if (covers(route, label)) coveredBefore++;
      if (covers(original, otherLabel)) coveredBefore++;
      if (covers(route, candidateLabel)) coveredAfter++;
      if (covers(candidate, otherLabel)) coveredAfter++;
    }
    if (after > before || coveredAfter > coveredBefore) continue;
    edgePoints[id] = candidate;
    if (moved != null) labelCenters[id] = moved;
  }
}

/// Drops repeated points and points a route passes straight through (the
/// Dart ELK splits routes at subgraph borders; elkjs returns only bends).
List<Point> _dropStraightThroughPoints(List<Point> pts) {
  final out = <Point>[];
  for (final p in pts) {
    if (out.isNotEmpty && out.last.distanceTo(p) <= _jogEps) continue;
    if (out.length >= 2) {
      final a = out[out.length - 2], b = out.last;
      final axis = _axisOf(a, b);
      final sameWay = axis == 'h'
          ? (b.x - a.x).sign == (p.x - b.x).sign
          : (b.y - a.y).sign == (p.y - b.y).sign;
      if (axis != null && _axisOf(b, p) == axis && sameWay) out.removeLast();
    }
    out.add(p);
  }
  return out;
}

/// `h` for a horizontal segment, `v` for a vertical one, null otherwise.
String? _axisOf(Point a, Point b) {
  final dx = (b.x - a.x).abs(), dy = (b.y - a.y).abs();
  if (dx > _jogEps && dy <= _jogEps) return 'h';
  if (dy > _jogEps && dx <= _jogEps) return 'v';
  return null;
}

(List<Point>, _Run)? _straightenFront(List<Point> pts) {
  if (pts.length < 5) return null;
  final [p0, p1, p2, p3, ...] = pts;
  final axis = _axisOf(p0, p1);
  final cross = axis == 'h' ? 'v' : 'h';
  if (axis == null || _axisOf(p2, p3) != axis || _axisOf(p1, p2) != cross) {
    return null;
  }
  if (p0.distanceTo(p1) > _terminalRunMax) return null;
  final horizontal = axis == 'h';
  final jog = horizontal ? (p2.y - p1.y).abs() : (p2.x - p1.x).abs();
  if (jog < _jogEps || jog > _terminalJogMax) return null;
  final forward = horizontal
      ? (p1.x - p0.x).sign == (p3.x - p2.x).sign
      : (p1.y - p0.y).sign == (p3.y - p2.y).sign;
  if (!forward) return null;
  var last = 3;
  while (last + 1 < pts.length && _axisOf(pts[last], pts[last + 1]) == axis) {
    last++;
  }
  if (last == pts.length - 1) return null;
  final moved = [...pts];
  for (var i = 2; i <= last; i++) {
    moved[i] = horizontal ? Point(pts[i].x, p0.y) : Point(p0.x, pts[i].y);
  }
  final run = (
    oldA: pts[2],
    oldB: pts[last],
    newA: moved[2],
    newB: moved[last],
  );
  moved.removeRange(1, 3);
  return (moved, run);
}

/// Moves [label] with the run nearest to it.
Point? _projectOntoRuns(Point label, List<_Run> runs) {
  Point? best;
  var bestDist = double.infinity;
  for (final run in runs) {
    final t = _paramOnSegment(label, run.oldA, run.oldB);
    final old = _pointAt(run.oldA, run.oldB, t);
    final d = old.distanceTo(label);
    if (d < bestDist) {
      bestDist = d;
      best = _pointAt(run.newA, run.newB, t);
    }
  }
  return best;
}

double _paramOnSegment(Point p, Point a, Point b) {
  final ab = b - a;
  final lenSq = ab.x * ab.x + ab.y * ab.y;
  if (lenSq == 0) return 0;
  final t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lenSq;
  return t.clamp(0.0, 1.0);
}

Point _pointAt(Point a, Point b, double t) =>
    Point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));

/// Whether segment [a]–[b] passes through [box] (Liang–Barsky).
bool _segmentHitsBox(Point a, Point b, Rect box) {
  var t0 = 0.0, t1 = 1.0;
  final dx = b.x - a.x, dy = b.y - a.y;
  for (final (p, q) in [
    (-dx, a.x - box.left),
    (dx, box.right - a.x),
    (-dy, a.y - box.top),
    (dy, box.bottom - a.y),
  ]) {
    if (p == 0) {
      if (q < 0) return false;
    } else if (p < 0) {
      t0 = math.max(t0, q / p);
    } else {
      t1 = math.min(t1, q / p);
    }
  }
  return t0 < t1;
}

/// Number of proper crossings between the segments of two polylines.
int _crossingCount(List<Point> a, List<Point> b) {
  double side(Point o, Point p, Point q) =>
      (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x);
  var n = 0;
  for (var i = 0; i < a.length - 1; i++) {
    for (var j = 0; j < b.length - 1; j++) {
      final d1 = side(b[j], b[j + 1], a[i]);
      final d2 = side(b[j], b[j + 1], a[i + 1]);
      final d3 = side(a[i], a[i + 1], b[j]);
      final d4 = side(a[i], a[i + 1], b[j + 1]);
      if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
          ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
        n++;
      }
    }
  }
  return n;
}

elk.ElkDirection _direction(FlowDirection d) => switch (d) {
      FlowDirection.tb => elk.ElkDirection.down,
      FlowDirection.bt => elk.ElkDirection.up,
      FlowDirection.lr => elk.ElkDirection.right,
      FlowDirection.rl => elk.ElkDirection.left,
    };

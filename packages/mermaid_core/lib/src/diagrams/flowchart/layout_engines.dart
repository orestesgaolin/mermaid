/// Alternate layout engines for graph diagrams, selected by `layout:` config.
///
/// - **tidy-tree**: a Reingold–Tilford / Walker tidy tree over a BFS spanning
///   forest of the graph. Produces node center positions; edges are routed as
///   straight segments by the caller.
/// - **elk**: keeps the (layered) dagre placement but routes edges as
///   orthogonal Manhattan paths, the characteristic ELK look.
///
/// Both are pure-geometry helpers operating on already-measured node sizes, so
/// they slot into the existing flowchart pipeline without a dagre dependency.
library;

import '../../geometry.dart';

/// Direction the tree grows.
enum TreeFlow { topBottom, bottomTop, leftRight, rightLeft }

class _TreeNode {
  _TreeNode(this.id, this.width, this.height);
  final String id;
  final double width;
  final double height;
  final children = <_TreeNode>[];
  _TreeNode? parent;
  double x = 0; // along the sibling axis
  double depth = 0; // along the growth axis (in pixels)
}

/// Computes tidy-tree center positions for [ids] given their sizes and the
/// directed [edges]. Roots are nodes with no incoming edge (or the first node
/// of each otherwise-cyclic component). Returns id → center.
Map<String, Point> tidyTreeLayout(
  List<String> ids,
  Map<String, Size> sizes,
  List<(String, String)> edges, {
  required TreeFlow flow,
  double siblingGap = 30,
  double levelGap = 60,
}) {
  final nodes = {for (final id in ids) id: _TreeNode(id, sizes[id]!.width, sizes[id]!.height)};
  final indeg = {for (final id in ids) id: 0};
  final childrenOf = {for (final id in ids) id: <String>[]};
  final seen = <String>{};
  for (final (a, b) in edges) {
    if (!nodes.containsKey(a) || !nodes.containsKey(b)) continue;
    // Build a tree: skip edges that would create a second parent / a cycle.
    if (seen.contains(b)) continue;
    if (a == b) continue;
    childrenOf[a]!.add(b);
    indeg[b] = indeg[b]! + 1;
    seen.add(b);
  }
  // Roots: no incoming tree edge.
  final roots = [for (final id in ids) if (indeg[id] == 0) id];
  if (roots.isEmpty && ids.isNotEmpty) roots.add(ids.first);

  // Wire up the _TreeNode children in declaration order.
  for (final id in ids) {
    for (final c in childrenOf[id]!) {
      nodes[c]!.parent = nodes[id];
      nodes[id]!.children.add(nodes[c]!);
    }
  }

  final vertical = flow == TreeFlow.topBottom || flow == TreeFlow.bottomTop;
  // Size along the sibling axis (the axis nodes spread along at one level).
  double sibSize(_TreeNode n) => vertical ? n.width : n.height;
  double lvlSize(_TreeNode n) => vertical ? n.height : n.width;

  // Resolve absolute positions: leaves consume the sibling axis left-to-right;
  // each parent centers over its children (a tidy, non-overlapping tree).
  var cursorAlongSibling = 0.0;
  final placed = <String, Point>{};
  // Guards against cyclic wiring (e.g. a 2-node cycle with no acyclic entry,
  // where seen-tracking can still make A and B each other's child) recursing
  // forever — a node is positioned once.
  final visited = <_TreeNode>{};
  // Track the running depth (level) position.
  void assign(_TreeNode n, double depthPx, double offset) {
    if (!visited.add(n)) return;
    n.depth = depthPx;
    if (n.children.isEmpty) {
      n.x = cursorAlongSibling + sibSize(n) / 2;
      cursorAlongSibling += sibSize(n) + siblingGap;
    } else {
      for (final c in n.children) {
        assign(c, depthPx + lvlSize(n) / 2 + levelGap + lvlSize(c) / 2, offset);
      }
      n.x = (n.children.first.x + n.children.last.x) / 2;
    }
  }

  var depthStart = 0.0;
  for (final root in roots) {
    final r = nodes[root]!;
    assign(r, depthStart + lvlSize(r) / 2, 0);
    // Advance so the next root component sits below/right of this one.
    depthStart = 0; // components share the top; separated along sibling axis
  }

  // Map (x along sibling axis, depth along growth axis) → screen Point.
  for (final n in nodes.values) {
    final sib = n.x;
    final lvl = n.depth;
    final p = switch (flow) {
      TreeFlow.topBottom => Point(sib, lvl),
      TreeFlow.bottomTop => Point(sib, -lvl),
      TreeFlow.leftRight => Point(lvl, sib),
      TreeFlow.rightLeft => Point(-lvl, sib),
    };
    placed[n.id] = p;
  }
  return placed;
}

/// Orthogonal (Manhattan) route between two node-boundary points, given the
/// flow direction. Produces an L- or Z-shaped path.
List<Point> orthogonalRoute(Point from, Point to, {required bool vertical}) {
  if ((from.x - to.x).abs() < 0.5 || (from.y - to.y).abs() < 0.5) {
    return [from, to];
  }
  if (vertical) {
    final midY = (from.y + to.y) / 2;
    return [from, Point(from.x, midY), Point(to.x, midY), to];
  } else {
    final midX = (from.x + to.x) / 2;
    return [from, Point(midX, from.y), Point(midX, to.y), to];
  }
}

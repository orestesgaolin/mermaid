/// The output of a layout run, mirroring the elkjs result shape: nodes gain
/// `x`/`y` (top-left, parent-relative) and edges gain `sections` with
/// `startPoint`, `bendPoints` and `endPoint`.
library;

/// A 2D point.
class ElkPoint {
  const ElkPoint(this.x, this.y);
  final double x;
  final double y;

  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// One routed section of an edge: a polyline from [startPoint] through the
/// [bendPoints] to [endPoint]. For the `layered` algorithm an edge has a
/// single section.
class ElkEdgeSection {
  const ElkEdgeSection({
    required this.startPoint,
    required this.endPoint,
    this.bendPoints = const [],
  });

  final ElkPoint startPoint;
  final ElkPoint endPoint;
  final List<ElkPoint> bendPoints;

  /// The full polyline: start, bends, end.
  List<ElkPoint> get points => [startPoint, ...bendPoints, endPoint];
}

/// A positioned label. [x]/[y] are the top-left, parent-relative.
class ElkPositionedLabel {
  const ElkPositionedLabel({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;
}

/// A port after layout. [x]/[y] are the top-left corner relative to the owning
/// node's origin (so the port's absolute position is the node's plus this).
class ElkPositionedPort {
  const ElkPositionedPort({
    required this.id,
    required this.x,
    required this.y,
    this.width = 0,
    this.height = 0,
  });
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
}

/// A node after layout. [x]/[y] are the top-left corner **relative to the
/// parent node's content origin** (elkjs convention); [children] are nested.
class ElkPositionedNode {
  const ElkPositionedNode({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.children = const [],
    this.labels = const [],
    this.ports = const [],
  });

  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final List<ElkPositionedNode> children;
  final List<ElkPositionedLabel> labels;
  final List<ElkPositionedPort> ports;
}

/// An edge after layout.
class ElkPositionedEdge {
  const ElkPositionedEdge({
    required this.id,
    required this.sections,
    this.labels = const [],
  });
  final String id;
  final List<ElkEdgeSection> sections;
  final List<ElkPositionedLabel> labels;
}

/// The full layout result. [width]/[height] are the root graph's computed
/// bounds; [children] and [edges] carry the positioned graph.
class ElkResult {
  const ElkResult({
    required this.width,
    required this.height,
    required this.children,
    required this.edges,
  });

  final double width;
  final double height;
  final List<ElkPositionedNode> children;
  final List<ElkPositionedEdge> edges;

  /// Flattened map of every positioned node by id, with **absolute** x/y
  /// (parent offsets accumulated). Convenient for consumers that work in a
  /// single coordinate space (e.g. the mermaid adapter).
  Map<String, ElkPositionedNode> get nodesById {
    final out = <String, ElkPositionedNode>{};
    void walk(List<ElkPositionedNode> nodes, double dx, double dy) {
      for (final n in nodes) {
        final ax = n.x + dx, ay = n.y + dy;
        out[n.id] = ElkPositionedNode(
          id: n.id,
          x: ax,
          y: ay,
          width: n.width,
          height: n.height,
          children: n.children,
          labels: n.labels,
          ports: n.ports,
        );
        if (n.children.isNotEmpty) walk(n.children, ax, ay);
      }
    }

    walk(children, 0, 0);
    return out;
  }
}

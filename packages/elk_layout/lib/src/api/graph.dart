/// The input graph model, mirroring the elkjs graph JSON. A graph is a root
/// node with [children] (which may themselves contain children — that nesting
/// is what makes a node *compound*/a cluster) and [edges] between them.
library;

import 'options.dart';

/// A label attached to a node or edge. Only its measured size matters to the
/// layout; [text] is carried through for the caller's convenience.
class ElkLabel {
  const ElkLabel({this.text = '', this.width = 0, this.height = 0});

  factory ElkLabel.fromJson(Map<String, dynamic> m) => ElkLabel(
        text: (m['text'] ?? '').toString(),
        width: (m['width'] as num?)?.toDouble() ?? 0,
        height: (m['height'] as num?)?.toDouble() ?? 0,
      );

  final String text;
  final double width;
  final double height;
}

/// Which border of its node a port sits on. When null, the engine infers it
/// from the flow direction and whether the port is used as an edge source
/// (outgoing side) or target (incoming side).
enum ElkPortSide { north, south, east, west }

/// An explicit edge attachment point on a node's border. Edges whose
/// `sources`/`targets` name a port id attach exactly at that port (distributed
/// along the [side], ordered to reduce crossings). When a node declares no
/// ports, edges attach to computed node sides instead.
class ElkPort {
  const ElkPort({required this.id, this.side, this.width = 0, this.height = 0});

  factory ElkPort.fromJson(Map<String, dynamic> m) {
    ElkPortSide? side;
    final s = (m['layoutOptions'] as Map?)?['port.side'] ?? m['side'];
    if (s != null) {
      side = switch ('$s'.toUpperCase()) {
        'NORTH' => ElkPortSide.north,
        'SOUTH' => ElkPortSide.south,
        'EAST' => ElkPortSide.east,
        'WEST' => ElkPortSide.west,
        _ => null,
      };
    }
    return ElkPort(
      id: m['id'].toString(),
      side: side,
      width: (m['width'] as num?)?.toDouble() ?? 0,
      height: (m['height'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final ElkPortSide? side;
  final double width;
  final double height;
}

/// A node. A leaf node carries [width]/[height]; a node with [children] is a
/// compound node (cluster) whose size is computed by the layout.
class ElkNode {
  const ElkNode({
    required this.id,
    this.width = 0,
    this.height = 0,
    this.children = const [],
    this.edges = const [],
    this.labels = const [],
    this.ports = const [],
    this.layoutOptions,
  });

  factory ElkNode.fromJson(Map<String, dynamic> m) {
    double num0(Object? v) => v is num ? v.toDouble() : 0;
    return ElkNode(
      id: m['id'].toString(),
      width: num0(m['width']),
      height: num0(m['height']),
      children: _nodeList(m['children']),
      edges: _edgeList(m['edges']),
      labels: [
        if (m['labels'] is List)
          for (final l in m['labels'] as List)
            if (l is Map) ElkLabel.fromJson(l.cast<String, dynamic>()),
      ],
      ports: [
        if (m['ports'] is List)
          for (final p in m['ports'] as List)
            if (p is Map) ElkPort.fromJson(p.cast<String, dynamic>()),
      ],
    );
  }

  final String id;
  final double width;
  final double height;
  final List<ElkNode> children;

  /// Edges whose scope is this node (elkjs allows edges nested in a node).
  /// Most callers put all edges on the root [ElkGraph.edges] instead.
  final List<ElkEdge> edges;

  final List<ElkLabel> labels;
  final List<ElkPort> ports;

  /// Per-node option overrides (e.g. a subgraph with its own [ElkDirection]).
  final ElkLayoutOptions? layoutOptions;

  bool get isCompound => children.isNotEmpty;
}

/// A directed edge from each id in [sources] to each id in [targets]. For
/// simple graphs both lists hold a single id (mirroring elkjs, which models
/// hyperedges as multi-source/target).
class ElkEdge {
  const ElkEdge({
    required this.id,
    required this.sources,
    required this.targets,
    this.labels = const [],
  });

  factory ElkEdge.fromJson(Map<String, dynamic> m) => ElkEdge(
        id: (m['id'] ?? '').toString(),
        sources: [for (final s in (m['sources'] as List? ?? const [])) '$s'],
        targets: [for (final t in (m['targets'] as List? ?? const [])) '$t'],
        labels: [
          if (m['labels'] is List)
            for (final l in m['labels'] as List)
              if (l is Map) ElkLabel.fromJson(l.cast<String, dynamic>()),
        ],
      );

  final String id;
  final List<String> sources;
  final List<String> targets;
  final List<ElkLabel> labels;

  String get source => sources.first;
  String get target => targets.first;
}

/// The root of an input graph.
class ElkGraph {
  const ElkGraph({
    this.id = 'root',
    this.layoutOptions = const ElkLayoutOptions(),
    this.children = const [],
    this.edges = const [],
  });

  /// Parses an elkjs-style graph JSON object (the shape elkjs accepts and
  /// returns): `{id, layoutOptions, children: [...], edges: [...]}`.
  factory ElkGraph.fromJson(Map<String, dynamic> m) {
    return ElkGraph(
      id: (m['id'] ?? 'root').toString(),
      layoutOptions: ElkLayoutOptions.fromElkJson(
          (m['layoutOptions'] as Map?)?.cast<String, dynamic>() ?? const {}),
      children: _nodeList(m['children']),
      edges: _edgeList(m['edges']),
    );
  }

  final String id;
  final ElkLayoutOptions layoutOptions;
  final List<ElkNode> children;
  final List<ElkEdge> edges;
}

List<ElkNode> _nodeList(Object? v) => [
      if (v is List)
        for (final n in v)
          if (n is Map) ElkNode.fromJson(n.cast<String, dynamic>()),
    ];

List<ElkEdge> _edgeList(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is Map) ElkEdge.fromJson(e.cast<String, dynamic>()),
    ];

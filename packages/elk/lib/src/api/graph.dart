/// The input graph model, mirroring the elkjs graph JSON. A graph is a root
/// node with [children] (which may themselves contain children — that nesting
/// is what makes a node *compound*/a cluster) and [edges] between them.
library;

import 'options.dart';

/// Position of an edge label along its directed route.
enum ElkEdgeLabelPlacement { center, head, tail }

/// Side of the edge in its internal flow coordinate system.
enum ElkLabelSide { above, below }

/// Measured label content. Edge placement and side follow elkjs label options.
class ElkLabel {
  const ElkLabel({
    this.text = '',
    this.width = 0,
    this.height = 0,
    this.placement = ElkEdgeLabelPlacement.center,
    this.side = ElkLabelSide.above,
  });

  factory ElkLabel.fromJson(Map<String, dynamic> m) {
    final options = (m['layoutOptions'] as Map?) ?? const {};
    Object? option(String key) => options['elk.$key'] ?? options[key];
    return ElkLabel(
      text: (m['text'] ?? '').toString(),
      width: (m['width'] as num?)?.toDouble() ?? 0,
      height: (m['height'] as num?)?.toDouble() ?? 0,
      placement: switch ('${option('edgeLabels.placement')}'.toUpperCase()) {
        'HEAD' => ElkEdgeLabelPlacement.head,
        'TAIL' => ElkEdgeLabelPlacement.tail,
        _ => ElkEdgeLabelPlacement.center,
      },
      side:
          '${option('layered.edgeLabels.sideSelection')}'.toUpperCase() ==
              'ALWAYS_DOWN'
          ? ElkLabelSide.below
          : ElkLabelSide.above,
    );
  }

  final String text;
  final double width;
  final double height;
  final ElkEdgeLabelPlacement placement;
  final ElkLabelSide side;
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
  const ElkPort({
    required this.id,
    this.side,
    this.width = 0,
    this.height = 0,
    this.labels = const [],
  });

  factory ElkPort.fromJson(Map<String, dynamic> m) {
    ElkPortSide? side;
    final s =
        (m['layoutOptions'] as Map?)?['elk.port.side'] ??
        (m['layoutOptions'] as Map?)?['port.side'] ??
        m['side'];
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
      labels: [
        for (final l in (m['labels'] as List? ?? const []))
          if (l is Map) ElkLabel.fromJson(l.cast<String, dynamic>()),
      ],
    );
  }

  final String id;
  final ElkPortSide? side;
  final double width;
  final double height;
  final List<ElkLabel> labels;
}

enum ElkNodeLabelPlacement { topLeft, topCenter, center, bottomCenter }

/// A node. A leaf node carries [width]/[height]; a node with [children] is a
/// compound node (cluster) whose size is computed by the layout.
class ElkNode {
  const ElkNode({
    required this.id,
    this.x,
    this.y,
    this.width = 0,
    this.height = 0,
    this.children = const [],
    this.edges = const [],
    this.labels = const [],
    this.ports = const [],
    this.layoutOptions,
    this.fixedSize = true,
    this.sizeForLabels = false,
    this.sizeForPorts = false,
    this.preserveMinimumSize = true,
    this.labelPlacement,
    this.inLayerSuccessors = const [],
    this.barycenterAssociates = const [],
  });

  factory ElkNode.fromJson(Map<String, dynamic> m) {
    double num0(Object? v) => v is num ? v.toDouble() : 0;
    return ElkNode(
      id: m['id'].toString(),
      x: (m['x'] as num?)?.toDouble(),
      y: (m['y'] as num?)?.toDouble(),
      layoutOptions: switch (m['layoutOptions']) {
        final Map options
            when options.containsKey('org.eclipse.elk.direction') ||
                options.containsKey('elk.direction') ||
                options.containsKey('direction') ||
                options.containsKey('org.eclipse.elk.hierarchyHandling') ||
                options.containsKey('elk.hierarchyHandling') ||
                options.containsKey('hierarchyHandling') =>
          ElkLayoutOptions.fromElkJson(options.cast<String, dynamic>()),
        _ => null,
      },
      labelPlacement:
          switch ('${(m['layoutOptions'] as Map?)?['elk.nodeLabels.placement'] ?? (m['layoutOptions'] as Map?)?['nodeLabels.placement'] ?? ''}') {
            final value when value.contains('V_CENTER') =>
              ElkNodeLabelPlacement.center,
            final value when value.contains('V_BOTTOM') =>
              ElkNodeLabelPlacement.bottomCenter,
            final value when value.contains('H_CENTER') =>
              ElkNodeLabelPlacement.topCenter,
            _ => null,
          },
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
      fixedSize: !_sizeConstraints(m).$1 && !_sizeConstraints(m).$2,
      sizeForLabels: _sizeConstraints(m).$1,
      sizeForPorts: _sizeConstraints(m).$2,
      preserveMinimumSize: _sizeConstraints(m).$3,
    );
  }

  final String id;

  /// Optional position from a previous layout. The interactive cycle-breaking
  /// strategy uses this drawing order before computing the new layout.
  final double? x;
  final double? y;
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

  /// Keeps the declared width and height unchanged. Set false to enable
  /// content-derived sizing; [sizeForLabels] and [sizeForPorts] select inputs.
  final bool fixedSize;

  /// Includes node-label bounds when computing a non-fixed node's size.
  final bool sizeForLabels;

  /// Includes each side's port group when computing a non-fixed node's size.
  final bool sizeForPorts;

  /// Treats the declared width and height as minima during content sizing.
  final bool preserveMinimumSize;
  final ElkNodeLabelPlacement? labelPlacement;

  /// Node IDs that must follow this node in the same layer. This is a Dart API
  /// reference and is not parsed from ELK JSON layout options.
  final List<String> inLayerSuccessors;

  /// Same-layer node IDs whose edge weights contribute to this node's
  /// barycenter. This is a Dart API reference, not an ELK JSON option.
  final List<String> barycenterAssociates;

  bool get isCompound => children.isNotEmpty;
}

(bool, bool, bool) _sizeConstraints(Map<String, dynamic> node) {
  final value =
      '${((node['layoutOptions'] as Map?) ?? const {})['elk.nodeSize.constraints'] ?? ''}'
          .toUpperCase();
  return (
    value.contains('NODE_LABELS'),
    value.contains('PORTS'),
    value.contains('MINIMUM_SIZE'),
  );
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
    this.thickness = 1,
  });

  factory ElkEdge.fromJson(Map<String, dynamic> m) => ElkEdge(
    id: (m['id'] ?? '').toString(),
    sources: [for (final s in (m['sources'] as List? ?? const [])) '$s'],
    targets: [for (final t in (m['targets'] as List? ?? const [])) '$t'],
    thickness:
        ((m['layoutOptions'] as Map?)?['elk.edge.thickness'] as num?)
            ?.toDouble() ??
        1,
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
  final double thickness;

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
        (m['layoutOptions'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
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

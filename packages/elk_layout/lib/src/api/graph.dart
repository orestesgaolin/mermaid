/// The input graph model, mirroring the elkjs graph JSON. A graph is a root
/// node with [children] (which may themselves contain children — that nesting
/// is what makes a node *compound*/a cluster) and [edges] between them.
library;

import 'options.dart';

/// A label attached to a node or edge. Only its measured size matters to the
/// layout; [text] is carried through for the caller's convenience.
class ElkLabel {
  const ElkLabel({this.text = '', this.width = 0, this.height = 0});
  final String text;
  final double width;
  final double height;
}

/// An explicit edge attachment point on a node's border. Optional — when a
/// node declares no ports, edges attach to computed sides.
class ElkPort {
  const ElkPort({required this.id, this.width = 0, this.height = 0});
  final String id;
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

  final String id;
  final ElkLayoutOptions layoutOptions;
  final List<ElkNode> children;
  final List<ElkEdge> edges;
}

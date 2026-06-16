/// Faithful port of ELK's layered graph data model
/// (`org.eclipse.elk.alg.layered.graph`): `LGraph`, `LNode`, `LPort`, `LEdge`,
/// `LLabel`, `Layer`, plus the `KVector` geometry and the `NodeType` /
/// `PortSide` / `PortType` enums. The phases (cycle breaking → layering →
/// crossing minimization → node placement → edge routing) operate on this
/// mutable model exactly as the Java does.
library;

import 'property.dart';

/// Mutable 2D vector — ELK's `KVector` (positions/sizes are mutated in place by
/// the phases, so this is intentionally mutable, unlike the package's immutable
/// `Point`).
class KVector {
  KVector([this.x = 0, this.y = 0]);
  double x;
  double y;

  KVector clone() => KVector(x, y);
  void reset() {
    x = 0;
    y = 0;
  }

  KVector add(KVector o) {
    x += o.x;
    y += o.y;
    return this;
  }

  @override
  String toString() => '($x, $y)';
}

/// An ordered chain of bend points — ELK's `KVectorChain`.
class KVectorChain {
  final List<KVector> points = [];
  void add(KVector p) => points.add(p);
  void addAll(Iterable<KVector> ps) => points.addAll(ps);
  void clear() => points.clear();
  bool get isEmpty => points.isEmpty;
  int get length => points.length;
}

/// Insets (margins/padding) — ELK's `LMargin` / `LPadding` (a `Spacing`).
class LInsets {
  LInsets([this.top = 0, this.right = 0, this.bottom = 0, this.left = 0]);
  double top, right, bottom, left;
}

/// The kind of an [LNode]. Dummy types are inserted by the algorithm; only
/// `normal` nodes correspond to real input nodes.
enum NodeType {
  normal,
  longEdge,
  externalPort,
  northSouthPort,
  label,
  breakingPoint,
}

/// The border a port is attached to.
enum PortSide { undefined, north, east, south, west }

/// Whether a port takes incoming edges, outgoing edges, or both.
enum PortType { undefined, input, output }

/// Base of every element in the layered graph: a stable [id] slot plus the
/// typed property store.
abstract class LGraphElement with MapPropertyHolder {
  int id = 0;
}

/// A positioned, sized element (`LShape`): nodes, ports and labels.
abstract class LShape extends LGraphElement {
  final KVector position = KVector();
  final KVector size = KVector();
}

/// A node — real (`NodeType.normal`) or a dummy inserted by the algorithm.
class LNode extends LShape {
  LNode(this.graph);

  LGraph graph;
  Layer? layer;
  NodeType type = NodeType.normal;
  final List<LPort> ports = [];
  final List<LLabel> labels = [];
  final LInsets margin = LInsets();
  final LInsets padding = LInsets();

  /// A compound node's contents (null for leaves).
  LGraph? nestedGraph;

  /// Original input id, for mapping the result back out (port carries its own).
  String? identifier;

  Iterable<LEdge> get incomingEdges =>
      ports.expand((p) => p.incomingEdges);
  Iterable<LEdge> get outgoingEdges =>
      ports.expand((p) => p.outgoingEdges);
  Iterable<LEdge> get connectedEdges => [...incomingEdges, ...outgoingEdges];

  /// The index of this node within its layer (-1 if layerless).
  int get index => layer?.nodes.indexOf(this) ?? -1;

  @override
  String toString() => 'LNode(${identifier ?? "n$id"}, $type)';
}

/// An attachment point on a node border — ELK's `LPort`.
class LPort extends LShape {
  LPort(this.node);

  LNode node;
  PortSide side = PortSide.undefined;

  /// Offset of the edge anchor from the port's top-left.
  final KVector anchor = KVector();
  final LInsets margin = LInsets();
  final List<LLabel> labels = [];
  final List<LEdge> incomingEdges = [];
  final List<LEdge> outgoingEdges = [];

  String? identifier;

  Iterable<LEdge> get connectedEdges => [...incomingEdges, ...outgoingEdges];
  int get degree => incomingEdges.length + outgoingEdges.length;

  /// ELK `LPort.getNetFlow()`: incoming − outgoing (so an output-dominated
  /// port has net flow < 0 → EAST side in the internal rightward flow).
  int get netFlow => incomingEdges.length - outgoingEdges.length;

  /// Absolute anchor position = node.position + port.position + anchor.
  KVector get absoluteAnchor => KVector(
        node.position.x + position.x + anchor.x,
        node.position.y + position.y + anchor.y,
      );
}

/// A directed edge between two ports — ELK's `LEdge`.
class LEdge extends LGraphElement {
  LPort? _source;
  LPort? _target;
  final KVectorChain bendPoints = KVectorChain();
  final List<LLabel> labels = [];
  String? identifier;

  /// True if the algorithm reversed this edge during cycle breaking (its
  /// points are flipped back when restored).
  bool reversed = false;

  LPort? get source => _source;
  LPort? get target => _target;

  set source(LPort? p) {
    _source?.outgoingEdges.remove(this);
    _source = p;
    p?.outgoingEdges.add(this);
  }

  set target(LPort? p) {
    _target?.incomingEdges.remove(this);
    _target = p;
    p?.incomingEdges.add(this);
  }

  bool get isSelfLoop => _source?.node != null && _source?.node == _target?.node;
  bool get isInLayerEdge =>
      !isSelfLoop && _source?.node.layer == _target?.node.layer;

  /// Swaps source and target, marking the edge reversed.
  void reverse() {
    final s = _source, t = _target;
    source = null;
    target = null;
    source = t;
    target = s;
    reversed = !reversed;
  }
}

/// A label on a node, port or edge.
class LLabel extends LShape {
  LLabel([this.text = '']);
  String text;
}

/// One layer (a column for LEFT/RIGHT flow, a row for UP/DOWN) of nodes.
class Layer extends LGraphElement {
  Layer(this.owner);
  LGraph owner;
  final KVector size = KVector();
  final List<LNode> nodes = [];

  int get index => owner.layers.indexOf(this);
}

/// The layered graph: layerless nodes (before layering), the ordered [layers]
/// (after), plus size/offset/padding and an optional [parentNode] for
/// hierarchy.
class LGraph extends LGraphElement {
  final KVector size = KVector();
  final KVector offset = KVector();
  final LInsets padding = LInsets();
  final List<LNode> layerlessNodes = [];
  final List<Layer> layers = [];
  LNode? parentNode;
}

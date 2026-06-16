/// Faithful port of three ELK layered intermediate processors that handle
/// port-side assignment, port-list ordering, and inverted-port dummy
/// insertion.
///
/// Sources (MIT-compatible EPL-2.0):
///   - `intermediate/PortSideProcessor.java`
///   - `intermediate/PortListSorter.java`
///   - `intermediate/InvertedPortProcessor.java`
library;

import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// Property constants (mirrors of ELK InternalProperties / LayeredOptions
// subsets needed by this file only).
// ---------------------------------------------------------------------------

/// Per-node port constraints.  Default: FREE (no constraint).
/// Mirrors `LayeredOptions.PORT_CONSTRAINTS` / `CoreOptions.PORT_CONSTRAINTS`.
const portConstraints =
    Property<PortConstraints>('portConstraints', PortConstraints.free);

/// Per-port explicit sort index used when portConstraints == FIXED_ORDER.
/// Mirrors `LayeredOptions.PORT_INDEX`.
const portIndex = Property<int?>('portIndex', null);

/// Port-sorting strategy used during FIXED_SIDE ordering.
/// Default: INPUT_ORDER (preserve input order; don't reorder by degree).
/// Mirrors `LayeredOptions.PORT_SORTING_STRATEGY`.
const portSortingStrategy = Property<PortSortingStrategy>(
    'portSortingStrategy', PortSortingStrategy.inputOrder);

/// Set on dummy nodes created by InvertedPortProcessor to point back to the
/// original edge.  Mirrors `InternalProperties.ORIGIN`.
const origin = Property<LEdge?>('origin', null);

/// Set on a LONG_EDGE dummy: the first real (non-dummy) source port of the
/// long-edge chain.  Mirrors `InternalProperties.LONG_EDGE_SOURCE`.
const longEdgeSource = Property<LPort?>('longEdgeSource', null);

/// Set on a LONG_EDGE dummy: the first real (non-dummy) target port of the
/// long-edge chain.  Mirrors `InternalProperties.LONG_EDGE_TARGET`.
const longEdgeTarget = Property<LPort?>('longEdgeTarget', null);

/// Whether an edge was originally reversed by cycle-breaking (the Dart model
/// already has `LEdge.reversed`, but the Java also stores it as a property
/// on the edge element so other processors can query it without coupling to
/// the field).  Mirrors `InternalProperties.REVERSED`.
const reversedProperty = Property<bool>('reversed', false);

/// Set on an external-port dummy: the PortSide it represents.
/// Mirrors `InternalProperties.EXT_PORT_SIDE`.
/// Used by PortSideProcessor when assigning sides to ports that have a dummy.
const extPortSide = Property<PortSide>('extPortSide', PortSide.undefined);

/// Pointer from a port to its external-port dummy node, if any.
/// Mirrors `InternalProperties.PORT_DUMMY`.
const portDummy = Property<LNode?>('portDummy', null);

// ---------------------------------------------------------------------------
// Supporting enums
// ---------------------------------------------------------------------------

/// Mirrors `org.eclipse.elk.core.options.PortConstraints`.
enum PortConstraints {
  undefined,
  free,
  fixedSide,
  fixedOrder,
  fixedRatio,
  fixedPos;

  /// Whether the exact port position is locked.
  bool get isPosFixed => this == fixedPos;

  /// Whether the port-position ratio is locked (but not absolute position).
  bool get isRatioFixed => this == fixedRatio;

  /// Whether the relative order of ports on a side is fixed.
  bool get isOrderFixed =>
      this == fixedOrder || this == fixedRatio || this == fixedPos;

  /// Whether the side each port belongs to is fixed (i.e. not free to move).
  bool get isSideFixed => this != free && this != undefined;
}

/// Mirrors `org.eclipse.elk.alg.layered.options.PortSortingStrategy`.
enum PortSortingStrategy {
  /// Preserve the order in which ports appear in the input (default).
  inputOrder,

  /// Re-order ports on EAST/WEST sides by their out/in degree.
  portDegree,
}

// ---------------------------------------------------------------------------
// PortSideProcessor
// ---------------------------------------------------------------------------

/// Assigns each port a [PortSide] when it doesn't have one yet:
/// output ports (netFlow < 0) go on the EAST side (outgoing / right),
/// input ports (netFlow >= 0) go on the WEST side (incoming / left).
///
/// Mirrors `intermediate/PortSideProcessor.java`.
///
/// Runs: before P1 **or** before P3.
///
/// Postcondition: every port has a side != [PortSide.undefined] and the node's
/// port-constraint is elevated to at least [PortConstraints.fixedSide].
class PortSideProcessor implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    // Before P1: layerless nodes.
    for (final node in graph.layerlessNodes) {
      _processNode(node);
    }
    // Before P3: layered nodes.
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        _processNode(node);
      }
    }
  }

  void _processNode(LNode node) {
    final pc = node.getProperty(portConstraints);
    if (pc.isSideFixed) {
      // Only assign sides to ports that still have UNDEFINED side.
      for (final port in node.ports) {
        if (port.side == PortSide.undefined) {
          _setPortSide(port);
        }
      }
    } else {
      // Distribute all ports and elevate constraint to FIXED_SIDE.
      for (final port in node.ports) {
        _setPortSide(port);
      }
      node.setProperty(portConstraints, PortConstraints.fixedSide);
    }
  }

  /// Public helper so other processors can reuse the assignment logic.
  /// Input ports (netFlow >= 0) → WEST; output ports (netFlow < 0) → EAST.
  ///
  /// If the port has an external-port dummy attached, the dummy's EXT_PORT_SIDE
  /// takes precedence.
  ///
  /// Mirrors `PortSideProcessor.setPortSide(LPort)`.
  static void setPortSide(LPort port) => _setPortSide(port);
}

void _setPortSide(LPort port) {
  final dummy = port.getProperty(portDummy);
  if (dummy != null) {
    // TODO(elk-faithful): hierarchical / external-port handling
    port.side = dummy.getProperty(extPortSide);
  } else if (port.netFlow < 0) {
    // More outgoing than incoming edges → output port → EAST (right side in
    // the internal LEFT→RIGHT flow direction).
    port.side = PortSide.east;
  } else {
    // More incoming than outgoing edges (or balanced) → input port → WEST.
    port.side = PortSide.west;
  }
}

// ---------------------------------------------------------------------------
// PortListSorter
// ---------------------------------------------------------------------------

/// Sorts each node's [LNode.ports] list into clockwise order:
/// NORTH → EAST → SOUTH → WEST, then by position within each side.
///
/// For the default [PortConstraints.fixedSide] case the side order is applied
/// and SOUTH/WEST sub-lists are reversed so that they read clockwise (i.e. SOUTH
/// goes right-to-left, WEST goes bottom-to-top).
/// For [PortConstraints.fixedOrder] / [PortConstraints.fixedPos] an explicit
/// position or index comparator is also applied within each side.
///
/// Mirrors `intermediate/PortListSorter.java`.
///
/// Runs: before P3 (after PortSideProcessor).
class PortListSorter implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final pss = graph.getProperty(portSortingStrategy);

    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        final pc = node.getProperty(portConstraints);

        if (pc.isOrderFixed) {
          // FIXED_ORDER / FIXED_RATIO / FIXED_POS: sort by side first, then
          // by explicit index / position within each side.
          node.ports.sort(_cmpCombined);
        } else if (pc.isSideFixed) {
          // FIXED_SIDE: sort by side, then reverse SOUTH and WEST sub-lists so
          // the overall order is clockwise.
          node.ports.sort(_cmpPortSide);
          _reverseWestAndSouthSide(node.ports);

          if (pss == PortSortingStrategy.portDegree) {
            node.ports.sort(_cmpPortDegreeEastWest);
          }
        }
        // FREE / UNDEFINED: no sorting.
      }
    }
  }

  // -------------------------------------------------------------------------
  // Sort helpers
  // -------------------------------------------------------------------------

  /// Sort only by PortSide ordinal (NORTH < EAST < SOUTH < WEST < UNDEFINED).
  static int _cmpPortSide(LPort a, LPort b) =>
      a.side.index - b.side.index;

  /// Sort by side, then within a side by explicit index / position.
  static int _cmpCombined(LPort a, LPort b) {
    final sideDiff = _cmpPortSide(a, b);
    if (sideDiff != 0) return sideDiff;
    return _cmpFixedOrderAndFixedPos(a, b);
  }

  /// Within a side for FIXED_ORDER / FIXED_POS: first try the PORT_INDEX
  /// property, then fall back to geometric position.
  ///
  /// Mirrors `CMP_FIXED_ORDER_AND_FIXED_POS`.
  static int _cmpFixedOrderAndFixedPos(LPort a, LPort b) {
    // Different sides — not our job (handled by the combined comparator).
    if (a.side != b.side) return 0;

    final pc = a.node.getProperty(portConstraints);
    if (!pc.isOrderFixed) return 0;

    if (pc == PortConstraints.fixedOrder) {
      final ia = a.getProperty(portIndex);
      final ib = b.getProperty(portIndex);
      if (ia != null && ib != null) {
        final diff = ia - ib;
        if (diff != 0) return diff;
      }
    }

    // Fall back to geometric position (also covers FIXED_POS).
    switch (a.side) {
      case PortSide.north:
        return a.position.x.compareTo(b.position.x);
      case PortSide.east:
        return a.position.y.compareTo(b.position.y);
      case PortSide.south:
        // Clockwise on south: decreasing x.
        return b.position.x.compareTo(a.position.x);
      case PortSide.west:
        // Clockwise on west: decreasing y.
        return b.position.y.compareTo(a.position.y);
      case PortSide.undefined:
        return 0;
    }
  }

  /// Re-order EAST/WEST ports by degree (out-degree on EAST, in-degree on WEST)
  /// so that high-degree ports are listed first.
  ///
  /// Mirrors `CMP_PORT_DEGREE_EAST_WEST`.
  static int _cmpPortDegreeEastWest(LPort a, LPort b) {
    if (a.side != b.side) return 0;
    switch (a.side) {
      case PortSide.east:
        return _realOutDegree(b) - _realOutDegree(a);
      case PortSide.west:
        return _realInDegree(a) - _realInDegree(b);
      default:
        return 0;
    }
  }

  /// Count outgoing edges that were NOT reversed by cycle-breaking.
  static int _realOutDegree(LPort p) {
    var d = 0;
    for (final e in p.outgoingEdges) {
      if (!e.getProperty(reversedProperty)) d++;
    }
    return d;
  }

  /// Count incoming edges that were NOT reversed by cycle-breaking.
  static int _realInDegree(LPort p) {
    var d = 0;
    for (final e in p.incomingEdges) {
      if (!e.getProperty(reversedProperty)) d++;
    }
    return d;
  }

  // -------------------------------------------------------------------------
  // Clockwise reversal of SOUTH and WEST sub-lists
  // -------------------------------------------------------------------------

  /// Reverses the SOUTH and WEST sub-lists in [ports] so that the overall list
  /// reads clockwise (the side comparator places them in increasing ordinal
  /// order, but SOUTH reads right-to-left and WEST reads bottom-to-top for
  /// clockwise traversal).
  ///
  /// Mirrors `PortListSorter.reverseWestAndSouthSide`.
  static void _reverseWestAndSouthSide(List<LPort> ports) {
    if (ports.length <= 1) return;

    final south = _findPortSideRange(ports, PortSide.south);
    _reverseRange(ports, south.$1, south.$2);

    final west = _findPortSideRange(ports, PortSide.west);
    _reverseRange(ports, west.$1, west.$2);
  }

  /// Returns the half-open range [lo, hi) of indices in [ports] occupied by
  /// ports whose [side] equals [side].  Ports must already be side-sorted.
  ///
  /// Mirrors `PortListSorter.findPortSideRange`.
  static (int, int) _findPortSideRange(List<LPort> ports, PortSide side) {
    if (ports.isEmpty) return (0, 0);

    final lb = side.index;
    final hb = side.index + 1;

    int lo = 0;
    while (lo < ports.length - 1 && ports[lo].side.index < lb) {
      lo++;
    }
    int hi = lo;
    while (hi < ports.length - 1 && ports[hi].side.index < hb) {
      hi++;
    }
    // hi is now the last index still in [lo, hi) if side matches; adjust.
    // Java's findPortSideRange returns (lowIdx, highIdx) where highIdx is
    // exclusive only if ports[highIdx].side >= hb, otherwise it IS the last
    // matching index.  Mirror exactly: hi points at the last matching port or
    // just past the end.
    return (lo, hi);
  }

  /// In-place reversal of [ports] in the half-open range [lo, hi).
  ///
  /// Mirrors `PortListSorter.reverse(ports, lowIdx, highIdx)`.
  static void _reverseRange(List<LPort> ports, int lo, int hi) {
    // Java's reverse returns early when highIdx <= lowIdx + 2 and then
    // iterates n = (highIdx - lowIdx) / 2 swaps.
    if (hi <= lo + 2) return;
    final n = (hi - lo) ~/ 2;
    for (var i = 0; i < n; i++) {
      final tmp = ports[lo + i];
      ports[lo + i] = ports[hi - i - 1];
      ports[hi - i - 1] = tmp;
    }
  }
}

// ---------------------------------------------------------------------------
// InvertedPortProcessor
// ---------------------------------------------------------------------------

/// Inserts LONG_EDGE dummy nodes to handle "inverted" ports — i.e. ports
/// whose side faces away from the expected flow direction:
///
/// - An **input** port on the **EAST** side (right): the incoming edge comes
///   from the west but the port sits on the east, so a dummy is inserted in
///   the same layer to accept the edge on its west port and re-emit it
///   eastward onto the offending port.
///
/// - An **output** port on the **WEST** side (left): the outgoing edge should
///   go east but the port sits on the west, so a dummy re-routes it.
///
/// Mirrors `intermediate/InvertedPortProcessor.java`.
///
/// Runs: before P3, after PortSideProcessor.
class InvertedPortProcessor implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final layers = graph.layers;

    // Dummy nodes that belong to the *previous* layer accumulate here while we
    // are iterating the current layer, to avoid concurrent-modification issues.
    final unassigned = <LNode>[];
    Layer? previousLayer;

    for (var li = 0; li < layers.length; li++) {
      final currentLayer = layers[li];

      // Flush dummies that belong to the previous layer.
      for (final dummy in unassigned) {
        _assignToLayer(dummy, previousLayer!);
      }
      unassigned.clear();

      // Snapshot the node list so additions inside the loop don't affect us.
      final nodeSnapshot = List<LNode>.of(currentLayer.nodes);

      for (final node in nodeSnapshot) {
        // Only process real (normal) nodes.
        if (node.type != NodeType.normal) continue;

        // Only process nodes whose port sides are already fixed.
        if (!node.getProperty(portConstraints).isSideFixed) continue;

        // --- Input ports on the EAST side ---
        final eastInputPorts = node.ports
            .where((p) =>
                p.side == PortSide.east && p.incomingEdges.isNotEmpty)
            .toList();

        for (final port in eastInputPorts) {
          // Copy the incoming-edge list because it is mutated as dummies are
          // created.
          final edges = List<LEdge>.of(port.incomingEdges);
          for (final edge in edges) {
            _createEastPortSideDummies(graph, port, edge, unassigned);
          }
        }

        // --- Output ports on the WEST side ---
        final westOutputPorts = node.ports
            .where((p) =>
                p.side == PortSide.west && p.outgoingEdges.isNotEmpty)
            .toList();

        for (final port in westOutputPorts) {
          final edges = List<LEdge>.of(port.outgoingEdges);
          for (final edge in edges) {
            _createWestPortSideDummies(graph, port, edge, unassigned);
          }
        }
      }

      previousLayer = currentLayer;
    }

    // Assign any remaining dummies to the last layer.
    if (previousLayer != null) {
      for (final dummy in unassigned) {
        _assignToLayer(dummy, previousLayer);
      }
    }
  }

  // -------------------------------------------------------------------------
  // East-side input port dummy
  // -------------------------------------------------------------------------

  /// Inserts a LONG_EDGE dummy for an incoming edge that arrives at an input
  /// port on the EAST side of its target node.
  ///
  ///   [source] ──edge──▶ [eastwardPort (EAST, INPUT)]
  ///
  /// becomes:
  ///
  ///   [source] ──edge──▶ [dummy.W] [dummy.E] ──dummyEdge──▶ [eastwardPort]
  ///
  /// Mirrors `createEastPortSideDummies`.
  void _createEastPortSideDummies(
    LGraph graph,
    LPort eastwardPort,
    LEdge edge,
    List<LNode> unassigned,
  ) {
    assert(edge.target == eastwardPort);

    // Ignore self-loops.
    if (edge.source?.node == eastwardPort.node) return;

    final dummy = _makeLongEdgeDummy(graph, edge);
    unassigned.add(dummy);

    final dummyInput = _addDummyPort(dummy, PortSide.west);
    final dummyOutput = _addDummyPort(dummy, PortSide.east);

    // Redirect the original edge to the dummy's input port.
    edge.target = dummyInput;

    // New edge from dummy's output to the offending port.
    final dummyEdge = _copyEdge(edge);
    dummyEdge.source = dummyOutput;
    dummyEdge.target = eastwardPort;

    _setLongEdgeSourceAndTarget(dummy, dummyInput, dummyOutput, eastwardPort);

    // Move HEAD labels from the original edge to the new dummy edge.
    // TODO(elk-faithful): EdgeLabelPlacement.head label migration omitted —
    //   label-placement properties are not yet in the data model.
  }

  // -------------------------------------------------------------------------
  // West-side output port dummy
  // -------------------------------------------------------------------------

  /// Inserts a LONG_EDGE dummy for an outgoing edge that leaves from an output
  /// port on the WEST side of its source node.
  ///
  ///   [westwardPort (WEST, OUTPUT)] ──edge──▶ [target]
  ///
  /// becomes:
  ///
  ///   [westwardPort] ──edge──▶ [dummy.W] [dummy.E] ──dummyEdge──▶ [target]
  ///
  /// Mirrors `createWestPortSideDummies`.
  void _createWestPortSideDummies(
    LGraph graph,
    LPort westwardPort,
    LEdge edge,
    List<LNode> unassigned,
  ) {
    assert(edge.source == westwardPort);

    // Ignore self-loops.
    if (edge.target?.node == westwardPort.node) return;

    final dummy = _makeLongEdgeDummy(graph, edge);
    unassigned.add(dummy);

    final dummyInput = _addDummyPort(dummy, PortSide.west);
    final dummyOutput = _addDummyPort(dummy, PortSide.east);

    // The original edge now targets the dummy's input port; the original
    // target gets a fresh dummy edge.
    final originalTarget = edge.target!;
    edge.target = dummyInput;

    final dummyEdge = _copyEdge(edge);
    dummyEdge.source = dummyOutput;
    dummyEdge.target = originalTarget;

    _setLongEdgeSourceAndTarget(dummy, dummyInput, dummyOutput, westwardPort);

    // TODO(elk-faithful): HEAD label migration omitted (see east variant).
  }

  // -------------------------------------------------------------------------
  // Private utilities
  // -------------------------------------------------------------------------

  /// Creates a bare LONG_EDGE dummy node wired to [graph], holding a
  /// back-reference to the original [edge] via the [origin] property.
  LNode _makeLongEdgeDummy(LGraph graph, LEdge edge) {
    final dummy = LNode(graph);
    dummy.type = NodeType.longEdge;
    dummy.setProperty(origin, edge);
    // Dummy's own ports must stay where we place them (FIXED_POS).
    dummy.setProperty(portConstraints, PortConstraints.fixedPos);
    return dummy;
  }

  /// Adds a new [LPort] with the given [side] to [dummy].
  LPort _addDummyPort(LNode dummy, PortSide side) {
    final port = LPort(dummy);
    port.side = side;
    dummy.ports.add(port);
    return port;
  }

  /// Assigns [dummy] into [layer] (appends to the layer's node list and sets
  /// the node's layer back-reference).
  void _assignToLayer(LNode dummy, Layer layer) {
    layer.nodes.add(dummy);
    dummy.layer = layer;
  }

  /// Returns a shallow copy of [edge] with no source/target set (the caller
  /// wires those up).  Copies all properties.
  LEdge _copyEdge(LEdge edge) {
    final copy = LEdge();
    copy.copyPropertiesFrom(edge);
    // Remove junction points — these will be recomputed by edge routing.
    // TODO(elk-faithful): LayeredOptions.JUNCTION_POINTS reset not yet in
    //   the data model (it's a KVectorChain property set during routing).
    return copy;
  }

  /// Sets [longEdgeSource] and [longEdgeTarget] on [longEdgeDummy], honouring
  /// any existing chain (if a neighbour is itself a LONG_EDGE dummy, propagate
  /// its source/target instead of that dummy's port).
  ///
  /// Mirrors `InvertedPortProcessor.setLongEdgeSourceAndTarget`.
  void _setLongEdgeSourceAndTarget(
    LNode longEdgeDummy,
    LPort dummyInputPort,
    LPort dummyOutputPort,
    LPort oddPort,
  ) {
    // There is exactly one edge on each dummy port at this point.
    final sourcePort = dummyInputPort.incomingEdges.first.source!;
    final sourceNode = sourcePort.node;

    final targetPort = dummyOutputPort.outgoingEdges.first.target!;
    final targetNode = targetPort.node;

    // LONG_EDGE_SOURCE
    if (sourceNode.type == NodeType.longEdge) {
      longEdgeDummy.setProperty(
          longEdgeSource, sourceNode.getProperty(longEdgeSource));
    } else {
      longEdgeDummy.setProperty(longEdgeSource, sourcePort);
    }

    // LONG_EDGE_TARGET
    if (targetNode.type == NodeType.longEdge) {
      longEdgeDummy.setProperty(
          longEdgeTarget, targetNode.getProperty(longEdgeTarget));
    } else {
      longEdgeDummy.setProperty(longEdgeTarget, targetPort);
    }
  }
}

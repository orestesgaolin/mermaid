/// Faithful port of four ELK layered intermediate processors that enforce
/// layer-level and in-layer node constraints:
///
///   • [EdgeAndLayerConstraintEdgeReverser]
///   • [LayerConstraintPreprocessor]
///   • [LayerConstraintPostprocessor]
///   • [InLayerConstraintProcessor]
///
/// Reference Java sources (all under
/// `org.eclipse.elk.alg.layered.intermediate`):
///   `EdgeAndLayerConstraintEdgeReverser.java`
///   `LayerConstraintPreprocessor.java`
///   `LayerConstraintPostprocessor.java`
///   `InLayerConstraintProcessor.java`
///
/// Omissions (all marked TODO(elk-faithful)):
///   - Hierarchical / external-port constraint handling
///   - UnsupportedConfigurationException propagation (replaced by assert / no-op)
///   - Full `PortConstraints` enum; only the `isSideFixed()` notion is ported
///     (i.e., not FREE and not UNDEFINED → side is fixed).
library;

import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Mirrors `org.eclipse.elk.alg.layered.options.LayerConstraint`.
enum LayerConstraint {
  /// No constraint on the layering.
  none,

  /// Place into the first layer.
  first,

  /// Place into a separate first layer (used internally).
  firstSeparate,

  /// Place into the last layer.
  last,

  /// Place into a separate last layer (used internally).
  lastSeparate,
}

/// Mirrors `org.eclipse.elk.alg.layered.options.InLayerConstraint`.
enum InLayerConstraint {
  /// No constraint on in-layer placement.
  none,

  /// Float to the top of the layer.
  top,

  /// Float to the bottom of the layer.
  bottom,
}

/// Mirrors `org.eclipse.elk.alg.layered.options.EdgeConstraint`.
enum EdgeConstraint {
  /// No constraint on incident edges.
  none,

  /// Node may have only incoming edges.
  incomingOnly,

  /// Node may have only outgoing edges.
  outgoingOnly,
}

/// Reduced mirror of `org.eclipse.elk.core.options.PortConstraints`.
/// Only the values relevant to `isSideFixed()` are represented here.
enum PortConstraints {
  undefined,
  free,
  fixedSide,
  fixedOrder,
  fixedRatio,
  fixedPos;

  /// Mirrors `PortConstraints.isSideFixed()`: true for every value except
  /// [undefined] and [free].
  bool get isSideFixed => this != undefined && this != free;
}

// ---------------------------------------------------------------------------
// Property constants (top-level, shared by all four processors)
// ---------------------------------------------------------------------------

/// Layer constraint on a node.
/// ELK: `LayeredOptions.LAYERING_LAYER_CONSTRAINT`.
const layerConstraint =
    Property<LayerConstraint>('layerConstraint', LayerConstraint.none);

/// In-layer placement constraint on a node.
/// ELK: `InternalProperties.IN_LAYER_CONSTRAINT`.
const inLayerConstraint =
    Property<InLayerConstraint>('inLayerConstraint', InLayerConstraint.none);

/// Edge constraint set on a node by the reverser.
/// ELK: `InternalProperties.EDGE_CONSTRAINT`.
const edgeConstraint =
    Property<EdgeConstraint>('edgeConstraint', EdgeConstraint.none);

/// Port-order / side-fixedness constraint on a node.
/// ELK: `LayeredOptions.PORT_CONSTRAINTS`.
const portConstraints =
    Property<PortConstraints>('portConstraints', PortConstraints.free);

// ---------------------------------------------------------------------------
// Private (file-local) Property constants used between pre- and postprocessor
// ---------------------------------------------------------------------------

/// The list of nodes hidden by [LayerConstraintPreprocessor].
/// ELK: `InternalProperties.HIDDEN_NODES`.
const _hiddenNodes = Property<List<LNode>?>('layerConstraints.hiddenNodes');

/// Saved opposite port when an edge is partially disconnected during hiding.
/// ELK: `InternalProperties.ORIGINAL_OPPOSITE_PORT`.
const _originalOppositePort =
    Property<LPort?>('layerConstraints.oppositePort');

/// Tracks which kinds of hidden nodes a normal node was connected to.
/// Used during hide to decide if a spare layer constraint should be added.
/// ELK: file-private `HIDDEN_NODE_CONNECTIONS` property.
const _hiddenNodeConnections =
    Property<_HiddenNodeConnections>(
        'separateLayerConnections', _HiddenNodeConnections.none);

// ---------------------------------------------------------------------------
// _HiddenNodeConnections helper (file-private)
// ---------------------------------------------------------------------------

/// Mirrors the private `HiddenNodeConnections` enum in
/// `LayerConstraintPreprocessor.java`.
enum _HiddenNodeConnections {
  none,
  firstSeparate,
  lastSeparate,
  both;

  _HiddenNodeConnections combine(LayerConstraint lc) {
    switch (this) {
      case none:
        return lc == LayerConstraint.firstSeparate
            ? firstSeparate
            : lastSeparate;
      case firstSeparate:
        return lc == LayerConstraint.firstSeparate ? firstSeparate : both;
      case lastSeparate:
        return lc == LayerConstraint.firstSeparate ? both : lastSeparate;
      case both:
        return both;
    }
  }
}

// ---------------------------------------------------------------------------
// 1. EdgeAndLayerConstraintEdgeReverser
// ---------------------------------------------------------------------------

/// Ensures nodes with layer constraints have only the appropriate edge
/// direction (outgoing-only for FIRST/FIRST_SEPARATE, incoming-only for
/// LAST/LAST_SEPARATE). Also reverses all edges when a node's ports are all
/// reversed (the "feedback node" case).
///
/// Must run before phase 1 (cycle breaking).
///
/// Faithful port of `EdgeAndLayerConstraintEdgeReverser.java`.
class EdgeAndLayerConstraintEdgeReverser implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final remainingNodes = _handleOuterNodes(graph);
    _handleInnerNodes(graph, remainingNodes);
  }

  // ---- outer nodes --------------------------------------------------------

  List<LNode> _handleOuterNodes(LGraph graph) {
    final remaining = <LNode>[];
    for (final node in graph.layerlessNodes) {
      final lc = node.getProperty(layerConstraint);
      EdgeConstraint? ec;
      switch (lc) {
        case LayerConstraint.first:
        case LayerConstraint.firstSeparate:
          ec = EdgeConstraint.outgoingOnly;
          break;
        case LayerConstraint.last:
        case LayerConstraint.lastSeparate:
          ec = EdgeConstraint.incomingOnly;
          break;
        default:
          break;
      }

      if (ec != null) {
        // Java sets OUTGOING_ONLY unconditionally here (looks like a minor bug
        // in the Java source, but we faithfully reproduce it).
        node.setProperty(edgeConstraint, EdgeConstraint.outgoingOnly);

        if (ec == EdgeConstraint.incomingOnly) {
          _reverseEdges(graph, node, lc, PortType.input);
        } else {
          _reverseEdges(graph, node, lc, PortType.output);
        }
      } else {
        remaining.add(node);
      }
    }
    return remaining;
  }

  // ---- inner nodes --------------------------------------------------------

  void _handleInnerNodes(LGraph graph, List<LNode> nodes) {
    for (final node in nodes) {
      final lc = node.getProperty(layerConstraint);
      EdgeConstraint? ec;
      switch (lc) {
        case LayerConstraint.first:
        case LayerConstraint.firstSeparate:
          ec = EdgeConstraint.outgoingOnly;
          break;
        case LayerConstraint.last:
        case LayerConstraint.lastSeparate:
          ec = EdgeConstraint.incomingOnly;
          break;
        default:
          break;
      }

      if (ec != null) {
        node.setProperty(edgeConstraint, EdgeConstraint.outgoingOnly);
        if (ec == EdgeConstraint.incomingOnly) {
          _reverseEdges(graph, node, lc, PortType.input);
        } else {
          _reverseEdges(graph, node, lc, PortType.output);
        }
      } else {
        // Feedback-node detection: if port sides are fixed and every port is
        // reversed, flip all incident edges.
        final pc = node.getProperty(portConstraints);
        if (pc.isSideFixed && node.ports.isNotEmpty) {
          bool allReversed = true;
          outer:
          for (final port in node.ports) {
            // A non-reversed east port has net flow <= 0; non-reversed west
            // port has net flow >= 0. Violation means not reversed.
            final flow = port.netFlow;
            if (!((port.side == PortSide.east && flow > 0) ||
                (port.side == PortSide.west && flow < 0))) {
              allReversed = false;
              break;
            }
            // LAST/LAST_SEPARATE target on outgoing edge → not a feedback node
            for (final e in port.outgoingEdges) {
              final tlc = e.target?.node.getProperty(layerConstraint);
              if (tlc == LayerConstraint.last ||
                  tlc == LayerConstraint.lastSeparate) {
                allReversed = false;
                break outer;
              }
            }
            // FIRST/FIRST_SEPARATE source on incoming edge → not a feedback node
            for (final e in port.incomingEdges) {
              final slc = e.source?.node.getProperty(layerConstraint);
              if (slc == LayerConstraint.first ||
                  slc == LayerConstraint.firstSeparate) {
                allReversed = false;
                break outer;
              }
            }
          }

          if (allReversed) {
            _reverseEdges(graph, node, lc, PortType.undefined);
          }
        }
      }
    }
  }

  // ---- reverseEdges -------------------------------------------------------

  /// Reverses edges incident to [node] as appropriate for the given
  /// [targetPortType].
  ///
  /// [targetPortType] == [PortType.output] → reverse incoming edges (make
  /// the node purely outgoing).
  /// [targetPortType] == [PortType.input]  → reverse outgoing edges (make
  /// the node purely incoming).
  /// [targetPortType] == [PortType.undefined] → reverse all edges.
  void _reverseEdges(
    LGraph graph,
    LNode node,
    LayerConstraint nodeLayerConstraint,
    PortType targetPortType,
  ) {
    for (final port in node.ports.toList()) {
      // Reverse outgoing edges when targeting INPUT or UNDEFINED
      if (targetPortType == PortType.input ||
          targetPortType == PortType.undefined) {
        for (final edge in port.outgoingEdges.toList()) {
          if (_canReverseOutgoing(nodeLayerConstraint, edge)) {
            edge.reverse();
          }
        }
      }

      // Reverse incoming edges when targeting OUTPUT or UNDEFINED
      if (targetPortType == PortType.output ||
          targetPortType == PortType.undefined) {
        for (final edge in port.incomingEdges.toList()) {
          if (_canReverseIncoming(nodeLayerConstraint, edge)) {
            edge.reverse();
          }
        }
      }
    }
  }

  bool _canReverseOutgoing(LayerConstraint sourceLC, LEdge edge) {
    if (edge.reversed) return false;

    final target = edge.target?.node;
    if (target == null) return false;

    // LAST node connected to a LABEL dummy: keep it (dummy goes between LAST
    // and LAST_SEPARATE).
    if (sourceLC == LayerConstraint.last && target.type == NodeType.label) {
      return false;
    }

    // Don't reverse if target is LAST_SEPARATE.
    if (target.getProperty(layerConstraint) == LayerConstraint.lastSeparate) {
      return false;
    }

    return true;
  }

  bool _canReverseIncoming(LayerConstraint targetLC, LEdge edge) {
    if (edge.reversed) return false;

    final source = edge.source?.node;
    if (source == null) return false;

    // FIRST node connected to a LABEL dummy: keep it.
    if (targetLC == LayerConstraint.first && source.type == NodeType.label) {
      return false;
    }

    // Don't reverse if source is FIRST_SEPARATE.
    if (source.getProperty(layerConstraint) == LayerConstraint.firstSeparate) {
      return false;
    }

    return true;
  }
}

// ---------------------------------------------------------------------------
// 2. LayerConstraintPreprocessor
// ---------------------------------------------------------------------------

/// Hides FIRST_SEPARATE and LAST_SEPARATE nodes from the graph before layering
/// so they do not influence it. The hidden nodes (and the edges connecting them
/// to the rest of the graph) are temporarily disconnected and stored on the
/// graph via the [_hiddenNodes] property.
///
/// Must run before phase 2 (layering).
///
/// Faithful port of `LayerConstraintPreprocessor.java`.
class LayerConstraintPreprocessor implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final hidden = <LNode>[];

    // Iterate via index so we can remove elements safely.
    int i = 0;
    while (i < graph.layerlessNodes.length) {
      final node = graph.layerlessNodes[i];
      final lc = node.getProperty(layerConstraint);
      if (lc == LayerConstraint.firstSeparate ||
          lc == LayerConstraint.lastSeparate) {
        _hide(node);
        hidden.add(node);
        graph.layerlessNodes.removeAt(i);
        // do not increment i
      } else {
        i++;
      }
    }

    if (hidden.isNotEmpty) {
      graph.setProperty(_hiddenNodes, hidden);
    }
  }

  // ---- hiding -------------------------------------------------------------

  void _hide(LNode node) {
    _ensureNoUnacceptableEdges(node);
    for (final edge in node.connectedEdges.toList()) {
      _hideEdge(node, edge);
    }
  }

  void _hideEdge(LNode hiddenNode, LEdge edge) {
    final isOutgoing = edge.source?.node == hiddenNode;
    final oppositePort = isOutgoing ? edge.target : edge.source;
    if (oppositePort == null) return;

    // Disconnect the edge end that points away from the hidden node.
    if (isOutgoing) {
      edge.target = null;
    } else {
      edge.source = null;
    }

    edge.setProperty(_originalOppositePort, oppositePort);

    _updateOppositeNodeLayerConstraints(hiddenNode, oppositePort.node);
  }

  void _updateOppositeNodeLayerConstraints(
      LNode hiddenNode, LNode oppositeNode) {
    // If the opposite node already has a layer constraint, leave it alone.
    if (oppositeNode.hasProperty(layerConstraint as Property<Object?>)) return;

    final hiddenLC = hiddenNode.getProperty(layerConstraint);
    final connections = oppositeNode
        .getProperty(_hiddenNodeConnections)
        .combine(hiddenLC);
    oppositeNode.setProperty(_hiddenNodeConnections, connections);

    // If the opposite node still has live connections, nothing more to do.
    if (oppositeNode.connectedEdges.isNotEmpty) return;

    // The hidden node was the last neighbour: possibly pin the opposite node.
    switch (connections) {
      case _HiddenNodeConnections.firstSeparate:
        oppositeNode.setProperty(layerConstraint, LayerConstraint.first);
        break;
      case _HiddenNodeConnections.lastSeparate:
        oppositeNode.setProperty(layerConstraint, LayerConstraint.last);
        break;
      default:
        break;
    }
  }

  // ---- validation ---------------------------------------------------------

  /// Asserts that FIRST_SEPARATE nodes have no incoming edges (except between
  /// two external-port dummies) and LAST_SEPARATE nodes have no outgoing edges.
  void _ensureNoUnacceptableEdges(LNode node) {
    final lc = node.getProperty(layerConstraint);
    if (lc == LayerConstraint.firstSeparate) {
      for (final e in node.incomingEdges) {
        assert(
          _isAcceptableEdge(e),
          'FIRST_SEPARATE node has an incoming edge that is not between two '
          'external-port dummies.',
        );
      }
    } else if (lc == LayerConstraint.lastSeparate) {
      for (final e in node.outgoingEdges) {
        assert(
          _isAcceptableEdge(e),
          'LAST_SEPARATE node has an outgoing edge that is not between two '
          'external-port dummies.',
        );
      }
    }
  }

  bool _isAcceptableEdge(LEdge edge) {
    return edge.source?.node.type == NodeType.externalPort &&
        edge.target?.node.type == NodeType.externalPort;
  }
}

// ---------------------------------------------------------------------------
// 3. LayerConstraintPostprocessor
// ---------------------------------------------------------------------------

/// Restores nodes hidden by [LayerConstraintPreprocessor] and moves nodes with
/// FIRST/LAST constraints into dedicated first/last layers.
///
/// Must run before phase 3 (crossing minimisation).
///
/// Faithful port of `LayerConstraintPostprocessor.java`.
class LayerConstraintPostprocessor implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final layers = graph.layers;

    if (layers.isNotEmpty) {
      final firstLayer = layers.first;
      final lastLayer = layers.last;

      // Label dummy layers that sit just outside the FIRST / LAST layers.
      final firstLabelLayer = Layer(graph);
      final lastLabelLayer = Layer(graph);

      _moveFirstAndLastNodes(
          graph, firstLayer, lastLayer, firstLabelLayer, lastLabelLayer);

      if (firstLabelLayer.nodes.isNotEmpty) {
        layers.insert(0, firstLabelLayer);
      }
      if (lastLabelLayer.nodes.isNotEmpty) {
        layers.add(lastLabelLayer);
      }
    }

    // Restore FIRST_SEPARATE / LAST_SEPARATE nodes that were hidden.
    if (graph.hasProperty(_hiddenNodes)) {
      final firstSeparateLayer = Layer(graph);
      final lastSeparateLayer = Layer(graph);

      _restoreHiddenNodes(graph, firstSeparateLayer, lastSeparateLayer);

      if (firstSeparateLayer.nodes.isNotEmpty) {
        layers.insert(0, firstSeparateLayer);
      }
      if (lastSeparateLayer.nodes.isNotEmpty) {
        layers.add(lastSeparateLayer);
      }
    }
  }

  // ---- FIRST / LAST movement ----------------------------------------------

  void _moveFirstAndLastNodes(
    LGraph graph,
    Layer firstLayer,
    Layer lastLayer,
    Layer firstLabelLayer,
    Layer lastLabelLayer,
  ) {
    // Snapshot the layer list so we can safely add to it.
    for (final layer in graph.layers.toList()) {
      // Snapshot nodes for this layer.
      for (final node in layer.nodes.toList()) {
        final lc = node.getProperty(layerConstraint);
        switch (lc) {
          case LayerConstraint.first:
            _assertNoIncomingEdgesExceptLabel(node);
            _setLayer(node, firstLayer);
            _moveLabelsToLabelLayer(node, true, firstLabelLayer);
            break;
          case LayerConstraint.last:
            _assertNoOutgoingEdgesExceptLabel(node);
            _setLayer(node, lastLayer);
            _moveLabelsToLabelLayer(node, false, lastLabelLayer);
            break;
          default:
            break;
        }
      }
    }

    // Remove layers that have become empty.
    graph.layers.removeWhere((l) => l.nodes.isEmpty);
  }

  void _moveLabelsToLabelLayer(
      LNode node, bool incoming, Layer labelLayer) {
    final edges = incoming ? node.incomingEdges : node.outgoingEdges;
    for (final edge in edges) {
      final candidate =
          incoming ? edge.source?.node : edge.target?.node;
      if (candidate != null && candidate.type == NodeType.label) {
        _setLayer(candidate, labelLayer);
      }
    }
  }

  // ---- FIRST_SEPARATE / LAST_SEPARATE restoration -------------------------

  void _restoreHiddenNodes(
      LGraph graph, Layer firstSepLayer, Layer lastSepLayer) {
    final hidden = graph.getProperty(_hiddenNodes) ?? [];
    for (final node in hidden) {
      final lc = node.getProperty(layerConstraint);
      switch (lc) {
        case LayerConstraint.firstSeparate:
          _setLayer(node, firstSepLayer);
          break;
        case LayerConstraint.lastSeparate:
          _setLayer(node, lastSepLayer);
          break;
        default:
          assert(false, 'Only *_SEPARATE nodes should be in HIDDEN_NODES');
      }

      // Restore the edges of this hidden node.
      for (final edge in node.connectedEdges.toList()) {
        // May already be restored if both endpoints are hidden nodes and
        // the other one was processed first.
        if (edge.source != null && edge.target != null) continue;

        final isOutgoing = edge.target == null;
        final oppositePort = edge.getProperty(_originalOppositePort);
        if (oppositePort == null) continue;

        if (isOutgoing) {
          edge.target = oppositePort;
        } else {
          edge.source = oppositePort;
        }
      }
    }
  }

  // ---- helpers ------------------------------------------------------------

  /// Moves [node] to [newLayer], maintaining [LNode.layer] and the layer's
  /// node list — mirrors `LNode.setLayer(Layer)` in Java.
  void _setLayer(LNode node, Layer newLayer) {
    node.layer?.nodes.remove(node);
    node.layer = newLayer;
    newLayer.nodes.add(node);
  }

  void _assertNoIncomingEdgesExceptLabel(LNode node) {
    for (final e in node.incomingEdges) {
      assert(
        e.source?.node.type == NodeType.label,
        'FIRST node has an incoming edge not from a LABEL dummy.',
      );
    }
  }

  void _assertNoOutgoingEdgesExceptLabel(LNode node) {
    for (final e in node.outgoingEdges) {
      assert(
        e.target?.node.type == NodeType.label,
        'LAST node has an outgoing edge not to a LABEL dummy.',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// 4. InLayerConstraintProcessor
// ---------------------------------------------------------------------------

/// Reorders nodes within each layer so that TOP-constrained nodes appear at
/// the top and BOTTOM-constrained nodes appear at the bottom.
///
/// Must run before phase 4 (node placement).
///
/// Faithful port of `InLayerConstraintProcessor.java`.
///
/// Note: in-layer successor constraints among TOP/BOTTOM nodes are not
/// enforced by this processor (matching Java behaviour).
class InLayerConstraintProcessor implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    for (final layer in graph.layers) {
      // Take a snapshot; we will mutate layer.nodes.
      final nodes = layer.nodes.toList();

      // Index at which the next TOP-constrained node (discovered after the
      // first non-TOP node) should be inserted.
      int topInsertionIndex = -1;

      // BOTTOM-constrained nodes collected in order; appended at the end.
      final bottomNodes = <LNode>[];

      for (int i = 0; i < nodes.length; i++) {
        final constraint = nodes[i].getProperty(inLayerConstraint);

        if (topInsertionIndex == -1) {
          // Still in the leading TOP section.
          if (constraint != InLayerConstraint.top) {
            topInsertionIndex = i;
          }
        } else {
          // We have passed the first non-TOP node.
          if (constraint == InLayerConstraint.top) {
            // Move this node to the insertion point.
            _setLayerAt(nodes[i], topInsertionIndex, layer);
            topInsertionIndex++;
          }
        }

        if (constraint == InLayerConstraint.bottom) {
          bottomNodes.add(nodes[i]);
        }
      }

      // Append BOTTOM nodes at the end.
      for (final node in bottomNodes) {
        // Remove from current position, then append.
        layer.nodes.remove(node);
        layer.nodes.add(node);
        // node.layer is already this layer; no reassignment needed.
      }
    }
  }

  /// Removes [node] from its current position in [layer] and inserts it at
  /// [index] — mirrors `LNode.setLayer(int, Layer)` in Java.
  void _setLayerAt(LNode node, int index, Layer layer) {
    layer.nodes.remove(node);
    layer.nodes.insert(index, node);
    // node.layer is already this layer.
  }
}

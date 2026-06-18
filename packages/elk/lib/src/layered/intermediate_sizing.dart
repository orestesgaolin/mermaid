/// Faithful ports of four ELK intermediate sizing/merging processors:
///
///   - [InnermostNodeMarginCalculator]  — computes each node's [LNode.margin]
///     from the extents of its ports (and labels, when present).
///   - [LabelAndNodeSizeProcessor]      — for the default config (fixed node
///     sizes, free ports, no edge labels, no hierarchy) this positions ports
///     evenly along the E/W borders and leaves node sizes alone.
///   - [LayerSizeAndGraphHeightCalculator] — computes [Layer.size] for every
///     layer and sets [LGraph.size].y / [LGraph.offset].y.
///   - [HyperedgeDummyMerger]           — merges adjacent long-edge dummy nodes
///     that share the same hyperedge (same source/target port).
///
/// Scope: default config only — fixed node sizes, free E/W ports, no labels,
/// no hierarchy. Branches for other configs are stubbed with
/// `// TODO(elk-faithful): ...`.
library;

import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// Property constants (defined locally — do NOT edit shared model files)
// ---------------------------------------------------------------------------

/// Marks a cluster's external port (created for a split cross-hierarchy edge) as
/// having a fixed position propagated from the inner boundary dummy, so the port
/// placer leaves it where it is. Same id as the engine's const (Property
/// equality is by id), so both refer to the same property slot.
const crossHierarchyFixedPort = Property<bool>('xh.fixedPortPos', false);

/// The original source port of a long edge before it was split into segments.
/// ELK `InternalProperties.LONG_EDGE_SOURCE`.
const longEdgeSource = Property<LPort?>('longEdgeSource');

/// The original target port of a long edge before it was split into segments.
/// ELK `InternalProperties.LONG_EDGE_TARGET`.
const longEdgeTarget = Property<LPort?>('longEdgeTarget');

/// Whether any long-edge dummy in this chain has a label dummy.
/// ELK `InternalProperties.LONG_EDGE_HAS_LABEL_DUMMIES`.
const longEdgeHasLabelDummies = Property<bool>('longEdgeHasLabelDummies', false);

/// Whether this long-edge dummy comes *before* the label dummy in its chain.
/// ELK `InternalProperties.LONG_EDGE_BEFORE_LABEL_DUMMY`.
const longEdgeBeforeLabelDummy =
    Property<bool>('longEdgeBeforeLabelDummy', false);

/// Per-port ratio or absolute position used by fixed-ratio port placement.
/// ELK `PortPlacementCalculator.PORT_RATIO_OR_POSITION`.
const portRatioOrPosition = Property<double>('portRatioOrPosition', 0.0);

/// Spacing between adjacent ports on the same node side (ELK
/// `SPACING_PORT_PORT`).  Default matches ELK's default of 10.
const spacingPortPort = Property<double>('spacingPortPort', 10.0);

// ---------------------------------------------------------------------------
// 1.  InnermostNodeMarginCalculator
// ---------------------------------------------------------------------------

/// Computes [LNode.margin] for every node in the graph so that the margin
/// forms a bounding box around the node box and all of its ports (and labels
/// when present).
///
/// Faithful port of
/// `intermediate/InnermostNodeMarginCalculator.java` (which delegates to
/// `NodeMarginCalculator` with `excludeEdgeHeadTailLabels()`).
///
/// Scope simplification: edge head/tail labels are excluded (matching the
/// `excludeEdgeHeadTailLabels()` call in the Java). Node labels and port
/// labels are included if present.
class InnermostNodeMarginCalculator implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        _processNode(node);
      }
    }
    // Also cover layerless nodes (pre-layering pass, rarely needed here but
    // matches ELK's "adapt whole graph" call).
    for (final node in graph.layerlessNodes) {
      _processNode(node);
    }
  }

  /// Mirrors `NodeMarginCalculator.processNode` with
  /// `includeEdgeHeadTailLabels = false`.
  void _processNode(LNode node) {
    // Bounding box starts identical to the node box (in absolute coords).
    double bbLeft = node.position.x;
    double bbTop = node.position.y;
    double bbRight = node.position.x + node.size.x;
    double bbBottom = node.position.y + node.size.y;

    // Expand for node labels.
    for (final label in node.labels) {
      final lx = node.position.x + label.position.x;
      final ly = node.position.y + label.position.y;
      bbLeft = _min(bbLeft, lx);
      bbTop = _min(bbTop, ly);
      bbRight = _max(bbRight, lx + label.size.x);
      bbBottom = _max(bbBottom, ly + label.size.y);
    }

    // Expand for ports and their labels.
    for (final port in node.ports) {
      final px = node.position.x + port.position.x;
      final py = node.position.y + port.position.y;

      // The port box.
      bbLeft = _min(bbLeft, px);
      bbTop = _min(bbTop, py);
      bbRight = _max(bbRight, px + port.size.x);
      bbBottom = _max(bbBottom, py + port.size.y);

      // Port labels.
      for (final label in port.labels) {
        final lx = px + label.position.x;
        final ly = py + label.position.y;
        bbLeft = _min(bbLeft, lx);
        bbTop = _min(bbTop, ly);
        bbRight = _max(bbRight, lx + label.size.x);
        bbBottom = _max(bbBottom, ly + label.size.y);
      }
      // TODO(elk-faithful): head/tail edge labels are excluded here to match
      // `excludeEdgeHeadTailLabels()`.  Add them when edge-label support is
      // needed.
    }

    // Convert the absolute bounding box back to per-side margins (clamped to 0
    // to guard against floating-point noise, matching ELK's `Math.max(0, ...)`).
    node.margin.top = _max(0, node.position.y - bbTop);
    node.margin.bottom =
        _max(0, bbBottom - (node.position.y + node.size.y));
    node.margin.left = _max(0, node.position.x - bbLeft);
    node.margin.right =
        _max(0, bbRight - (node.position.x + node.size.x));
  }
}

// ---------------------------------------------------------------------------
// 2.  LabelAndNodeSizeProcessor
// ---------------------------------------------------------------------------

/// Positions ports along node borders and (for non-fixed-size configs) sizes
/// nodes to fit their ports and labels.
///
/// Faithful port of `intermediate/LabelAndNodeSizeProcessor.java`, which
/// delegates to `NodeLabelAndSizeCalculator.calculateLabelAndNodeSizes`.
///
/// Scope: default config — fixed node sizes, free E/W ports, no labels.
/// Ports are distributed evenly (CENTER alignment) along the E/W borders.
/// The x-coordinate of east ports is set to [LNode.size].x; west ports to
/// `-port.size.x` (i.e. outside the left edge), matching ELK's
/// `calculateVerticalPortXCoordinate` with no border offset.
class LabelAndNodeSizeProcessor implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        if (node.type == NodeType.normal) {
          _processNode(node, graph);
        }
        // TODO(elk-faithful): external-port dummies need label placement via
        // `placeExternalPortDummyLabels`; skip for now (no external ports in
        // default config).
      }
    }
  }

  void _processNode(LNode node, LGraph graph) {
    // TODO(elk-faithful): for non-fixed-size nodes ELK resizes the node to
    // fit its ports and labels.  We only handle the default: fixed size.

    final portPortSpacing = graph.getProperty(spacingPortPort);

    // Place E and W ports (vertical free placement = CENTER alignment).
    _placeVerticalFreePorts(
        node, PortSide.east, portPortSpacing);
    _placeVerticalFreePorts(
        node, PortSide.west, portPortSpacing);

    // TODO(elk-faithful): place N/S ports (horizontal free placement).
    // TODO(elk-faithful): place node labels.
    // TODO(elk-faithful): place port labels.
  }

  /// Mirrors `PortPlacementCalculator.placeVerticalFreePorts` for the CENTER
  /// alignment case (the default when there is only free port ordering).
  ///
  /// Port x-coordinate: east → [LNode.size].x, west → `-port.size.x`
  ///   (no border offset in the default config).
  /// Port y-coordinate: ports are stacked top-to-bottom, centred vertically
  ///   in the node height with [portPortSpacing] between them.
  void _placeVerticalFreePorts(
      LNode node, PortSide side, double portPortSpacing) {
    // Cross-hierarchy external ports carry a fixed position (set from the inner
    // boundary dummy after the nested layout) so the outer edge segment meets
    // the inner one orthogonally; never re-distribute those.
    final ports = node.ports
        .where((p) => p.side == side && !p.getProperty(crossHierarchyFixedPort))
        .toList();
    if (ports.isEmpty) return;

    // Order the ports along the side by the cross-axis order of the node each
    // edge connects to (the barycenter port order). Without this, two ports
    // can be placed opposite to their neighbours' order, forcing the edges to
    // cross right at the node — the defect ELK's AbstractBarycenterPort
    // distributor prevents. A port with no resolvable neighbour sorts last.
    double neighbourRank(LPort p) {
      final ranks = <double>[];
      for (final e in p.incomingEdges) {
        final i = e.source?.node.index;
        if (i != null && i >= 0) ranks.add(i.toDouble());
      }
      for (final e in p.outgoingEdges) {
        final i = e.target?.node.index;
        if (i != null && i >= 0) ranks.add(i.toDouble());
      }
      if (ranks.isEmpty) return double.maxFinite;
      return ranks.reduce((a, b) => a + b) / ranks.length;
    }

    // Secondary key for ports tied on neighbour node (e.g. two antiparallel
    // edges B→D and D→B both connect this node to the same neighbour): order
    // by where each edge attaches on the *other* node, so the two ends stay in
    // the same vertical order and the edges don't cross at this node. The
    // neighbour's ports are already placed when its layer precedes this one;
    // otherwise this reads 0 and the tie falls back to stable order.
    double connectedPortRank(LPort p) {
      final ys = <double>[];
      for (final e in p.incomingEdges) {
        final o = e.source;
        if (o != null) ys.add(o.absoluteAnchor.y);
      }
      for (final e in p.outgoingEdges) {
        final o = e.target;
        if (o != null) ys.add(o.absoluteAnchor.y);
      }
      if (ys.isEmpty) return double.maxFinite;
      return ys.reduce((a, b) => a + b) / ys.length;
    }

    ports.sort((a, b) {
      final byNode = neighbourRank(a).compareTo(neighbourRank(b));
      if (byNode != 0) return byNode;
      return connectedPortRank(a).compareTo(connectedPortRank(b));
    });

    final nodeWidth = node.size.x;
    final nodeHeight = node.size.y;

    // Total height occupied by all ports + inter-port gaps.
    double totalHeight = 0;
    for (final p in ports) {
      totalHeight += p.size.y;
    }
    totalHeight += (ports.length - 1) * portPortSpacing;

    // Starting y so that the group is centred in the node.
    double currentY = (nodeHeight - totalHeight) / 2;

    for (final port in ports) {
      // x: east ports flush with the right edge; west ports flush with the
      // left edge (negative, i.e. outside the node box).
      port.position.x =
          side == PortSide.east ? nodeWidth : -port.size.x;
      port.position.y = currentY;

      // Anchor = centre of the port face that connects to edges.
      port.anchor.x = side == PortSide.east ? 0 : port.size.x;
      port.anchor.y = port.size.y / 2;

      currentY += port.size.y + portPortSpacing;
    }
  }
}

// ---------------------------------------------------------------------------
// 3.  LayerSizeAndGraphHeightCalculator
// ---------------------------------------------------------------------------

/// Computes [Layer.size] for every layer and sets [LGraph.size].y and adjusts
/// [LGraph.offset].y so that the topmost node edge is at y = 0.
///
/// Faithful port of `intermediate/LayerSizeAndGraphHeightCalculator.java`.
///
/// Scope simplification: the `EXTERNAL_PORT` branch (which subtracts/adds
/// `SPACING_PORTS_SURROUNDING`) is stubbed out.
class LayerSizeAndGraphHeightCalculator implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    var foundNodes = false;

    for (final layer in graph.layers) {
      // Reset layer size.
      layer.size.x = 0;
      layer.size.y = 0;

      if (layer.nodes.isEmpty) continue;

      foundNodes = true;

      // Layer width = max of (node width + left/right margin).
      for (final node in layer.nodes) {
        final w = node.size.x + node.margin.left + node.margin.right;
        if (w > layer.size.x) layer.size.x = w;
      }

      // Layer height = distance from top edge of first node to bottom edge of
      // last node (including margins).
      final firstNode = layer.nodes.first;
      var top = firstNode.position.y - firstNode.margin.top;
      if (firstNode.type == NodeType.externalPort) {
        // TODO(elk-faithful): subtract graph.getProperty(spacingPortsSurrounding).top
        // for external port dummies.
      }

      final lastNode = layer.nodes.last;
      var bottom =
          lastNode.position.y + lastNode.size.y + lastNode.margin.bottom;
      if (lastNode.type == NodeType.externalPort) {
        // TODO(elk-faithful): add graph.getProperty(spacingPortsSurrounding).bottom
        // for external port dummies.
      }

      layer.size.y = bottom - top;

      if (top < minY) minY = top;
      if (bottom > maxY) maxY = bottom;
    }

    if (!foundNodes) {
      minY = 0;
      maxY = 0;
    }

    graph.size.y = maxY - minY;
    graph.offset.y -= minY;
  }
}

// ---------------------------------------------------------------------------
// 4.  HyperedgeDummyMerger
// ---------------------------------------------------------------------------

/// Merges adjacent long-edge dummy nodes that belong to the same hyperedge
/// (same source *or* target port) so that they share a single dummy and route
/// together.
///
/// Faithful port of `intermediate/HyperedgeDummyMerger.java`.
class HyperedgeDummyMerger implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    // Step 1: assign hyperedge ids to all ports via DFS.
    _identifyHyperedges(graph);

    // Step 2: iterate through layers and merge eligible adjacent dummies.
    for (final layer in graph.layers) {
      final nodes = layer.nodes;
      if (nodes.isEmpty) continue;

      LNode? lastNode;
      NodeType? lastNodeType;

      var nodeIndex = 0;
      while (nodeIndex < nodes.length) {
        final currNode = nodes[nodeIndex];
        final currNodeType = currNode.type;

        if (currNodeType == NodeType.longEdge &&
            lastNodeType == NodeType.longEdge &&
            lastNode != null) {
          final state = _checkMergeAllowed(currNode, lastNode);
          if (state.allowMerge) {
            _mergeNodes(currNode, lastNode, state.sameSource, state.sameTarget);
            // Remove currNode and keep lastNode as the effective current node.
            nodes.removeAt(nodeIndex);
            // Don't advance: re-check the new node at nodeIndex against lastNode
            // (which is still the merged node).
            continue;
          }
        }

        lastNode = currNode;
        lastNodeType = currNodeType;
        nodeIndex++;
      }
    }
  }

  /// Assigns a hyperedge group id to every port by DFS over the port
  /// connectivity graph (two ports in the same hyperedge share an id).
  ///
  /// Mirrors `HyperedgeDummyMerger.identifyHyperedges`.
  void _identifyHyperedges(LGraph graph) {
    // Collect all ports in layer order.
    final ports = <LPort>[];
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        ports.addAll(node.ports);
      }
    }

    // Mark all unvisited.
    for (final p in ports) {
      p.id = -1;
    }

    var index = 0;
    for (final p in ports) {
      if (p.id == -1) {
        _dfs(p, index++);
      }
    }
  }

  void _dfs(LPort p, int index) {
    p.id = index;
    // Follow all edges connected to this port (both directions).
    for (final e in p.connectedEdges) {
      final other = e.source == p ? e.target : e.source;
      if (other != null && other.id == -1) {
        _dfs(other, index);
      }
    }
    // If the port's node is a long-edge dummy, also propagate to the dummy's
    // other ports (so the whole dummy gets the same id).
    if (p.node.type == NodeType.longEdge) {
      for (final p2 in p.node.ports) {
        if (p2 != p && p2.id == -1) {
          _dfs(p2, index);
        }
      }
    }
  }

  /// Mirrors `HyperedgeDummyMerger.checkMergeAllowed`.
  _MergeState _checkMergeAllowed(LNode currNode, LNode lastNode) {
    final currHasLabel =
        currNode.getProperty(longEdgeHasLabelDummies);
    final lastHasLabel =
        lastNode.getProperty(longEdgeHasLabelDummies);

    final currSource = currNode.getProperty(longEdgeSource);
    final lastSource = lastNode.getProperty(longEdgeSource);
    final currTarget = currNode.getProperty(longEdgeTarget);
    final lastTarget = lastNode.getProperty(longEdgeTarget);

    final sameSource =
        currSource != null && identical(currSource, lastSource);
    final sameTarget =
        currTarget != null && identical(currTarget, lastTarget);

    if (!currHasLabel && !lastHasLabel) {
      // No label dummies in either chain: merge when the ports share the same
      // hyperedge id (ELK: "both ports have the same id").
      final currFirstPortId =
          currNode.ports.isNotEmpty ? currNode.ports.first.id : -2;
      final lastFirstPortId =
          lastNode.ports.isNotEmpty ? lastNode.ports.first.id : -3;
      return _MergeState(
        allowMerge: currFirstPortId == lastFirstPortId,
        sameSource: sameSource,
        sameTarget: sameTarget,
      );
    }

    // One or both chains have label dummies: merge only if we are entirely
    // before or entirely after the label dummy in each chain.
    final eligibleForSourceMerging =
        (!currNode.getProperty(longEdgeHasLabelDummies) ||
            currNode.getProperty(longEdgeBeforeLabelDummy)) &&
        (!lastNode.getProperty(longEdgeHasLabelDummies) ||
            lastNode.getProperty(longEdgeBeforeLabelDummy));

    final eligibleForTargetMerging =
        (!currNode.getProperty(longEdgeHasLabelDummies) ||
            !currNode.getProperty(longEdgeBeforeLabelDummy)) &&
        (!lastNode.getProperty(longEdgeHasLabelDummies) ||
            !lastNode.getProperty(longEdgeBeforeLabelDummy));

    return _MergeState(
      allowMerge: (sameSource && eligibleForSourceMerging) ||
          (sameTarget && eligibleForTargetMerging),
      sameSource: sameSource,
      sameTarget: sameTarget,
    );
  }

  /// Reroutes all edges from [mergeSource]'s ports to [mergeTarget]'s
  /// matching W (input) and E (output) ports, then optionally clears the
  /// [longEdgeSource] / [longEdgeTarget] properties on [mergeTarget].
  ///
  /// Mirrors `HyperedgeDummyMerger.mergeNodes`.
  void _mergeNodes(
      LNode mergeSource, LNode mergeTarget, bool keepSource, bool keepTarget) {
    // Long-edge dummies always have exactly one west (input) and one east
    // (output) port.
    final targetIn = mergeTarget.ports
        .firstWhere((p) => p.side == PortSide.west);
    final targetOut = mergeTarget.ports
        .firstWhere((p) => p.side == PortSide.east);

    for (final port in mergeSource.ports) {
      while (port.incomingEdges.isNotEmpty) {
        port.incomingEdges.first.target = targetIn;
      }
      while (port.outgoingEdges.isNotEmpty) {
        port.outgoingEdges.first.source = targetOut;
      }
    }

    if (!keepSource) {
      mergeTarget.setProperty(longEdgeSource, null);
    }
    if (!keepTarget) {
      mergeTarget.setProperty(longEdgeTarget, null);
    }
  }
}

/// Result of a merge-eligibility check.
class _MergeState {
  const _MergeState({
    required this.allowMerge,
    required this.sameSource,
    required this.sameTarget,
  });
  final bool allowMerge;
  final bool sameSource;
  final bool sameTarget;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

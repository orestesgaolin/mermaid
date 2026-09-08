/// Faithful port of ELK's self-loop intermediate processors:
///   • [SelfLoopPreProcessor]  — hides self-loop edges from the main pipeline
///   • [SelfLoopRouter]        — routes each self-loop orthogonally around its
///                               node and writes bend points (node-relative)
///   • [SelfLoopPostProcessor] — reconnects hidden edges and translates bend
///                               points to graph-absolute coordinates
///
/// Java originals:
///   `intermediate/SelfLoopPreProcessor.java`
///   `intermediate/SelfLoopRouter.java`  (delegates to
///     `intermediate/loops/routing/OrthogonalSelfLoopRouter.java`)
///   `intermediate/SelfLoopPostProcessor.java`
///
/// Supports one-side, adjacent-side, and opposing-side orthogonal self-loops
/// on `NodeType.normal` nodes, with independent spacing on each side. The full hyper-loop
/// label machinery (`SelfHyperLoopLabels`, `LabelPlacer`) is deferred.
///
/// ## Self-loop port side
/// With no explicit port constraints the preprocessor has no side information
/// yet. All free self-loop ports are assigned to the NORTH side and stacked
/// outward; this matches ELK's default `SELF_LOOP_DISTRIBUTION = NORTH`.
///
/// ## Coordinate convention
/// The router works in *node-relative* space (origin = node top-left). The
/// postprocessor translates every bend point to graph-absolute coordinates by
/// adding `lNode.position`.
library;

import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// Property constants
// ---------------------------------------------------------------------------

/// Per-node: [SelfLoopHolder] built by the preprocessor.
///
/// Property id: `'selfLoopHolder'`
const _selfLoopHolder = Property<SelfLoopHolder?>('selfLoopHolder');

const selfLoopNodeSpacing = Property<double>('selfLoopNodeSpacing', 10.0);
const selfLoopEdgeSpacing = Property<double>('selfLoopEdgeSpacing', 10.0);

// ---------------------------------------------------------------------------
// Internal data model  (mirrors SelfLoopHolder / SelfLoopEdge / SelfLoopPort)
// ---------------------------------------------------------------------------

/// Holds all self-loop state for a single [LNode].
class SelfLoopHolder {
  SelfLoopHolder(this.node)
      : originalMargin = LInsets(node.margin.top, node.margin.right,
            node.margin.bottom, node.margin.left);

  final LNode node;
  final LInsets originalMargin;

  /// All self-loop edges on this node, in original port-list order.
  final List<_SelfLoopEdge> edges = [];

  /// Per-side: the number of routing slots consumed (= stack depth).
  final Map<PortSide, int> routingSlotCount = {
    PortSide.north: 0,
    PortSide.east: 0,
    PortSide.south: 0,
    PortSide.west: 0,
  };
}

/// A self-loop edge together with the ports it connects and its assigned routing
/// slot on a given side.
class _SelfLoopEdge {
  _SelfLoopEdge(this.lEdge, this.sourcePort, this.targetPort);

  final LEdge lEdge;
  LPort sourcePort;
  LPort targetPort;

  /// Which side the loop is routed on (always a single side in the common case).
  PortSide routingSide = PortSide.north;

  /// Depth within the side's stack (0 = closest to the node).
  int routingSlot = 0;
  int sourceSlot = 0;
  int targetSlot = 0;
}

// ---------------------------------------------------------------------------
// Stage 1: SelfLoopPreProcessor
// ---------------------------------------------------------------------------

/// Hides self-loop edges from the rest of the pipeline so layering and edge
/// routing don't see them.
///
/// For each `NodeType.normal` node that has at least one self-loop:
///   1. Creates a [SelfLoopHolder] and attaches it via [_selfLoopHolder].
///   2. Temporarily detaches self-loop edges (`source = null`, `target = null`)
///      so they are invisible to all pipeline steps that follow.
///
/// Mirrors `SelfLoopPreProcessor.java`. Runs **before P1** (cycle breaking).
class SelfLoopPreProcessor implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        _processNode(node);
      }
    }
    // Also handle layerless nodes (called before P1, so nodes are still here).
    for (final node in graph.layerlessNodes) {
      _processNode(node);
    }
  }

  void _processNode(LNode node) {
    if (node.type != NodeType.normal) return;

    // Collect self-loop edges from all ports.
    final selfLoopEdges = <_SelfLoopEdge>[];
    for (final port in node.ports) {
      // outgoing edges whose target is on the same node.
      for (final edge in port.outgoingEdges.toList()) {
        if (edge.isSelfLoop) {
          final target = edge.target;
          if (target == null) continue;
          selfLoopEdges.add(_SelfLoopEdge(edge, port, target));
        }
      }
    }

    if (selfLoopEdges.isEmpty) return;

    final holder = SelfLoopHolder(node);
    holder.edges.addAll(selfLoopEdges);
    node.setProperty(_selfLoopHolder, holder);
    final counts = <PortSide, int>{};
    for (final loop in selfLoopEdges) {
      final source = loop.sourcePort.side == PortSide.undefined
          ? PortSide.north
          : loop.sourcePort.side;
      final target = loop.targetPort.side == PortSide.undefined
          ? source
          : loop.targetPort.side;
      counts[source] = (counts[source] ?? 0) + 1;
      if (target != source) counts[target] = (counts[target] ?? 0) + 1;
    }
    final nodeGap = node.graph.getProperty(selfLoopNodeSpacing);
    final edgeGap = node.graph.getProperty(selfLoopEdgeSpacing);
    double extra(PortSide side) => (counts[side] ?? 0) == 0
        ? 0
        : nodeGap + ((counts[side] ?? 1) - 1) * edgeGap;
    node.margin.top += extra(PortSide.north);
    node.margin.right += extra(PortSide.east);
    node.margin.bottom += extra(PortSide.south);
    node.margin.left += extra(PortSide.west);


    // Detach edges from the port graph so the pipeline doesn't see them.
    for (final sle in selfLoopEdges) {
      sle.lEdge.source = null;
      sle.lEdge.target = null;
    }
  }
}


// ---------------------------------------------------------------------------
// Stage 2: SelfLoopRouter
// ---------------------------------------------------------------------------

/// Routes self-loop edges orthogonally and writes their bend points in
/// node-relative coordinates.
///
/// Algorithm (faithful to `OrthogonalSelfLoopRouter.java` for the common case):
///
/// For each node with a [SelfLoopHolder]:
///   1. Assign all loops to the NORTH side (default distribution).
///   2. Stack them outward: slot 0 is closest to the node, increasing slots go
///      further out.
///   3. Compute 2 bend points per loop (left and right outer bends).
///
/// Spacing constants mirror ELK's `SelfLoopProperties` defaults:
///   - `nodeSLDistance` = 10  (gap between node border and slot 0 loop line)
///   - `edgeEdgeDistance` = 10 (pitch between successive routing slots)
///
/// Runs **after P5** (edge routing), once node positions are set, but the
/// [SelfLoopPostProcessor] translates the results to absolute coords, so the
/// router works in node-relative space.
///
/// Mirrors `SelfLoopRouter.java` / `OrthogonalSelfLoopRouter.java`.
class SelfLoopRouter implements ILayoutProcessor {
  /// Gap from the node border (or margin) to the innermost routing slot.

  /// Centre-to-centre spacing between consecutive routing slots.

  @override
  void process(LGraph graph) {
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        _routeNode(node);
      }
    }
    // Layerless nodes (shouldn't normally have layout yet, but be safe).
    for (final node in graph.layerlessNodes) {
      _routeNode(node);
    }
  }

  void _routeNode(LNode node) {
    final holder = node.getProperty(_selfLoopHolder);
    if (holder == null) return;

    // --- 1. Assign routing side and slot for each self-loop -----------------
    // Simple strategy: all loops on NORTH, stacked outward.
    // A future improvement can distribute across sides using the port's side
    // and the `SELF_LOOP_DISTRIBUTION` option.
    final slots = <PortSide, int>{};
    for (final sle in holder.edges) {
      final sourceSide = sle.sourcePort.side;
      final targetSide = sle.targetPort.side;
      sle.routingSide = sourceSide == PortSide.undefined
          ? PortSide.north
          : sourceSide;
      sle.sourceSlot = slots[sle.routingSide] ?? 0;
      slots[sle.routingSide] = sle.sourceSlot + 1;
      final resolvedTarget = targetSide == PortSide.undefined
          ? sle.routingSide
          : targetSide;
      if (resolvedTarget == sle.routingSide) {
        sle.targetSlot = sle.sourceSlot;
      } else {
        sle.targetSlot = slots[resolvedTarget] ?? 0;
        slots[resolvedTarget] = sle.targetSlot + 1;
      }
      sle.routingSlot = sle.sourceSlot;
    }
    holder.routingSlotCount.addAll(slots);

    // --- 2. Compute routing slot positions -----------------------------------
    // NORTH: routing lines sit *above* the node (negative y in node-relative
    // coords). Slot 0 is at y = -(margin.top + nodeSLDistance), each additional
    // slot moves further upward by edgeEdgeDistance.
    //
    // The position is the y coordinate of the horizontal run of the loop.
    final marginTop = holder.originalMargin.top;
    final marginEast = holder.originalMargin.right;
    final marginSouth = holder.originalMargin.bottom;
    final marginWest = holder.originalMargin.left;

    // Pre-compute slot y/x positions for all four sides (mirrors
    // OrthogonalSelfLoopRouter.computeRoutingSlotPositions).
    // Only NORTH is used by the default strategy, but all four are computed
    // for completeness and future multi-side support.
    final nodeDistance = node.graph.getProperty(selfLoopNodeSpacing);
    final edgeDistance = node.graph.getProperty(selfLoopEdgeSpacing);
    Map<PortSide, double Function(int slot)> slotPos = {
      // NORTH: grows negative (upward)
      PortSide.north: (slot) =>
          -(marginTop + nodeDistance + slot * edgeDistance),
      // EAST: grows positive (rightward)
      PortSide.east: (slot) =>
          node.size.x + marginEast + nodeDistance + slot * edgeDistance,
      // SOUTH: grows positive (downward)
      PortSide.south: (slot) =>
          node.size.y + marginSouth + nodeDistance + slot * edgeDistance,
      // WEST: grows negative (leftward)
      PortSide.west: (slot) =>
          -(marginWest + nodeDistance + slot * edgeDistance),
    };

    // --- 3. Compute bend points for each self-loop --------------------------
    for (final sle in holder.edges) {
      _computeBendPoints(sle, node, slotPos);
    }
  }

  /// Computes the 2 bend points for a single one-sided self-loop.
  ///
  /// A one-sided NORTH loop over ports [sp] (source) and [tp] (target) looks
  /// like:
  ///
  /// ```
  ///  BP1 ──── BP2
  ///   │          │
  ///  sp  [node]  tp
  /// ```
  ///
  /// BP1 = (sp.anchorX, routeY)  — outer bend at source port
  /// BP2 = (tp.anchorX, routeY)  — outer bend at target port
  ///
  /// For EAST/WEST/SOUTH the coordinates are transposed analogously.
  void _computeBendPoints(
    _SelfLoopEdge sle,
    LNode node,
    Map<PortSide, double Function(int slot)> slotPos,
  ) {
    sle.lEdge.bendPoints.clear();

    final side = sle.routingSide;
    final routeCoord = slotPos[side]!(sle.routingSlot);

    // Node-relative anchor of each port.
    // Port positions are relative to the node top-left; anchor is within the
    // port. We want the point on the port's outward face where the edge leaves,
    // i.e. port.position + port.anchor.
    final spAnchorX = sle.sourcePort.position.x + sle.sourcePort.anchor.x;
    final spAnchorY = sle.sourcePort.position.y + sle.sourcePort.anchor.y;
    final tpAnchorX = sle.targetPort.position.x + sle.targetPort.anchor.x;
    final tpAnchorY = sle.targetPort.position.y + sle.targetPort.anchor.y;

    final targetSide = sle.targetPort.side == PortSide.undefined
        ? side
        : sle.targetPort.side;
    if (targetSide != side) {
      final sourceRoute = slotPos[side]!(sle.sourceSlot);
      final targetRoute = slotPos[targetSide]!(sle.targetSlot);
      KVector outward(PortSide portSide, double route, double x, double y) =>
          switch (portSide) {
            PortSide.north || PortSide.south => KVector(x, route),
            PortSide.east || PortSide.west => KVector(route, y),
            PortSide.undefined => KVector(x, route),
          };
      final sourceOut = outward(side, sourceRoute, spAnchorX, spAnchorY);
      final targetOut = outward(targetSide, targetRoute, tpAnchorX, tpAnchorY);
      sle.lEdge.bendPoints.add(sourceOut);
      final opposite =
          (side == PortSide.north && targetSide == PortSide.south) ||
          (side == PortSide.south && targetSide == PortSide.north) ||
          (side == PortSide.east && targetSide == PortSide.west) ||
          (side == PortSide.west && targetSide == PortSide.east);
      if (opposite) {
        if (side == PortSide.north || side == PortSide.south) {
          final around = slotPos[PortSide.east]!(0);
          sle.lEdge.bendPoints
            ..add(KVector(around, sourceRoute))
            ..add(KVector(around, targetRoute));
        } else {
          final around = slotPos[PortSide.north]!(0);
          sle.lEdge.bendPoints
            ..add(KVector(sourceRoute, around))
            ..add(KVector(targetRoute, around));
        }
      } else {
        sle.lEdge.bendPoints.add(
          side == PortSide.north || side == PortSide.south
              ? KVector(targetOut.x, sourceOut.y)
              : KVector(sourceOut.x, targetOut.y),
        );
      }
      sle.lEdge.bendPoints.add(targetOut);
      return;
    }

    // For a one-sided loop the bend points are:
    //   NORTH/SOUTH: horizontal run at routeCoord, vertical stubs at each port.
    //   EAST/WEST:   vertical run at routeCoord, horizontal stubs at each port.
    switch (side) {
      case PortSide.north:
      case PortSide.south:
        // BP at source: same x as source port anchor, y = route line
        sle.lEdge.bendPoints.add(KVector(spAnchorX, routeCoord));
        // BP at target: same x as target port anchor, y = route line
        sle.lEdge.bendPoints.add(KVector(tpAnchorX, routeCoord));

      case PortSide.east:
      case PortSide.west:
        // BP at source: x = route line, same y as source port anchor
        sle.lEdge.bendPoints.add(KVector(routeCoord, spAnchorY));
        // BP at target: x = route line, same y as target port anchor
        sle.lEdge.bendPoints.add(KVector(routeCoord, tpAnchorY));

      case PortSide.undefined:
        // Fallback: route on NORTH.
        final y =
            -(node.margin.top +
                node.graph.getProperty(selfLoopNodeSpacing) +
                sle.routingSlot * node.graph.getProperty(selfLoopEdgeSpacing));
        sle.lEdge.bendPoints.add(KVector(spAnchorX, y));
        sle.lEdge.bendPoints.add(KVector(tpAnchorX, y));
    }

  }
}

// ---------------------------------------------------------------------------
// Stage 3: SelfLoopPostProcessor
// ---------------------------------------------------------------------------

/// Reconnects self-loop edges and translates their bend points from
/// node-relative to graph-absolute coordinates.
///
/// For every node with a [SelfLoopHolder]:
///   1. Restores `lEdge.source` / `lEdge.target` to the original ports.
///   2. Shifts every bend point by `node.position` (node-relative → absolute).
///
/// Mirrors `SelfLoopPostProcessor.java`. Runs **after P5**.
class SelfLoopPostProcessor implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        _postprocessNode(node);
      }
    }
    for (final node in graph.layerlessNodes) {
      _postprocessNode(node);
    }
  }

  void _postprocessNode(LNode node) {
    final holder = node.getProperty(_selfLoopHolder);
    if (holder == null) return;

    for (final sle in holder.edges) {
      // Reconnect the edge (restores it to the live port graph).
      sle.lEdge.source = sle.sourcePort;
      sle.lEdge.target = sle.targetPort;

      // Translate node-relative bend points to graph-absolute coords.
      final ox = node.position.x;
      final oy = node.position.y;
      for (final bp in sle.lEdge.bendPoints.points) {
        bp.x += ox;
        bp.y += oy;
      }
    }
  }
}

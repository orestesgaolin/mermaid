/// Faithful port of three ELK layered intermediate processors:
///   • `LongEdgeSplitter`  — splits edges that span >1 layer into dummy chains
///   • `LongEdgeJoiner`    — merges dummy chains back and collects bend points
///   • `ReversedEdgeRestorer` — re-reverses edges that cycle-breaking flipped
///
/// Java originals live in
///   `org.eclipse.elk.alg.layered.intermediate/LongEdgeSplitter.java`
///   `org.eclipse.elk.alg.layered.intermediate/LongEdgeJoiner.java`
///   `org.eclipse.elk.alg.layered.intermediate/ReversedEdgeRestorer.java`
library;

import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// Shared Property constants (splitter writes, joiner reads)
// Mirrors InternalProperties.LONG_EDGE_SOURCE / LONG_EDGE_TARGET.
// ---------------------------------------------------------------------------

/// The original source port of the long-edge chain.
const longEdgeSource = Property<LPort?>('longEdgeSource');

/// The original target port of the long-edge chain.
const longEdgeTarget = Property<LPort?>('longEdgeTarget');

// ---------------------------------------------------------------------------
// LongEdgeSplitter
// ---------------------------------------------------------------------------

/// Splits edges that connect nodes more than one layer apart by inserting
/// [NodeType.longEdge] dummy nodes — one per intermediate layer — so the
/// layering becomes *proper* (every edge connects adjacent layers only).
///
/// Port of `LongEdgeSplitter.java`. Runs before phase 3.
class LongEdgeSplitter implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    // Nothing to do if there are fewer than three layers (no edge can span >1).
    if (graph.layers.length <= 2) return;

    // Walk through layers pairwise: layer[i] → layer[i+1].
    for (var i = 0; i < graph.layers.length - 1; i++) {
      final layer = graph.layers[i];
      final nextLayer = graph.layers[i + 1];

      // Snapshot of nodes to avoid mutating while iterating.
      for (final node in layer.nodes.toList()) {
        for (final port in node.ports.toList()) {
          for (final edge in port.outgoingEdges.toList()) {
            if (edge.isSelfLoop) {
              // TODO(elk-faithful): self-loops are skipped in this port.
              continue;
            }
            final targetLayer = edge.target?.node.layer;
            // Only split if the edge skips over nextLayer.
            if (targetLayer != layer && targetLayer != nextLayer) {
              final dummy = _createDummyNode(graph, nextLayer, edge);
              _splitEdge(edge, dummy);
            }
          }
        }
      }
    }
  }

  /// Creates a [NodeType.longEdge] dummy node in [targetLayer].
  LNode _createDummyNode(LGraph graph, Layer targetLayer, LEdge edgeToSplit) {
    final dummy = LNode(graph)
      ..type = NodeType.longEdge
      ..layer = targetLayer
      ..graph = graph;
    targetLayer.nodes.add(dummy);
    return dummy;
  }

  /// Reroutes [edge] through [dummyNode], introducing a new continuation edge.
  ///
  /// After this call:
  ///   original source → dummyInput  (the original [edge], shortened)
  ///   dummyOutput     → old target  (the new continuation edge returned)
  static LEdge _splitEdge(LEdge edge, LNode dummyNode) {
    final oldTarget = edge.target!;

    // Dummy input port (west = incoming).
    final dummyInput = LPort(dummyNode)
      ..side = PortSide.west
      ..node = dummyNode;
    dummyNode.ports.add(dummyInput);

    // Dummy output port (east = outgoing).
    final dummyOutput = LPort(dummyNode)
      ..side = PortSide.east
      ..node = dummyNode;
    dummyNode.ports.add(dummyOutput);

    // Reroute original edge to end at dummy input.
    edge.target = dummyInput;

    // New continuation edge from dummy output to the old target.
    final dummyEdge = LEdge()
      ..copyPropertiesFrom(edge)
      ..source = dummyOutput
      ..target = oldTarget;

    // TODO(elk-faithful): JUNCTION_POINTS cleared on dummyEdge (LayeredOptions
    // not ported).

    _setDummyNodeProperties(dummyNode, edge, dummyEdge);

    // TODO(elk-faithful): HEAD edge-label migration (moveHeadLabels) skipped;
    // edge labels are not part of this port's scope.

    return dummyEdge;
  }

  /// Mirrors `setDummyNodeProperties`: propagates [longEdgeSource] /
  /// [longEdgeTarget] along the dummy chain.
  static void _setDummyNodeProperties(
      LNode dummyNode, LEdge inEdge, LEdge outEdge) {
    final inSrcNode = inEdge.source!.node;
    final outTgtNode = outEdge.target!.node;

    if (inSrcNode.type == NodeType.longEdge) {
      // Propagate from the preceding dummy.
      dummyNode.setProperty(longEdgeSource, inSrcNode.getProperty(longEdgeSource));
      dummyNode.setProperty(longEdgeTarget, inSrcNode.getProperty(longEdgeTarget));
    } else if (outTgtNode.type == NodeType.longEdge) {
      // TODO(elk-faithful): LABEL dummy node handling skipped.
      dummyNode.setProperty(longEdgeSource, outTgtNode.getProperty(longEdgeSource));
      dummyNode.setProperty(longEdgeTarget, outTgtNode.getProperty(longEdgeTarget));
    } else {
      // First dummy in the chain: source is the in-edge's source port, target
      // is the out-edge's target port.
      dummyNode.setProperty(longEdgeSource, inEdge.source);
      dummyNode.setProperty(longEdgeTarget, outEdge.target);
    }
  }
}

// ---------------------------------------------------------------------------
// LongEdgeJoiner
// ---------------------------------------------------------------------------

/// Removes [NodeType.longEdge] dummy nodes after edge routing, merging the
/// chain of dummy edges back into the original surviving edge and collecting
/// all bend points.
///
/// Port of `LongEdgeJoiner.java`. Runs after phase 5.
class LongEdgeJoiner implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    // TODO(elk-faithful): UNNECESSARY_BENDPOINTS option not ported; the bend
    // point at the dummy position is never added.
    const addUnnecessaryBendpoints = false;

    for (final layer in graph.layers) {
      // Remove LONG_EDGE dummies while iterating (use index loop for safe removal).
      for (var i = layer.nodes.length - 1; i >= 0; i--) {
        final node = layer.nodes[i];
        if (node.type == NodeType.longEdge) {
          _joinAt(node, addUnnecessaryBendpoints);
          layer.nodes.removeAt(i);
        }
      }
    }
  }

  /// Joins the edges connected to [longEdgeDummy].
  ///
  /// Mirrors `LongEdgeJoiner.joinAt`.  The western (input) port's edges
  /// *survive*; the eastern (output) port's edges are *discarded*.
  static void _joinAt(LNode longEdgeDummy, bool addUnnecessaryBendpoints) {
    // Find the single west (input) and east (output) port.
    final inputPort = longEdgeDummy.ports
        .firstWhere((p) => p.side == PortSide.west);
    final outputPort = longEdgeDummy.ports
        .firstWhere((p) => p.side == PortSide.east);

    // Optional bend point at the dummy node position.
    // The Java uses the first port's absoluteAnchor.
    final unnecessaryBp = addUnnecessaryBendpoints
        ? longEdgeDummy.ports.first.absoluteAnchor
        : null;

    final inputEdges = inputPort.incomingEdges;
    final outputEdges = outputPort.outgoingEdges;

    // The Java comment: edges at equal indices on input/output belong to the
    // same long edge (invariant maintained by LongEdgeSplitter).
    var count = inputEdges.length;
    while (count-- > 0) {
      final survivingEdge = inputEdges[0];
      final droppedEdge = outputEdges[0];

      // Reconnect survivingEdge to droppedEdge's target, preserving the index
      // that the dropped edge occupied (mirrors setTargetAndInsertAtIndex,
      // the KIPRA-1670 fix in the Java source).
      final targetPort = droppedEdge.target!;
      final targetIncoming = targetPort.incomingEdges;
      final insertIdx = targetIncoming.indexOf(droppedEdge);

      // Use the public setter: removes from old target's incomingEdges,
      // appends to new target's incomingEdges.
      survivingEdge.target = targetPort;

      // Fix up the insertion order: the setter appended, but we need the edge
      // at the position where droppedEdge was (which is now insertIdx+1 since
      // the surviving edge was appended after it — but droppedEdge is still
      // present at this point, so insertIdx is still valid).
      if (insertIdx >= 0) {
        // The surviving edge was just appended; move it to insertIdx.
        targetIncoming.remove(survivingEdge);
        targetIncoming.insert(insertIdx, survivingEdge);
      }

      // Disconnect dropped edge.
      droppedEdge.source = null;
      droppedEdge.target = null;

      // Merge bend points: surviving ++ [optional bp] ++ dropped.
      if (unnecessaryBp != null) {
        survivingEdge.bendPoints.add(unnecessaryBp.clone());
      }
      for (final bp in droppedEdge.bendPoints.points) {
        survivingEdge.bendPoints.add(bp.clone());
      }

      // Merge labels.
      survivingEdge.labels.addAll(droppedEdge.labels);

      // TODO(elk-faithful): JUNCTION_POINTS merging skipped (LayeredOptions not
      // ported).
    }
  }
}

// ---------------------------------------------------------------------------
// ReversedEdgeRestorer
// ---------------------------------------------------------------------------

/// Restores the direction of every edge that cycle-breaking reversed (i.e.
/// [LEdge.reversed] == true), also reversing their accumulated bend points.
///
/// Port of `ReversedEdgeRestorer.java`. Runs after phase 5.
class ReversedEdgeRestorer implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        // Iterate over a snapshot to avoid concurrent-modification issues.
        for (final port in node.ports.toList()) {
          for (final edge in port.outgoingEdges.toList()) {
            if (edge.reversed) {
              // Reverse source/target and toggle the flag.
              edge.reverse();
              // Also reverse the bend-point list (the Java does this too via
              // KVectorChain.reverse inside LEdge.reverse).
              _reverseBendPoints(edge);
            }
          }
        }
      }
    }
  }

  void _reverseBendPoints(LEdge edge) {
    final pts = edge.bendPoints.points;
    for (var lo = 0, hi = pts.length - 1; lo < hi; lo++, hi--) {
      final tmp = pts[lo];
      pts[lo] = pts[hi];
      pts[hi] = tmp;
    }
  }
}

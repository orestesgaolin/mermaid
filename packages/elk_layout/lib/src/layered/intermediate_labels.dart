/// Faithful port of two ELK layered intermediate processors:
///   • `LabelDummyInserter` — inserts [NodeType.label] dummy nodes before P2,
///     one per edge that carries center labels, sized to the labels and
///     splitting the edge so the dummy participates in layering/placement.
///   • `LabelDummyRemover`  — after P5, reads the dummy's computed position,
///     writes it back as each label's position, rejoins the edge through the
///     dummy's location, and removes the dummy.
///
/// Java originals live in
///   `org.eclipse.elk.alg.layered.intermediate/LabelDummyInserter.java`
///   `org.eclipse.elk.alg.layered.intermediate/LabelDummyRemover.java`
///
/// Refinement processors (LabelDummySwitcher, LabelSideSelector) are stubbed
/// with `// TODO(elk-faithful)` comments.
library;

import 'intermediate_edges.dart' show longEdgeSource, longEdgeTarget;
import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// Shared Property constants
// Inserter writes these; remover reads them.  Mirrors ELK's InternalProperties.
// ---------------------------------------------------------------------------

/// The list of [LLabel]s that have been moved from the edge onto the label
/// dummy node. Mirrors `InternalProperties.REPRESENTED_LABELS`.
const representedLabels =
    Property<List<LLabel>?>('labelDummy.representedLabels');

/// The original [LEdge] that the label dummy was inserted for. Mirrors
/// `InternalProperties.ORIGIN` (in the label-dummy context).
const labelDummyOriginEdge = Property<LEdge?>('labelDummy.originEdge');

/// Default spacing between an edge line and its label (px).
/// Mirrors `LayeredOptions.SPACING_EDGE_LABEL` default.
const double _defaultEdgeLabelSpacing = 2.0;

/// Default spacing between stacked labels (px).
/// Mirrors `LayeredOptions.SPACING_LABEL_LABEL` default.
const double _defaultLabelLabelSpacing = 0.0;

// ---------------------------------------------------------------------------
// LabelDummyInserter
// ---------------------------------------------------------------------------

/// Inserts [NodeType.label] dummy nodes for every non-self-loop edge that
/// carries at least one label. The dummy is sized to the label(s) and splits
/// the edge so the dummy participates in layering and placement, reserving
/// the required space.
///
/// Port of `LabelDummyInserter.java`. Slot: **before P2** (after P1 /
/// cycle-breaking, before the network-simplex layerer).
///
/// TODO(elk-faithful): head/tail label placement (EdgeLabelPlacement.HEAD /
/// TAIL) is not handled; only center labels are supported here.
class LabelDummyInserter implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    // Collect new dummies first; we cannot mutate layerlessNodes while iterating.
    final newDummies = <LNode>[];

    for (final node in graph.layerlessNodes.toList()) {
      for (final port in node.ports.toList()) {
        for (final edge in port.outgoingEdges.toList()) {
          if (_edgeNeedsProcessing(edge)) {
            final dummy = _createLabelDummy(graph, edge);
            newDummies.add(dummy);
          }
        }
      }
    }

    graph.layerlessNodes.addAll(newDummies);
  }

  /// An edge needs processing if it is not a self-loop and has at least one
  /// label. (ELK additionally filters to CENTER placement; we treat any label
  /// as a center label here and TODO the head/tail distinction.)
  bool _edgeNeedsProcessing(LEdge edge) {
    if (edge.isSelfLoop) return false;
    return edge.labels.isNotEmpty;
  }

  /// Creates the label dummy node, sizes it to the labels, and splits [edge]
  /// so the dummy lies mid-edge.
  ///
  /// Mirrors `createLabelDummy` + the label-iteration block in `process`.
  LNode _createLabelDummy(LGraph graph, LEdge edge) {
    // Collect labels that will be represented by this dummy.
    final labels = List<LLabel>.from(edge.labels);

    final dummy = LNode(graph)
      ..type = NodeType.label
      ..graph = graph;

    // Wire up the cross-references the remover needs.
    dummy.setProperty(labelDummyOriginEdge, edge);
    dummy.setProperty(representedLabels, labels);

    // Propagate long-edge source/target so this dummy is transparent to
    // LongEdgeSplitter/Joiner chain traversal.
    dummy.setProperty(longEdgeSource, edge.source);
    dummy.setProperty(longEdgeTarget, edge.target);

    // --- Compute dummy size (mirrors ELK's label-stacking logic) -----------
    // Internal flow direction is always RIGHT (horizontal), so labels stack
    // vertically (one per row), widths take the max.
    // TODO(elk-faithful): DIRECTION-aware stacking (vertical layouts stack
    // labels horizontally; see LabelDummyInserter.process isVertical branch).
    var dummyW = 0.0;
    var dummyH = 0.0;

    for (final label in labels) {
      dummyW = dummyW > label.size.x ? dummyW : label.size.x;
      dummyH += label.size.y + _defaultLabelLabelSpacing;
    }

    // Remove the extra labelLabelSpacing added in the last iteration and add
    // the edge-label spacing so the edge line itself is included in the
    // reserved height.
    if (labels.isNotEmpty) {
      dummyH += _defaultEdgeLabelSpacing - _defaultLabelLabelSpacing;
    }

    dummy.size.x = dummyW;
    dummy.size.y = dummyH;

    // --- Split the edge through the dummy (mirrors LongEdgeSplitter.splitEdge) ---
    _splitEdgeThroughDummy(edge, dummy);

    // Place dummy ports at edge centre (y offset = floor(thickness / 2)).
    // Thickness is not tracked in this port, so we use 0.
    // TODO(elk-faithful): read edge thickness property when ported.
    for (final p in dummy.ports) {
      p.position.y = 0;
    }

    // Move labels from edge onto the dummy (edge.labels stays empty until
    // remover restores them).
    edge.labels.clear();

    return dummy;
  }

  /// Splits [edge] by inserting [dummy] between the existing source and
  /// target, creating a new continuation edge from dummy's output port to
  /// the old target.
  ///
  /// After this call:
  ///   original-source → dummyInputPort  (via the original [edge], shortened)
  ///   dummyOutputPort → old-target      (via a new edge)
  ///
  /// Mirrors `LongEdgeSplitter.splitEdge` (which LabelDummyInserter delegates
  /// to in the Java source).
  static void _splitEdgeThroughDummy(LEdge edge, LNode dummy) {
    final oldTarget = edge.target!;

    // West (input) port on the dummy.
    final inputPort = LPort(dummy)
      ..side = PortSide.west
      ..node = dummy;
    dummy.ports.add(inputPort);

    // East (output) port on the dummy.
    final outputPort = LPort(dummy)
      ..side = PortSide.east
      ..node = dummy;
    dummy.ports.add(outputPort);

    // Shorten original edge to end at the dummy's input port.
    edge.target = inputPort;

    // New continuation edge from dummy output to the original target.
    final continuation = LEdge()
      ..copyPropertiesFrom(edge)
      ..source = outputPort
      ..target = oldTarget;

    // Suppress unused variable warning — the continuation edge is live
    // because its source/target ports reference it.
    continuation; // registered via port setters above
  }
}

// ---------------------------------------------------------------------------
// LabelDummyRemover
// ---------------------------------------------------------------------------

/// Removes [NodeType.label] dummy nodes after edge routing (P5), reads their
/// computed positions, writes those positions back as the labels' positions,
/// rejoins the split edge through the dummy, and removes the dummy from its
/// layer.
///
/// Port of `LabelDummyRemover.java`. Slot: **after P5**, before
/// [LongEdgeJoiner] (the remover calls `LongEdgeJoiner.joinAt` internally for
/// label dummies).
///
/// TODO(elk-faithful): LabelDummySwitcher (optimal-layer switching) and
/// LabelSideSelector (above/below placement) are not ported; labels are always
/// placed at the dummy's top-left with horizontal centering.
class LabelDummyRemover implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    for (final layer in graph.layers) {
      // Iterate backwards so index-based removal is safe.
      for (var i = layer.nodes.length - 1; i >= 0; i--) {
        final node = layer.nodes[i];
        if (node.type != NodeType.label) continue;

        _processLabelDummy(node);
        layer.nodes.removeAt(i);
      }
    }
  }

  /// Extracts the dummy's placed position, positions each label relative to
  /// that position, adds the labels back to the origin edge, then rejoins
  /// the split edge (mirroring `LongEdgeJoiner.joinAt`).
  void _processLabelDummy(LNode dummy) {
    final originEdge = dummy.getProperty(labelDummyOriginEdge);
    final labels = dummy.getProperty(representedLabels);

    if (originEdge == null || labels == null || labels.isEmpty) {
      // Defensive: still rejoin even if the label data is missing.
      _rejoin(dummy);
      return;
    }

    // --- Place labels ---
    // Mirrors `placeLabelsForHorizontalLayout` in LabelDummyRemover.java.
    // Internal flow is RIGHT (horizontal), so labels stack vertically.
    // TODO(elk-faithful): DIRECTION-aware placement (vertical layouts place
    // labels horizontally; see LabelDummyRemover.placeLabelsForVerticalLayout).
    // TODO(elk-faithful): LabelSide.BELOW offset (labelsBelowEdge branch).
    _placeLabelsHorizontal(labels, dummy);

    // Restore labels to the original edge.
    originEdge.labels.addAll(labels);

    // Rejoin the long-edge-style split that was introduced by the inserter.
    // We pass false for addUnnecessaryBendpoints because we use orthogonal routing.
    // TODO(elk-faithful): read EDGE_ROUTING option to decide on bend points.
    _rejoin(dummy);
  }

  /// Places [labels] at the dummy's position, centering each horizontally
  /// within the dummy's width and stacking them vertically.
  ///
  /// Mirrors `placeLabelsForHorizontalLayout` in LabelDummyRemover.java.
  void _placeLabelsHorizontal(List<LLabel> labels, LNode dummy) {
    var curY = dummy.position.y;
    final dummyW = dummy.size.x;

    for (final label in labels) {
      // Horizontal center-alignment within the dummy's width.
      label.position.x = dummy.position.x + (dummyW - label.size.x) / 2.0;
      label.position.y = curY;
      curY += label.size.y + _defaultLabelLabelSpacing;
    }
  }

  /// Rejoins the label-dummy split by delegating to [LongEdgeJoiner.joinAt].
  ///
  /// Label dummies use the same split structure as long-edge dummies (one west
  /// input port, one east output port), so the same joiner logic applies.
  /// No unnecessary bend points are added (orthogonal routing).
  void _rejoin(LNode dummy) {
    // LongEdgeJoiner._joinAt is private; we inline the same logic here.
    // It finds west/east ports, merges bend points, and reconnects the edges.
    _joinLabelDummyAt(dummy);
  }

  /// Inlined version of `LongEdgeJoiner._joinAt` for label dummies.
  ///
  /// The structure is identical: the western (input) edge survives and its
  /// target is updated to the eastern (output) edge's target. Bend points
  /// from the output edge are appended to the input edge.
  static void _joinLabelDummyAt(LNode dummy) {
    final inputPort = dummy.ports.firstWhere((p) => p.side == PortSide.west);
    final outputPort = dummy.ports.firstWhere((p) => p.side == PortSide.east);

    final inputEdges = inputPort.incomingEdges;
    final outputEdges = outputPort.outgoingEdges;

    var count = inputEdges.length;
    while (count-- > 0) {
      final survivingEdge = inputEdges[0];
      final droppedEdge = outputEdges[0];

      final targetPort = droppedEdge.target!;
      final targetIncoming = targetPort.incomingEdges;
      final insertIdx = targetIncoming.indexOf(droppedEdge);

      // Reconnect surviving edge to the final target.
      survivingEdge.target = targetPort;

      // Preserve insertion order (mirrors KIPRA-1670 fix in LongEdgeJoiner).
      if (insertIdx >= 0) {
        targetIncoming.remove(survivingEdge);
        targetIncoming.insert(insertIdx, survivingEdge);
      }

      // Disconnect dropped edge.
      droppedEdge.source = null;
      droppedEdge.target = null;

      // Merge bend points: surviving ++ dropped (no unnecessary bend point at
      // the dummy position for orthogonal routing).
      for (final bp in droppedEdge.bendPoints.points) {
        survivingEdge.bendPoints.add(bp.clone());
      }

      // Merge any extra labels (should be empty at this point since the
      // inserter cleared them; kept for safety).
      survivingEdge.labels.addAll(droppedEdge.labels);
    }
  }
}

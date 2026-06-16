/// Phase 5 — faithful port of ELK's `OrthogonalRoutingGenerator`
/// (`p5edges/orthogonal/OrthogonalRoutingGenerator.java`) plus its supporting
/// classes: [_HyperEdgeSegment], [_HyperEdgeSegmentDependency],
/// [_HyperEdgeCycleDetector], and the west-to-east routing strategy
/// [_WestToEastRoutingStrategy].
///
/// Algorithm outline (for each pair of adjacent layers):
///   1. Create [_HyperEdgeSegment]s for source-side EAST ports and target-side
///      WEST ports, grouping connected ports into one segment.
///   2. Build ordering dependencies between segments (critical = would overlap,
///      regular = weighted by crossings).
///   3. Break critical dependency cycles (via segment splitting, simplified here
///      to cycle-edge removal — see TODO below).
///   4. Break non-critical cycles by reversing / removing the minimum-weight
///      dependency.
///   5. Topological slot assignment (BFS-based numbering).
///   6. Emit [LEdge.bendPoints] for each non-straight edge.
///
/// Faithfulness notes:
///   - The random tie-break in [_HyperEdgeCycleDetector] uses the first element
///     rather than a seeded RNG (same deviation as p1).
///   - [_HyperEdgeSegmentSplitter] is stubbed: critical dependency cycles are
///     broken by removing the cycle-back dependency rather than by splitting the
///     segment. This produces correct routing in almost all practical cases; full
///     splitting would be needed only when two hyper-segments genuinely overlap
///     after slot assignment.
///   - Junction points (ELK `JUNCTION_POINTS` property) are not emitted; a
///     separate post-processor can add them if needed.
///
/// Other directions (NORTH_TO_SOUTH, SOUTH_TO_NORTH) are stubbed out with a
/// `TODO(elk-faithful)` comment.
library;

import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// Property constants defined in this file
// ---------------------------------------------------------------------------

/// Edge-to-edge spacing inside a routing channel (ELK `SPACING_EDGE_EDGE_BETWEEN_LAYERS`).
/// Default matches ELK's spacing default of 10.
const edgeEdgeSpacing = 10.0;

/// Spacing between an edge and a node across a layer gap
/// (ELK `SPACING_EDGE_NODE_BETWEEN_LAYERS`, default 10). This is the offset of
/// the first routing slot from the node border — i.e. the length of the stub by
/// which every edge leaves its node before turning.
const edgeNodeSpacing = 10.0;

/// Node-to-node spacing between adjacent layers (ELK
/// `SPACING_NODE_NODE_BETWEEN_LAYERS`). The engine stores this on the graph as
/// `bk.spacing.layer` (default 20); the edge router falls back to that default.
const _nodeNodeBetweenLayers = Property<double>('bk.spacing.layer', 20.0);

// ---------------------------------------------------------------------------
// Public processor
// ---------------------------------------------------------------------------

/// Routes edges orthogonally between every pair of adjacent layers.
///
/// Pre-conditions:
///   - The graph has been layered and nodes placed (positions set).
///   - Long edges have been split into adjacent-layer hops via dummy nodes.
///
/// Post-conditions:
///   - Every [LEdge] that spans adjacent layers has [LEdge.bendPoints]
///     populated with the axis-aligned route.
class OrthogonalRoutingGenerator implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final layers = graph.layers;
    if (layers.isEmpty) return;

    // ELK's OrthogonalEdgeRouter owns flow-axis (x) layer placement: it walks
    // layers left→right, placing each layer, routing the gap to it, and sizing
    // that gap by the number of routing slots actually needed. This is why
    // edges always leave a node with a stub (startPos is offset from the border
    // by `edgeNodeSpacing`) and why layers spread apart when many edges route
    // between them. (Our BK placer no longer assigns x — see p4_bk_node_placer.)
    final nodeNodeSpacing = graph.getProperty(_nodeNodeBetweenLayers);
    final generator = _OrthogonalRoutingGenerator(edgeEdgeSpacing);

    double xpos = 0;
    Layer? leftLayer;
    List<LNode>? leftNodes;

    // Iterate over the gaps: (null,L0), (L0,L1), …, (Llast,null).
    for (var i = 0; i <= layers.length; i++) {
      final rightLayer = i < layers.length ? layers[i] : null;
      final rightNodes = rightLayer?.nodes;

      // Place the left layer's nodes horizontally, then advance past its width.
      if (leftLayer != null) {
        _placeNodesHorizontally(leftLayer, xpos);
        xpos += leftLayer.size.x;
      }

      // The first routing slot sits `edgeNodeSpacing` past the source border.
      final startPos = leftLayer == null ? xpos : xpos + edgeNodeSpacing;
      final slotsCount = generator.routeEdges(leftNodes, rightNodes, startPos);

      final leftExternal = leftLayer == null ||
          leftNodes!.every((n) => n.type == NodeType.externalPort);
      final rightExternal = rightLayer == null ||
          rightNodes!.every((n) => n.type == NodeType.externalPort);

      if (slotsCount > 0) {
        var routingWidth = (slotsCount - 1) * edgeEdgeSpacing;
        if (leftLayer != null) routingWidth += edgeNodeSpacing;
        if (rightLayer != null) routingWidth += edgeNodeSpacing;
        // Between two real layers, never tighter than the node-node spacing.
        if (routingWidth < nodeNodeSpacing && !leftExternal && !rightExternal) {
          routingWidth = nodeNodeSpacing;
        }
        xpos += routingWidth;
      } else if (!leftExternal && !rightExternal) {
        // All edges straight → the usual node-node spacing.
        xpos += nodeNodeSpacing;
      }

      leftLayer = rightLayer;
      leftNodes = rightNodes;
    }

    graph.size.x = xpos;
  }

  /// Faithful port of `LGraphUtil.placeNodesHorizontally`: align each node
  /// within its layer's width by the ratio of out-ports to total ports (so a
  /// node feeding the next layer sits toward the gap), clamped to its margins.
  void _placeNodesHorizontally(Layer layer, double xoffset) {
    double maxLeftMargin = 0, maxRightMargin = 0;
    for (final node in layer.nodes) {
      if (node.margin.left > maxLeftMargin) maxLeftMargin = node.margin.left;
      if (node.margin.right > maxRightMargin) maxRightMargin = node.margin.right;
    }

    final layerWidth = layer.size.x;
    for (final node in layer.nodes) {
      // Default (AUTO) alignment: ratio by in/out port counts. We do not set
      // the ALIGNMENT property, so this branch always applies.
      var inports = 0, outports = 0;
      for (final port in node.ports) {
        if (port.incomingEdges.isNotEmpty) inports++;
        if (port.outgoingEdges.isNotEmpty) outports++;
      }
      final double ratio =
          (inports + outports == 0) ? 0.5 : outports / (inports + outports);

      final nodeSize = node.size.x;
      var xp = (layerWidth - nodeSize) * ratio;
      if (ratio > 0.5) {
        xp -= maxRightMargin * 2 * (ratio - 0.5);
      } else if (ratio < 0.5) {
        xp += maxLeftMargin * 2 * (0.5 - ratio);
      }

      final leftMargin = node.margin.left;
      if (xp < leftMargin) xp = leftMargin;
      final rightMargin = node.margin.right;
      if (xp > layerWidth - rightMargin - nodeSize) {
        xp = layerWidth - rightMargin - nodeSize;
      }

      node.position.x = xoffset + xp;
    }
  }
}

// ---------------------------------------------------------------------------
// Core generator (package-private within this file)
// ---------------------------------------------------------------------------

class _OrthogonalRoutingGenerator {
  static const double _tolerance = 1e-3;
  static const double _conflictThresholdFactor = 0.5;
  static const double _criticalConflictThresholdFactor = 0.2;
  static const int _conflictPenalty = 1;
  static const int _crossingPenalty = 16;

  final double _edgeSpacing;
  late double _criticalConflictThreshold;

  final _WestToEastRoutingStrategy _strategy = _WestToEastRoutingStrategy();

  _OrthogonalRoutingGenerator(this._edgeSpacing);

  /// Route edges that cross the channel between [sourceNodes] and [targetNodes].
  ///
  /// Either list may be null (external-port channels).
  /// [startPos] is the x coordinate of the channel's left edge.
  /// Returns the number of routing slots consumed.
  int routeEdges(
    List<LNode>? sourceNodes,
    List<LNode>? targetNodes,
    double startPos,
  ) {
    final portToSegment = <LPort, _HyperEdgeSegment>{};
    final segments = <_HyperEdgeSegment>[];

    _createHyperEdgeSegments(sourceNodes, _strategy.sourcePortSide, segments, portToSegment);
    _createHyperEdgeSegments(targetNodes, _strategy.targetPortSide, segments, portToSegment);

    _criticalConflictThreshold =
        _criticalConflictThresholdFactor * _minimumHorizontalSegmentDistance(segments);

    int criticalDependencyCount = 0;
    for (var i = 0; i < segments.length - 1; i++) {
      for (var j = i + 1; j < segments.length; j++) {
        criticalDependencyCount += _createDependencyIfNecessary(segments[i], segments[j]);
      }
    }

    if (criticalDependencyCount >= 2) {
      _breakCriticalCycles(segments);
    }

    _breakNonCriticalCycles(segments);

    _topologicalNumbering(segments);

    int rankCount = -1;
    for (final seg in segments) {
      if ((seg.startCoordinate - seg.endCoordinate).abs() < _tolerance) continue;
      if (seg.routingSlot > rankCount) rankCount = seg.routingSlot;
      _strategy.calculateBendPoints(seg, startPos, _edgeSpacing);
    }

    _strategy.clearCreatedJunctionPoints();
    return rankCount + 1;
  }

  // -------------------------------------------------------------------------
  // Segment creation
  // -------------------------------------------------------------------------

  void _createHyperEdgeSegments(
    List<LNode>? nodes,
    PortSide portSide,
    List<_HyperEdgeSegment> segments,
    Map<LPort, _HyperEdgeSegment> portToSegment,
  ) {
    if (nodes == null) return;
    for (final node in nodes) {
      for (final port in node.ports) {
        if (port.side != portSide) continue;
        // We treat every OUTPUT port on the source side / INPUT port on the
        // target side as a potential segment anchor.  ELK filters by
        // PortType.OUTPUT; in our model incoming/outgoing lists serve the same
        // purpose: a port that has outgoing edges on the EAST side is a source
        // connection point; a port that has incoming edges on the WEST side is
        // a target connection point.
        final hasEdgesForThisChannel =
            portSide == PortSide.east
                ? port.outgoingEdges.isNotEmpty
                : port.incomingEdges.isNotEmpty;
        if (!hasEdgesForThisChannel) continue;

        if (!portToSegment.containsKey(port)) {
          final seg = _HyperEdgeSegment(_strategy);
          segments.add(seg);
          seg.addPortPositions(port, portToSegment);
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Dependency creation
  // -------------------------------------------------------------------------

  /// Returns the number of critical dependencies added.
  int _createDependencyIfNecessary(_HyperEdgeSegment he1, _HyperEdgeSegment he2) {
    if ((he1.startCoordinate - he1.endCoordinate).abs() < _tolerance ||
        (he2.startCoordinate - he2.endCoordinate).abs() < _tolerance) {
      return 0;
    }

    final conflicts1 = _countConflicts(he1.outgoingCoords, he2.incomingCoords);
    final conflicts2 = _countConflicts(he2.outgoingCoords, he1.incomingCoords);

    final criticalDetected =
        conflicts1 == _criticalConflictsDetected || conflicts2 == _criticalConflictsDetected;
    int criticalCount = 0;

    if (criticalDetected) {
      if (conflicts1 == _criticalConflictsDetected) {
        _HyperEdgeSegmentDependency.createCritical(he2, he1);
        criticalCount++;
      }
      if (conflicts2 == _criticalConflictsDetected) {
        _HyperEdgeSegmentDependency.createCritical(he1, he2);
        criticalCount++;
      }
    } else {
      int crossings1 = _countCrossings(he1.outgoingCoords, he2.startCoordinate, he2.endCoordinate);
      crossings1 += _countCrossings(he2.incomingCoords, he1.startCoordinate, he1.endCoordinate);
      int crossings2 = _countCrossings(he2.outgoingCoords, he1.startCoordinate, he1.endCoordinate);
      crossings2 += _countCrossings(he1.incomingCoords, he2.startCoordinate, he2.endCoordinate);

      final val1 = _conflictPenalty * conflicts1 + _crossingPenalty * crossings1;
      final val2 = _conflictPenalty * conflicts2 + _crossingPenalty * crossings2;

      if (val1 < val2) {
        _HyperEdgeSegmentDependency.createRegular(he1, he2, val2 - val1);
      } else if (val1 > val2) {
        _HyperEdgeSegmentDependency.createRegular(he2, he1, val1 - val2);
      } else if (val1 > 0) {
        _HyperEdgeSegmentDependency.createRegular(he1, he2, 0);
        _HyperEdgeSegmentDependency.createRegular(he2, he1, 0);
      }
    }

    return criticalCount;
  }

  static const int _criticalConflictsDetected = -1;

  /// Two-pointer merge on sorted coordinate lists. Returns -1 if a critical
  /// conflict (positions within [_criticalConflictThreshold]) is found.
  int _countConflicts(List<double> coords1, List<double> coords2) {
    if (coords1.isEmpty || coords2.isEmpty) return 0;
    int conflicts = 0;
    int i = 0, j = 0;
    while (i < coords1.length && j < coords2.length) {
      final p1 = coords1[i], p2 = coords2[j];
      final diff = (p1 - p2).abs();
      if (diff < _criticalConflictThreshold) return _criticalConflictsDetected;
      if (diff < _edgeSpacing * _conflictThresholdFactor) conflicts++;
      if (p1 <= p2) {
        i++;
      } else {
        j++;
      }
    }
    return conflicts;
  }

  static int _countCrossings(List<double> coords, double start, double end) {
    int count = 0;
    for (final p in coords) {
      if (p > end) break;
      if (p >= start) count++;
    }
    return count;
  }

  // -------------------------------------------------------------------------
  // Minimum horizontal segment distance
  // -------------------------------------------------------------------------

  double _minimumHorizontalSegmentDistance(List<_HyperEdgeSegment> segments) {
    final allIncoming = <double>[];
    final allOutgoing = <double>[];
    for (final seg in segments) {
      allIncoming.addAll(seg.incomingCoords);
      allOutgoing.addAll(seg.outgoingCoords);
    }
    return _min(
      _minimumDifference(allIncoming),
      _minimumDifference(allOutgoing),
    );
  }

  static double _minimumDifference(List<double> values) {
    if (values.length < 2) return double.maxFinite;
    // Build a sorted, deduplicated list.
    final deduped = <double>[];
    for (final v in (List<double>.from(values)..sort())) {
      if (deduped.isEmpty || (v - deduped.last).abs() > 1e-10) deduped.add(v);
    }
    if (deduped.length < 2) return double.maxFinite;
    double minDiff = double.maxFinite;
    for (var i = 1; i < deduped.length; i++) {
      final diff = deduped[i] - deduped[i - 1];
      if (diff < minDiff) minDiff = diff;
    }
    return minDiff;
  }

  static double _min(double a, double b) => a < b ? a : b;

  // -------------------------------------------------------------------------
  // Cycle breaking
  // -------------------------------------------------------------------------

  void _breakCriticalCycles(List<_HyperEdgeSegment> segments) {
    // TODO(elk-faithful): implement full HyperEdgeSegmentSplitter. For now, we
    // simply remove the back-dependency in each critical cycle (same as the
    // non-critical case). This avoids edge overlaps in the vast majority of
    // diagrams; proper splitting would handle the rare residual overlap.
    final cycleDeps = _HyperEdgeCycleDetector.detectCycles(segments, criticalOnly: true);
    for (final dep in cycleDeps) {
      dep.remove();
    }
  }

  static void _breakNonCriticalCycles(List<_HyperEdgeSegment> segments) {
    final cycleDeps = _HyperEdgeCycleDetector.detectCycles(segments, criticalOnly: false);
    for (final dep in cycleDeps) {
      if (dep.weight == 0) {
        dep.remove();
      } else {
        dep.reverse();
      }
    }
  }

  // -------------------------------------------------------------------------
  // Topological slot assignment
  // -------------------------------------------------------------------------

  static void _topologicalNumbering(List<_HyperEdgeSegment> segments) {
    final sources = <_HyperEdgeSegment>[];
    final rightwardTargets = <_HyperEdgeSegment>[];

    for (final seg in segments) {
      seg.inWeight = seg.incomingDeps.length;
      seg.outWeight = seg.outgoingDeps.length;

      if (seg.inWeight == 0) sources.add(seg);
      if (seg.outWeight == 0 && seg.incomingCoords.isEmpty) rightwardTargets.add(seg);
    }

    int maxRank = -1;

    while (sources.isNotEmpty) {
      final node = sources.removeAt(0);
      for (final dep in node.outgoingDeps.toList()) {
        final tgt = dep.target!;
        final newSlot = node.routingSlot + 1;
        if (newSlot > tgt.routingSlot) tgt.routingSlot = newSlot;
        if (tgt.routingSlot > maxRank) maxRank = tgt.routingSlot;

        tgt.inWeight--;
        if (tgt.inWeight == 0) sources.add(tgt);
      }
    }

    if (maxRank > -1) {
      for (final node in rightwardTargets) {
        node.routingSlot = maxRank;
      }

      final queue = List<_HyperEdgeSegment>.from(rightwardTargets);
      while (queue.isNotEmpty) {
        final node = queue.removeAt(0);
        for (final dep in node.incomingDeps.toList()) {
          final src = dep.source!;
          if (src.incomingCoords.isNotEmpty) continue;

          final newSlot = node.routingSlot - 1;
          if (newSlot < src.routingSlot) src.routingSlot = newSlot;

          src.outWeight--;
          if (src.outWeight == 0) queue.add(src);
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// _HyperEdgeSegment
// ---------------------------------------------------------------------------

class _HyperEdgeSegment {
  _HyperEdgeSegment(this._strategy);

  final _WestToEastRoutingStrategy _strategy;

  final List<LPort> ports = [];

  /// Mark used during cycle detection (mutable, like the Java `int mark` field).
  int mark = 0;

  int routingSlot = 0;

  double _startCoord = double.nan;
  double _endCoord = double.nan;

  /// Sorted incoming (source-side) y coordinates.
  final List<double> incomingCoords = [];

  /// Sorted outgoing (target-side) y coordinates.
  final List<double> outgoingCoords = [];

  final List<_HyperEdgeSegmentDependency> outgoingDeps = [];
  final List<_HyperEdgeSegmentDependency> incomingDeps = [];

  int inWeight = 0;
  int outWeight = 0;
  int criticalInWeight = 0;
  int criticalOutWeight = 0;

  _HyperEdgeSegment? splitPartner;
  _HyperEdgeSegment? splitBy;

  double get startCoordinate => _startCoord;
  double get endCoordinate => _endCoord;

  bool get isDummy => splitPartner != null && splitBy == null;

  void addPortPositions(LPort port, Map<LPort, _HyperEdgeSegment> map) {
    map[port] = this;
    ports.add(port);

    final portPos = _strategy.getPortPositionOnHyperNode(port);

    if (port.side == _strategy.sourcePortSide) {
      _insertSorted(incomingCoords, portPos);
    } else {
      _insertSorted(outgoingCoords, portPos);
    }

    _recomputeExtent();

    // Recurse into connected ports not yet visited.
    for (final edge in port.outgoingEdges) {
      final other = edge.target;
      if (other != null && !map.containsKey(other)) {
        addPortPositions(other, map);
      }
    }
    for (final edge in port.incomingEdges) {
      final other = edge.source;
      if (other != null && !map.containsKey(other)) {
        addPortPositions(other, map);
      }
    }
  }

  static void _insertSorted(List<double> list, double value) {
    for (var i = 0; i < list.length; i++) {
      if ((list[i] - value).abs() < 1e-10) return; // duplicate
      if (list[i] > value) {
        list.insert(i, value);
        return;
      }
    }
    list.add(value);
  }

  void _recomputeExtent() {
    _startCoord = double.nan;
    _endCoord = double.nan;
    _updateExtent(incomingCoords);
    _updateExtent(outgoingCoords);
  }

  void _updateExtent(List<double> coords) {
    if (coords.isEmpty) return;
    final first = coords.first, last = coords.last;
    if (_startCoord.isNaN || first < _startCoord) _startCoord = first;
    if (_endCoord.isNaN || last > _endCoord) _endCoord = last;
  }
}

// ---------------------------------------------------------------------------
// _HyperEdgeSegmentDependency
// ---------------------------------------------------------------------------

enum _DependencyType { regular, critical }

class _HyperEdgeSegmentDependency {
  static const int _criticalWeight = 1;

  _HyperEdgeSegmentDependency._(this.type, this.weight, _HyperEdgeSegment src, _HyperEdgeSegment tgt) {
    _setSource(src);
    _setTarget(tgt);
  }

  final _DependencyType type;
  final int weight;

  _HyperEdgeSegment? source;
  _HyperEdgeSegment? target;

  static _HyperEdgeSegmentDependency createRegular(
      _HyperEdgeSegment src, _HyperEdgeSegment tgt, int weight) =>
      _HyperEdgeSegmentDependency._(_DependencyType.regular, weight, src, tgt);

  static _HyperEdgeSegmentDependency createCritical(
      _HyperEdgeSegment src, _HyperEdgeSegment tgt) =>
      _HyperEdgeSegmentDependency._(_DependencyType.critical, _criticalWeight, src, tgt);

  void remove() {
    _setSource(null);
    _setTarget(null);
  }

  void reverse() {
    final oldSrc = source, oldTgt = target;
    _setSource(null);
    _setTarget(null);
    if (oldTgt != null) _setSource(oldTgt);
    if (oldSrc != null) _setTarget(oldSrc);
  }

  void _setSource(_HyperEdgeSegment? seg) {
    source?.outgoingDeps.remove(this);
    source = seg;
    seg?.outgoingDeps.add(this);
  }

  void _setTarget(_HyperEdgeSegment? seg) {
    target?.incomingDeps.remove(this);
    target = seg;
    seg?.incomingDeps.add(this);
  }
}

// ---------------------------------------------------------------------------
// _HyperEdgeCycleDetector
// ---------------------------------------------------------------------------

class _HyperEdgeCycleDetector {
  _HyperEdgeCycleDetector._();

  static List<_HyperEdgeSegmentDependency> detectCycles(
    List<_HyperEdgeSegment> segments, {
    required bool criticalOnly,
  }) {
    final sources = <_HyperEdgeSegment>[];
    final sinks = <_HyperEdgeSegment>[];

    _initialize(segments, sources, sinks, criticalOnly);
    _computeMarks(segments, sources, sinks, criticalOnly);

    final result = <_HyperEdgeSegmentDependency>[];
    for (final seg in segments) {
      for (final dep in seg.outgoingDeps) {
        if (criticalOnly && dep.type != _DependencyType.critical) continue;
        if (seg.mark > (dep.target?.mark ?? 0)) {
          result.add(dep);
        }
      }
    }
    return result;
  }

  static void _initialize(
    List<_HyperEdgeSegment> segments,
    List<_HyperEdgeSegment> sources,
    List<_HyperEdgeSegment> sinks,
    bool criticalOnly,
  ) {
    int nextMark = -1;
    for (final seg in segments) {
      seg.mark = nextMark--;

      final critIn = seg.incomingDeps
          .where((d) => d.type == _DependencyType.critical)
          .fold(0, (s, d) => s + d.weight);
      final critOut = seg.outgoingDeps
          .where((d) => d.type == _DependencyType.critical)
          .fold(0, (s, d) => s + d.weight);

      int inW, outW;
      if (criticalOnly) {
        inW = critIn;
        outW = critOut;
      } else {
        inW = seg.incomingDeps.fold(0, (s, d) => s + d.weight);
        outW = seg.outgoingDeps.fold(0, (s, d) => s + d.weight);
      }

      seg.inWeight = inW;
      seg.outWeight = outW;
      seg.criticalInWeight = critIn;
      seg.criticalOutWeight = critOut;

      if (outW == 0) {
        sinks.add(seg);
      } else if (inW == 0) {
        sources.add(seg);
      }
    }
  }

  static void _computeMarks(
    List<_HyperEdgeSegment> segments,
    List<_HyperEdgeSegment> sources,
    List<_HyperEdgeSegment> sinks,
    bool criticalOnly,
  ) {
    // Use a mutable set ordered by initial mark (negative values become the
    // natural ordering via the default comparator after we convert to a list).
    final unprocessed = segments.toList();
    final markBase = segments.length;
    int nextSinkMark = markBase - 1;
    int nextSourceMark = markBase + 1;

    while (unprocessed.isNotEmpty) {
      while (sinks.isNotEmpty) {
        final sink = sinks.removeAt(0);
        unprocessed.remove(sink);
        sink.mark = nextSinkMark--;
        _updateNeighbors(sink, sources, sinks, criticalOnly);
      }

      while (sources.isNotEmpty) {
        final source = sources.removeAt(0);
        unprocessed.remove(source);
        source.mark = nextSourceMark++;
        _updateNeighbors(source, sources, sinks, criticalOnly);
      }

      // Pick the node with maximum out-flow among remaining unprocessed.
      if (unprocessed.isNotEmpty) {
        _HyperEdgeSegment? maxNode;
        int maxOutflow = -0x7fffffff;

        for (final seg in unprocessed) {
          // If considering both types, ensure critical deps remain rightward.
          if (!criticalOnly && seg.criticalOutWeight > 0 && seg.criticalInWeight <= 0) {
            maxNode = seg;
            break;
          }
          final outflow = seg.outWeight - seg.inWeight;
          if (outflow >= maxOutflow) {
            maxOutflow = outflow;
            maxNode = seg; // ELK: random tie-break; we take first for determinism
          }
        }

        if (maxNode != null) {
          unprocessed.remove(maxNode);
          maxNode.mark = nextSourceMark++;
          _updateNeighbors(maxNode, sources, sinks, criticalOnly);
        }
      }
    }

    // Shift sink marks above source marks.
    final shiftBase = segments.length + 1;
    for (final seg in segments) {
      if (seg.mark < markBase) seg.mark += shiftBase;
    }
  }

  static void _updateNeighbors(
    _HyperEdgeSegment node,
    List<_HyperEdgeSegment> sources,
    List<_HyperEdgeSegment> sinks,
    bool criticalOnly,
  ) {
    for (final dep in node.outgoingDeps) {
      if (criticalOnly && dep.type != _DependencyType.critical) continue;
      final tgt = dep.target;
      if (tgt == null || tgt.mark >= 0) continue;
      if (dep.weight > 0) {
        tgt.inWeight -= dep.weight;
        if (dep.type == _DependencyType.critical) tgt.criticalInWeight -= dep.weight;
        if (tgt.inWeight <= 0 && tgt.outWeight > 0) sources.add(tgt);
      }
    }

    for (final dep in node.incomingDeps) {
      if (criticalOnly && dep.type != _DependencyType.critical) continue;
      final src = dep.source;
      if (src == null || src.mark >= 0) continue;
      if (dep.weight > 0) {
        src.outWeight -= dep.weight;
        if (dep.type == _DependencyType.critical) src.criticalOutWeight -= dep.weight;
        if (src.outWeight <= 0 && src.inWeight > 0) sinks.add(src);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// _WestToEastRoutingStrategy
// ---------------------------------------------------------------------------

class _WestToEastRoutingStrategy {
  static const double _tolerance = 1e-3;

  /// Junction point deduplication (not emitted; reserved for future use).
  final _junctionPoints = <KVector>{};

  PortSide get sourcePortSide => PortSide.east;
  PortSide get targetPortSide => PortSide.west;

  double getPortPositionOnHyperNode(LPort port) =>
      port.node.position.y + port.position.y + port.anchor.y;

  void clearCreatedJunctionPoints() => _junctionPoints.clear();

  void calculateBendPoints(
    _HyperEdgeSegment segment,
    double startPos,
    double edgeSpacing,
  ) {
    // Dummy segments (introduced by splitting) are handled via their partner.
    if (segment.isDummy) return;

    final segmentX = startPos + segment.routingSlot * edgeSpacing;

    for (final port in segment.ports) {
      final sourceY = port.absoluteAnchor.y;

      for (final edge in port.outgoingEdges) {
        if (edge.isSelfLoop) continue;

        final target = edge.target;
        if (target == null) continue;

        final targetY = target.absoluteAnchor.y;

        if ((sourceY - targetY).abs() <= _tolerance) {
          // Straight horizontal line — no bend points needed.
          continue;
        }

        edge.bendPoints.clear();

        double currentX = segmentX;
        _HyperEdgeSegment currentSegment = segment;

        // First bend: horizontal exit from source port.
        edge.bendPoints.add(KVector(currentX, sourceY));

        // If this segment was split, add the detour through the split partner.
        final splitPartner = segment.splitPartner;
        if (splitPartner != null) {
          final splitY = splitPartner.incomingCoords.isNotEmpty
              ? splitPartner.incomingCoords.first
              : sourceY;

          edge.bendPoints.add(KVector(currentX, splitY));

          currentX = startPos + splitPartner.routingSlot * edgeSpacing;
          currentSegment = splitPartner; // suppress unused-variable lint

          edge.bendPoints.add(KVector(currentX, splitY));
        }

        // Final bend: horizontal entry to target port.
        edge.bendPoints.add(KVector(currentX, targetY));

        // Prevent currentSegment from being optimised away in future refactors.
        _ = currentSegment;
      }
    }
  }
}

// Dart requires the identifier `_` to exist; use a top-level no-op setter.
// ignore: unused_element
set _(Object? _v) {}

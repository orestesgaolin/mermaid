/// Phase 4 — faithful port of ELK's Brandes–Köpf node placer
/// (`p4nodes/bk/BKNodePlacer.java` + `BKAligner.java` + `BKCompactor.java` +
/// `BKAlignedLayout.java` + `NeighborhoodInformation.java`).
///
/// Assigns each node's y-coordinate (cross-axis, perpendicular to the flow
/// direction). Layer x-coordinates are also set here by stacking layers with
/// the configured separation.
///
/// The algorithm:
///   1. Mark type-1 conflicts (short edge crossing inner long-edge segment).
///   2. For each of the four direction combinations (UP/DOWN × LEFT/RIGHT):
///      a. Vertical alignment — group nodes into blocks.
///      b. Inside-block shift — align ports within a block; compute block size.
///      c. Horizontal compaction — assign y-coordinates to blocks/classes.
///   3. Balance the four layouts (median of shifted coordinates).
///   4. Apply chosen y to every node; set x by stacking layers.
///
/// Deviations from Java:
///   - Guava / EMF replaced with plain Dart collections.
///   - Spacings read from [BKProps] property constants defined below.
///   - [ThresholdStrategy]: only [_NullThresholdStrategy] is wired (default
///     `fixedAlignment = NONE` with no IMPROVE_STRAIGHTNESS option).
///     [_SimpleThresholdStrategy] is included but NOT activated by default.
///   - Self-loop / north-south-port / big-node niche paths omitted (see TODOs).
///   - No RNG — deterministic.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// Property constants (define here; do NOT edit shared model files)
// ---------------------------------------------------------------------------

/// Spacing between two adjacent regular nodes inside a layer (y-axis).
/// Mirrors ELK's `LayeredOptions.SPACING_NODE_NODE` default of 20.
const bkNodeNodeSpacing = Property<double>('bk.spacing.nodeNode', 20.0);

/// Spacing between a regular node and a dummy node inside a layer.
/// Mirrors ELK's dummy-spacing which is usually half of node-node.
const bkNodeEdgeSpacing = Property<double>('bk.spacing.nodeEdge', 10.0);

/// Spacing between a dummy and a dummy node inside a layer.
const bkEdgeEdgeSpacing = Property<double>('bk.spacing.edgeEdge', 10.0);

/// Spacing between layers (x-axis — along the flow direction).
/// Mirrors ELK's `LayeredOptions.SPACING_NODE_NODE_BETWEEN_LAYERS` default of 20.
const bkLayerSpacing = Property<double>('bk.spacing.layer', 20.0);

/// Fixed-alignment option.  Default: [_FixedAlignment.none] (balance all four).
const bkFixedAlignment =
    Property<_FixedAlignment>('bk.fixedAlignment', _FixedAlignment.none);

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Which of the four single alignments to lock in (or NONE = balance all).
enum _FixedAlignment { none, leftDown, leftUp, rightDown, rightUp, balanced }

/// Vertical traversal direction within a layer.
enum _VDirection { down, up }

/// Horizontal traversal direction across layers.
enum _HDirection { right, left }

// ---------------------------------------------------------------------------
// Public phase entry point
// ---------------------------------------------------------------------------

/// Phase 4 of the layered algorithm: Brandes–Köpf node placement.
///
/// Pre-conditions (ensured by earlier phases):
///   - Every node is assigned to a [Layer] and [Layer.nodes] is in order.
///   - Dummy nodes for long edges are present.
///   - Ports are set up.
///
/// Post-conditions:
///   - [LNode.position.y] is the final cross-axis coordinate.
///   - [LNode.position.x] is the cumulative layer x (layers stacked left→right).
class BKNodePlacer implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    if (graph.layers.isEmpty) return;

    // --- Step 0: assign stable ids and collect neighbourhood information ----
    final ni = _NeighborhoodInformation.buildFor(graph);

    // --- Step 1: mark type-1 conflicts (needs at least 3 layers) -----------
    final markedEdges = <LEdge>{};
    _markConflicts(graph, ni, markedEdges);

    // --- Step 2: build the set of layouts to compute -----------------------
    final fixedAlign = graph.getProperty(bkFixedAlignment);
    // ELK's `favorStraightEdges` option (BKNodePlacer.process) defaults to TRUE
    // when the edge routing style is orthogonal — which is the only style this
    // engine uses. With it true, the default `NONE` alignment does NOT produce a
    // balanced (median-of-four) layout; instead it picks the single alignment
    // with the smallest height (favouring straight edges). elkjs, also routing
    // orthogonally, behaves the same — which is why it looks "left aligned" on
    // graphs like the wide layer (it lands on the LEFTDOWN/LEFTUP alignment).
    // Balancing happens only when explicitly requested via BALANCED.
    const bool favorStraightEdges = true; // orthogonal edge routing
    final bool produceBalanced =
        (fixedAlign == _FixedAlignment.none && !favorStraightEdges) ||
            fixedAlign == _FixedAlignment.balanced;

    final layouts = <_BKAlignedLayout>[];
    _BKAlignedLayout? rightDown, rightUp, leftDown, leftUp;

    switch (fixedAlign) {
      case _FixedAlignment.leftDown:
        leftDown = _BKAlignedLayout(graph, ni.nodeCount, _VDirection.down, _HDirection.left);
        layouts.add(leftDown);
      case _FixedAlignment.leftUp:
        leftUp = _BKAlignedLayout(graph, ni.nodeCount, _VDirection.up, _HDirection.left);
        layouts.add(leftUp);
      case _FixedAlignment.rightDown:
        rightDown = _BKAlignedLayout(graph, ni.nodeCount, _VDirection.down, _HDirection.right);
        layouts.add(rightDown);
      case _FixedAlignment.rightUp:
        rightUp = _BKAlignedLayout(graph, ni.nodeCount, _VDirection.up, _HDirection.right);
        layouts.add(rightUp);
      default:
        rightDown = _BKAlignedLayout(graph, ni.nodeCount, _VDirection.down, _HDirection.right);
        rightUp = _BKAlignedLayout(graph, ni.nodeCount, _VDirection.up, _HDirection.right);
        leftDown = _BKAlignedLayout(graph, ni.nodeCount, _VDirection.down, _HDirection.left);
        leftUp = _BKAlignedLayout(graph, ni.nodeCount, _VDirection.up, _HDirection.left);
        layouts.addAll([rightDown, rightUp, leftDown, leftUp]);
    }

    // --- Step 3: align + inside-block shift for each layout ----------------
    final aligner = _BKAligner(graph, ni);
    for (final bal in layouts) {
      aligner.verticalAlignment(bal, markedEdges);
      aligner.insideBlockShift(bal);
    }

    // --- Step 4: horizontal compaction for each layout ---------------------
    final compactor = _BKCompactor(graph, ni);
    for (final bal in layouts) {
      compactor.horizontalCompaction(bal);
    }

    // --- Step 5: choose / balance layout -----------------------------------
    _BKAlignedLayout? chosen;

    if (produceBalanced) {
      final balanced = _createBalancedLayout(graph, layouts, ni.nodeCount);
      if (_checkOrderConstraint(graph, balanced)) {
        chosen = balanced;
      }
    }

    if (chosen == null) {
      for (final bal in layouts) {
        if (_checkOrderConstraint(graph, bal)) {
          if (chosen == null || chosen.layoutSize() > bal.layoutSize()) {
            chosen = bal;
          }
        }
      }
    }

    // Fallback: first layout (should never reach here, but be safe).
    chosen ??= layouts.first;

    // --- Step 6: apply y-coordinates to nodes ------------------------------
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        node.position.y = chosen.y[node.id]! + chosen.innerShift[node.id]!;
      }
    }

    // NOTE: flow-axis (x) layer placement is NOT done here. ELK's Brandes-Köpf
    // placer only assigns the cross axis (y); the flow-axis x-coordinates are
    // assigned later by the orthogonal edge router (`OrthogonalRoutingGenerator`),
    // which spaces layers apart by the number of routing slots each gap needs.
    // Assigning a fixed layer spacing here (as we used to) both ignored the
    // routing width and left edges with no exit stub from their nodes.
  }

  // -------------------------------------------------------------------------
  // Conflict detection
  // -------------------------------------------------------------------------

  static const int _minLayersForConflicts = 3;

  void _markConflicts(
      LGraph graph, _NeighborhoodInformation ni, Set<LEdge> markedEdges) {
    final layers = graph.layers;
    if (layers.length < _minLayersForConflicts) return;

    final layerSize = List<int>.generate(layers.length, (i) => layers[i].nodes.length);

    // iterate from layer index 1 (need layer i-1 and i+1)
    for (int i = 1; i < layers.length - 1; i++) {
      final currentLayer = layers[i + 1]; // "next" layer (right)
      int k0 = 0;
      int l = 0;

      for (int l1 = 0; l1 < layerSize[i + 1]; l1++) {
        final vl1 = currentLayer.nodes[l1];
        final isLast = l1 == layerSize[i + 1] - 1;
        final isInner = _incidentToInnerSegment(vl1, i + 1, i, ni);

        if (isLast || isInner) {
          int k1 = layerSize[i] - 1;
          if (isInner) {
            final leftNeighbors = ni.leftNeighbors[vl1.id];
            if (leftNeighbors.isNotEmpty) {
              k1 = ni.nodeIndex[leftNeighbors.first.node.id];
            }
          }

          while (l <= l1) {
            final vl = currentLayer.nodes[l];
            if (!_incidentToInnerSegment(vl, i + 1, i, ni)) {
              for (final neighbor in ni.leftNeighbors[vl.id]) {
                final k = ni.nodeIndex[neighbor.node.id];
                if (k < k0 || k > k1) {
                  markedEdges.add(neighbor.edge);
                }
              }
            }
            l++;
          }
          k0 = k1;
        }
      }
    }
  }

  /// True when [node] in [layer1] is connected to a LONG_EDGE dummy in [layer2]
  /// via an incoming edge (i.e. it is part of an inner segment).
  bool _incidentToInnerSegment(
      LNode node, int layer1, int layer2, _NeighborhoodInformation ni) {
    if (node.type != NodeType.longEdge) return false;
    for (final edge in node.incomingEdges) {
      final srcNode = edge.source?.node;
      if (srcNode == null) continue;
      if (srcNode.type == NodeType.longEdge &&
          ni.layerIndex[srcNode.layer!.id] == layer2 &&
          ni.layerIndex[node.layer!.id] == layer1) {
        return true;
      }
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Layout balancing
  // -------------------------------------------------------------------------

  _BKAlignedLayout _createBalancedLayout(
      LGraph graph, List<_BKAlignedLayout> layouts, int nodeCount) {
    final n = layouts.length;
    final balanced = _BKAlignedLayout(graph, nodeCount, null, null);
    final width = List<double>.filled(n, 0);
    final minY = List<double>.filled(n, double.infinity);
    final maxY = List<double>.filled(n, double.negativeInfinity);
    int minWidthIdx = 0;

    for (int i = 0; i < n; i++) {
      final bal = layouts[i];
      width[i] = bal.layoutSize();
      if (width[minWidthIdx] > width[i]) minWidthIdx = i;
      for (final layer in graph.layers) {
        for (final node in layer.nodes) {
          final pos = bal.y[node.id]! + bal.innerShift[node.id]!;
          if (pos < minY[i]) minY[i] = pos;
          if (pos + node.size.y > maxY[i]) maxY[i] = pos + node.size.y;
        }
      }
    }

    final shift = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      if (layouts[i].vdir == _VDirection.down) {
        shift[i] = minY[minWidthIdx] - minY[i];
      } else {
        shift[i] = maxY[minWidthIdx] - maxY[i];
      }
    }

    final ys = List<double>.filled(n, 0);
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        for (int i = 0; i < n; i++) {
          ys[i] = layouts[i].y[node.id]! + layouts[i].innerShift[node.id]! + shift[i];
        }
        ys.sort();
        balanced.y[node.id] = (ys[(n ~/ 2) - 1] + ys[n ~/ 2]) / 2.0;
        balanced.innerShift[node.id] = 0.0;
      }
    }

    return balanced;
  }

  // -------------------------------------------------------------------------
  // Order constraint check
  // -------------------------------------------------------------------------

  bool _checkOrderConstraint(LGraph graph, _BKAlignedLayout bal) {
    for (final layer in graph.layers) {
      double pos = double.negativeInfinity;
      for (final node in layer.nodes) {
        final y = bal.y[node.id];
        final innerShift = bal.innerShift[node.id];
        if (y == null || innerShift == null) return false;
        final top = y + innerShift - node.margin.top;
        final bottom = y + innerShift + node.size.y + node.margin.bottom;
        if (top > pos && bottom > pos) {
          pos = bottom;
        } else {
          return false;
        }
      }
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Utility: find an edge between two nodes
  // -------------------------------------------------------------------------

  static LEdge? _getEdge(LNode source, LNode target) {
    for (final edge in source.connectedEdges) {
      if (edge.target?.node == target || edge.source?.node == target) {
        return edge;
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// _NeighborhoodInformation
// ---------------------------------------------------------------------------

/// Pre-computed neighbourhood data: layer/node indices, left/right neighbors.
/// Mirrors `NeighborhoodInformation.java`.
class _NeighborhoodInformation {
  int nodeCount = 0;

  /// layerIndex[layer.id] → index of that layer in graph.layers.
  late List<int> layerIndex;

  /// nodeIndex[node.id] → position of that node within its layer.
  late List<int> nodeIndex;

  /// leftNeighbors[node.id] → list of (node, edge) pairs for nodes in the
  /// immediately preceding layer that have an edge pointing to this node.
  late List<List<_NodeEdgePair>> leftNeighbors;

  /// rightNeighbors[node.id] → nodes in the immediately following layer
  /// reachable from this node.
  late List<List<_NodeEdgePair>> rightNeighbors;

  _NeighborhoodInformation._();

  static _NeighborhoodInformation buildFor(LGraph graph) {
    final ni = _NeighborhoodInformation._();

    // Count nodes and assign ids.
    ni.nodeCount = 0;
    for (final layer in graph.layers) {
      ni.nodeCount += layer.nodes.length;
    }

    ni.layerIndex = List<int>.filled(graph.layers.length, 0);
    ni.nodeIndex = List<int>.filled(ni.nodeCount, 0);

    int lId = 0;
    int nId = 0;
    for (int li = 0; li < graph.layers.length; li++) {
      final layer = graph.layers[li];
      layer.id = lId++;
      ni.layerIndex[layer.id] = li;
      for (int ni2 = 0; ni2 < layer.nodes.length; ni2++) {
        final node = layer.nodes[ni2];
        node.id = nId++;
        ni.nodeIndex[node.id] = ni2;
      }
    }

    // Build neighbor lists.
    ni.leftNeighbors = List.generate(ni.nodeCount, (_) => []);
    ni.rightNeighbors = List.generate(ni.nodeCount, (_) => []);
    _determineLeftNeighbors(ni, graph);
    _determineRightNeighbors(ni, graph);

    return ni;
  }

  static void _determineLeftNeighbors(
      _NeighborhoodInformation ni, LGraph graph) {
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        int maxPrio = 0;
        final result = <_NodeEdgePair>[];
        for (final edge in node.incomingEdges) {
          if (edge.isSelfLoop || edge.isInLayerEdge) continue;
          final srcNode = edge.source?.node;
          if (srcNode == null) continue;
          final prio = edge.getProperty(_BKProps.priorityStraightness);
          if (prio > maxPrio) {
            maxPrio = prio;
            result.clear();
          }
          if (prio == maxPrio) {
            result.add(_NodeEdgePair(srcNode, edge));
          }
        }
        result.sort((a, b) => ni.nodeIndex[a.node.id] - ni.nodeIndex[b.node.id]);
        ni.leftNeighbors[node.id] = result;
      }
    }
  }

  static void _determineRightNeighbors(
      _NeighborhoodInformation ni, LGraph graph) {
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        int maxPrio = 0;
        final result = <_NodeEdgePair>[];
        for (final edge in node.outgoingEdges) {
          if (edge.isSelfLoop || edge.isInLayerEdge) continue;
          final tgtNode = edge.target?.node;
          if (tgtNode == null) continue;
          final prio = edge.getProperty(_BKProps.priorityStraightness);
          if (prio > maxPrio) {
            maxPrio = prio;
            result.clear();
          }
          if (prio == maxPrio) {
            result.add(_NodeEdgePair(tgtNode, edge));
          }
        }
        result.sort((a, b) => ni.nodeIndex[a.node.id] - ni.nodeIndex[b.node.id]);
        ni.rightNeighbors[node.id] = result;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// _BKProps — internal properties used by BK
// ---------------------------------------------------------------------------

class _BKProps {
  /// Edge straightness priority — mirrors ELK `PRIORITY_STRAIGHTNESS`.
  static const priorityStraightness = Property<int>('bk.priority.straightness', 0);
}

// ---------------------------------------------------------------------------
// _NodeEdgePair — replaces Guava Pair<LNode, LEdge>
// ---------------------------------------------------------------------------

class _NodeEdgePair {
  final LNode node;
  final LEdge edge;
  const _NodeEdgePair(this.node, this.edge);
}

// ---------------------------------------------------------------------------
// _BKAlignedLayout — holds all per-layout arrays
// ---------------------------------------------------------------------------

/// Mirrors `BKAlignedLayout.java`.
class _BKAlignedLayout {
  final LGraph layeredGraph;
  final _VDirection? vdir;
  final _HDirection? hdir;

  /// root[node.id] — the root node of this node's block.
  late final List<LNode?> root;

  /// blockSize[node.id] — total height of the block (only valid for root nodes).
  late final List<double?> blockSize;

  /// align[node.id] — next node in the block (ring).
  late final List<LNode?> align;

  /// innerShift[node.id] — y offset within the block.
  late final List<double?> innerShift;

  /// sink[node.id] — class sink of this block's root.
  late final List<LNode?> sink;

  /// shift[node.id] — additional shift to apply to this class.
  late final List<double?> shift;

  /// y[node.id] — final y-coordinate of the block root.
  late final List<double?> y;

  /// su[node.id] — block is part of a straightened edge (used by SimpleThreshold).
  late final List<bool> su;

  /// od[node.id] — block consists only of dummy (long-edge) nodes.
  late final List<bool> od;

  _BKAlignedLayout(this.layeredGraph, int nodeCount, this.vdir, this.hdir) {
    root = List<LNode?>.filled(nodeCount, null);
    blockSize = List<double?>.filled(nodeCount, null);
    align = List<LNode?>.filled(nodeCount, null);
    innerShift = List<double?>.filled(nodeCount, null);
    sink = List<LNode?>.filled(nodeCount, null);
    shift = List<double?>.filled(nodeCount, null);
    y = List<double?>.filled(nodeCount, null);
    su = List<bool>.filled(nodeCount, false);
    od = List<bool>.filled(nodeCount, true);
  }

  /// Total y-extent of this layout.
  double layoutSize() {
    double min = double.infinity;
    double max = double.negativeInfinity;
    for (final layer in layeredGraph.layers) {
      for (final node in layer.nodes) {
        final yVal = y[node.id];
        if (yVal == null) continue;
        final bs = blockSize[root[node.id]!.id];
        if (bs == null) continue;
        if (yVal < min) min = yVal;
        final yMax = yVal + bs;
        if (yMax > max) max = yMax;
      }
    }
    return (min == double.infinity) ? 0 : max - min;
  }

  /// y delta between [src] port and [tgt] port (for block-shift calculations).
  double calculateDelta(LPort src, LPort tgt) {
    final srcPos = y[src.node.id]! +
        innerShift[src.node.id]! +
        src.position.y +
        src.anchor.y;
    final tgtPos = y[tgt.node.id]! +
        innerShift[tgt.node.id]! +
        tgt.position.y +
        tgt.anchor.y;
    return tgtPos - srcPos;
  }

  /// Shift all y-values in the block rooted at [rootNode] by [delta].
  void shiftBlock(LNode rootNode, double delta) {
    LNode current = rootNode;
    do {
      y[current.id] = y[current.id]! + delta;
      current = align[current.id]!;
    } while (current != rootNode);
  }

  double getMinY(LNode n) {
    return y[root[n.id]!.id]! + innerShift[n.id]! - n.margin.top;
  }

  double getMaxY(LNode n) {
    return y[root[n.id]!.id]! + innerShift[n.id]! + n.size.y + n.margin.bottom;
  }

  /// Maximum space the block can move upward without overlapping (UP direction).
  double checkSpaceAbove(LNode blockRoot, double delta, _NeighborhoodInformation ni) {
    double available = delta;
    LNode current = blockRoot;
    do {
      current = align[current.id]!;
      final minYCurrent = getMinY(current);
      final neighbor = _upperNeighbor(current, ni);
      if (neighbor != null) {
        final maxYNeighbor = getMaxY(neighbor);
        final spacing = _verticalSpacing(current, neighbor);
        available = math.min(available, minYCurrent - (maxYNeighbor + spacing));
      }
    } while (current != blockRoot);
    return available;
  }

  /// Maximum space the block can move downward without overlapping (DOWN direction).
  double checkSpaceBelow(LNode blockRoot, double delta, _NeighborhoodInformation ni) {
    double available = delta;
    LNode current = blockRoot;
    do {
      current = align[current.id]!;
      final maxYCurrent = getMaxY(current);
      final neighbor = _lowerNeighbor(current, ni);
      if (neighbor != null) {
        final minYNeighbor = getMinY(neighbor);
        final spacing = _verticalSpacing(current, neighbor);
        available = math.min(available, minYNeighbor - (maxYCurrent + spacing));
      }
    } while (current != blockRoot);
    return available;
  }

  LNode? _upperNeighbor(LNode n, _NeighborhoodInformation ni) {
    final idx = ni.nodeIndex[n.id];
    if (idx > 0) return n.layer!.nodes[idx - 1];
    return null;
  }

  LNode? _lowerNeighbor(LNode n, _NeighborhoodInformation ni) {
    final idx = ni.nodeIndex[n.id];
    final layerNodes = n.layer!.nodes;
    if (idx < layerNodes.length - 1) return layerNodes[idx + 1];
    return null;
  }
}

// ---------------------------------------------------------------------------
// _BKAligner
// ---------------------------------------------------------------------------

/// Performs vertical alignment and inside-block shifts.
/// Mirrors `BKAligner.java`.
class _BKAligner {
  final LGraph _graph;
  final _NeighborhoodInformation _ni;

  _BKAligner(this._graph, this._ni);

  // -------------------------------------------------------------------------
  // Vertical alignment
  // -------------------------------------------------------------------------

  void verticalAlignment(_BKAlignedLayout bal, Set<LEdge> markedEdges) {
    // Initialize root / align / innerShift for every node.
    for (final layer in _graph.layers) {
      for (final node in layer.nodes) {
        bal.root[node.id] = node;
        bal.align[node.id] = node;
        bal.innerShift[node.id] = 0.0;
      }
    }

    // Determine layer traversal order.
    final layers = bal.hdir == _HDirection.left
        ? _graph.layers.reversed.toList()
        : List<Layer>.from(_graph.layers);

    for (final layer in layers) {
      // Position counter: -1 for DOWN (increasing), MAX_INT for UP (decreasing).
      int r = bal.vdir == _VDirection.up ? 0x7fffffff : -1;

      final nodes = bal.vdir == _VDirection.up
          ? layer.nodes.reversed.toList()
          : List<LNode>.from(layer.nodes);

      for (final vik in nodes) {
        final neighbors = bal.hdir == _HDirection.left
            ? _ni.rightNeighbors[vik.id]
            : _ni.leftNeighbors[vik.id];

        if (neighbors.isEmpty) continue;

        final d = neighbors.length;
        final low = ((d + 1.0) / 2.0).floor() - 1;
        final high = ((d + 1.0) / 2.0).ceil() - 1;

        if (bal.vdir == _VDirection.up) {
          for (int m = high; m >= low; m--) {
            if (bal.align[vik.id] == vik) {
              final um = neighbors[m];
              if (!markedEdges.contains(um.edge) &&
                  r > _ni.nodeIndex[um.node.id]) {
                bal.align[um.node.id] = vik;
                bal.root[vik.id] = bal.root[um.node.id]!;
                bal.align[vik.id] = bal.root[vik.id];
                bal.od[bal.root[vik.id]!.id] =
                    bal.od[bal.root[vik.id]!.id] &&
                        vik.type == NodeType.longEdge;
                r = _ni.nodeIndex[um.node.id];
              }
            }
          }
        } else {
          for (int m = low; m <= high; m++) {
            if (bal.align[vik.id] == vik) {
              final um = neighbors[m];
              if (!markedEdges.contains(um.edge) &&
                  r < _ni.nodeIndex[um.node.id]) {
                bal.align[um.node.id] = vik;
                bal.root[vik.id] = bal.root[um.node.id]!;
                bal.align[vik.id] = bal.root[vik.id];
                bal.od[bal.root[vik.id]!.id] =
                    bal.od[bal.root[vik.id]!.id] &&
                        vik.type == NodeType.longEdge;
                r = _ni.nodeIndex[um.node.id];
              }
            }
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Inside-block shift
  // -------------------------------------------------------------------------

  void insideBlockShift(_BKAlignedLayout bal) {
    final blocks = _getBlocks(bal);

    for (final root in blocks.keys) {
      double spaceAbove = root.margin.top;
      double spaceBelow = root.size.y + root.margin.bottom;
      bal.innerShift[root.id] = 0.0;

      LNode current = root;
      LNode? next;
      while ((next = bal.align[current.id]) != root) {
        final edge = BKNodePlacer._getEdge(current, next!);
        if (edge == null) {
          // Guard: edge might not exist (e.g. in degenerate graphs).
          bal.innerShift[next.id] = bal.innerShift[current.id];
        } else {
          double portPosDiff;
          if (bal.hdir == _HDirection.left) {
            portPosDiff = (edge.target!.position.y + edge.target!.anchor.y) -
                (edge.source!.position.y + edge.source!.anchor.y);
          } else {
            portPosDiff = (edge.source!.position.y + edge.source!.anchor.y) -
                (edge.target!.position.y + edge.target!.anchor.y);
          }
          final nextInnerShift = bal.innerShift[current.id]! + portPosDiff;
          bal.innerShift[next.id] = nextInnerShift;
          spaceAbove = math.max(spaceAbove, next.margin.top - nextInnerShift);
          spaceBelow = math.max(
              spaceBelow, nextInnerShift + next.size.y + next.margin.bottom);
        }
        current = next;
      }

      // Shift all inner shifts up by spaceAbove so that the block's top = 0.
      LNode cur = root;
      do {
        bal.innerShift[cur.id] = bal.innerShift[cur.id]! + spaceAbove;
        cur = bal.align[cur.id]!;
      } while (cur != root);

      bal.blockSize[root.id] = spaceAbove + spaceBelow;
    }
  }

  // -------------------------------------------------------------------------
  // Block map helper
  // -------------------------------------------------------------------------

  static Map<LNode, List<LNode>> _getBlocks(_BKAlignedLayout bal) {
    final blocks = LinkedHashMap<LNode, List<LNode>>();
    for (final layer in bal.layeredGraph.layers) {
      for (final node in layer.nodes) {
        final root = bal.root[node.id]!;
        blocks.putIfAbsent(root, () => []).add(node);
      }
    }
    return blocks;
  }
}

// ---------------------------------------------------------------------------
// _BKCompactor
// ---------------------------------------------------------------------------

/// Performs horizontal compaction (assigns y-coordinates to blocks/classes).
/// Mirrors `BKCompactor.java`.
class _BKCompactor {
  final LGraph _graph;
  final _NeighborhoodInformation _ni;
  final Map<LNode, _ClassNode> _sinkNodes = {};

  _BKCompactor(this._graph, this._ni);

  void horizontalCompaction(_BKAlignedLayout bal) {
    // Init sink and shift arrays.
    for (final layer in _graph.layers) {
      for (final node in layer.nodes) {
        bal.sink[node.id] = node;
        bal.shift[node.id] = bal.vdir == _VDirection.up
            ? double.negativeInfinity
            : double.infinity;
      }
    }
    _sinkNodes.clear();

    // Determine layer traversal order (reversed for LEFT).
    final layers = bal.hdir == _HDirection.left
        ? _graph.layers.reversed.toList()
        : List<Layer>.from(_graph.layers);

    // Mark all blocks as unplaced.
    for (int i = 0; i < bal.y.length; i++) {
      bal.y[i] = null;
    }

    // Init threshold strategy (NullThreshold = default, no IMPROVE_STRAIGHTNESS).
    final thresh = _NullThresholdStrategy();
    thresh.init(bal, _ni);

    // Initial block placement.
    for (final layer in layers) {
      final nodes = bal.vdir == _VDirection.up
          ? layer.nodes.reversed.toList()
          : List<LNode>.from(layer.nodes);

      for (final v in nodes) {
        if (bal.root[v.id] == v) {
          _placeBlock(v, bal, thresh);
        }
      }
    }

    // Compact classes using a class-graph / longest-path approach.
    _placeClasses(bal);

    // Apply final coordinates.
    for (final layer in layers) {
      for (final v in layer.nodes) {
        bal.y[v.id] = bal.y[bal.root[v.id]!.id];

        if (v == bal.root[v.id]) {
          final sinkShift = bal.shift[bal.sink[v.id]!.id];
          if (sinkShift != null) {
            if ((bal.vdir == _VDirection.up &&
                    sinkShift > double.negativeInfinity) ||
                (bal.vdir == _VDirection.down &&
                    sinkShift < double.infinity)) {
              bal.y[v.id] = bal.y[v.id]! + sinkShift;
            }
          }
        }
      }
    }

    thresh.postProcess();
  }

  // -------------------------------------------------------------------------
  // Block placement
  // -------------------------------------------------------------------------

  void _placeBlock(LNode root, _BKAlignedLayout bal, _ThresholdStrategy thresh) {
    if (bal.y[root.id] != null) return; // already placed

    bool isInitial = true;
    bal.y[root.id] = 0.0;

    LNode currentNode = root;
    double threshVal = bal.vdir == _VDirection.down
        ? double.negativeInfinity
        : double.infinity;

    do {
      final currentIdx = _ni.nodeIndex[currentNode.id];
      final layerNodes = currentNode.layer!.nodes;
      final layerSize = layerNodes.length;

      final needsNeighborCheck = (bal.vdir == _VDirection.down && currentIdx > 0) ||
          (bal.vdir == _VDirection.up && currentIdx < layerSize - 1);

      if (needsNeighborCheck) {
        // Get the node above (DOWN) or below (UP) in this layer.
        final neighbor = bal.vdir == _VDirection.up
            ? layerNodes[currentIdx + 1]
            : layerNodes[currentIdx - 1];
        final neighborRoot = bal.root[neighbor.id]!;

        // Recursively ensure neighbor's block is placed.
        _placeBlock(neighborRoot, bal, thresh);

        threshVal = thresh.calculateThreshold(threshVal, root, currentNode);

        // Update class membership.
        if (bal.sink[root.id] == root) {
          bal.sink[root.id] = bal.sink[neighborRoot.id];
        }

        final spacing = _verticalSpacing(currentNode, neighbor);

        if (bal.sink[root.id] == bal.sink[neighborRoot.id]) {
          // Same class — place relative to neighbor.
          double newPos;
          if (bal.vdir == _VDirection.up) {
            newPos = bal.y[neighborRoot.id]! +
                bal.innerShift[neighbor.id]! -
                neighbor.margin.top -
                spacing -
                currentNode.margin.bottom -
                currentNode.size.y -
                bal.innerShift[currentNode.id]!;

            if (isInitial) {
              isInitial = false;
              bal.y[root.id] = math.min(newPos, threshVal);
            } else {
              bal.y[root.id] = math.min(
                  bal.y[root.id]!, math.min(newPos, threshVal));
            }
          } else {
            // DOWN
            newPos = bal.y[neighborRoot.id]! +
                bal.innerShift[neighbor.id]! +
                neighbor.size.y +
                neighbor.margin.bottom +
                spacing +
                currentNode.margin.top -
                bal.innerShift[currentNode.id]!;

            if (isInitial) {
              isInitial = false;
              bal.y[root.id] = math.max(newPos, threshVal);
            } else {
              bal.y[root.id] = math.max(
                  bal.y[root.id]!, math.max(newPos, threshVal));
            }
          }
        } else {
          // Different classes — record required separation in class graph.
          final nodeSpacing = _graph.getProperty(bkNodeNodeSpacing);
          final sinkNode = _getOrCreateClassNode(bal.sink[root.id]!, bal);
          final neighborSink =
              _getOrCreateClassNode(bal.sink[neighborRoot.id]!, bal);

          if (bal.vdir == _VDirection.up) {
            final requiredSpace = bal.y[root.id]! +
                bal.innerShift[currentNode.id]! +
                currentNode.size.y +
                currentNode.margin.bottom +
                nodeSpacing -
                (bal.y[neighborRoot.id]! +
                    bal.innerShift[neighbor.id]! -
                    neighbor.margin.top);
            sinkNode.addEdge(neighborSink, requiredSpace);
          } else {
            final requiredSpace = bal.y[root.id]! +
                bal.innerShift[currentNode.id]! -
                currentNode.margin.top -
                bal.y[neighborRoot.id]! -
                bal.innerShift[neighbor.id]! -
                neighbor.size.y -
                neighbor.margin.bottom -
                nodeSpacing;
            sinkNode.addEdge(neighborSink, requiredSpace);
          }
        }
      } else {
        threshVal = thresh.calculateThreshold(threshVal, root, currentNode);
      }

      currentNode = bal.align[currentNode.id]!;
    } while (currentNode != root);

    thresh.finishBlock(root);
  }

  // -------------------------------------------------------------------------
  // Class placement (longest-path in class graph)
  // -------------------------------------------------------------------------

  void _placeClasses(_BKAlignedLayout bal) {
    final Queue<_ClassNode> sinks = Queue();
    for (final cn in _sinkNodes.values) {
      if (cn.indegree == 0) sinks.add(cn);
    }

    while (sinks.isNotEmpty) {
      final cn = sinks.removeFirst();
      cn.classShift ??= 0.0;

      for (final edge in cn.outgoing) {
        if (edge.target.classShift == null) {
          edge.target.classShift = cn.classShift! + edge.separation;
        } else if (bal.vdir == _VDirection.down) {
          edge.target.classShift =
              math.min(edge.target.classShift!, cn.classShift! + edge.separation);
        } else {
          edge.target.classShift =
              math.max(edge.target.classShift!, cn.classShift! + edge.separation);
        }

        edge.target.indegree--;
        if (edge.target.indegree == 0) sinks.add(edge.target);
      }
    }

    for (final cn in _sinkNodes.values) {
      bal.shift[cn.node.id] = cn.classShift;
    }
  }

  _ClassNode _getOrCreateClassNode(LNode sinkNode, _BKAlignedLayout bal) {
    return _sinkNodes.putIfAbsent(sinkNode, () {
      final cn = _ClassNode();
      cn.node = sinkNode;
      return cn;
    });
  }
}

// ---------------------------------------------------------------------------
// _ClassNode / _ClassEdge (class graph for compaction)
// ---------------------------------------------------------------------------

class _ClassNode {
  double? classShift;
  late LNode node;
  final List<_ClassEdge> outgoing = [];
  int indegree = 0;

  void addEdge(_ClassNode target, double separation) {
    final e = _ClassEdge();
    e.target = target;
    e.separation = separation;
    target.indegree++;
    outgoing.add(e);
  }
}

class _ClassEdge {
  double separation = 0;
  late _ClassNode target;
}

// ---------------------------------------------------------------------------
// Threshold strategies
// ---------------------------------------------------------------------------

abstract class _ThresholdStrategy {
  late _BKAlignedLayout bal;
  late _NeighborhoodInformation ni;

  void init(_BKAlignedLayout theBal, _NeighborhoodInformation theNi) {
    bal = theBal;
    ni = theNi;
  }

  void finishBlock(LNode n) {}

  double calculateThreshold(double oldThresh, LNode blockRoot, LNode currentNode);

  void postProcess();
}

/// Classic BK compaction — threshold has no effect.
/// Mirrors `NullThresholdStrategy`.
class _NullThresholdStrategy extends _ThresholdStrategy {
  @override
  double calculateThreshold(double oldThresh, LNode blockRoot, LNode currentNode) {
    return bal.vdir == _VDirection.up
        ? double.infinity
        : double.negativeInfinity;
  }

  @override
  void postProcess() {
    // Nothing to do.
  }
}

// TODO(elk-faithful): Port SimpleThresholdStrategy (IMPROVE_STRAIGHTNESS option).
// TODO(elk-faithful): North/south port handling in verticalAlignment / insideBlockShift.
// TODO(elk-faithful): Big-node handling.
// TODO(elk-faithful): Self-loop spacing in verticalSpacing.

// ---------------------------------------------------------------------------
// Spacing helper (package-private)
// ---------------------------------------------------------------------------

/// Returns the required vertical separation between two nodes in the same layer.
/// Mirrors ELK's `Spacings.getVerticalSpacing`.
double _verticalSpacing(LNode a, LNode b) {
  final g = a.graph;
  final isDummyA = a.type != NodeType.normal;
  final isDummyB = b.type != NodeType.normal;
  if (!isDummyA && !isDummyB) return g.getProperty(bkNodeNodeSpacing);
  if (isDummyA && isDummyB) return g.getProperty(bkEdgeEdgeSpacing);
  return g.getProperty(bkNodeEdgeSpacing);
}

/// Phase 3 — faithful port of ELK's `LayerSweepCrossingMinimizer` with the
/// `BarycenterHeuristic` (default strategy).
///
/// Reference Java sources:
///   p3order/LayerSweepCrossingMinimizer.java
///   p3order/BarycenterHeuristic.java
///   p3order/AbstractBarycenterPortDistributor.java
///   p3order/counting/CrossingsCounter.java
///   p3order/counting/AllCrossingsCounter.java
///   p3order/counting/BinaryIndexedTree.java
///   p3order/GraphInfoHolder.java
///   p3order/SweepCopy.java
///
/// Scope: default config only — barycenter heuristic, forward/backward sweeps,
/// per-layer port distribution, between-layer and in-layer crossing counting.
///
/// Omissions (all marked TODO(elk-faithful)):
///   - Hierarchical / compound-graph sweep (nested graphs)
///   - ForsterConstraintResolver (ordering constraints between nodes)
///   - NorthSouth-port dummy crossing counting
///   - HyperedgeCrossingsCounter (multi-edge hyperedge variant)
///   - Greedy-switch heuristic, median heuristic (non-default CrossMinTypes)
///   - Model-order influence on the crossing counter (the soft considerModelOrder
///     node/port influence terms); the deterministic model-order *ordering* path
///     is ported.
///
/// Randomization IS faithful: ELK's barycenter heuristic is non-deterministic
/// (it randomizes the first layer and perturbs barycenters), and the driver
/// runs `thoroughness` (default 7) randomized restarts keeping the order with
/// the fewest crossings (`compareDifferentRandomizedLayouts`). We replicate the
/// algorithm with a faithful `java.util.Random` port (see `java_random.dart`).
/// Exact bit-parity with elkjs is not claimed (the RNG call sequence over the
/// whole computation would have to match), but the multi-restart keep-best
/// behaviour finds crossing-free layouts where they exist, as ELK does.
library;

import 'java_random.dart';
import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// ELK default option values (default-config port)
// ---------------------------------------------------------------------------

/// ELK option `org.eclipse.elk.layered.thoroughness` — number of randomized
/// restarts in `compareDifferentRandomizedLayouts`. Default 7.
const int _thoroughness = 7;

/// ELK option `org.eclipse.elk.randomSeed` — default 1. ELK builds
/// `new Random(randomSeed)` for the minimizer.
const int _randomSeed = 1;

// ---------------------------------------------------------------------------
// Property constants defined here (not in shared files)
// ---------------------------------------------------------------------------

/// Whether port order is fixed on a node. ELK: `LayeredOptions.PORT_CONSTRAINTS`
/// mapped to the `isOrderFixed()` notion — here a simple bool: true = fixed order.
const _portOrderFixed = Property<bool>('p3.portOrderFixed', false);

// ---------------------------------------------------------------------------
// Model-order properties (public — wired by elk_layered_engine.dart)
// ---------------------------------------------------------------------------

/// Per-node model-order index (declaration order in the input graph).
/// ELK internal property id: `"modelOrder"`.
/// Set by the engine on every LNode before P3 runs.
const modelOrder = Property<int>('modelOrder');

/// Graph-level flag: bias barycenter tie-breaking toward input-model order.
/// ELK option id: `"org.eclipse.elk.layered.considerModelOrder.strategy"`
/// (non-NONE activates the ModelOrderBarycenterHeuristic comparator path).
/// Set this to `true` on the LGraph when the elk option is not NONE.
const considerModelOrder = Property<bool>('considerModelOrder', false);

/// Graph-level flag: model order dominates — no reordering that violates it.
/// ELK option id: `"org.eclipse.elk.layered.crossingMinimization.forceNodeModelOrder"`.
/// When `true`, insertion sort is used so no real node ever moves past another
/// real node against their model-order index.
const forceNodeModelOrder = Property<bool>('forceNodeModelOrder', false);

// ---------------------------------------------------------------------------
// Public processor
// ---------------------------------------------------------------------------

/// Minimizes edge crossings by sweeping left→right then right→left through
/// the layers, applying the barycenter heuristic to reorder nodes within each
/// free layer, and keeping the arrangement with the fewest crossings.
///
/// Postcondition: `Layer.nodes` lists are reordered; port lists within each
/// node are also reordered (when port order is not fixed).
class LayerSweepCrossingMinimizer implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final layers = graph.layers;
    if (layers.isEmpty) return;
    if (layers.every((l) => l.nodes.isEmpty)) return;
    if (layers.length == 1 && layers[0].nodes.length == 1) return;

    // Build the working node-order matrix  [layer][position]
    final order = _buildOrder(layers);

    // Assign stable IDs for layers, nodes and ports (used as array indices).
    _assignIds(order);

    // Initialise port-rank and barycenter state arrays.
    final nPorts = _countPorts(order);
    final portRanks = List<double>.filled(nPorts, 0);
    final portPositions = List<int>.filled(nPorts, 0);
    final bary = _initBarycenterState(order);

    // ELK seeds one `java.util.Random` for the whole minimizer:
    //   random = new Random(randomSeed);            // randomSeed option, default 1
    //   long reseed = random.nextLong();
    //   ... compareDifferentRandomizedLayouts() does random.setSeed(reseed)
    // We replicate that exact handshake with a faithful java.util.Random port.
    final random = JavaRandom(_randomSeed);
    final reseed = random.nextLong();
    random.setSeed(reseed);

    final portDist = _PortDistributor(portRanks, order);
    final crossMin = _BarycenterHeuristic(portRanks, bary, graph, random);
    final crossCount = _AllCrossingsCounter(portPositions, order);

    // ELK's chooseMinimizingMethod: the barycenter heuristic is *not*
    // deterministic (it randomizes the first layer and perturbs barycenters),
    // so the driver is compareDifferentRandomizedLayouts — `thoroughness`
    // randomized restarts, keeping the order with the fewest crossings. The
    // model-order path is deterministic (FIRST_TRY_WITH_INITIAL_ORDER), so we
    // run it once.
    final _SweepCopy best;
    if (crossMin.useModelOrder) {
      best = _minimizeCrossingsWithCounter(order, crossMin, portDist, crossCount)
          .bestCopy;
    } else {
      best = _compareDifferentRandomizedLayouts(
          order, crossMin, portDist, crossCount);
    }

    // Apply the best found order back to the graph.
    best.transferToGraph(graph);
  }

  /// Mirrors `LayerSweepCrossingMinimizer.compareDifferentRandomizedLayouts`:
  /// run up to `thoroughness` randomized restarts and keep the order with the
  /// fewest total crossings, stopping early at zero.
  _SweepCopy _compareDifferentRandomizedLayouts(
    List<List<LNode>> order,
    _BarycenterHeuristic crossMin,
    _PortDistributor portDist,
    _AllCrossingsCounter crossCount,
  ) {
    var bestCrossings = 1 << 62;
    _SweepCopy? bestCopy;
    for (var i = 0; i < _thoroughness; i++) {
      final run =
          _minimizeCrossingsWithCounter(order, crossMin, portDist, crossCount);
      if (run.crossings < bestCrossings) {
        bestCrossings = run.crossings;
        bestCopy = run.bestCopy;
        if (bestCrossings == 0) break;
      }
    }
    return bestCopy!;
  }

  /// Mirrors `LayerSweepCrossingMinimizer.minimizeCrossingsWithCounter`: one
  /// randomized restart. Randomizes the first layer, sweeps forward, then keeps
  /// alternating direction while crossings strictly decrease. Returns the best
  /// order reached in this run and its crossing count.
  ({int crossings, _SweepCopy bestCopy}) _minimizeCrossingsWithCounter(
    List<List<LNode>> order,
    _BarycenterHeuristic crossMin,
    _PortDistributor portDist,
    _AllCrossingsCounter crossCount,
  ) {
    // Model-order path is deterministic and starts forward; otherwise the
    // initial sweep direction is random (ELK: random.nextBoolean()).
    var forward = crossMin.useModelOrder ? true : crossMin.random.nextBoolean();

    _setFirstLayerOrder(order, forward, crossMin);
    _sweepReducingCrossings(order, forward, true, crossMin, portDist);

    var crossingsInGraph = crossCount.countAllCrossings(order);
    var currentlyBest = _SweepCopy(order);
    int oldCrossings;
    do {
      // Capture the current (best-so-far) order before the next sweep.
      currentlyBest = _SweepCopy(order);
      if (crossingsInGraph == 0) {
        return (crossings: 0, bestCopy: currentlyBest);
      }
      forward = !forward;
      oldCrossings = crossingsInGraph;
      _sweepReducingCrossings(order, forward, false, crossMin, portDist);
      crossingsInGraph = crossCount.countAllCrossings(order);
    } while (oldCrossings > crossingsInGraph);

    return (crossings: oldCrossings, bestCopy: currentlyBest);
  }

  // -------------------------------------------------------------------------
  // Initialisation helpers
  // -------------------------------------------------------------------------

  /// Builds the [layer][position] working matrix from the graph's layers.
  List<List<LNode>> _buildOrder(List<Layer> layers) {
    return [
      for (final layer in layers) List<LNode>.from(layer.nodes),
    ];
  }

  /// Assigns contiguous IDs needed as array indices.
  /// - `layer.id` = layer index
  /// - `node.id`  = position within its layer (node index)
  /// - `port.id`  = global port index
  void _assignIds(List<List<LNode>> order) {
    int portId = 0;
    for (var l = 0; l < order.length; l++) {
      final layer = order[l];
      for (var n = 0; n < layer.length; n++) {
        final node = layer[n];
        node.id = n;
        for (final port in node.ports) {
          port.id = portId++;
        }
      }
    }
  }

  int _countPorts(List<List<LNode>> order) {
    int count = 0;
    for (final layer in order) {
      for (final node in layer) {
        count += node.ports.length;
      }
    }
    return count;
  }

  /// Allocate a [_BarycenterState] for every node, indexed by [layer][node].
  List<List<_BarycenterState>> _initBarycenterState(List<List<LNode>> order) {
    return [
      for (final layer in order)
        [for (final node in layer) _BarycenterState(node)],
    ];
  }

  // -------------------------------------------------------------------------
  // Sweep orchestration (mirrors LayerSweepCrossingMinimizer.sweepReducingCrossings)
  // -------------------------------------------------------------------------

  int _firstIndex(bool forward, int length) => forward ? 0 : length - 1;
  int _firstFree(bool forward, int length) => forward ? 1 : length - 2;
  int _next(bool forward) => forward ? 1 : -1;
  bool _notEnd(int length, int i, bool forward) =>
      forward ? i < length : i >= 0;

  void _setFirstLayerOrder(
    List<List<LNode>> order,
    bool isForward,
    _BarycenterHeuristic crossMin,
  ) {
    final startIdx = _firstIndex(isForward, order.length);
    // ELK: setFirstLayerOrder → minimizeCrossings(randomize=true) →
    //   randomizeBarycenters: barycenter = random.nextDouble() per node.
    // When considerModelOrder is active we instead seed by each node's
    // model-order index so the first layer starts in declaration order
    // (the FIRST_TRY_WITH_INITIAL_ORDER behaviour).
    final layer = order[startIdx];
    final baryList = crossMin.bary;
    final useModelOrder = crossMin.useModelOrder;
    for (var i = 0; i < layer.length; i++) {
      final node = layer[i];
      final state = baryList[startIdx][node.id];
      final double seedValue = useModelOrder
          ? (node.hasProperty(modelOrder)
              ? node.getProperty(modelOrder).toDouble()
              : i.toDouble())
          : crossMin.random.nextDouble();
      state.barycenter = seedValue;
      state.summedWeight = seedValue;
      state.degree = 1;
    }
    // Sort by those barycenters (model-order-aware when useModelOrder is set).
    _sortByBarycenter(order, startIdx, crossMin.bary, crossMin: crossMin);
  }

  void _sweepReducingCrossings(
    List<List<LNode>> order,
    bool forward,
    bool firstSweep,
    _BarycenterHeuristic crossMin,
    _PortDistributor portDist,
  ) {
    final length = order.length;
    // Distribute ports for the first (fixed) layer.
    portDist.distributePortsWhileSweeping(order, _firstIndex(forward, length), forward);

    // Sweep through the free layers.
    for (
      var i = _firstFree(forward, length);
      _notEnd(length, i, forward);
      i += _next(forward)
    ) {
      crossMin.minimizeCrossings(order, i, forward, firstSweep);
      portDist.distributePortsWhileSweeping(order, i, forward);
      // TODO(elk-faithful): sweepInHierarchicalNodes omitted (nested graphs).
    }
  }

  void _sortByBarycenter(
    List<List<LNode>> order,
    int layerIdx,
    List<List<_BarycenterState>> bary, {
    _BarycenterHeuristic? crossMin,
  }) {
    final stateList = bary[layerIdx];
    if (crossMin != null && crossMin.useModelOrder) {
      order[layerIdx].sort((a, b) => crossMin._compareNodes(a, b, stateList));
    } else {
      order[layerIdx].sort((a, b) {
        final sa = stateList[a.id];
        final sb = stateList[b.id];
        final ba = sa.barycenter;
        final bb = sb.barycenter;
        if (ba != null && bb != null) return ba.compareTo(bb);
        if (ba != null) return -1;
        if (bb != null) return 1;
        return 0;
      });
    }
    // Re-assign node IDs after sort so they remain contiguous indices.
    for (var n = 0; n < order[layerIdx].length; n++) {
      order[layerIdx][n].id = n;
    }
  }
}

// ---------------------------------------------------------------------------
// Barycenter heuristic
// (BarycenterHeuristic.java — inner calculation methods)
// ---------------------------------------------------------------------------

class _BarycenterState {
  _BarycenterState(this.node);
  final LNode node;
  double summedWeight = 0;
  int degree = 0;
  double? barycenter;
  bool visited = false;
}

class _BarycenterHeuristic {
  _BarycenterHeuristic(this._portRanks, this.bary, LGraph graph, this.random)
      : useModelOrder = graph.getProperty(considerModelOrder),
        _forceModelOrder = graph.getProperty(forceNodeModelOrder);

  /// Shared port-ranks array (written by `_PortDistributor.calculatePortRanks`).
  final List<double> _portRanks;

  /// The seeded RNG (faithful `java.util.Random`) used for barycenter
  /// perturbation and first-layer randomization.
  final JavaRandom random;

  /// Per-layer per-node barycenter state; indexed [layer][node.id].
  final List<List<_BarycenterState>> bary;

  /// True when the graph has `considerModelOrder = true` (NONE strategy → false).
  final bool useModelOrder;

  /// True when `forceNodeModelOrder` is set on the graph — insertion sort is
  /// used instead of stable sort so that model order dominates for real nodes.
  final bool _forceModelOrder;

  // Transitive ordering caches for ModelOrderBarycenterHeuristic.
  // Mirrors the per-sort `biggerThan` / `smallerThan` maps.
  final Map<LNode, Set<LNode>> _biggerThan = {};
  final Map<LNode, Set<LNode>> _smallerThan = {};

  /// ELK adds a small random perturbation in `[-RANDOM_AMOUNT/2, +RANDOM_AMOUNT/2]`
  /// to each computed barycenter to increase the diversity of solutions across
  /// the `thoroughness` restarts. `BarycenterHeuristic.RANDOM_AMOUNT = 0.07f`.
  static const double _randomAmount = 0.07;

  /// Mirrors `ICrossingMinimizationHeuristic.minimizeCrossings`.
  void minimizeCrossings(
    List<List<LNode>> order,
    int freeLayerIndex,
    bool forwardSweep,
    bool isFirstSweep,
  ) {
    // Calculate port ranks for the fixed (already-ordered) neighbour layer.
    final isFirst = freeLayerIndex ==
        (forwardSweep ? 0 : order.length - 1);
    if (!isFirst) {
      final fixedLayerIndex = freeLayerIndex + (forwardSweep ? -1 : 1);
      final portType = forwardSweep ? _PortType.output : _PortType.input;
      _calculatePortRanks(order[fixedLayerIndex], portType, _portRanks);
    }

    final firstNodeInLayer = order[freeLayerIndex].isEmpty
        ? null
        : order[freeLayerIndex][0];
    // preOrdered = not first sweep, or first node is an external-port dummy.
    final preOrdered = !isFirstSweep ||
        (firstNodeInLayer?.type == NodeType.externalPort);

    final layer = order[freeLayerIndex];
    _calculateBarycenters(layer, freeLayerIndex, forwardSweep);
    _fillInUnknownBarycenters(layer, freeLayerIndex, preOrdered);

    if (layer.length > 1) {
      if (_forceModelOrder) {
        // Insertion sort: no real node may move past another real node against
        // model order. Faithful to ModelOrderBarycenterHeuristic.insertionSort.
        _insertionSort(layer, freeLayerIndex);
        _clearTransitiveOrdering();
      } else {
        final stateList = bary[freeLayerIndex];
        layer.sort((a, b) => _compareNodes(a, b, stateList));
        // TODO(elk-faithful): constraintResolver.processConstraints omitted
        //   (ForsterConstraintResolver / ordering constraints not ported).
      }
    }

    // Re-number node IDs to reflect new positions.
    for (var n = 0; n < layer.length; n++) {
      layer[n].id = n;
    }
  }

  // ---------------------------------------------------------------------------
  // Model-order comparator (faithful to ModelOrderBarycenterHeuristic)
  // ---------------------------------------------------------------------------

  /// Compares two nodes: model order takes priority (when both have it and
  /// `useModelOrder` is set), falling back to barycenter.
  /// Mirrors the `barycenterStateComparator` lambda in
  /// `ModelOrderBarycenterHeuristic` (without the group-model-order sub-path
  /// which is not ported).
  int _compareNodes(LNode n1, LNode n2, List<_BarycenterState> stateList) {
    if (!useModelOrder) {
      return _compareByBarycenter(n1, n2, stateList);
    }

    // First check transitive ordering already established in this sort pass.
    final transitiveResult = _compareByTransitiveDeps(n1, n2);
    if (transitiveResult != 0) return transitiveResult;

    // Both have model order → compare by model order index.
    if (n1.hasProperty(modelOrder) && n2.hasProperty(modelOrder)) {
      final mo1 = n1.getProperty(modelOrder);
      final mo2 = n2.getProperty(modelOrder);
      final cmp = mo1.compareTo(mo2);
      if (cmp < 0) {
        _updateBiggerAndSmaller(n1, n2);
        return cmp;
      } else if (cmp > 0) {
        _updateBiggerAndSmaller(n2, n1);
        return cmp;
      }
      // Equal model orders: fall through to barycenter.
    }
    // One or both nodes have no model order → fall back to barycenter.
    return _compareByBarycenter(n1, n2, stateList);
  }

  int _compareByBarycenter(LNode n1, LNode n2, List<_BarycenterState> stateList) {
    final sa = stateList[n1.id];
    final sb = stateList[n2.id];
    final ba = sa.barycenter;
    final bb = sb.barycenter;
    if (ba != null && bb != null) {
      final cmp = ba.compareTo(bb);
      if (cmp < 0) {
        _updateBiggerAndSmaller(n1, n2);
      } else if (cmp > 0) {
        _updateBiggerAndSmaller(n2, n1);
      }
      return cmp;
    }
    if (ba != null) {
      _updateBiggerAndSmaller(n1, n2);
      return -1;
    }
    if (bb != null) {
      _updateBiggerAndSmaller(n2, n1);
      return 1;
    }
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Transitive ordering (ModelOrderBarycenterHeuristic.biggerThan/smallerThan)
  // ---------------------------------------------------------------------------

  int _compareByTransitiveDeps(LNode n1, LNode n2) {
    final n1BiggerThan = _biggerThan.putIfAbsent(n1, () => {});
    final n2BiggerThan = _biggerThan.putIfAbsent(n2, () => {});
    _smallerThan.putIfAbsent(n1, () => {});
    _smallerThan.putIfAbsent(n2, () => {});

    if (n1BiggerThan.contains(n2)) return 1;
    if (n2BiggerThan.contains(n1)) return -1;

    final n1SmallerThan = _smallerThan[n1]!;
    final n2SmallerThan = _smallerThan[n2]!;

    if (n1SmallerThan.contains(n2)) return -1;
    if (n2SmallerThan.contains(n1)) return 1;

    return 0;
  }

  /// Mirrors `ModelOrderBarycenterHeuristic.updateBiggerAndSmallerAssociations`.
  void _updateBiggerAndSmaller(LNode bigger, LNode smaller) {
    final biggerBT = _biggerThan.putIfAbsent(bigger, () => {});
    final smallerBT = _biggerThan.putIfAbsent(smaller, () => {});
    final biggerST = _smallerThan.putIfAbsent(bigger, () => {});
    final smallerST = _smallerThan.putIfAbsent(smaller, () => {});

    biggerBT.add(smaller);
    smallerST.add(bigger);

    for (final verySmall in List.of(smallerBT)) {
      biggerBT.add(verySmall);
      _smallerThan.putIfAbsent(verySmall, () => {}).add(bigger);
      _smallerThan[verySmall]!.addAll(biggerST);
    }
    for (final veryBig in List.of(biggerST)) {
      smallerST.add(veryBig);
      _biggerThan.putIfAbsent(veryBig, () => {}).add(smaller);
      _biggerThan[veryBig]!.addAll(smallerBT);
    }
  }

  void _clearTransitiveOrdering() {
    _biggerThan.clear();
    _smallerThan.clear();
  }

  // ---------------------------------------------------------------------------
  // Insertion sort (ModelOrderBarycenterHeuristic.insertionSort)
  // ---------------------------------------------------------------------------

  /// Insertion sort that respects transitive model-order constraints: a real
  /// node (one with a `modelOrder` property) is never moved past another real
  /// node if their model orders conflict — dummy nodes (long edges, etc.) are
  /// still freely placed by barycenter.
  ///
  /// Mirrors `ModelOrderBarycenterHeuristic.insertionSort`.
  void _insertionSort(List<LNode> layer, int layerIndex) {
    final stateList = bary[layerIndex];
    for (var i = 1; i < layer.length; i++) {
      final temp = layer[i];
      var j = i;
      while (j > 0 && _compareNodes(layer[j - 1], temp, stateList) > 0) {
        layer[j] = layer[j - 1];
        j--;
      }
      layer[j] = temp;
    }
    _clearTransitiveOrdering();
  }

  void _calculateBarycenters(
    List<LNode> layer,
    int layerIndex,
    bool forward,
  ) {
    for (final node in layer) {
      bary[layerIndex][node.id].visited = false;
    }
    for (final node in layer) {
      _calculateBarycenter(node, layerIndex, forward);
    }
  }

  void _calculateBarycenter(LNode node, int layerIndex, bool forward) {
    final state = bary[layerIndex][node.id];
    if (state.visited) return;
    state.visited = true;
    state.degree = 0;
    state.summedWeight = 0;
    state.barycenter = null;

    for (final freePort in node.ports) {
      // Predecessor ports when forward (ports of nodes in the fixed left layer);
      // successor ports when backward.
      final connectedPorts = forward
          ? freePort.incomingEdges.map((e) => e.source).whereType<LPort>()
          : freePort.outgoingEdges.map((e) => e.target).whereType<LPort>();

      for (final fixedPort in connectedPorts) {
        final fixedNode = fixedPort.node;
        if (fixedNode.layer == node.layer) {
          // In-layer edge: recurse and inherit the other node's barycenter.
          if (fixedNode != node) {
            // Determine the layer index of the fixed node.
            // Since all in-layer nodes share the same Layer object, layerIndex is correct.
            _calculateBarycenter(fixedNode, layerIndex, forward);
            state.degree += bary[layerIndex][fixedNode.id].degree;
            state.summedWeight += bary[layerIndex][fixedNode.id].summedWeight;
          }
        } else {
          // Cross-layer edge: use the port's pre-computed rank.
          state.summedWeight += _portRanks[fixedPort.id];
          state.degree++;
        }
      }
    }
    // TODO(elk-faithful): BARYCENTER_ASSOCIATES property not handled.

    if (state.degree > 0) {
      // Small random perturbation, exactly as ELK: increases solution diversity
      // so the thoroughness restarts can escape tie-broken local optima.
      state.summedWeight += random.nextFloat() * _randomAmount - _randomAmount / 2;
      state.barycenter = state.summedWeight / state.degree;
    }
  }

  /// Mirrors `BarycenterHeuristic.fillInUnknownBarycenters`.
  void _fillInUnknownBarycenters(
    List<LNode> layer,
    int layerIndex,
    bool preOrdered,
  ) {
    if (preOrdered) {
      // Use the midpoint between neighbouring known values.
      double lastValue = -1;
      for (var idx = 0; idx < layer.length; idx++) {
        final node = layer[idx];
        final state = bary[layerIndex][node.id];
        if (state.barycenter == null) {
          double nextValue = lastValue + 1;
          // Look ahead for next defined value.
          for (var j = idx + 1; j < layer.length; j++) {
            final nb = bary[layerIndex][layer[j].id].barycenter;
            if (nb != null) {
              nextValue = nb;
              break;
            }
          }
          final value = (lastValue + nextValue) / 2;
          state.barycenter = value;
          state.summedWeight = value;
          state.degree = 1;
          lastValue = value;
        } else {
          lastValue = state.barycenter!;
        }
      }
    } else {
      // No previous ordering: ELK gives each barycenter-less node a random
      // placement `random.nextFloat() * maxBary - 1`.
      double maxBary = 0;
      for (final node in layer) {
        final b = bary[layerIndex][node.id].barycenter;
        if (b != null && b > maxBary) maxBary = b;
      }
      maxBary += 2;
      for (final node in layer) {
        final state = bary[layerIndex][node.id];
        if (state.barycenter == null) {
          final value = random.nextFloat() * maxBary - 1;
          state.barycenter = value;
          state.summedWeight = value;
          state.degree = 1;
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Port distributor
// (AbstractBarycenterPortDistributor.java — concrete logic inlined)
// ---------------------------------------------------------------------------

enum _PortType { input, output }

/// Port-rank calculator and port distributor.
/// Mirrors `AbstractBarycenterPortDistributor` with the concrete subclass
/// logic for the "barycenter" variant (ranks = position within layer).
class _PortDistributor {
  _PortDistributor(this._portRanks, List<List<LNode>> initialOrder) {
    _nodePositions = List<List<int>>.generate(
      initialOrder.length,
      (l) => List<int>.filled(initialOrder[l].length, 0),
    );
    for (var l = 0; l < initialOrder.length; l++) {
      for (var n = 0; n < initialOrder[l].length; n++) {
        _nodePositions[l][n] = n;
      }
    }
  }

  final List<double> _portRanks;
  late List<List<int>> _nodePositions;
  final List<LPort> _inLayerPorts = [];
  final List<double> _portBarycenter = [];

  // Grow _portBarycenter lazily to cover any port id.
  void _ensurePortBary(int portId) {
    while (_portBarycenter.length <= portId) {
      _portBarycenter.add(0);
    }
  }

  /// Mirrors `AbstractBarycenterPortDistributor.distributePortsWhileSweeping`.
  void distributePortsWhileSweeping(
    List<List<LNode>> nodeOrder,
    int currentIndex,
    bool isForwardSweep,
  ) {
    _updateNodePositions(nodeOrder, currentIndex);
    final freeLayer = nodeOrder[currentIndex];
    final side = isForwardSweep ? PortSide.west : PortSide.east;
    final isFirst = isForwardSweep
        ? currentIndex == 0
        : currentIndex == nodeOrder.length - 1;

    if (!isFirst) {
      final fixedIdx = isForwardSweep ? currentIndex - 1 : currentIndex + 1;
      final fixedLayer = nodeOrder[fixedIdx];
      final ptFree = isForwardSweep ? _PortType.output : _PortType.input;
      _calculatePortRanks(fixedLayer, ptFree, _portRanks);
      for (final node in freeLayer) {
        _distributePorts(node, side, nodeOrder[currentIndex]);
      }
      // Calculate ranks from the free layer for the fixed layer's other side.
      final ptFixed = isForwardSweep ? _PortType.input : _PortType.output;
      _calculatePortRanks(freeLayer, ptFixed, _portRanks);
      for (final node in fixedLayer) {
        if (node.nestedGraph == null) {
          _distributePorts(node, _opposedSide(side), fixedLayer);
        }
      }
    } else {
      for (final node in freeLayer) {
        _distributePorts(node, side, nodeOrder[currentIndex]);
      }
    }
  }

  PortSide _opposedSide(PortSide side) {
    switch (side) {
      case PortSide.east:
        return PortSide.west;
      case PortSide.west:
        return PortSide.east;
      case PortSide.north:
        return PortSide.south;
      case PortSide.south:
        return PortSide.north;
      default:
        return PortSide.undefined;
    }
  }

  void _updateNodePositions(List<List<LNode>> nodeOrder, int currentIndex) {
    final layer = nodeOrder[currentIndex];
    // Ensure _nodePositions is large enough for this layer.
    while (_nodePositions.length <= currentIndex) {
      _nodePositions.add([]);
    }
    if (_nodePositions[currentIndex].length < layer.length) {
      _nodePositions[currentIndex] = List<int>.filled(layer.length, 0);
    }
    for (var i = 0; i < layer.length; i++) {
      final node = layer[i];
      // nodePositions indexed by [layerId][nodeId]; nodeId = position in layer.
      // We store per-layer position of each node by its id.
      final layerIdx = node.layer!.index;
      while (_nodePositions.length <= layerIdx) {
        _nodePositions.add([]);
      }
      while (_nodePositions[layerIdx].length <= node.id) {
        _nodePositions[layerIdx].add(0);
      }
      _nodePositions[layerIdx][node.id] = i;
    }
  }

  int _positionOf(LNode node) {
    final layerIdx = node.layer!.index;
    if (layerIdx < _nodePositions.length &&
        node.id < _nodePositions[layerIdx].length) {
      return _nodePositions[layerIdx][node.id];
    }
    return 0;
  }

  /// Distributes ports on the given side using barycenter values.
  void _distributePorts(LNode node, PortSide side, List<LNode> currentLayer) {
    if (node.getProperty(_portOrderFixed)) return;
    _distributePortsOnSide(node, _portsOnSide(node, side), currentLayer);
    _distributePortsOnSide(node, _portsOnSide(node, PortSide.south), currentLayer);
    _distributePortsOnSide(node, _portsOnSide(node, PortSide.north), currentLayer);
    _sortPorts(node);
  }

  List<LPort> _portsOnSide(LNode node, PortSide side) =>
      node.ports.where((p) => p.side == side).toList();

  void _distributePortsOnSide(
    LNode node,
    List<LPort> ports,
    List<LNode> layer,
  ) {
    _inLayerPorts.clear();
    double minBary = 0, maxBary = 0;

    for (final port in ports) {
      _ensurePortBary(port.id);
      final isNS = port.side == PortSide.north || port.side == PortSide.south;
      double sum = 0;

      if (isNS) {
        // TODO(elk-faithful): north/south port dummy handling omitted.
        continue;
      } else {
        bool isInLayer = false;
        for (final edge in port.outgoingEdges) {
          final connected = edge.target;
          if (connected == null) continue;
          if (connected.node.layer == node.layer) {
            _inLayerPorts.add(port);
            isInLayer = true;
            break;
          } else {
            sum += _portRanks[connected.id];
          }
        }
        if (isInLayer) continue;
        for (final edge in port.incomingEdges) {
          final connected = edge.source;
          if (connected == null) continue;
          if (connected.node.layer == node.layer) {
            _inLayerPorts.add(port);
            isInLayer = true;
            break;
          } else {
            sum -= _portRanks[connected.id];
          }
        }
        if (isInLayer) continue;
      }

      if (port.degree > 0) {
        _portBarycenter[port.id] = sum / port.degree;
        if (_portBarycenter[port.id] < minBary) minBary = _portBarycenter[port.id];
        if (_portBarycenter[port.id] > maxBary) maxBary = _portBarycenter[port.id];
      }
    }

    if (_inLayerPorts.isNotEmpty) {
      _calculateInLayerPortBarycenters(node, layer, minBary, maxBary);
    }
  }

  void _calculateInLayerPortBarycenters(
    LNode node,
    List<LNode> layer,
    double minBary,
    double maxBary,
  ) {
    final nodeIndexInLayer = _positionOf(node) + 1;
    final layerSize = layer.length + 1;

    for (final port in _inLayerPorts) {
      _ensurePortBary(port.id);
      int sum = 0;
      int inLayerConnections = 0;
      for (final edge in port.connectedEdges) {
        final other = edge.source == port ? edge.target : edge.source;
        if (other != null && other.node.layer == node.layer) {
          sum += _positionOf(other.node) + 1;
          inLayerConnections++;
        }
      }
      if (inLayerConnections == 0) continue;

      final barycenter = sum / inLayerConnections;
      final side = port.side;
      if (side == PortSide.east) {
        _portBarycenter[port.id] = barycenter < nodeIndexInLayer
            ? minBary - barycenter
            : maxBary + (layerSize - barycenter);
      } else if (side == PortSide.west) {
        _portBarycenter[port.id] = barycenter < nodeIndexInLayer
            ? maxBary + barycenter
            : minBary - (layerSize - barycenter);
      }
    }
  }

  /// Sorts ports clockwise by side ordinal then by barycenter value.
  void _sortPorts(LNode node) {
    node.ports.sort((p1, p2) {
      final s1 = p1.side.index;
      final s2 = p2.side.index;
      if (s1 != s2) return s1 - s2;
      _ensurePortBary(p1.id);
      _ensurePortBary(p2.id);
      final b1 = _portBarycenter[p1.id];
      final b2 = _portBarycenter[p2.id];
      if (b1 == 0 && b2 == 0) return 0;
      if (b1 == 0) return -1;
      if (b2 == 0) return 1;
      return b1.compareTo(b2);
    });
  }
}

/// Assign port ranks for one layer's ports of the given type.
/// Mirrors `AbstractBarycenterPortDistributor.calculatePortRanks`.
void _calculatePortRanks(
  List<LNode> layer,
  _PortType portType,
  List<double> portRanks,
) {
  double consumedRank = 0;
  for (final node in layer) {
    consumedRank += _calculateNodePortRanks(node, consumedRank, portType, portRanks);
  }
}

/// Returns the rank consumed by this node (= number of relevant ports).
double _calculateNodePortRanks(
  LNode node,
  double rankSum,
  _PortType portType,
  List<double> portRanks,
) {
  // For fixed port order: assign ranks in the order the ports appear.
  // For free port order: same behaviour (ELK subclass GreedyPortDistributor
  // uses the same approach for the barycenter case).
  final relevant = portType == _PortType.output
      ? node.ports.where((p) => p.outgoingEdges.isNotEmpty || p.side == PortSide.east)
      : node.ports.where((p) => p.incomingEdges.isNotEmpty || p.side == PortSide.west);

  final ports = relevant.toList();
  if (ports.isEmpty) {
    // Still consume one unit of rank so nodes without relevant ports are spaced.
    return 1;
  }
  for (var i = 0; i < ports.length; i++) {
    portRanks[ports[i].id] = rankSum + i + 1;
  }
  return ports.length.toDouble();
}

// ---------------------------------------------------------------------------
// Crossings counter
// (AllCrossingsCounter + CrossingsCounter + BinaryIndexedTree)
// ---------------------------------------------------------------------------

class _AllCrossingsCounter {
  _AllCrossingsCounter(this._portPositions, List<List<LNode>> initialOrder)
      : _hasNorthSouthPorts = List<bool>.filled(initialOrder.length, false) {
    // Detect north/south-port dummy layers for later use.
    for (var l = 0; l < initialOrder.length; l++) {
      for (final node in initialOrder[l]) {
        if (node.type == NodeType.northSouthPort) {
          _hasNorthSouthPorts[l] = true;
        }
      }
    }
  }

  final List<int> _portPositions;
  final List<bool> _hasNorthSouthPorts;

  /// Mirrors `AllCrossingsCounter.countAllCrossings`.
  int countAllCrossings(List<List<LNode>> order) {
    if (order.isEmpty) return 0;
    int crossings = 0;
    // In-layer crossings on the west side of the leftmost layer.
    crossings +=
        _crossingCounter().countInLayerCrossingsOnSide(order[0], order[0], PortSide.west);
    // In-layer crossings on the east side of the rightmost layer.
    crossings += _crossingCounter().countInLayerCrossingsOnSide(
        order[order.length - 1], order[order.length - 1], PortSide.east);
    for (var layerIndex = 0; layerIndex < order.length; layerIndex++) {
      crossings += _countCrossingsAt(layerIndex, order);
    }
    return crossings;
  }

  int _countCrossingsAt(int layerIndex, List<List<LNode>> order) {
    int total = 0;
    if (layerIndex < order.length - 1) {
      // Between-layer crossings (no hyperedge variant in scope).
      total += _crossingCounter()
          .countCrossingsBetweenLayers(order[layerIndex], order[layerIndex + 1]);
    }
    // TODO(elk-faithful): north/south port crossing counting omitted.
    // if (_hasNorthSouthPorts[layerIndex]) { ... }
    return total;
  }

  _CrossingsCounter _crossingCounter() => _CrossingsCounter(_portPositions);
}

/// Mirrors `CrossingsCounter` (the between-layer and in-layer algorithms).
class _CrossingsCounter {
  _CrossingsCounter(this._portPositions);

  final List<int> _portPositions;

  // ---- Between-layer crossings ----

  /// Mirrors `CrossingsCounter.countCrossingsBetweenLayers`.
  int countCrossingsBetweenLayers(
    List<LNode> leftLayerNodes,
    List<LNode> rightLayerNodes,
  ) {
    // Assign port positions in counter-clockwise order.
    final ports = _initPortPositionsCounterClockwise(leftLayerNodes, rightLayerNodes);
    final tree = _BinaryIndexedTree(ports.length);
    return _countCrossingsOnPorts(ports, tree);
  }

  /// Mirrors `CrossingsCounter.countInLayerCrossingsOnSide`.
  int countInLayerCrossingsOnSide(
    List<LNode> nodes,
    List<LNode> layerNodes,
    PortSide side,
  ) {
    final ports = _initPortPositionsForInLayerCrossings(nodes, side);
    final tree = _BinaryIndexedTree(ports.length);
    return _countInLayerCrossingsOnPorts(ports, tree);
  }

  // ---- Position initialisation ----

  /// Mirrors `CrossingsCounter.initPortPositionsCounterClockwise`:
  /// left layer east ports top-to-bottom, right layer west ports bottom-to-top.
  List<LPort> _initPortPositionsCounterClockwise(
    List<LNode> leftLayerNodes,
    List<LNode> rightLayerNodes,
  ) {
    final ports = <LPort>[];
    _initPositions(leftLayerNodes, ports, PortSide.east, topDown: true);
    _initPositions(rightLayerNodes, ports, PortSide.west, topDown: false);
    return ports;
  }

  List<LPort> _initPortPositionsForInLayerCrossings(
    List<LNode> nodes,
    PortSide side,
  ) {
    final ports = <LPort>[];
    _initPositions(nodes, ports, side, topDown: true);
    return ports;
  }

  void _initPositions(
    List<LNode> nodes,
    List<LPort> ports,
    PortSide side, {
    required bool topDown,
  }) {
    final start = topDown ? 0 : nodes.length - 1;
    final step = topDown ? 1 : -1;
    int numPorts = ports.length;
    for (var i = start; topDown ? i < nodes.length : i >= 0; i += step) {
      final node = nodes[i];
      final nodePorts = _getPortsOnSide(node, side, topDown);
      for (final port in nodePorts) {
        _ensurePortPositions(port.id);
        _portPositions[port.id] = numPorts++;
      }
      ports.addAll(nodePorts);
    }
  }

  void _ensurePortPositions(int portId) {
    // _portPositions is pre-allocated to nPorts length; do nothing extra.
    // (If portId exceeds size this is a bug in ID assignment.)
  }

  /// Mirrors `CrossingsCounter.getPorts`:
  /// east = top-to-bottom (topDown) or bottom-to-top (!topDown).
  /// west = reversed of east.
  List<LPort> _getPortsOnSide(LNode node, PortSide side, bool topDown) {
    final all = node.ports.where((p) => p.side == side).toList();
    if (side == PortSide.east) {
      return topDown ? all : all.reversed.toList();
    } else {
      return topDown ? all.reversed.toList() : all;
    }
  }

  int _positionOf(LPort port) {
    if (port.id < _portPositions.length) return _portPositions[port.id];
    return 0;
  }

  LPort _otherEndOf(LEdge edge, LPort fromPort) =>
      fromPort == edge.source ? edge.target! : edge.source!;

  // ---- Crossing count algorithms ----

  /// Mirrors `CrossingsCounter.countCrossingsOnPorts`.
  int _countCrossingsOnPorts(List<LPort> ports, _BinaryIndexedTree tree) {
    int crossings = 0;
    final ends = <int>[];
    for (final port in ports) {
      tree.removeAll(_positionOf(port));
      ends.clear();
      for (final edge in port.connectedEdges) {
        if (edge.isSelfLoop) continue;
        final endPos = _positionOf(_otherEndOf(edge, port));
        if (endPos > _positionOf(port)) {
          crossings += tree.rank(endPos);
          ends.add(endPos);
        }
      }
      for (final ep in ends) {
        tree.add(ep);
      }
    }
    return crossings;
  }

  /// Mirrors `CrossingsCounter.countInLayerCrossingsOnPorts`.
  int _countInLayerCrossingsOnPorts(List<LPort> ports, _BinaryIndexedTree tree) {
    int crossings = 0;
    final ends = <int>[];
    for (final port in ports) {
      tree.removeAll(_positionOf(port));
      ends.clear();
      int numBetweenLayerEdges = 0;
      for (final edge in port.connectedEdges) {
        if (edge.isSelfLoop) continue;
        if (edge.isInLayerEdge) {
          final endPos = _positionOf(_otherEndOf(edge, port));
          if (endPos > _positionOf(port)) {
            crossings += tree.rank(endPos);
            ends.add(endPos);
          }
        } else {
          numBetweenLayerEdges++;
        }
      }
      crossings += tree.size * numBetweenLayerEdges;
      for (final ep in ends) {
        tree.add(ep);
      }
    }
    return crossings;
  }
}

// ---------------------------------------------------------------------------
// Binary indexed tree (Fenwick tree) — BinaryIndexedTree.java
// ---------------------------------------------------------------------------

class _BinaryIndexedTree {
  _BinaryIndexedTree(int maxNum)
      : _maxNum = maxNum,
        _binarySums = List<int>.filled(maxNum + 1, 0),
        _numsPerIndex = List<int>.filled(maxNum, 0);

  final int _maxNum;
  final List<int> _binarySums;
  final List<int> _numsPerIndex;
  int _size = 0;

  int get size => _size;
  bool get isEmpty => _size == 0;

  void add(int index) {
    if (index < 0 || index >= _maxNum) return;
    _size++;
    _numsPerIndex[index]++;
    var i = index + 1;
    while (i < _binarySums.length) {
      _binarySums[i]++;
      i += i & -i;
    }
  }

  /// Returns the sum of entries at indices < [index] (i.e., rank).
  int rank(int index) {
    var i = index;
    var sum = 0;
    while (i > 0) {
      sum += _binarySums[i];
      i -= i & -i;
    }
    return sum;
  }

  void removeAll(int index) {
    if (index < 0 || index >= _maxNum) return;
    final numEntries = _numsPerIndex[index];
    if (numEntries == 0) return;
    _numsPerIndex[index] = 0;
    _size -= numEntries;
    var i = index + 1;
    while (i < _binarySums.length) {
      _binarySums[i] -= numEntries;
      i += i & -i;
    }
  }

  void clear() {
    _binarySums.fillRange(0, _binarySums.length, 0);
    _numsPerIndex.fillRange(0, _numsPerIndex.length, 0);
    _size = 0;
  }
}

// ---------------------------------------------------------------------------
// Sweep copy — stores best node + port order and restores it
// (SweepCopy.java — node/port snapshot and transfer)
// ---------------------------------------------------------------------------

class _SweepCopy {
  _SweepCopy(List<List<LNode>> order)
      : _nodeOrder = [for (final layer in order) List<LNode>.from(layer)],
        _portOrders = [
          for (final layer in order)
            [for (final node in layer) List<LPort>.from(node.ports)],
        ];

  final List<List<LNode>> _nodeOrder;
  final List<List<List<LPort>>> _portOrders;

  /// Applies saved node and port order back to `graph.layers`.
  void transferToGraph(LGraph graph) {
    for (var i = 0; i < graph.layers.length; i++) {
      final layer = graph.layers[i];
      final savedNodes = _nodeOrder[i];
      final savedPorts = _portOrders[i];
      for (var j = 0; j < savedNodes.length; j++) {
        final node = savedNodes[j];
        layer.nodes[j] = node;
        node.id = j;
        node.ports
          ..clear()
          ..addAll(savedPorts[j]);
      }
    }
  }
}

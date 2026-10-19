part of 'index.dart';

/// One layer graph of [buildLayerGraph] over node indices.
///
/// Node ids are indices into the layout graph; the synthetic root of each
/// layer graph gets an id past the last node. It keeps what the sweeps read:
/// - the members' children, in the order buildLayerGraph parents them,
/// - the members' merged edge ends with summed weights, in edge order. They
///   depend only on the sweep direction, so all layer graphs of one
///   direction share [sources] and [weights],
/// - the border nodes of clusters at this rank,
/// - which nodes have their own label (clusters), because order writes to
///   those labels do not reach `g`.
class IndexedLayerGraph {
  IndexedLayerGraph(this.root, this.sources, this.weights, this._graphParent);

  final int root;
  final List<List<int>> sources;
  final List<List<double>> weights;

  /// Parent of every node in the layout graph, -1 for the graph root.
  final List<int> _graphParent;
  final List<int> rootChildren = [];
  final Map<int, List<int>> clusterChildren = {};

  /// Members that are parents of other members (clusters).
  final Set<int> clusterMembers = {};
  final Map<int, (int?, int?)> borders = {};
  final Set<int> ownLabel = {};

  /// Adds member [v] under its layout-graph parent.
  void addMember(int v) {
    final p = _graphParent[v];
    if (p < 0) {
      rootChildren.add(v);
    } else {
      clusterChildren.putIfAbsent(p, () => []).add(v);
    }
  }

  List<int>? childrenOf(int v) => v == root ? rootChildren : clusterChildren[v];

  /// The layer graph parent of [v]: null for the root and for nodes that
  /// are not members, which buildLayerGraph leaves without a parent.
  int? parentOf(int v, {required bool member}) {
    if (v == root || !member) return null;
    final p = _graphParent[v];
    return p < 0 ? root : p;
  }
}

class _Entry {
  _Entry(this.v);

  final int v;
  num? barycenter;
  num? weight;
}

class _Conflict {
  num inDegree = 0;
  List<_Conflict> inner = [];
  List<_Conflict> out = [];
  List<int> vs = [];
  int i = -1;
  num? barycenter;
  num weight = 0;
  bool merged = false;
}

class _Sorted {
  List<int> vs = [];
  late int i;
  num? barycenter;
  late num weight;
}

/// The barycenter sweeps of [order] over node indices. Each step mirrors the
/// string-keyed code in this directory (sortSubgraph, barycenter,
/// resolveConflicts, sort, addSubgraphConstraints, crossCount,
/// buildLayerMatrix) in the same iteration order, so the result is the same.
class IndexedOrder {
  /// [order] and [rank] are per node index; [outTargets]/[outWeights]
  /// list each node's out-edges in edge order, as crossCount reads them.
  IndexedOrder(
    this.order,
    this.rank,
    this.outTargets,
    this.outWeights,
    this.down,
    this.up,
  );

  final List<IndexedLayerGraph> down;
  final List<IndexedLayerGraph> up;
  final List<double> order;
  final List<int?> rank;
  final List<List<int>> outTargets;
  final List<List<num>> outWeights;

  int get nodeCount => order.length;

  /// Runs the sweeps and returns the layering with the fewest crossings.
  List<List<int>> run(int maxRank) {
    num bestCC = double.infinity;
    List<List<int>> best = [];
    for (int i = 0, lastBest = 0; lastBest < 4; ++i, ++lastBest) {
      _sweep((i % 2) != 0 ? down : up, i % 4 >= 2);
      final layering = _layerMatrix(maxRank);
      final cc = crossCount(layering);
      if (cc < bestCC) {
        lastBest = 0;
        best = [for (final layer in layering) List<int>.of(layer)];
        bestCC = cc;
        // No later sweep can beat zero crossings, and only [best] is used,
        // so the remaining sweeps of the reference loop cannot change the
        // result.
        if (cc == 0) break;
      }
    }
    return best;
  }

  void _sweep(List<IndexedLayerGraph> layerGraphs, bool biasRight) {
    // Constraint graph: unique edges in insertion order.
    final cgEdges = <(int, int)>[];
    final cgKeys = <(int, int)>{};
    for (final lg in layerGraphs) {
      final sorted = _sortSubgraph(lg, lg.root, cgEdges, biasRight);
      for (var i = 0; i < sorted.vs.length; i++) {
        final v = sorted.vs[i];
        if (!lg.ownLabel.contains(v)) order[v] = i.toDouble();
      }
      // addSubgraphConstraints
      final prev = <int, int>{};
      int? rootPrev;
      for (final v in sorted.vs) {
        int? child = lg.parentOf(v, member: true);
        while (child != null) {
          final parent = lg.parentOf(
            child,
            member: lg.clusterMembers.contains(child),
          );
          int? prevChild;
          if (parent != null) {
            prevChild = prev[parent];
            prev[parent] = child;
          } else {
            prevChild = rootPrev;
            rootPrev = child;
          }
          if (prevChild != null && prevChild != child) {
            if (cgKeys.add((prevChild, child))) cgEdges.add((prevChild, child));
            break;
          }
          child = parent;
        }
      }
    }
  }

  _Sorted _sortSubgraph(
    IndexedLayerGraph lg,
    int v,
    List<(int, int)> cgEdges,
    bool biasRight,
  ) {
    var movable = lg.childrenOf(v) ?? const <int>[];
    final (bl, br) = lg.borders[v] ?? (null, null);
    if (bl != null) {
      movable = [
        for (final w in movable)
          if (w != bl && w != br) w,
      ];
    }

    final barycenters = <_Entry>[];
    for (final w in movable) {
      final entry = _Entry(w);
      final sources = lg.sources[w];
      if (sources.isNotEmpty) {
        final weights = lg.weights[w];
        num sum = 0, weight = 0;
        for (var i = 0; i < sources.length; i++) {
          sum = sum + weights[i] * order[sources[i]];
          weight = weight + weights[i];
        }
        entry.barycenter = sum / weight;
        entry.weight = weight;
      }
      barycenters.add(entry);
    }

    final subgraphs = <int, _Sorted>{};
    for (final entry in barycenters) {
      final list = lg.childrenOf(entry.v);
      if (list != null && list.isNotEmpty) {
        final sub = _sortSubgraph(lg, entry.v, cgEdges, biasRight);
        subgraphs[entry.v] = sub;
        if (sub.barycenter != null) {
          if (entry.barycenter != null) {
            entry.barycenter =
                (entry.barycenter! * entry.weight! +
                    sub.barycenter! * sub.weight) /
                (entry.weight! + sub.weight);
            entry.weight = entry.weight! + sub.weight;
          } else {
            entry.barycenter = sub.barycenter;
            entry.weight = sub.weight;
          }
        }
      }
    }

    final entries = _resolveConflicts(barycenters, cgEdges);
    for (final entry in entries) {
      final expanded = <int>[];
      for (final w in entry.vs) {
        final sub = subgraphs[w];
        if (sub != null) {
          expanded.addAll(sub.vs);
        } else {
          expanded.add(w);
        }
      }
      entry.vs = expanded;
    }
    final result = _sort(entries, biasRight);
    if (bl != null) {
      result.vs = [bl, ...result.vs, br!];
      final blPreds = lg.sources[bl];
      if (blPreds.isNotEmpty) {
        final blPred = order[blPreds[0]];
        final brPred = order[lg.sources[br][0]];
        if (result.barycenter == null) {
          result.barycenter = 0;
          result.weight = 0;
        }
        result.barycenter =
            (result.barycenter! * result.weight + blPred + brPred) /
            (result.weight + 2);
        result.weight = result.weight + 2;
      }
    }
    return result;
  }

  List<_Sorted> _resolveConflicts(
    List<_Entry> entries,
    List<(int, int)> cgEdges,
  ) {
    final mapped = <int, _Conflict>{};
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final tmp = _Conflict()
        ..vs = [entry.v]
        ..i = i;
      mapped[entry.v] = tmp;
      if (entry.barycenter != null) {
        tmp.barycenter = entry.barycenter!;
        tmp.weight = entry.weight!;
      }
    }
    for (final (v, w) in cgEdges) {
      final entryV = mapped[v];
      final entryW = mapped[w];
      if (entryV != null && entryW != null) {
        entryW.inDegree += 1;
        entryV.out.add(entryW);
      }
    }
    final sourceSet = [
      for (final e in mapped.values)
        if (e.inDegree == 0) e,
    ];

    final resolved = <_Conflict>[];
    while (sourceSet.isNotEmpty) {
      final entry = sourceSet.removeLast();
      resolved.add(entry);
      for (final uEntry in entry.inner.reversed) {
        if (uEntry.merged) continue;
        if (uEntry.barycenter == null ||
            entry.barycenter == null ||
            uEntry.barycenter! >= entry.barycenter!) {
          _mergeEntries(entry, uEntry);
        }
      }
      for (final wEntry in entry.out) {
        wEntry.inner.add(entry);
        if (--wEntry.inDegree == 0) sourceSet.add(wEntry);
      }
    }
    return [
      for (final entry in resolved)
        if (!entry.merged)
          _Sorted()
            ..vs = entry.vs
            ..i = entry.i
            ..barycenter = entry.barycenter
            ..weight = entry.weight,
    ];
  }

  void _mergeEntries(_Conflict target, _Conflict source) {
    num sum = 0;
    num weight = 0;
    if (target.weight != 0) {
      sum += target.barycenter! * target.weight;
      weight += target.weight;
    }
    if (source.weight != 0) {
      sum += source.barycenter! * source.weight;
      weight += source.weight;
    }
    target.vs = [...source.vs, ...target.vs];
    target.barycenter = sum / weight;
    target.weight = weight;
    target.i = math.min(source.i, target.i);
    source.merged = true;
  }

  _Sorted _sort(List<_Sorted> entries, bool biasRight) {
    final sortable = <_Sorted>[];
    final unsortable = <_Sorted>[];
    for (final entry in entries) {
      (entry.barycenter != null ? sortable : unsortable).add(entry);
    }
    unsortable.sort((a, b) => b.i.compareTo(a.i));
    final vs = <int>[];
    num sum = 0, weight = 0;
    var vsIndex = 0;
    sortable.sort((entryV, entryW) {
      if (entryV.barycenter! < entryW.barycenter!) return -1;
      if (entryV.barycenter! > entryW.barycenter!) return 1;
      return !biasRight ? entryV.i - entryW.i : entryW.i - entryV.i;
    });
    int consume(int index) {
      while (unsortable.isNotEmpty && unsortable.last.i <= index) {
        vs.addAll(unsortable.removeLast().vs);
        index++;
      }
      return index;
    }

    vsIndex = consume(vsIndex);
    for (final entry in sortable) {
      vsIndex += entry.vs.length;
      vs.addAll(entry.vs);
      sum += entry.barycenter! * entry.weight;
      weight += entry.weight;
      vsIndex = consume(vsIndex);
    }
    final result = _Sorted()..vs = vs;
    if (weight != 0) {
      result.barycenter = sum / weight;
      result.weight = weight;
    }
    return result;
  }

  /// buildLayerMatrix: per rank, nodes keyed by order (a later node with
  /// the same order replaces an earlier one), sorted by order.
  List<List<int>> _layerMatrix(int maxRank) {
    // Orders are usually 0..k-1 per rank, which fills a dense list; anything
    // else (gaps, two nodes with one order) takes the keyed path.
    final counts = List<int>.filled(maxRank + 1, 0);
    for (var v = 0; v < nodeCount; v++) {
      final r = rank[v];
      if (r != null) counts[r]++;
    }
    final layers = [for (final c in counts) List<int>.filled(c, -1)];
    var dense = true;
    for (var v = 0; v < nodeCount && dense; v++) {
      final r = rank[v];
      if (r == null) continue;
      final layer = layers[r];
      final o = order[v].toInt();
      if (o < 0 || o >= layer.length || layer[o] >= 0) {
        dense = false;
      } else {
        layer[o] = v;
      }
    }
    if (dense) return layers;
    final byOrder = List<Map<int, int>>.generate(maxRank + 1, (_) => {});
    for (var v = 0; v < nodeCount; v++) {
      final r = rank[v];
      if (r != null) byOrder[r][order[v].toInt()] = v;
    }
    return [
      for (final m in byOrder)
        [for (final k in (m.keys.toList()..sort())) m[k]!],
    ];
  }


  int crossCount(List<List<int>> layering) {
    var cc = 0;
    final southPos = List<int>.filled(nodeCount, 0);
    for (var l = 1; l < layering.length; ++l) {
      final north = layering[l - 1], south = layering[l];
      for (var i = 0; i < south.length; i++) {
        southPos[south[i]] = i;
      }
      final positions = <int>[];
      final weights = <num>[];
      final idx = <int>[];
      for (final v in north) {
        final targets = outTargets[v];
        final start = positions.length;
        for (var i = 0; i < targets.length; i++) {
          positions.add(southPos[targets[i]]);
          weights.add(outWeights[v][i]);
        }
        // As dagre.js: each north node's entries sorted by south position,
        // north nodes kept in layer order. Entries with equal positions do
        // not count against each other, so their relative order is
        // irrelevant.
        idx.addAll(
          List<int>.generate(positions.length - start, (i) => start + i)
            ..sort((a, b) => positions[a].compareTo(positions[b])),
        );
      }
      var firstIndex = 1;
      while (firstIndex < south.length) {
        firstIndex <<= 1;
      }
      final tree = List<num>.filled(2 * firstIndex - 1, 0);
      firstIndex -= 1;
      for (final k in idx) {
        var index = positions[k] + firstIndex;
        final weight = weights[k];
        tree[index] += weight;
        num weightSum = 0;
        while (index > 0) {
          if ((index % 2) != 0) weightSum += tree[index + 1];
          index = (index - 1) >> 1;
          tree[index] += weight;
        }
        cc += (weight * weightSum).toInt();
      }
    }
    return cc;
  }
}

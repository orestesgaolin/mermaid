part of 'bk.dart';

/// Brandes-Köpf x-coordinates over integer indices instead of string-keyed
/// maps. It reproduces the reference code above step for step, including the
/// behaviour of this port that differs from dagre.js, because the output
/// must not change:
/// - _findType2Conflicts runs its trailing scan once per south node instead
///   of once per layer, as dagre-d3-es (the dagre build mermaid uses) does,
/// - _findSmallestWidthAlignment starts its maximum at double.minPositive.
/// Neighbour lists keep the graph's insertion order, so `find`, `sort` and
/// the compaction stack see the same sequences as the reference code.
class IndexedBk {
  IndexedBk(
    this.label,
    this.layers,
    this.order,
    this.width,
    this.isDummy,
    this.isBorder,
    this.labelPos,
    this.borderType,
    this.preds,
    this.succs,
  );

  final GraphLabel label;
  final List<List<int>> layers;
  final List<double> order;
  final List<double> width;
  final List<bool> isDummy;
  final List<bool> isBorder;
  final List<Object?> labelPos;
  final List<Object?> borderType;
  final List<List<int>> preds;
  final List<List<int>> succs;

  /// Conflicting (u, v) pairs, stored as `min * n + max`.
  late final List<List<int>?> _conflicts = List.filled(n, null);

  int get n => order.length;

  /// Conflicts as an unordered pair set: each pair is kept once, under its
  /// smaller node.
  void _addConflict(int u, int v) {
    final a = u < v ? u : v, b = u < v ? v : u;
    final list = _conflicts[a] ??= [];
    if (!list.contains(b)) list.add(b);
  }

  bool _hasConflict(int u, int v) {
    final a = u < v ? u : v, b = u < v ? v : u;
    return _conflicts[a]?.contains(b) ?? false;
  }

  void _findType1Conflicts() {
    for (var l = 1; l < layers.length; l++) {
      final prevLayerLength = layers[l - 1].length;
      final layer = layers[l];
      final lastNode = layer.last;
      var k0 = 0.0;
      var scanPos = 0;
      for (var i = 0; i < layer.length; i++) {
        final v = layer[i];
        int? w;
        if (isDummy[v]) {
          for (final u in preds[v]) {
            if (isDummy[u]) {
              w = u;
              break;
            }
          }
        }
        final k1 = w != null ? order[w] : prevLayerLength.toDouble();
        if (w != null || v == lastNode) {
          for (var s = scanPos; s <= i; s++) {
            final scanNode = layer[s];
            for (final u in preds[scanNode]) {
              final uPos = order[u];
              if ((uPos < k0 || k1 < uPos) &&
                  !(isDummy[u] && isDummy[scanNode])) {
                _addConflict(u, scanNode);
              }
            }
          }
          scanPos = i + 1;
          k0 = k1;
        }
      }
    }
  }

  void _findType2Conflicts() {
    if (layers.isEmpty) return;
    var south = layers[0];
    void scan(
      int from,
      int to,
      double prevNorthBorder,
      double nextNorthBorder,
    ) {
      for (var i = from; i < to; i++) {
        final v = south[i];
        if (!isDummy[v]) continue;
        for (final u in preds[v]) {
          if (isDummy[u] &&
              (order[u] < prevNorthBorder || order[u] > nextNorthBorder)) {
            _addConflict(u, v);
          }
        }
      }
    }

    // Each layer is the `south` below the layer before it.
    for (var l = 1; l < layers.length; l++) {
      final northLength = layers[l - 1].length.toDouble();
      south = layers[l];
      var prevNorthPos = -1.0;
      double? nextNorthPos;
      var southPos = 0;
      // The trailing scan repeats with the same arguments until a border
      // node moves them; repeating it cannot add conflicts.
      int? lastFrom;
      double? lastBorder;
      for (
        var southLookahead = 0;
        southLookahead < south.length;
        southLookahead++
      ) {
        final v = south[southLookahead];
        if (isBorder[v] && preds[v].isNotEmpty) {
          nextNorthPos = order[preds[v][0]];
          scan(southPos, southLookahead, prevNorthPos, nextNorthPos);
          southPos = southLookahead;
          prevNorthPos = nextNorthPos;
        }
        final border = nextNorthPos ?? double.nan;
        if (lastFrom == southPos &&
            (lastBorder == border || (lastBorder!.isNaN && border.isNaN))) {
          continue;
        }
        lastFrom = southPos;
        lastBorder = border;
        scan(southPos, south.length, border, northLength);
      }
    }
  }

  /// Returns the block root of every node.
  List<int> _verticalAlignment(
    List<List<int>> layering,
    List<List<int>> neighbors,
  ) {
    final root = List<int>.generate(n, (i) => i);
    final align = List<int>.generate(n, (i) => i);
    final pos = List<int>.filled(n, 0);
    for (final layer in layering) {
      for (var i = 0; i < layer.length; i++) {
        pos[layer[i]] = i;
      }
    }
    for (final layer in layering) {
      var prevIdx = -1;
      for (final v in layer) {
        var ws = neighbors[v];
        if (ws.isEmpty) continue;
        // A single neighbour needs no copy or sort.
        if (ws.length > 1) {
          ws = List<int>.of(ws)..sort((a, b) => pos[a].compareTo(pos[b]));
        }
        final mp = (ws.length - 1) / 2;
        for (int i = mp.floor(), il = mp.ceil(); i <= il; ++i) {
          final w = ws[i];
          if (align[v] == v && prevIdx < pos[w] && !_hasConflict(v, w)) {
            align[w] = v;
            align[v] = root[v] = root[w];
            prevIdx = pos[w];
          }
        }
      }
    }
    return root;
  }

  double _sep(int v, int w, bool reverseSep, double nodeSep, double edgeSep) {
    var sum = 0.0;
    var delta = 0.0;
    sum += width[v] / 2;
    if (labelPos[v] == LabelPosition.left) {
      delta = -width[v] / 2;
    } else if (labelPos[v] == LabelPosition.right) {
      delta = width[v] / 2;
    }
    if (delta != 0) {
      sum += reverseSep ? delta : -delta;
    }
    delta = 0;
    sum += (isDummy[v] ? edgeSep : nodeSep) / 2;
    sum += (isDummy[w] ? edgeSep : nodeSep) / 2;
    sum += width[w] / 2;
    if (labelPos[w] == LabelPosition.left) {
      delta = width[w] / 2;
    } else if (labelPos[w] == LabelPosition.right) {
      delta = -width[w] / 2;
    }
    if (delta != 0) {
      sum += reverseSep ? delta : -delta;
    }
    return sum;
  }

  List<double> _horizontalCompaction(
    List<List<int>> layering,
    List<int> root,
    bool reverseSep,
  ) {
    // Block graph over roots: nodes in insertion order, one edge per pair
    // holding the largest separation.
    final blockNodes = <int>[];
    final inBlock = List<bool>.filled(n, false);
    final edgeFrom = <int>[], edgeTo = <int>[];
    final edgeSep = <double>[];
    final edgeOf = <int, int>{};
    final lastOut = Int32List(n)..fillRange(0, n, -1);
    for (final layer in layering) {
      var u = -1;
      for (final v in layer) {
        final vRoot = root[v];
        if (!inBlock[vRoot]) {
          inBlock[vRoot] = true;
          blockNodes.add(vRoot);
        }
        if (u >= 0) {
          final uRoot = root[u];
          final s = _sep(v, u, reverseSep, label.nodeSep, label.edgeSep);
          // Blocks next to each other in one layer usually are in the next
          // layer too, so try uRoot's latest block edge before the map.
          final last = lastOut[uRoot];
          final key = uRoot * n + vRoot;
          final e = last >= 0 && edgeTo[last] == vRoot ? last : edgeOf[key];
          if (e == null) {
            lastOut[uRoot] = edgeSep.length;
            edgeOf[key] = edgeSep.length;
            edgeFrom.add(uRoot);
            edgeTo.add(vRoot);
            edgeSep.add(math.max(s, 0).toDouble());
          } else {
            edgeSep[e] = math.max(s, edgeSep[e]).toDouble();
          }
        }
        u = v;
      }
    }

    // In- and out-edges per node as flat arrays (CSR), filled in edge
    // order, which is the order the block graph's adjacency maps have.
    final m = edgeSep.length;
    final inStart = Int32List(n + 1), outStart = Int32List(n + 1);
    for (var e = 0; e < m; e++) {
      inStart[edgeTo[e] + 1]++;
      outStart[edgeFrom[e] + 1]++;
    }
    for (var i = 0; i < n; i++) {
      inStart[i + 1] += inStart[i];
      outStart[i + 1] += outStart[i];
    }
    final inEdge = Int32List(m), outEdge = Int32List(m);
    final inFill = Int32List.fromList(inStart),
        outFill = Int32List.fromList(outStart);
    for (var e = 0; e < m; e++) {
      inEdge[inFill[edgeTo[e]]++] = e;
      outEdge[outFill[edgeFrom[e]]++] = e;
    }

    // Both passes walk the block graph with the reference's explicit stack:
    // a node's coordinate is (re)computed each time it is popped after its
    // first visit.
    final xs = Float64List(n);
    final visited = Uint8List(n);
    final stack = <int>[];

    // First pass, assign smallest coordinates.
    stack.addAll(blockNodes);
    while (stack.isNotEmpty) {
      final elem = stack.removeLast();
      if (visited[elem] != 0) {
        // Starts at 0.0 rather than the reference's int 0: max() gives the
        // same double either way, without mixed int/double comparisons.
        var acc = 0.0;
        for (var k = inStart[elem]; k < inStart[elem + 1]; k++) {
          final e = inEdge[k];
          acc = math.max(acc, xs[edgeFrom[e]] + edgeSep[e]);
        }
        xs[elem] = acc;
      } else {
        visited[elem] = 1;
        stack.add(elem);
        for (var k = inStart[elem]; k < inStart[elem + 1]; k++) {
          stack.add(edgeFrom[inEdge[k]]);
        }
      }
    }

    // Second pass, assign greatest coordinates.
    final ownBorder = reverseSep ? 'borderLeft' : 'borderRight';
    visited.fillRange(0, n, 0);
    stack.addAll(blockNodes);
    while (stack.isNotEmpty) {
      final elem = stack.removeLast();
      if (visited[elem] != 0) {
        var minv = double.maxFinite;
        for (var k = outStart[elem]; k < outStart[elem + 1]; k++) {
          final e = outEdge[k];
          minv = math.min(minv, xs[edgeTo[e]] - edgeSep[e]);
        }
        if (minv != double.maxFinite && borderType[elem] != ownBorder) {
          xs[elem] = math.max(xs[elem], minv);
        }
      } else {
        visited[elem] = 1;
        stack.add(elem);
        for (var k = outStart[elem]; k < outStart[elem + 1]; k++) {
          stack.add(edgeTo[outEdge[k]]);
        }
      }
    }

    return [for (var v = 0; v < n; v++) xs[root[v]]];
  }

  /// Balanced x per node, in layer order.
  List<double> runIndexed() {
    _findType1Conflicts();
    _findType2Conflicts();

    final down = layers.reversed.toList();
    List<List<int>> reversedInner(List<List<int>> l) => [
      for (final layer in l) layer.reversed.toList(),
    ];
    final alignments = <GraphAlign, List<double>>{};
    for (final (align, layering, neighbors, right) in [
      (GraphAlign.utl, layers, preds, false),
      (GraphAlign.utr, reversedInner(layers), preds, true),
      (GraphAlign.dtl, down, succs, false),
      (GraphAlign.dtr, reversedInner(down), succs, true),
    ]) {
      final root = _verticalAlignment(layering, neighbors);
      var xs = _horizontalCompaction(layering, root, right);
      if (right) xs = [for (final x in xs) -x];
      alignments[align] = xs;
    }

    // _findSmallestWidthAlignment
    List<double>? alignTo;
    var best = double.infinity;
    for (final xs in alignments.values) {
      double maxX = double.minPositive;
      double minX = double.maxFinite;
      for (var v = 0; v < n; v++) {
        final halfWidth = width[v] / 2;
        maxX = math.max(xs[v] + halfWidth, maxX);
        minX = math.min(xs[v] - halfWidth, minX);
      }
      if (maxX - minX < best) {
        best = maxX - minX;
        alignTo = xs;
      }
    }

    // _alignCoordinates
    if (alignTo != null && n > 0) {
      final alignToMin = alignTo.reduce(math.min);
      final alignToMax = alignTo.reduce(math.max);
      for (final align in GraphAlign.values) {
        final xs = alignments[align]!;
        if (identical(xs, alignTo)) continue;
        final delta = align == GraphAlign.utl || align == GraphAlign.dtl
            ? alignToMin - xs.reduce(math.min)
            : alignToMax - xs.reduce(math.max);
        if (delta != 0) {
          alignments[align] = [for (final x in xs) x + delta];
        }
      }
    }

    // _balance
    final fixed = label.align;
    final result = List<double>.filled(n, 0);
    final ul = alignments[GraphAlign.utl]!, ur = alignments[GraphAlign.utr]!;
    final dl = alignments[GraphAlign.dtl]!, dr = alignments[GraphAlign.dtr]!;
    for (var v = 0; v < n; v++) {
      result[v] = fixed != null
          ? alignments[fixed]![v]
          : _median4(ul[v], ur[v], dl[v], dr[v]);
    }
    return result;
  }

  /// (xs[1] + xs[2]) / 2 of the four values sorted as `List.sort` sorts
  /// doubles (by compareTo), with a five-comparison sorting network.
  static double _median4(double a, double b, double c, double d) {
    double t;
    if (a.compareTo(b) > 0) {
      t = a;
      a = b;
      b = t;
    }
    if (c.compareTo(d) > 0) {
      t = c;
      c = d;
      d = t;
    }
    if (a.compareTo(c) > 0) {
      t = a;
      a = c;
      c = t;
    }
    if (b.compareTo(d) > 0) {
      t = b;
      b = d;
      d = t;
    }
    if (b.compareTo(c) > 0) {
      t = b;
      b = c;
      c = t;
    }
    return (b + c) / 2;
  }
}

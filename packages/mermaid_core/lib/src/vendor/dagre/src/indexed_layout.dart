/// The dagre layout pipeline of `dart_dagre.dart` and `layout.dart` on node
/// and edge indices with typed labels, instead of string-keyed graphs with
/// `Props` maps.
///
/// Every phase is a port of the reference code it replaces and keeps its
/// iteration orders, so the layout is the same: nodes and edges in insertion
/// order (a removed edge that is set again goes to the end), per-node edge
/// lists in insertion order, children in the order they were parented, and
/// successors in the order of the graph's successor count maps. The quirks
/// of this port are kept as well; they are pointed out where they occur.
/// `test/dagre_indexed_equivalence_test.dart` renders random diagrams with
/// both pipelines and requires identical output.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mermaid_core/src/geometry.dart';

import '../dart_dagre.dart';
import 'model/enums/dummy.dart';
import 'model/enums/relationship.dart';
import 'model/graph_label.dart';
import 'model/graph_point.dart';
import 'model/graph_rect.dart';
import 'order/index.dart';
import 'position/bk.dart';
import 'rank/network_simplex.dart';
import 'util.dart' as util;

/// Runs the layout and writes the result to [input], like `layout()` in
/// `dart_dagre.dart`. Returns null, with [input] untouched, when the graph
/// uses a feature this pipeline does not port; the caller then runs the
/// reference code.
DagreResult? layoutIndexed(DagreGraph input, DagreConfig config) {
  if (config.acyclicer == Acyclicer.greedy ||
      config.ranker != Ranker.networkSimplex ||
      config.customOrder != null) {
    return null;
  }
  for (final node in input.nodeMap.values) {
    if (node.parent != null && !input.nodeMap.containsKey(node.parent)) {
      return null;
    }
  }
  try {
    final layout = _Layout(config);
    final g = layout.g;
    layout.build(input);
    if (g.nodeCount == 0) {
      return DagreResult(0, 0, input);
    }
    layout.run();
    layout.writeBack(input);
    return DagreResult(layout.width, layout.height, input);
  } on _Unsupported {
    return null;
  }
}

/// Thrown when the graph reaches a case the reference code handles
/// differently (usually by failing); the caller falls back to it.
class _Unsupported implements Exception {}

/// An edge's identity, used to set a removed edge again.
class _EdgeKey {
  _EdgeKey(this.v, this.w, this.name);

  final int v;
  final int w;
  final String? name;
}

class _SelfEdge {
  _SelfEdge(this.key, this.label);

  final _EdgeKey key;
  final _EdgeLabel label;
}

/// The keys of a node label that the layout reads or writes. Null stands for
/// an absent key; the reference code never stores null in these.
class _NodeLabel {
  double? width;
  double? height;
  double? x;
  double? y;
  double? rank;
  double? order;
  Dummy? dummy;
  LabelPosition? labelPos;
  String? borderType;
  int borderTop = -1;
  int borderBottom = -1;

  /// Border nodes by rank; -1 marks the empty slots the reference pads with.
  List<int>? borderLeft;
  List<int>? borderRight;
  double? minRank;
  double? maxRank;
  List<_SelfEdge>? selfEdges;

  /// Edge dummies: the label and identity of the edge they replace.
  _EdgeLabel? edgeLabel;
  _EdgeKey? edgeObj;

  /// Edge label proxies: the edge they stand for.
  int proxyEdge = -1;

  /// Self-edge dummies: the self edge and its label.
  _SelfEdge? selfEdge;
}

class _EdgeLabel {
  double? minLen;
  double? weight;
  double? width;
  double? height;
  double? labelOffset;
  LabelPosition? labelPos;
  double? labelRank;
  List<GraphPoint>? points;
  double? x;
  double? y;
  bool reversed = false;
  String? forwardName;
  bool nestingEdge = false;
}

/// Compound multigraph on indices with the iteration orders of `Graph`.
/// Nodes are never added again after removal, so node order is index order.
/// Every edge the pipeline sets has a new (v, w, name) key, so unlike
/// `Graph.setEdge` this one never has to replace the label of an existing
/// edge.
class _Graph {
  final List<_NodeLabel> labels = [];
  final List<bool> alive = [];
  final List<int> parent = [];

  /// Children in the order they were parented; allocated on first use.
  final List<LinkedHashSet<int>?> _children = [];
  final LinkedHashSet<int> rootChildren = LinkedHashSet<int>();
  final List<List<int>> inEdges = [];
  final List<List<int>> outEdges = [];

  /// Successors and their numbers of parallel edges, in the order of
  /// `Graph._sucs`: a successor is appended when its first edge is set and
  /// dropped when its last edge is removed.
  final List<List<int>?> _sucs = [];
  final List<List<int>?> _sucCounts = [];
  int nodeCount = 0;

  final List<int> edgeV = [];
  final List<int> edgeW = [];
  final List<String?> edgeName = [];
  final List<_EdgeLabel> edgeLabels = [];
  final List<bool> edgeAlive = [];

  int addNode(_NodeLabel label) {
    final id = labels.length;
    labels.add(label);
    alive.add(true);
    parent.add(-1);
    _children.add(null);
    rootChildren.add(id);
    inEdges.add([]);
    outEdges.add([]);
    _sucs.add(null);
    _sucCounts.add(null);
    nodeCount++;
    return id;
  }

  /// Alive nodes in insertion order.
  List<int> get nodes => [
    for (var v = 0; v < labels.length; v++)
      if (alive[v]) v,
  ];

  /// Alive edges in insertion order.
  List<int> get edges => [
    for (var e = 0; e < edgeV.length; e++)
      if (edgeAlive[e]) e,
  ];

  /// Children of [v], or of the graph root for -1.
  List<int> childrenOf(int v) =>
      (v < 0 ? rootChildren : _children[v])?.toList() ?? <int>[];

  bool hasChildren(int v) => _children[v]?.isNotEmpty ?? false;

  /// Successors of [v] in `Graph.successors` order.
  List<int> successors(int v) => _sucs[v] ?? const <int>[];

  /// `Graph.setParent`: moves [v] to the end of [p]'s children (-1 is the
  /// graph root) even when [p] is already its parent.
  void setParent(int v, int p) {
    if (p >= 0) {
      var ancestor = p;
      while (ancestor >= 0) {
        ancestor = parent[ancestor];
        if (ancestor == v) {
          throw StateError(
            'Setting  $p   as parent of $v  would create a cycle',
          );
        }
      }
    }
    final old = parent[v];
    (old < 0 ? rootChildren : _children[old])?.remove(v);
    parent[v] = p;
    (p < 0 ? rootChildren : (_children[p] ??= LinkedHashSet<int>())).add(v);
  }

  static String? _name(String? name) =>
      name == null || name.isEmpty ? null : name;

  int setEdge(int v, int w, String? name, _EdgeLabel label) {
    final e = edgeV.length;
    edgeV.add(v);
    edgeW.add(w);
    edgeName.add(_name(name));
    edgeLabels.add(label);
    edgeAlive.add(true);
    inEdges[w].add(e);
    outEdges[v].add(e);
    final sucs = _sucs[v] ??= [];
    final counts = _sucCounts[v] ??= [];
    final at = sucs.indexOf(w);
    if (at < 0) {
      sucs.add(w);
      counts.add(1);
    } else {
      counts[at]++;
    }
    return e;
  }

  /// The alive edge with key (v, w, name).
  int edgeId(int v, int w, String? name) {
    name = _name(name);
    for (final e in outEdges[v]) {
      if (edgeW[e] == w && edgeName[e] == name) return e;
    }
    throw StateError('no edge $v -> $w ($name)');
  }

  void removeEdge(int e) {
    if (!edgeAlive[e]) return;
    edgeAlive[e] = false;
    final v = edgeV[e], w = edgeW[e];
    inEdges[w].remove(e);
    outEdges[v].remove(e);
    _dropSuccessor(v, w);
  }

  void _dropSuccessor(int v, int w) {
    final sucs = _sucs[v]!, counts = _sucCounts[v]!;
    final at = sucs.indexOf(w);
    if (--counts[at] == 0) {
      sucs.removeAt(at);
      counts.removeAt(at);
    }
  }

  /// Like removing the node's in-edges, then its out-edges, one by one, but
  /// the node's own (possibly long) edge lists are cleared once at the end.
  void removeNode(int v) {
    if (!alive[v]) return;
    final p = parent[v];
    (p < 0 ? rootChildren : _children[p])?.remove(v);
    final children = _children[v];
    if (children != null) {
      for (final child in children.toList()) {
        setParent(child, -1);
      }
      children.clear();
    }
    for (final e in inEdges[v]) {
      if (!edgeAlive[e]) continue;
      edgeAlive[e] = false;
      final u = edgeV[e];
      if (u != v) {
        outEdges[u].remove(e);
        _dropSuccessor(u, v);
      }
    }
    for (final e in outEdges[v]) {
      if (!edgeAlive[e]) continue;
      edgeAlive[e] = false;
      final w = edgeW[e];
      if (w != v) inEdges[w].remove(e);
    }
    inEdges[v].clear();
    outEdges[v].clear();
    _sucs[v]?.clear();
    _sucCounts[v]?.clear();
    alive[v] = false;
    nodeCount--;
  }

  /// `util.addDummyNode`.
  int addDummy(Dummy type, _NodeLabel label) {
    label.dummy = type;
    return addNode(label);
  }

  /// `util.addBorderNode` without rank or order.
  int addBorder() => addDummy(
    Dummy.border,
    _NodeLabel()
      ..width = 0
      ..height = 0,
  );
}

class _Layout {
  _Layout(this.config) : rankDir = config.rankDir, rankSep = config.rankSep;

  final DagreConfig config;
  final _Graph g = _Graph();
  final RankDir rankDir;
  double rankSep;
  late double nodeRankFactor;
  final List<int> dummyChains = [];
  double width = 0;
  double height = 0;

  /// Input node id -> index, for the nodes of the input graph.
  final Map<String, int> _index = {};
  int _reversedNames = 0;

  _NodeLabel n(int v) => g.labels[v];

  // `layout()` in dart_dagre.dart builds a graph from the input, and
  // `_buildLayoutGraph` copies it: nodes in input order, each moved under
  // its parent right after it is set. A parent first seen as a parent is
  // created at that point, so it can come before its own turn.
  void build(DagreGraph input) {
    int idOf(String id) =>
        _index.putIfAbsent(id, () => g.addNode(_NodeLabel()));
    for (final node in input.nodeMap.values) {
      final v = idOf(node.id);
      n(v)
        ..width = node.width
        ..height = node.height;
      final parent = node.parent;
      g.setParent(v, parent == null ? -1 : idOf(parent));
    }
    for (final edge in input.edgeMap.values) {
      g.setEdge(
        _index[edge.source]!,
        _index[edge.target]!,
        edge.id,
        _EdgeLabel()
          ..minLen = edge.minLen
          ..weight = edge.weight
          ..width = edge.width
          ..height = edge.height
          ..labelOffset = edge.labelOffset
          ..labelPos = edge.labelPos,
      );
    }
  }

  void run() {
    _makeSpaceForEdgeLabels();
    _removeSelfEdges();
    _acyclic();
    final root = _nestingGraph();
    _rank();
    _injectEdgeLabelProxies();
    _removeEmptyRanks();
    _nestingCleanup(root);
    _normalizeRanks();
    _assignRankMinMax();
    _removeEdgeLabelProxies();
    _normalize();
    _parentDummyChains();
    _addBorderSegments();
    _order();
    _insertSelfEdges();
    if (rankDir == RankDir.ltr || rankDir == RankDir.rtl) {
      _swapWidthHeight();
    }
    _position();
    _positionSelfEdges();
    _removeBorderNodes();
    _normalizeUndo();
    _fixupEdgeLabelCoords();
    _coordinateSystemUndo();
    _translateGraph();
    _assignNodeIntersects();
    _reversePointsForReversedEdges();
    _acyclicUndo();
  }

  void _makeSpaceForEdgeLabels() {
    rankSep /= 2;
    for (final e in g.edges) {
      final edge = g.edgeLabels[e];
      edge.minLen = edge.minLen! * 2;
      if (edge.labelPos != LabelPosition.center) {
        if (rankDir == RankDir.ttb || rankDir == RankDir.btt) {
          edge.width = edge.width! + edge.labelOffset!;
        } else {
          edge.height = edge.height! + edge.labelOffset!;
        }
      }
    }
  }

  void _removeSelfEdges() {
    for (final e in g.edges) {
      final v = g.edgeV[e];
      if (v == g.edgeW[e]) {
        (n(v).selfEdges ??= []).add(
          _SelfEdge(_EdgeKey(v, v, g.edgeName[e]), g.edgeLabels[e]),
        );
        g.removeEdge(e);
      }
    }
  }

  // acyclic.run with dfsFAS (the acyclicer is never greedy here).
  void _acyclic() {
    final fas = <int>[];
    final onStack = List<bool>.filled(g.labels.length, false);
    final visited = List<bool>.filled(g.labels.length, false);
    final stack = <int>[];
    for (final root in g.nodes) {
      if (visited[root]) continue;
      // Entries are node ids; -id - 1 marks the post-visit of node id. (Not
      // ~id: on the web, bitwise operators give unsigned 32-bit results.)
      stack.add(root);
      while (stack.isNotEmpty) {
        final entry = stack.removeLast();
        if (entry < 0) {
          onStack[-entry - 1] = false;
          continue;
        }
        if (visited[entry]) continue;
        visited[entry] = true;
        onStack[entry] = true;
        stack.add(-entry - 1);
        final outs = g.outEdges[entry];
        for (var i = outs.length - 1; i >= 0; i--) {
          final e = outs[i];
          final w = g.edgeW[e];
          if (onStack[w]) {
            fas.add(e);
          } else {
            stack.add(w);
          }
        }
      }
    }
    for (final e in fas) {
      final label = g.edgeLabels[e];
      g.removeEdge(e);
      label.forwardName = g.edgeName[e];
      label.reversed = true;
      // uniqueId("rev"): only needs to be distinct from other edge names.
      g.setEdge(g.edgeW[e], g.edgeV[e], '\u0000rev${_reversedNames++}', label);
    }
  }

  int _nestingGraph() {
    final root = g.addDummy(Dummy.root, _NodeLabel());
    // _treeDepths
    final depths = <int, int>{};
    var level = g.childrenOf(-1);
    var depth = 1;
    while (level.isNotEmpty) {
      final next = <int>[];
      for (final item in level) {
        depths[item] = depth;
        next.addAll(g.childrenOf(item));
      }
      level = next;
      depth += 1;
    }
    var maxDepth = depths.values.first;
    for (final d in depths.values) {
      maxDepth = math.max(maxDepth, d);
    }
    final double height = (maxDepth - 1).toDouble();
    final double nodeSep = 2 * height + 1;

    for (final e in g.edges) {
      final edge = g.edgeLabels[e];
      edge.minLen = edge.minLen! * nodeSep;
    }
    num sum = 0;
    for (final e in g.edges) {
      sum = sum + g.edgeLabels[e].weight!;
    }
    final double weight = (sum + 1).toDouble();

    void dfs(int v) {
      final children = g.childrenOf(v);
      if (children.isEmpty) {
        if (v != root) {
          g.setEdge(
            root,
            v,
            null,
            _EdgeLabel()
              ..weight = 0
              ..minLen = nodeSep,
          );
        }
        return;
      }
      final top = g.addBorder();
      final bottom = g.addBorder();
      final label = n(v);
      g.setParent(top, v);
      label.borderTop = top;
      g.setParent(bottom, v);
      label.borderBottom = bottom;
      for (final child in children) {
        dfs(child);
        final childNode = n(child);
        final childTop = childNode.borderTop >= 0 ? childNode.borderTop : child;
        final childBottom = childNode.borderBottom >= 0
            ? childNode.borderBottom
            : child;
        final thisWeight = childNode.borderTop >= 0 ? weight : 2 * weight;
        final double minLen = childTop != childBottom
            ? 1
            : height - depths[v]! + 1;
        g.setEdge(
          top,
          childTop,
          null,
          _EdgeLabel()
            ..weight = thisWeight
            ..minLen = minLen
            ..nestingEdge = true,
        );
        g.setEdge(
          childBottom,
          bottom,
          null,
          _EdgeLabel()
            ..weight = thisWeight
            ..minLen = minLen
            ..nestingEdge = true,
        );
      }
      if (g.parent[v] < 0) {
        g.setEdge(
          root,
          top,
          null,
          _EdgeLabel()
            ..weight = 0
            ..minLen = height + depths[v]!,
        );
      }
    }

    for (final child in g.childrenOf(-1)) {
      dfs(child);
    }
    nodeRankFactor = nodeSep;
    return root;
  }

  // rankFun(asNonCompoundGraph(g)) with network simplex: leaf nodes in node
  // order, every edge in edge order.
  void _rank() {
    final local = List<int>.filled(g.labels.length, -1);
    final leaves = <int>[];
    for (final v in g.nodes) {
      if (!g.hasChildren(v)) {
        local[v] = leaves.length;
        leaves.add(v);
      }
    }
    final edgeV = <int>[], edgeW = <int>[];
    final weight = <double>[], minLen = <double>[];
    for (final e in g.edges) {
      final v = local[g.edgeV[e]], w = local[g.edgeW[e]];
      if (v < 0 || w < 0) throw _Unsupported();
      edgeV.add(v);
      edgeW.add(w);
      weight.add(g.edgeLabels[e].weight!);
      minLen.add(g.edgeLabels[e].minLen!);
    }
    final ranks = networkSimplexRanks(
      leaves.length,
      edgeV,
      edgeW,
      weight,
      minLen,
    );
    if (ranks == null) throw _Unsupported();
    for (var i = 0; i < leaves.length; i++) {
      n(leaves[i]).rank = ranks[i];
    }
  }

  void _injectEdgeLabelProxies() {
    for (final e in g.edges) {
      final edge = g.edgeLabels[e];
      // getI truncates: a label 0.5 wide gets no proxy.
      final bw = edge.width != null && edge.width!.toInt() != 0;
      final bh = edge.height != null && edge.height!.toInt() != 0;
      if (bw && bh) {
        final v = n(g.edgeV[e]), w = n(g.edgeW[e]);
        g.addDummy(
          Dummy.edgeProxy,
          _NodeLabel()
            ..rank = (w.rank! - v.rank!) / 2 + v.rank!
            ..proxyEdge = e,
        );
      }
    }
  }

  void _removeEmptyRanks() {
    int? offset;
    for (final v in g.nodes) {
      final r = n(v).rank;
      if (r != null) {
        offset = offset == null ? r.toInt() : math.min(offset, r.toInt());
      }
    }
    offset ??= 0;
    // An `Array` keyed by rank - offset, visited from its lowest to its
    // highest key, gaps included.
    final layers = <int, List<int>>{};
    for (final v in g.nodes) {
      final r = n(v).rank;
      if (r == null) continue;
      layers.putIfAbsent(r.toInt() - offset, () => []).add(v);
    }
    if (layers.isEmpty) return;
    final keys = layers.keys.toList()..sort();
    var delta = 0;
    for (var i = keys.first; i <= keys.last; i++) {
      final vs = layers[i];
      if ((vs == null || vs.isEmpty) && i % nodeRankFactor != 0) {
        --delta;
      } else if ((vs != null && vs.isNotEmpty) && delta != 0) {
        for (final v in vs) {
          n(v).rank = n(v).rank! + delta;
        }
      }
    }
  }

  void _nestingCleanup(int root) {
    g.removeNode(root);
    for (final e in g.edges) {
      if (g.edgeLabels[e].nestingEdge) g.removeEdge(e);
    }
  }

  void _normalizeRanks() {
    num? minV;
    for (final v in g.nodes) {
      final r = n(v).rank ?? double.maxFinite;
      minV = minV == null ? r : math.min(minV, r);
    }
    if (minV == null) return;
    for (final v in g.nodes) {
      final r = n(v).rank;
      if (r != null) n(v).rank = r - minV;
    }
  }

  void _assignRankMinMax() {
    for (final v in g.nodes) {
      final node = n(v);
      if (node.borderTop >= 0) {
        node.minRank = n(node.borderTop).rank;
        node.maxRank = n(node.borderBottom).rank;
      }
    }
  }

  void _removeEdgeLabelProxies() {
    for (final v in g.nodes) {
      final node = n(v);
      if (node.dummy == Dummy.edgeProxy) {
        g.edgeLabels[node.proxyEdge].labelRank = node.rank;
        g.removeNode(v);
      }
    }
  }

  void _normalize() {
    for (final e in g.edges) {
      var v = g.edgeV[e];
      var vRank = n(v).rank!.toInt();
      final w = g.edgeW[e];
      final wRank = n(w).rank!.toInt();
      final name = g.edgeName[e];
      final edgeLabel = g.edgeLabels[e];
      final labelRank = edgeLabel.labelRank?.toInt();
      if (wRank == vRank + 1) continue;
      g.removeEdge(e);
      final edgeObj = _EdgeKey(v, w, name);
      var i = 0;
      for (++vRank; vRank < wRank; ++i, ++vRank) {
        edgeLabel.points = <GraphPoint>[];
        final attrs = _NodeLabel()
          ..width = 0
          ..height = 0
          ..edgeLabel = edgeLabel
          ..edgeObj = edgeObj
          ..rank = vRank.toDouble();
        final dummy = g.addDummy(Dummy.edge, attrs);
        if (vRank == labelRank) {
          attrs
            ..width = edgeLabel.width
            ..height = edgeLabel.height
            ..dummy = Dummy.edgeLabel
            ..labelPos = edgeLabel.labelPos;
        }
        g.setEdge(v, dummy, name, _EdgeLabel()..weight = edgeLabel.weight);
        if (i == 0) dummyChains.add(dummy);
        v = dummy;
      }
      g.setEdge(v, w, name, _EdgeLabel()..weight = edgeLabel.weight);
    }
  }

  void _parentDummyChains() {
    // Postorder numbers of the compound tree.
    final low = List<int>.filled(g.labels.length, 0);
    final lim = List<int>.filled(g.labels.length, 0);
    var next = 0;
    void dfs(int v) {
      final l = next;
      for (final child in g.childrenOf(v)) {
        dfs(child);
      }
      low[v] = l;
      lim[v] = next++;
    }

    for (final child in g.childrenOf(-1)) {
      dfs(child);
    }

    for (final start in dummyChains) {
      var v = start;
      final edgeObj = n(v).edgeObj!;
      // _findPath: up from v to the lowest common ancestor (-1 is the
      // root), then down to w.
      final ev = edgeObj.v, ew = edgeObj.w;
      final pathLow = math.min(low[ev], low[ew]);
      final pathLim = math.max(lim[ev], lim[ew]);
      final path = <int>[];
      var p = ev;
      do {
        p = g.parent[p];
        path.add(p);
      } while (p >= 0 && (low[p] > pathLow || pathLim > lim[p]));
      final lca = p;
      final wPath = <int>[];
      p = ew;
      while ((p = g.parent[p]) != lca) {
        wPath.add(p);
      }
      path.addAll(wPath.reversed);

      var pathIdx = 0;
      var pathV = path[pathIdx];
      var ascending = true;
      while (v != ew) {
        final node = n(v);
        if (ascending) {
          while ((pathV = path[pathIdx]) != lca &&
              n(pathV).maxRank! < node.rank!) {
            pathIdx++;
          }
          if (pathV == lca) ascending = false;
        }
        if (!ascending) {
          while (pathIdx < path.length - 1 &&
              n(pathV = path[pathIdx + 1]).minRank! <= node.rank!) {
            pathIdx++;
          }
          pathV = path[pathIdx];
        }
        g.setParent(v, pathV);
        v = g.successors(v).first;
      }
    }
  }

  void _addBorderSegments() {
    void addBorderNode(bool left, int sg, _NodeLabel sgNode, int rank) {
      final label = _NodeLabel()
        ..width = 0
        ..height = 0
        ..rank = rank.toDouble()
        ..borderType = left ? 'borderLeft' : 'borderRight';
      final bl = left ? sgNode.borderLeft! : sgNode.borderRight!;
      final prev = (rank - 1 >= 0 && rank - 1 < bl.length && bl[rank - 1] >= 0)
          ? bl[rank - 1]
          : null;
      final curr = g.addDummy(Dummy.border, label);
      while (bl.length <= rank) {
        bl.add(-1);
      }
      bl[rank] = curr;
      g.setParent(curr, sg);
      if (prev != null) g.setEdge(prev, curr, null, _EdgeLabel()..weight = 1);
    }

    void dfs(int v) {
      final children = g.childrenOf(v);
      final node = n(v);
      children.forEach(dfs);
      if (node.minRank != null) {
        node.borderLeft = [];
        node.borderRight = [];
        for (
          var rank = node.minRank!.toInt(), maxRank = node.maxRank!.toInt() + 1;
          rank < maxRank;
          ++rank
        ) {
          addBorderNode(true, v, node, rank);
          addBorderNode(false, v, node, rank);
        }
      }
    }

    g.childrenOf(-1).forEach(dfs);
  }

  /// util.maxRank: no rank counts as double.minPositive.
  int _maxRank() {
    double? m;
    for (final v in g.nodes) {
      final r = n(v).rank ?? double.minPositive;
      m = m == null ? r : math.max(m, r);
    }
    return m!.toInt();
  }

  /// util.buildLayerMatrix: per rank, nodes keyed by order (a later node
  /// with the same order replaces an earlier one), sorted by order.
  List<List<int>> _layerMatrix() => _layersByOrder(g.nodes, _maxRank() + 1);

  /// Nodes of [nodes] with a rank, per rank and keyed by order as
  /// buildLayerMatrix keys them. Orders are usually 0..k-1 per rank, which
  /// fills a dense list; anything else takes the keyed path.
  List<List<int>> _layersByOrder(List<int> nodes, int rankCount) {
    final counts = List<int>.filled(rankCount, 0);
    for (final v in nodes) {
      final r = n(v).rank;
      if (r != null) counts[r.toInt()]++;
    }
    final layers = [for (final c in counts) List<int>.filled(c, -1)];
    var dense = true;
    for (final v in nodes) {
      final r = n(v).rank;
      if (r == null) continue;
      final layer = layers[r.toInt()];
      final o = n(v).order!.toInt();
      if (o < 0 || o >= layer.length || layer[o] >= 0) {
        dense = false;
        break;
      }
      layer[o] = v;
    }
    if (dense) return layers;
    final byOrder = List<Map<int, int>>.generate(rankCount, (_) => {});
    for (final v in nodes) {
      final r = n(v).rank;
      if (r != null) byOrder[r.toInt()][n(v).order!.toInt()] = v;
    }
    return [
      for (final m in byOrder)
        [for (final k in (m.keys.toList()..sort())) m[k]!],
    ];
  }

  void _order() {
    final maxRank = _maxRank();
    final nodes = g.nodes;

    // nodesByRank
    final byRank = <int, List<int>>{};
    for (final v in nodes) {
      final node = n(v);
      final rank = node.rank?.toInt();
      final minRank = node.minRank, maxRankV = node.maxRank;
      final ranks = <int>{
        ?rank,
        if (minRank != null &&
            maxRankV != null &&
            minRank.isFinite &&
            maxRankV.isFinite)
          for (var r = minRank.ceil(); r <= maxRankV; r++) r,
      };
      for (final r in ranks) {
        final list = byRank.putIfAbsent(r, () => []);
        if (list.isEmpty || list.last != v) list.add(v);
      }
    }

    // Merged edge ends per node for each sweep direction: in-edges for
    // the down sweeps, out-edges for the up sweeps, summed per neighbour.
    final count = g.labels.length;
    List<List<int>> mergedSources(
      bool incoming,
      List<List<double>> weightsOut,
    ) {
      final result = <List<int>>[];
      for (var v = 0; v < count; v++) {
        final sources = <int>[];
        final weights = <double>[];
        if (g.alive[v]) {
          for (final e in incoming ? g.inEdges[v] : g.outEdges[v]) {
            final u = incoming ? g.edgeV[e] : g.edgeW[e];
            final w = g.edgeLabels[e].weight!;
            final at = sources.indexOf(u);
            if (at < 0) {
              sources.add(u);
              weights.add(w);
            } else {
              weights[at] = w + weights[at];
            }
          }
        }
        result.add(sources);
        weightsOut.add(weights);
      }
      return result;
    }

    final downWeights = <List<double>>[], upWeights = <List<double>>[];
    final downSources = mergedSources(true, downWeights);
    final upSources = mergedSources(false, upWeights);

    var nextRoot = count;
    IndexedLayerGraph build(int rank, Relationship ship) {
      final down = ship == Relationship.inEdges;
      final lg = IndexedLayerGraph(
        nextRoot++,
        down ? downSources : upSources,
        down ? downWeights : upWeights,
        g.parent,
      );
      for (final v in byRank[rank] ?? const <int>[]) {
        final node = n(v);
        if (!(node.rank?.toInt() == rank ||
            (node.minRank ?? double.nan) <= rank &&
                rank <= (node.maxRank ?? double.nan))) {
          continue;
        }
        lg.addMember(v);
        if (g.hasChildren(v)) lg.clusterMembers.add(v);
        // Clusters get their own label with this rank's border nodes.
        if (node.minRank != null) {
          lg.ownLabel.add(v);
          lg.borders[v] = (node.borderLeft![rank], node.borderRight![rank]);
        } else if (node.borderLeft != null || node.borderRight != null) {
          final bl = node.borderLeft, br = node.borderRight;
          lg.borders[v] = (
            bl == null || bl.isEmpty ? null : bl.first,
            br == null || br.isEmpty ? null : br.first,
          );
        }
      }
      return lg;
    }

    final down = [
      for (var r = 1; r < maxRank + 1; r++) build(r, Relationship.inEdges),
    ];
    final up = [
      for (var r = maxRank - 1; r > -1; r--) build(r, Relationship.outEdges),
    ];

    // initOrder
    final simpleNodes = [
      for (final v in nodes)
        if (!g.hasChildren(v)) v,
    ];
    var maxSimpleRank = n(simpleNodes.first).rank!.toInt();
    for (final v in simpleNodes) {
      maxSimpleRank = math.max(maxSimpleRank, n(v).rank!.toInt());
    }
    final layering = List<List<int>>.generate(maxSimpleRank + 1, (_) => []);
    final visited = List<bool>.filled(g.labels.length, false);
    final rankOf = Float64List(g.labels.length);
    for (final v in simpleNodes) {
      rankOf[v] = n(v).rank!;
    }
    // Stable, as lodash sortBy in dagre.js: nodes of one rank keep graph
    // order. List.sort is not stable for longer lists.
    final graphPos = Int32List(g.labels.length);
    for (var i = 0; i < simpleNodes.length; i++) {
      graphPos[simpleNodes[i]] = i;
    }
    simpleNodes.sort((a, b) {
      final byRank = rankOf[a].compareTo(rankOf[b]);
      return byRank != 0 ? byRank : graphPos[a] - graphPos[b];
    });
    final stack = <int>[];
    for (final start in simpleNodes) {
      stack.add(start);
      while (stack.isNotEmpty) {
        final curr = stack.removeLast();
        if (visited[curr]) continue;
        visited[curr] = true;
        layering[n(curr).rank!.toInt()].add(curr);
        final succ = g.successors(curr);
        for (var i = succ.length - 1; i >= 0; i--) {
          stack.add(succ[i]);
        }
      }
    }
    for (final layer in layering) {
      for (var i = 0; i < layer.length; i++) {
        n(layer[i]).order = i.toDouble();
      }
    }

    final isCompoundLayout = nodes.any(g.hasChildren);
    final outTargets = <List<int>>[];
    final outWeights = <List<num>>[];
    for (var v = 0; v < count; v++) {
      outTargets.add([for (final e in g.outEdges[v]) g.edgeW[e]]);
      outWeights.add([for (final e in g.outEdges[v]) g.edgeLabels[e].weight!]);
    }
    final sweeps = IndexedOrder(
      [for (var v = 0; v < count; v++) n(v).order ?? 0],
      [for (var v = 0; v < count; v++) g.alive[v] ? n(v).rank?.toInt() : null],
      outTargets,
      outWeights,
      down,
      up,
    );
    if (!isCompoundLayout && sweeps.crossCount(layering) == 0) return;
    if (config.disableOptimalOrderHeuristic) return;
    for (final layer in sweeps.run(maxRank)) {
      for (var i = 0; i < layer.length; i++) {
        n(layer[i]).order = i.toDouble();
      }
    }
  }

  void _insertSelfEdges() {
    for (final layer in _layerMatrix()) {
      var orderShift = 0;
      for (var i = 0; i < layer.length; i++) {
        final node = n(layer[i]);
        node.order = (i + orderShift).toDouble();
        for (final selfEdge in node.selfEdges ?? const <_SelfEdge>[]) {
          g.addDummy(
            Dummy.selfEdge,
            _NodeLabel()
              ..width = selfEdge.label.width
              ..height = selfEdge.label.height
              ..rank = node.rank
              ..order = (i + (++orderShift)).toDouble()
              ..selfEdge = selfEdge,
          );
        }
        node.selfEdges = null;
      }
    }
  }

  void _swapWidthHeight() {
    for (final v in g.nodes) {
      final node = n(v);
      final w = node.width;
      node.width = node.height;
      node.height = w;
    }
    for (final e in g.edges) {
      final edge = g.edgeLabels[e];
      final w = edge.width;
      edge.width = edge.height;
      edge.height = w;
    }
  }

  // position(): leaf nodes, the layering, y per layer, then Brandes-Köpf x.
  void _position() {
    final count = g.labels.length;
    final isLeaf = List<bool>.filled(count, false);
    final leaves = <int>[];
    for (final v in g.nodes) {
      if (!g.hasChildren(v)) {
        isLeaf[v] = true;
        leaves.add(v);
      }
    }
    final predsAll = List<List<int>?>.filled(count, null);
    final succsAll = List<List<int>?>.filled(count, null);
    for (final e in g.edges) {
      final v = g.edgeV[e], w = g.edgeW[e];
      if (!isLeaf[v] || !isLeaf[w]) throw _Unsupported();
      final p = predsAll[w] ??= [];
      if (!p.contains(v)) p.add(v);
      final s = succsAll[v] ??= [];
      if (!s.contains(w)) s.add(w);
    }

    double? maxRankValue;
    for (final v in leaves) {
      final r = n(v).rank ?? double.minPositive;
      maxRankValue = maxRankValue == null ? r : math.max(maxRankValue, r);
    }
    final rankCount = maxRankValue!.toInt() + 1;
    for (final v in leaves) {
      final r = n(v).rank;
      if (r != null && (r.toInt() < 0 || r.toInt() >= rankCount)) {
        throw _Unsupported();
      }
    }
    final layering = _layersByOrder(leaves, rankCount);
    final local = List<int>.filled(count, -1);
    final layerNodes = <int>[];
    final layers = <List<int>>[];
    for (final layer in layering) {
      final ids = <int>[];
      for (final v in layer) {
        local[v] = layerNodes.length;
        ids.add(layerNodes.length);
        layerNodes.add(v);
      }
      layers.add(ids);
    }
    List<int> mapped(List<int>? list) {
      final out = <int>[];
      for (final u in list ?? const <int>[]) {
        if (local[u] < 0) throw _Unsupported();
        out.add(local[u]);
      }
      return out;
    }

    final preds = [for (final v in layerNodes) mapped(predsAll[v])];
    final succs = [for (final v in layerNodes) mapped(succsAll[v])];

    // positionY
    num prevY = 0;
    for (final layer in layers) {
      num? maxHeight;
      for (final v in layer) {
        final h = n(layerNodes[v]).height!;
        maxHeight = maxHeight == null ? h : math.max(maxHeight, h);
      }
      maxHeight ??= 0;
      for (final v in layer) {
        n(layerNodes[v]).y = (prevY + maxHeight / 2).toDouble();
      }
      prevY += maxHeight + rankSep;
    }

    final label = GraphLabel(nodeSep: config.nodeSep, edgeSep: config.edgeSep)
      ..align = config.align;
    final xs = IndexedBk(
      label,
      layers,
      [for (final v in layerNodes) n(v).order!],
      [for (final v in layerNodes) n(v).width!],
      [for (final v in layerNodes) n(v).dummy != null],
      [for (final v in layerNodes) n(v).dummy == Dummy.border],
      [for (final v in layerNodes) n(v).labelPos],
      [for (final v in layerNodes) n(v).borderType],
      preds,
      succs,
    ).runIndexed();
    for (var i = 0; i < xs.length; i++) {
      n(layerNodes[i]).x = xs[i];
    }
  }

  void _positionSelfEdges() {
    for (final v in g.nodes) {
      final node = n(v);
      if (node.dummy != Dummy.selfEdge) continue;
      final selfEdge = node.selfEdge!;
      final selfNode = n(selfEdge.key.v);
      final x = selfNode.x! + selfNode.width! / 2;
      final y = selfNode.y!;
      final dx = node.x! - x;
      final dy = selfNode.height! / 2;
      g.setEdge(
        selfEdge.key.v,
        selfEdge.key.w,
        selfEdge.key.name,
        selfEdge.label,
      );
      g.removeNode(v);
      selfEdge.label
        ..points = <GraphPoint>[
          GraphPoint(x + 2 * dx / 3, y - dy),
          GraphPoint(x + 5 * dx / 6, y - dy),
          GraphPoint(x + dx, y),
          GraphPoint(x + 5 * dx / 6, y + dy),
          GraphPoint(x + 2 * dx / 3, y + dy),
        ]
        ..x = node.x
        ..y = node.y;
    }
  }

  void _removeBorderNodes() {
    for (final v in g.nodes) {
      if (!g.hasChildren(v)) continue;
      final node = n(v);
      final t = n(node.borderTop), b = n(node.borderBottom);
      final l = n(node.borderLeft!.last), r = n(node.borderRight!.last);
      node.width = (r.x! - l.x!).abs();
      node.height = (b.y! - t.y!).abs();
      node.x = l.x! + node.width! / 2;
      node.y = t.y! + node.height! / 2;
    }
    for (final v in g.nodes) {
      if (n(v).dummy == Dummy.border) g.removeNode(v);
    }
  }

  void _normalizeUndo() {
    for (var v in dummyChains) {
      var node = n(v);
      final origLabel = node.edgeLabel!;
      final edgeObj = node.edgeObj!;
      g.setEdge(edgeObj.v, edgeObj.w, edgeObj.name, origLabel);
      while (node.dummy != null) {
        final w = g.successors(v).first;
        g.removeNode(v);
        origLabel.points!.add(GraphPoint(node.x!, node.y!));
        if (node.dummy == Dummy.edgeLabel) {
          origLabel
            ..x = node.x
            ..y = node.y
            ..width = node.width
            ..height = node.height;
        }
        v = w;
        node = n(v);
      }
    }
  }

  void _fixupEdgeLabelCoords() {
    for (final e in g.edges) {
      final edge = g.edgeLabels[e];
      final xValue = edge.x;
      if (xValue == null) continue;
      if (edge.labelPos == LabelPosition.left ||
          edge.labelPos == LabelPosition.right) {
        edge.width = edge.width! - edge.labelOffset!;
      }
      final lp = edge.labelPos!;
      if (lp == LabelPosition.left) {
        edge.x = xValue - (edge.width! / 2 + edge.labelOffset!);
      } else if (lp == LabelPosition.right) {
        edge.x = xValue + (edge.width! / 2 + edge.labelOffset!);
      }
    }
  }

  void _coordinateSystemUndo() {
    if (rankDir == RankDir.btt || rankDir == RankDir.rtl) {
      for (final v in g.nodes) {
        n(v).y = -n(v).y!;
      }
      for (final e in g.edges) {
        final edge = g.edgeLabels[e];
        for (final p in edge.points ?? const <GraphPoint>[]) {
          p.y = -p.y;
        }
        final y = edge.y;
        if (y != null && y != 0) edge.y = -y;
      }
    }
    if (rankDir == RankDir.ltr || rankDir == RankDir.rtl) {
      for (final v in g.nodes) {
        final node = n(v);
        final x = node.x;
        node.x = node.y;
        node.y = x;
      }
      for (final e in g.edges) {
        final edge = g.edgeLabels[e];
        final points = edge.points;
        if (points != null) {
          edge.points = [for (final p in points) GraphPoint(p.y, p.x)];
        }
        if (edge.x != null) {
          final x = edge.x;
          edge.x = edge.y;
          edge.y = x;
        }
      }
      _swapWidthHeight();
    }
  }

  void _translateGraph() {
    var minX = double.maxFinite;
    double maxX = 0;
    var minY = double.maxFinite;
    double maxY = 0;
    void extremes(double x, double y, double w, double h) {
      minX = math.min(minX, x - w / 2);
      maxX = math.max(maxX, x + w / 2);
      minY = math.min(minY, y - h / 2);
      maxY = math.max(maxY, y + h / 2);
    }

    final nodes = g.nodes, edges = g.edges;
    for (final v in nodes) {
      final node = n(v);
      extremes(node.x!, node.y!, node.width!, node.height!);
    }
    for (final e in edges) {
      final edge = g.edgeLabels[e];
      if (edge.x != null) extremes(edge.x!, edge.y!, edge.width!, edge.height!);
    }
    minX -= config.marginX;
    minY -= config.marginY;
    for (final v in nodes) {
      final node = n(v);
      node.x = node.x! - minX;
      node.y = node.y! - minY;
    }
    for (final e in edges) {
      final edge = g.edgeLabels[e];
      for (final p in edge.points ?? const <GraphPoint>[]) {
        p.x -= minX;
        p.y -= minY;
      }
      if (edge.x != null) edge.x = edge.x! - minX;
      if (edge.y != null) edge.y = edge.y! - minY;
    }
    width = maxX - minX + config.marginX;
    height = maxY - minY + config.marginY;
  }

  void _assignNodeIntersects() {
    for (final e in g.edges) {
      final edge = g.edgeLabels[e];
      final nodeV = n(g.edgeV[e]), nodeW = n(g.edgeW[e]);
      final points = edge.points;
      GraphPoint p1, p2;
      if (points == null || points.isEmpty) {
        p1 = GraphPoint(nodeW.x!, nodeW.y!);
        p2 = GraphPoint(nodeV.x!, nodeV.y!);
      } else {
        p1 = points[0];
        p2 = points.last;
      }
      points?.insert(
        0,
        util.intersectRect(
          GraphRect(nodeV.x!, nodeV.y!, nodeV.width!, nodeV.height!),
          p1,
        ),
      );
      points?.add(
        util.intersectRect(
          GraphRect(nodeW.x!, nodeW.y!, nodeW.width!, nodeW.height!),
          p2,
        ),
      );
    }
  }

  void _reversePointsForReversedEdges() {
    for (final e in g.edges) {
      final edge = g.edgeLabels[e];
      if (edge.reversed && edge.points != null) {
        edge.points = edge.points!.reversed.toList();
      }
    }
  }

  void _acyclicUndo() {
    for (final e in g.edges) {
      final label = g.edgeLabels[e];
      if (!label.reversed) continue;
      g.removeEdge(e);
      final name = label.forwardName;
      label
        ..reversed = false
        ..forwardName = null;
      g.setEdge(g.edgeW[e], g.edgeV[e], name, label);
    }
  }

  /// `_updateInputGraph` and the read-back in `layout()`: positions of all
  /// input nodes (clusters take their computed size), edge points and
  /// label centers.
  void writeBack(DagreGraph input) {
    for (final node in input.nodeMap.values) {
      final v = _index[node.id]!;
      final label = n(v);
      final cluster = g.hasChildren(v);
      input.nodeMap[node.id]!.position = Rect.fromCenter(
        Point(label.x!, label.y!),
        cluster ? label.width! : node.width,
        cluster ? label.height! : node.height,
      );
    }
    for (final edge in input.edgeMap.values) {
      final e = g.edgeId(_index[edge.source]!, _index[edge.target]!, edge.id);
      final label = g.edgeLabels[e];
      edge.points = [
        for (final p in label.points ?? const <GraphPoint>[]) Point(p.x, p.y),
      ];
      edge.labelX = label.x;
      edge.labelY = label.x != null ? label.y : null;
    }
  }
}

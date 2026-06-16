/// Phase 2 — faithful port of ELK's `NetworkSimplexLayerer`
/// (`p2layers/NetworkSimplexLayerer.java`) and the generic network-simplex
/// solver (`org.eclipse.elk.alg.common.networksimplex.NetworkSimplex`).
///
/// Assigns every node in `graph.layerlessNodes` to a [Layer] using the
/// network-simplex algorithm described in:
///   Gansner et al., "A Technique for Drawing Directed Graphs", IEEE Trans.
///   Software Engineering 19(3), 1993.
///
/// The graph must be acyclic (phase 1 has already reversed feedback edges).
/// After this phase every node has `node.layer` set, appears in exactly one
/// `Layer.nodes`, `graph.layers` is the ordered layer list, and
/// `graph.layerlessNodes` is cleared.
library;

import 'dart:math' show sqrt;

import 'lgraph.dart';
import 'phase.dart';
import 'property.dart';

// ---------------------------------------------------------------------------
// Property constants (ELK ids and defaults matching the Java sources)
// ---------------------------------------------------------------------------

/// How hard to work: ELK `LayeredOptions.THOROUGHNESS`. Default 7.
const _thoroughness = Property<int>('layered.thoroughness', 7);

/// Per-edge weight bias: ELK `LayeredOptions.PRIORITY_SHORTNESS`. Default 0.
/// Higher value = algorithm tries harder to keep the edge short.
const _priorityShortness = Property<int>('layered.priority.shortness', 0);

/// Factor by which the iteration limit is multiplied (ELK constant).
const int _iterLimitFactor = 4;

// ---------------------------------------------------------------------------
// Public phase entry point
// ---------------------------------------------------------------------------

/// Phase 2 implementation — network-simplex layering.
class NetworkSimplexLayerer implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final nodes = graph.layerlessNodes;
    if (nodes.isEmpty) return;

    final thoroughness =
        graph.getProperty(_thoroughness) * _iterLimitFactor;

    // Re-index all nodes so we can use node.id as an array index.
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].id = i;
    }

    // Split into connected components and layer each one independently.
    final components = _connectedComponents(nodes);
    List<int>? previousLayeringNodeCounts;

    for (final comp in components) {
      final iterLimit = thoroughness * _sqrt(comp.length);
      final ngraph = _buildNGraph(comp);

      _NetworkSimplex(ngraph)
        .._iterationLimit = iterLimit
        .._previousLayeringNodeCounts = previousLayeringNodeCounts
        .._balance = true
        ..execute();

      // Write computed NNode.layer back to LGraph.layers.
      final layers = graph.layers;
      for (final nNode in ngraph.nodes) {
        while (layers.length <= nNode.layer) {
          layers.add(Layer(graph));
        }
        final lNode = nNode.origin as LNode;
        lNode.layer = layers[nNode.layer];
        if (!layers[nNode.layer].nodes.contains(lNode)) {
          layers[nNode.layer].nodes.add(lNode);
        }
      }

      if (components.length > 1) {
        previousLayeringNodeCounts = [
          for (final l in graph.layers) l.nodes.length,
        ];
      }
    }

    nodes.clear();
  }

  // -------------------------------------------------------------------------
  // Connected components
  // -------------------------------------------------------------------------

  List<List<LNode>> _connectedComponents(List<LNode> theNodes) {
    final visited = List<bool>.filled(theNodes.length, false);
    final components = <List<LNode>>[];
    final current = <LNode>[];

    for (final node in theNodes) {
      if (!visited[node.id]) {
        current.clear();
        _ccDFS(node, visited, current);
        // Largest component first (like the Java: addFirst / addLast).
        if (components.isEmpty ||
            components.first.length < current.length) {
          components.insert(0, List<LNode>.of(current));
        } else {
          components.add(List<LNode>.of(current));
        }
      }
    }
    return components;
  }

  void _ccDFS(LNode node, List<bool> visited, List<LNode> out) {
    visited[node.id] = true;
    out.add(node);
    for (final port in node.ports) {
      for (final edge in port.connectedEdges) {
        final opposite =
            (edge.source == port ? edge.target! : edge.source!).node;
        if (!visited[opposite.id]) {
          _ccDFS(opposite, visited, out);
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Build NGraph from a connected component of LNodes
  // -------------------------------------------------------------------------

  _NGraph _buildNGraph(List<LNode> comp) {
    final ngraph = _NGraph();
    final nodeMap = <LNode, _NNode>{};

    for (final lNode in comp) {
      final nNode = _NNode()..origin = lNode;
      ngraph.nodes.add(nNode);
      nodeMap[lNode] = nNode;
    }

    for (final lNode in comp) {
      for (final lEdge in lNode.outgoingEdges) {
        if (lEdge.isSelfLoop) continue;
        final targetLNode = lEdge.target!.node;
        final src = nodeMap[lNode];
        final tgt = nodeMap[targetLNode];
        if (src == null || tgt == null) continue; // cross-component (shouldn't happen)
        final shortness = lEdge.getProperty(_priorityShortness);
        final nEdge = _NEdge()
          ..source = src
          ..target = tgt
          ..weight = 1.0 * (shortness < 1 ? 1 : shortness)
          ..delta = 1;
        src.outgoing.add(nEdge);
        tgt.incoming.add(nEdge);
      }
    }

    return ngraph;
  }

  // -------------------------------------------------------------------------
  // Utilities
  // -------------------------------------------------------------------------

  static int _sqrt(int n) => n <= 0 ? 0 : sqrt(n.toDouble()).floor();
}

// ---------------------------------------------------------------------------
// Lightweight network-simplex graph model
// (port of NGraph / NNode / NEdge — kept private, no public API needed)
// ---------------------------------------------------------------------------

class _NGraph {
  final List<_NNode> nodes = [];
}

class _NNode {
  Object? origin;
  int layer = 0;
  int internalId = 0;
  bool treeNode = false;
  final List<_NEdge> outgoing = [];
  final List<_NEdge> incoming = [];
  final List<_NEdge> unknownCutvalues = [];

  List<_NEdge> get connectedEdges => [...incoming, ...outgoing];
}

class _NEdge {
  late _NNode source;
  late _NNode target;
  double weight = 1.0;
  int delta = 1;
  int internalId = 0;
  bool treeEdge = false;

  _NNode getOther(_NNode node) =>
      node == source ? target : source;
}

// ---------------------------------------------------------------------------
// Network-simplex solver
// (port of org.eclipse.elk.alg.common.networksimplex.NetworkSimplex)
// ---------------------------------------------------------------------------

/// Port of ELK's `NetworkSimplex` solver.  All algorithm logic is faithful;
/// the only wiring difference is that we work with the private [_NGraph]
/// model above instead of the Java NGraph/NNode/NEdge classes.
class _NetworkSimplex {
  _NetworkSimplex(this._graph);

  final _NGraph _graph;

  // -- Configuration set by the layerer before calling execute() --
  int _iterationLimit = 0x7fffffff;
  bool _balance = false;
  List<int>? _previousLayeringNodeCounts;

  // -- Working state --
  late List<_NEdge> _edges;
  late Set<_NEdge> _treeEdges; // linked-hash-set order matters for leaveEdge
  late List<_NNode> _sources;
  late List<bool> _edgeVisited;
  late int _postOrder;
  late List<int> _poID;
  late List<int> _lowestPoID;
  late List<double> _cutvalue;

  // Subtree removal stack: (node, edge) pairs.
  final List<({_NNode node, _NEdge edge})> _subtreeStack = [];

  // Empirically determined threshold when removing subtrees pays off (ELK
  // constant).
  static const int _removeSubtreesThresh = 40;
  static const double _fuzzyStzero = -1e-10;

  void execute() {
    if (_graph.nodes.isEmpty) return;

    // Reset any old layering.
    for (final n in _graph.nodes) {
      n.layer = 0;
    }

    // Remove leaf subtrees for large graphs (optimisation from Java).
    final doRemoveSubtrees = _graph.nodes.length >= _removeSubtreesThresh;
    if (doRemoveSubtrees) _removeSubtrees();

    _initialize();
    _feasibleTree();

    var e = _leaveEdge();
    var iter = 0;
    while (e != null && iter < _iterationLimit) {
      _exchange(e, _enterEdge(e));
      e = _leaveEdge();
      iter++;
    }

    if (doRemoveSubtrees) _reattachSubtrees();

    if (_balance) {
      _balance2(_normalize());
    } else {
      _normalize();
    }
  }

  // -------------------------------------------------------------------------
  // Subtree removal (optimization)
  // -------------------------------------------------------------------------

  void _removeSubtrees() {
    _subtreeStack.clear();

    // Collect initial leaves (nodes with exactly one connected edge).
    final leaves = <_NNode>[];
    for (final node in _graph.nodes) {
      if (node.connectedEdges.length == 1) leaves.add(node);
    }

    while (leaves.isNotEmpty) {
      final node = leaves.removeAt(0);
      if (node.connectedEdges.isEmpty) continue;
      final edge = node.connectedEdges.first;
      final isOutEdge = node.outgoing.isNotEmpty;

      final other = edge.getOther(node);
      if (isOutEdge) {
        other.incoming.remove(edge);
      } else {
        other.outgoing.remove(edge);
      }
      if (other.connectedEdges.length == 1) leaves.add(other);

      _subtreeStack.add((node: node, edge: edge));
      _graph.nodes.remove(node);
    }
  }

  void _reattachSubtrees() {
    // Re-attach in reverse order.
    for (var i = _subtreeStack.length - 1; i >= 0; i--) {
      final (:node, :edge) = _subtreeStack[i];
      final placed = edge.getOther(node);
      if (edge.target == node) {
        placed.outgoing.add(edge);
        node.layer = placed.layer + edge.delta;
      } else {
        placed.incoming.add(edge);
        node.layer = placed.layer - edge.delta;
      }
      _graph.nodes.add(node);
    }
  }

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  void _initialize() {
    final numNodes = _graph.nodes.length;
    for (final n in _graph.nodes) {
      n.treeNode = false;
    }
    _poID = List.filled(numNodes, 0);
    _lowestPoID = List.filled(numNodes, 0);
    _sources = [];

    final theEdges = <_NEdge>[];
    var idx = 0;
    for (final node in _graph.nodes) {
      node.internalId = idx++;
      if (node.incoming.isEmpty) _sources.add(node);
      theEdges.addAll(node.outgoing);
    }

    var eIdx = 0;
    for (final e in theEdges) {
      e.internalId = eIdx++;
      e.treeEdge = false;
    }

    final numEdges = theEdges.length;
    _cutvalue = List.filled(numEdges, 0.0);
    _edgeVisited = List.filled(numEdges, false);
    _edges = theEdges;
    _treeEdges = <_NEdge>{}; // insertion-order set (Dart's LinkedHashSet default)
    _postOrder = 1;
  }

  // -------------------------------------------------------------------------
  // Feasible spanning tree
  // -------------------------------------------------------------------------

  void _feasibleTree() {
    _layeringTopologicalNumbering(_sources);

    if (_edges.isNotEmpty) {
      _edgeVisited.fillRange(0, _edgeVisited.length, false);
      while (_tightTreeDFS(_graph.nodes.first) < _graph.nodes.length) {
        final e = _minimalSlack()!;
        var slack = e.target.layer - e.source.layer - e.delta;
        if (e.target.treeNode) slack = -slack;
        for (final node in _graph.nodes) {
          if (node.treeNode) node.layer += slack;
        }
        _edgeVisited.fillRange(0, _edgeVisited.length, false);
      }
      _edgeVisited.fillRange(0, _edgeVisited.length, false);
      _postorderTraversal(_graph.nodes.first);
      _cutvalues();
    }
  }

  void _layeringTopologicalNumbering(List<_NNode> roots) {
    final incident = List.filled(_graph.nodes.length, 0);
    for (final node in _graph.nodes) {
      incident[node.internalId] += node.incoming.length;
    }
    final queue = List<_NNode>.of(roots);
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      for (final edge in node.outgoing) {
        final target = edge.target;
        final candidate = node.layer + edge.delta;
        if (candidate > target.layer) target.layer = candidate;
        incident[target.internalId]--;
        if (incident[target.internalId] == 0) queue.add(target);
      }
    }
  }

  int _tightTreeDFS(_NNode node) {
    var count = 1;
    node.treeNode = true;
    for (final edge in node.connectedEdges) {
      if (_edgeVisited[edge.internalId]) continue;
      _edgeVisited[edge.internalId] = true;
      final opposite = edge.getOther(node);
      if (edge.treeEdge) {
        count += _tightTreeDFS(opposite);
      } else if (!opposite.treeNode &&
          edge.delta == edge.target.layer - edge.source.layer) {
        edge.treeEdge = true;
        _treeEdges.add(edge);
        count += _tightTreeDFS(opposite);
      }
    }
    return count;
  }

  _NEdge? _minimalSlack() {
    var minSlack = 0x7fffffff;
    _NEdge? best;
    for (final edge in _edges) {
      if (edge.source.treeNode ^ edge.target.treeNode) {
        final slack = edge.target.layer - edge.source.layer - edge.delta;
        if (slack < minSlack) {
          minSlack = slack;
          best = edge;
        }
      }
    }
    return best;
  }

  // -------------------------------------------------------------------------
  // Postorder traversal + cut values
  // -------------------------------------------------------------------------

  int _postorderTraversal(_NNode node) {
    var lowest = 0x7fffffff;
    for (final edge in node.connectedEdges) {
      if (edge.treeEdge && !_edgeVisited[edge.internalId]) {
        _edgeVisited[edge.internalId] = true;
        lowest = _min(lowest, _postorderTraversal(edge.getOther(node)));
      }
    }
    _poID[node.internalId] = _postOrder;
    _lowestPoID[node.internalId] = _min(lowest, _postOrder++);
    return _lowestPoID[node.internalId];
  }

  bool _isInHead(_NNode node, _NEdge edge) {
    final src = edge.source;
    final tgt = edge.target;
    final nPo = _poID[node.internalId];

    if (_lowestPoID[src.internalId] <= nPo &&
        nPo <= _poID[src.internalId] &&
        _lowestPoID[tgt.internalId] <= nPo &&
        nPo <= _poID[tgt.internalId]) {
      if (_poID[src.internalId] < _poID[tgt.internalId]) return false;
      return true;
    }
    if (_poID[src.internalId] < _poID[tgt.internalId]) return true;
    return false;
  }

  void _cutvalues() {
    final leaves = <_NNode>[];
    for (final node in _graph.nodes) {
      node.unknownCutvalues.clear();
      var treeCount = 0;
      for (final edge in node.connectedEdges) {
        if (edge.treeEdge) {
          node.unknownCutvalues.add(edge);
          treeCount++;
        }
      }
      if (treeCount == 1) leaves.add(node);
    }

    for (var i = 0; i < leaves.length; i++) {
      var node = leaves[i];
      while (node.unknownCutvalues.length == 1) {
        final toDetermine = node.unknownCutvalues.first;
        _cutvalue[toDetermine.internalId] = toDetermine.weight;
        final src = toDetermine.source;
        final tgt = toDetermine.target;
        for (final edge in node.connectedEdges) {
          if (edge == toDetermine) continue;
          if (edge.treeEdge) {
            if (src == edge.source || tgt == edge.target) {
              _cutvalue[toDetermine.internalId] -=
                  _cutvalue[edge.internalId] - edge.weight;
            } else {
              _cutvalue[toDetermine.internalId] +=
                  _cutvalue[edge.internalId] - edge.weight;
            }
          } else {
            if (node == src) {
              if (edge.source == node) {
                _cutvalue[toDetermine.internalId] += edge.weight;
              } else {
                _cutvalue[toDetermine.internalId] -= edge.weight;
              }
            } else {
              if (edge.source == node) {
                _cutvalue[toDetermine.internalId] -= edge.weight;
              } else {
                _cutvalue[toDetermine.internalId] += edge.weight;
              }
            }
          }
        }
        src.unknownCutvalues.remove(toDetermine);
        tgt.unknownCutvalues.remove(toDetermine);
        node = (node == src) ? tgt : src;
      }
    }
  }

  // -------------------------------------------------------------------------
  // Leave / enter / exchange
  // -------------------------------------------------------------------------

  _NEdge? _leaveEdge() {
    for (final edge in _treeEdges) {
      if (edge.treeEdge && _cutvalue[edge.internalId] < _fuzzyStzero) {
        return edge;
      }
    }
    return null;
  }

  _NEdge _enterEdge(_NEdge leave) {
    _NEdge? replace;
    var repSlack = 0x7fffffff;
    for (final edge in _edges) {
      if (_isInHead(edge.source, leave) && !_isInHead(edge.target, leave)) {
        final slack = edge.target.layer - edge.source.layer - edge.delta;
        if (slack < repSlack) {
          repSlack = slack;
          replace = edge;
        }
      }
    }
    return replace!;
  }

  void _exchange(_NEdge leave, _NEdge enter) {
    leave.treeEdge = false;
    _treeEdges.remove(leave);
    enter.treeEdge = true;
    _treeEdges.add(enter);

    var delta = enter.target.layer - enter.source.layer - enter.delta;
    if (!_isInHead(enter.target, leave)) delta = -delta;
    for (final node in _graph.nodes) {
      if (!_isInHead(node, leave)) node.layer += delta;
    }

    _postOrder = 1;
    _edgeVisited.fillRange(0, _edgeVisited.length, false);
    _postorderTraversal(_graph.nodes.first);
    _cutvalues();
  }

  // -------------------------------------------------------------------------
  // Normalize + balance
  // -------------------------------------------------------------------------

  List<int> _normalize() {
    var highest = -0x80000000;
    var lowest = 0x7fffffff;
    for (final node in _graph.nodes) {
      if (node.layer < lowest) lowest = node.layer;
      if (node.layer > highest) highest = node.layer;
    }
    final filling = List.filled(highest - lowest + 1, 0);
    for (final node in _graph.nodes) {
      node.layer -= lowest;
      filling[node.layer]++;
    }
    // Consider nodes from already-layered connected components.
    final prev = _previousLayeringNodeCounts;
    if (prev != null) {
      for (var i = 0; i < prev.length && i < filling.length; i++) {
        filling[i] += prev[i];
      }
    }
    return filling;
  }

  void _balance2(List<int> filling) {
    for (final node in _graph.nodes) {
      if (node.incoming.length != node.outgoing.length) continue;
      final span = _minimalSpan(node);
      final minIn = span.$1;
      final minOut = span.$2;
      if (minIn < 0 || minOut < 0) continue;

      var newLayer = node.layer;
      final lo = node.layer - minIn + 1;
      final hi = node.layer + minOut;
      for (var i = lo; i < hi; i++) {
        if (i >= 0 && i < filling.length && filling[i] < filling[newLayer]) {
          newLayer = i;
        }
      }
      if (filling[newLayer] < filling[node.layer]) {
        filling[node.layer]--;
        filling[newLayer]++;
        node.layer = newLayer;
      }
    }
  }

  /// Returns (minSpanIn, minSpanOut): minimum span of incoming / outgoing edges.
  /// Returns -1 for a direction with no edges.
  (int, int) _minimalSpan(_NNode node) {
    var minIn = 0x7fffffff;
    var minOut = 0x7fffffff;
    for (final edge in node.connectedEdges) {
      final span = edge.target.layer - edge.source.layer;
      if (edge.target == node) {
        if (span < minIn) minIn = span;
      } else {
        if (span < minOut) minOut = span;
      }
    }
    return (minIn == 0x7fffffff ? -1 : minIn,
            minOut == 0x7fffffff ? -1 : minOut);
  }

  // -------------------------------------------------------------------------
  // Tiny helpers
  // -------------------------------------------------------------------------

  static int _min(int a, int b) => a < b ? a : b;
}


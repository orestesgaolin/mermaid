// ignore_for_file: unused_element
import 'package:elk_layout/src/dagre/src/model/props.dart';
import 'package:elk_layout/src/dagre/src/rank/util.dart';
import 'package:elk_layout/src/dagre/src/util/list_util.dart';
import '../graph/graph.dart';
import '../graph/alg/postorder.dart';
import '../graph/alg/preorder.dart';
import '../util.dart' as util;
import 'feasible_tree.dart';

void networkSimplex(Graph g) {
  g = util.simplify(g);
  longestPath(g);
  var t = feasibleTree(g);
  _initLowLimValues(t);
  _initCutValues(t, g);
  Edge? e;
  Edge f;
  while ((e = leaveEdge(t)) != null) {
    f = _enterEdge(t, g, e!);
    _exchangeEdges(t, g, e, f);
  }

  for (var v in g.nodes) {
    var np = g.node(v);
    var np2 = g.node(v);
    np2[rankK] = np[rankK];
  }
}

void _initCutValues(Graph t, Graph g) {
  List<String> vs = postorder(t, t.nodes);
  vs = List.from(vs.sublist(0, vs.length - 1));
  for (var v in vs) {
    _assignCutValue(t, g, v);
  }
}

void _assignCutValue(Graph t, Graph g, String child) {
  var childLab = t.node(child);
  var parent = childLab[parentK];
  t.edge(child, parent)[cutValueK] = _calcCutValue(t, g, child);
}

double _calcCutValue(Graph t, Graph g, String child) {
  Props childLab = t.node(child);
  String? parent = childLab[parentK];
  var childIsTail = true;
  Props? graphEdge = g.edgeNull(child, parent!);
  double cutValue = 0;
  if (graphEdge == null) {
    childIsTail = false;
    graphEdge = g.edge(parent, child);
  }
  cutValue = graphEdge[weightK];

  g.nodeEdges(child)?.forEach((e) {
    bool isOutEdge = e.v == child;
    String other = isOutEdge ? e.w : e.v;

    if (other != parent) {
      bool pointsToHead = isOutEdge == childIsTail;
      num otherWeight = g.edge2(e)[weightK];

      cutValue += pointsToHead ? otherWeight : -otherWeight;
      if (_isTreeEdge(t, child, other)) {
        var otherCutValue = t.edge(child, other).getD(cutValueK);
        cutValue += pointsToHead ? -otherCutValue : otherCutValue;
      }
    }
  });

  return cutValue;
}

void _initLowLimValues(Graph tree, [String? root]) {
  root ??= tree.nodes[0];
  _dfsAssignLowLim2(tree, {}, 1, root);
}

double _dfsAssignLowLim(Graph tree, Map<String, bool> visited, double nextLim, String v, [String? parent]) {
  double low = nextLim;
  Props label = tree.node(v);

  visited[v] = true;
  tree.neighbors(v)?.forEach((w) {
    if (!visited.containsKey(w)) {
      nextLim = _dfsAssignLowLim(tree, visited, nextLim, w, v);
    }
  });

  label[lowK] = low;
  label[limK] = nextLim++;
  if (parent != null) {
    label[parentK] = parent;
  } else {
    label.remove(parentK);
  }
  return nextLim;
}

void _dfsAssignLowLim2(Graph tree, Map<String, bool> visited, double nextLim, String v, [String? parent]) {
  List<dynamic> stack = [
    [
      nextLim,
      {valueK: nextLim},
      v,
      parent,
      false
    ]
  ];
  while (stack.isNotEmpty) {
    var current = stack.removeLast();
    if (current[4] == true) {
      var label = tree.node(current[2]);
      label[lowK] = current[0];
      // Vendored fix: lim must be the current counter value and the counter
      // must advance (dagre.js: `lim = nextLim++`). The original port read
      // `counter + 1` without ever incrementing, collapsing all low/lim
      // values and breaking the network-simplex enterEdge descendant test.
      label[limK] = current[1][valueK];
      current[1][valueK] = current[1][valueK] + 1;
      if (current[3] != null) {
        label[parentK] = current[3];
      } else {
        label.remove(parentK);
      }
    } else if (visited[current[2]] != true) {
      visited[current[2]] = true;
      stack.add([current[1][valueK], current[1], current[2], current[3], true]);
      tree.neighbors(current[2])?.eachRight((w, i) {
        if (visited[w] != true) {
          stack.add([current[1][valueK], current[1], w, current[2], false]);
        }
      });
    }
  }
}

Edge? leaveEdge(Graph tree) {
  return tree.edges.find((e) {
    var value = tree.edge2(e).getD(cutValueK);
    return value < 0;
  });
}

Edge _enterEdge(Graph t, Graph g, Edge edge) {
  var v = edge.v;
  var w = edge.w;

  if (!g.hasEdge2(v, w)) {
    v = edge.w;
    w = edge.v;
  }

  var vLabel = t.node(v);
  var wLabel = t.node(w);
  var tailLabel = vLabel;
  var flip = false;

  if (vLabel.getD(limK) > wLabel.getD(limK)) {
    tailLabel = wLabel;
    flip = true;
  }

  var candidates = g.edges.filter((edge) {
    return flip == _isDescendant(t, t.node(edge.v), tailLabel) && flip != _isDescendant(t, t.node(edge.w), tailLabel);
  });

  return candidates.reduce((acc, edge) {
    if (slack(g, edge) < slack(g, acc)) {
      return edge;
    }
    return acc;
  });
}

void _exchangeEdges(Graph t, Graph g, Edge e, Edge f) {
  var v = e.v;
  var w = e.w;
  t.removeEdge(v, w);
  t.setEdge2(f.v, f.w, value: Props());
  _initLowLimValues(t);
  _initCutValues(t, g);
  _updateRanks(t, g);
}

void _updateRanks(Graph t, Graph g) {
  String root = t.nodes.firstWhere((v) {
    var s = g.node(v).get2(parentK);
    return s == null;
  });

  List<String> vs = preorder(t, [root]);
  vs = List.from(vs.sublist(1));
  for (var v in vs) {
    var parent = t.node(v).getS(parentK);
    var edge = g.edgeNull(v, parent);
    var flipped = false;
    if (edge == null) {
      edge = g.edge(parent, v);
      flipped = true;
    }
    g.node(v)[rankK] = (g.node(parent).getD(rankK) + (flipped ? edge.getD(minLenK) : -edge.getD(minLenK)));
  }
}

bool _isTreeEdge(Graph tree, String u, String v) {
  return tree.hasEdge2(u, v);
}

bool _isDescendant(Graph tree, Props vLabel, Props rootLabel) {
  return rootLabel.getD(lowK) <= vLabel.getD(limK) && vLabel.getD(limK) <= rootLabel.getD(limK);
}

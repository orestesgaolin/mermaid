import 'package:elk_layout/src/dagre/src/model/props.dart';
import 'package:elk_layout/src/dagre/src/rank/util.dart';
import 'package:elk_layout/src/dagre/src/util/list_util.dart';
import '../graph/graph.dart';

Graph feasibleTree(Graph g) {
  var t = Graph(isDirected: false);
  var start = g.nodes[0];
  int size = g.nodeCount;
  t.setNode(start, Props());
  Edge edge;
  num delta;
  while (tightTree(t, g) < size) {
    edge = _findMinSlackEdge(t, g);
    delta = t.hasNode(edge.v) ? slack(g, edge) : -slack(g, edge);
    _shiftRanks(t, g, delta);
  }
  return t;
}

int tightTree(Graph t, Graph g) {
  // dfs(String v) {
  //   for (var e in (g.nodeEdges(v) ?? [])) {
  //     var edgeV = e.v;
  //     var w = (v == edgeV) ? e.w : edgeV;
  //     if (!t.hasNode(w)) {
  //       var vv = slack(g, e);
  //       if (vv.isNaN || vv.toInt() == 0) {
  //         t.setNode(w, Props());
  //         t.setEdge2(v, w, value: Props());
  //         dfs(w);
  //       }
  //     }
  //   }
  // }

  dfs(String v) {
    List<String> stack = [v];
    while (stack.isNotEmpty) {
      var curr = stack.removeLast();
      g.nodeEdges(curr)?.eachRight((e, i) {
        String edgeV = e.v, w = curr == edgeV ? e.w : edgeV;
        if (!t.hasNode(w)) {
          var vv = slack(g, e);
          if (vv.isNaN || vv.toInt() == 0) {
            t.setNode(w, Props());
            t.setEdge2(curr, w, value: Props());
            stack.add(w);
          }
        }
      });
    }
  }
  t.nodes.forEach(dfs);
  return t.nodeCount;
}

Edge _findMinSlackEdge(Graph t, Graph g) {
  var edges = g.edges;

  List<dynamic> acc = [double.infinity, null];
  for (var edge in edges) {
    double edgeSlack = double.infinity;
    if (t.hasNode(edge.v) != t.hasNode(edge.w)) {
      edgeSlack = slack(g, edge);
    }
    if (edgeSlack < acc[0]) {
      acc = [edgeSlack, edge];
      continue;
    }
  }
  return acc[1];
}

void _shiftRanks(Graph t, Graph g, num delta) {
  for (var v in t.nodes) {
    var rank = (g.node(v).getD2(rankK) ?? 0) + delta;
    g.node(v)[rankK] = rank;
  }
}

import 'package:mermaid_core/src/vendor/dagre/src/graph/graph.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/enums/acyclicer.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/util.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/list_util.dart';

import 'greedy_fas.dart';
import 'model/props.dart';

void run(Graph g) {
  double Function(Edge) weightFn(Graph g2) {
    return (e) {
      return g2.edge2(e).getD(weightK);
    };
  }

  List<Edge> fas = (g.label.acyclicer == Acyclicer.greedy ? greedyFAS(g, weightFn(g)) : dfsFAS(g));
  for (var e in fas) {
    var label = g.edge2(e);
    g.removeEdge2(e);
    label[forwardNameK] = e.id;
    label[reversedK] = true;
    g.setEdge2(e.w, e.v, value: label, name: uniqueId("rev"));
  }

}

List<Edge> dfsFAS(Graph g) {
  List<Edge> fas = [];
  Map<String, bool> stack = {};
  Map<String, bool> visited = {};

  // Vendored fix: the original port's iterative conversion of dagre.js
  // acyclic.js dfsFAS was broken: it tested `visited.containsKey(v)` (the
  // root argument) instead of the popped node, and it set `stack[v]` but
  // removed `stack[curr]` immediately after expanding a node, so the
  // "currently on the DFS path" set never contained any ancestors. As a
  // result no back edge was ever detected and cycles survived into ranking
  // (longestPath then crashed reading a rank that was never assigned).
  // dagre.js keeps a node in `stack` for the duration of its subtree and
  // records out-edges that point at an on-stack node as the feedback arc
  // set. Replicate that with explicit pre/post entries: on pre-visit mark
  // visited + on-stack and push a post-visit entry; on post-visit pop the
  // node from the path. Children are pushed right-to-left so they are
  // expanded in the same order dagre.js recurses.
  dfs(String v) {
    if (visited.containsKey(v)) {
      return;
    }
    List<List<dynamic>> s = [
      [v, false]
    ];
    while (s.isNotEmpty) {
      var curr = s.removeLast();
      String node = curr[0] as String;
      if (curr[1] == true) {
        stack.remove(node);
        continue;
      }
      if (visited.containsKey(node)) {
        continue;
      }
      visited[node] = true;
      stack[node] = true;
      s.add([node, true]);
      g.outEdges(node)?.eachRight((e, index) {
        if (stack.containsKey(e.w)) {
          fas.add(e);
        } else {
          s.add([e.w, false]);
        }
      });
    }
  }
  g.nodes.forEach(dfs);
  return fas;
}

void undo(Graph g) {
  for (var e in g.edges) {
    var label = g.edge2(e);
    if (label[reversedK] == true) {
      g.removeEdge2(e);
      var name = label.getS(forwardNameK);
      label.remove(reversedK);
      label.remove(forwardNameK);
      g.setEdge2(e.w, e.v, value: label, name: name);
    }
  }
}

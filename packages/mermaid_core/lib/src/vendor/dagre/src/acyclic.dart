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

  // dfs(v) {
  //   if (visited.containsKey(v)) {
  //     return;
  //   }
  //   visited[v] = true;
  //   stack[v] = true;
  //   g.outEdges(v)?.forEach((e) {
  //     if (stack.containsKey(e.w)) {
  //       fas.add(e);
  //     } else {
  //       dfs(e.w);
  //     }
  //   });
  //   stack.remove(v);
  // }

  dfs(String v) {
    List<String> s = [v];
    while (s.isNotEmpty) {
      var curr = s.removeLast();
      if (visited.containsKey(v)) {
        continue;
      }
      visited[curr] = true;
      stack[v] = true;
      g.outEdges(curr)?.eachRight((e, index) {
        if (stack[e.w] == true) {
          fas.add(e);
        } else {
          s.add(e.w);
        }
      });
      stack.remove(curr);
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

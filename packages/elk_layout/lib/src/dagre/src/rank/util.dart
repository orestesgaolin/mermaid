import 'package:elk_layout/src/dagre/src/model/props.dart';

import '../graph/graph.dart';
import '../util/list_util.dart';

Graph longestPath(Graph g) {
  Map<String, bool> visited = {};

  // double dfs(String v) {
  //   var label = g.node(v);
  //   if (visited.containsKey(v)) {
  //     return label.getD(rankK);
  //   }
  //   visited[v] = true;
  //
  //   var outEdgesMinLens = g.outEdges(v)!.map((e) {
  //     return dfs(e.w) - g.edge2(e).getD(minLenK);
  //   });
  //   double? rankValue = min(outEdgesMinLens)?.toDouble();
  //
  //   rankValue ??= double.infinity;
  //   if (rankValue.isInfinite || rankValue.isNaN) {
  //     rankValue = 0;
  //   }
  //   label[rankK] = rankValue;
  //   return rankValue;
  // }

  dfs2(String v) {
    List<dynamic> stack = [
      [v, false]
    ];
    while (stack.isNotEmpty) {
      var cur = stack.removeLast();
      if (cur[1] == true) {
        var outEdgesMinLens = g.outEdges(cur[0])!.map((e) {
          return g.node(e.w).getD(rankK) - g.edge2(e).getD(minLenK);
        });
        double? rankValue = min(outEdgesMinLens)?.toDouble();
        if (rankValue == null || rankValue.isInfinite || rankValue.isNaN) {
          rankValue = 0;
        }
        g.node(cur[0])[rankK] = rankValue;
      } else if (visited[cur[0]] != true) {
        visited[cur[0]] = true;
        stack.add([cur[0], true]);
        g.outEdges(cur[0])?.eachRight((e, i) {
          stack.add([e.w, false]);
        });
      }
    }
  }

  for (var s in g.sources) {
    dfs2(s);
  }

  return g;
}

double slack(Graph g, Edge e) {
  var r1 = g.node(e.w).getD(rankK);
  var r2 = g.node(e.v).getD(rankK);
  return r1 - r2 - g.edge2(e).getD(minLenK);
}

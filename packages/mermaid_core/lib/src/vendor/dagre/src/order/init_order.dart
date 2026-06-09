import 'package:mermaid_core/src/vendor/dagre/src/model/props.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/list_util.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/util.dart';
import '../graph/graph.dart';

List<List<String>> initOrder(Graph g) {
  Map<String, bool> visited = {};
  var simpleNodes = g.nodes.filter((v) {
    var list=g.children(v);
    return list==null||list.isEmpty;
  });
  var maxRank = max<int>(simpleNodes.map2((v,i) {
    return g.node(v).getI(rankK);
  }))!;

  List<List<String>> layers = List.from(range(0, maxRank + 1).map<List<String>>((e) {
    return [];
  }));

  // void dfs(String v) {
  //   if (visited.containsKey(v)) return;
  //   visited[v] = true;
  //   Props node = g.node(v);
  //   layers[node.getI(rankK)].add(v);
  //   g.successors(v)?.forEach(dfs);
  // }

  dfs(v) {
    var stack = [v];
    while (stack.isNotEmpty) {
      var curr = stack.removeLast();
      if (visited[curr] != true) {
        visited[curr] = true;
        var node = g.node(curr);
        layers[node.getI(rankK)].add(curr);
        g.successors(curr)?.eachRight((w, i) {
          stack.add(w);
        });
      }
    }
  }

  var orderedVs =simpleNodes;
  orderedVs.sort((a, b) {
    return g.node(a).getD(rankK).compareTo(g.node(b).getD(rankK));
  });
  orderedVs.forEach(dfs);
  return layers;
}

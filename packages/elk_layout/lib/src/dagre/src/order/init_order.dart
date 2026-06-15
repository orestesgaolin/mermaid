import 'package:elk_layout/src/dagre/src/model/props.dart';
import 'package:elk_layout/src/dagre/src/util/list_util.dart';
import 'package:elk_layout/src/dagre/src/util/util.dart';
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

  // elk_layout extension: when the graph asks for model order, the initial
  // layering follows the nodes' declaration order rather than edge-traversal
  // order, so siblings keep their input left-to-right order. A node without a
  // model-order index (dummies, borders) sorts last/stably.
  final useModelOrder = g.label[useModelOrderK] == true;
  double modelOrderKey(String v) => g.node(v).getD2(modelOrderK) ?? 1e30;

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
        var succ = g.successors(curr);
        if (succ != null && useModelOrder) {
          succ = List<String>.from(succ)
            ..sort((a, b) => modelOrderKey(a).compareTo(modelOrderKey(b)));
        }
        // Push in reverse so successors pop (and visit) in ascending order.
        succ?.eachRight((w, i) {
          stack.add(w);
        });
      }
    }
  }

  var orderedVs =simpleNodes;
  orderedVs.sort((a, b) {
    final byRank = g.node(a).getD(rankK).compareTo(g.node(b).getD(rankK));
    if (byRank != 0 || !useModelOrder) return byRank;
    return modelOrderKey(a).compareTo(modelOrderKey(b));
  });
  orderedVs.forEach(dfs);
  return layers;
}

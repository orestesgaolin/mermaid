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
  // Same comparisons as reading the labels in the comparator, read once.
  final rankOf = {for (var v in orderedVs) v: g.node(v).getD(rankK)};
  // Vendored fix: lodash sortBy in dagre.js is stable, so nodes of one rank
  // keep graph order. List.sort is not stable for longer lists, which
  // changed the initial order of clusters and disconnected components.
  final graphPos = {for (var i = 0; i < orderedVs.length; i++) orderedVs[i]: i};
  orderedVs.sort((a, b) {
    final byRank = rankOf[a]!.compareTo(rankOf[b]!);
    return byRank != 0 ? byRank : graphPos[a]! - graphPos[b]!;
  });
  orderedVs.forEach(dfs);
  return layers;
}

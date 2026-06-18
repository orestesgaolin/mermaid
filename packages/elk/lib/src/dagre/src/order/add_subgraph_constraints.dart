import '../graph/graph.dart';

void addSubgraphConstraints(Graph g, Graph cg, List<String> vs) {
  Map<String, String> prev = {};
  String? rootPrev;
  for (var v in vs) {
    String? child = g.parent(v);
    String? parent, prevChild;
    while (child != null) {
      parent = g.parent(child);
      if (parent != null) {
        prevChild = prev[parent];
        prev[parent] = child;
      } else {
        prevChild = rootPrev;
        rootPrev = child;
      }
      if (prevChild != null && prevChild != child) {
        cg.setEdge2(prevChild, child);
        break;
      }
      child = parent;
    }
  }
}

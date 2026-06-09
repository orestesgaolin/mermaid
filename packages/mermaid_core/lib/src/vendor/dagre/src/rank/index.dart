import 'package:mermaid_core/src/vendor/dagre/src/rank/util.dart' as ru;
import '../graph/graph.dart';
import '../model/enums/ranker.dart';
import 'feasible_tree.dart' as ft;
import 'network_simplex.dart';

void rankFun(Graph g) {
  Ranker ranker = g.label.ranker;
  if (ranker == Ranker.tightTree) {
    _tightTreeRanker(g);
    return;
  }
  if (ranker == Ranker.longestPath) {
    ru.longestPath(g);
    return;
  }
  _networkSimplexRanker(g);
}

void _tightTreeRanker(Graph g) {
  ru.longestPath(g);
  ft.feasibleTree(g);
}

void _networkSimplexRanker(Graph g) {
  networkSimplex(g);
}

import 'package:mermaid_core/src/vendor/dagre/src/model/graph_label.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/props.dart';
import '../graph/graph.dart';
import '../model/enums/relationship.dart';
import '../util/util.dart';

Graph buildLayerGraph(Graph g, int rank, Relationship ship) {
  String root = _createRootNode(g);
  Graph result = Graph(isCompound: true);
  GraphLabel gp = GraphLabel();
  gp[rootK] = root;
  result.label = gp;
  result.setDefaultNodePropsFun((v) {
    return g.nodeNull(v);
  });

  for (var v in g.nodes) {
    Props node = g.node(v);
    String? parent = g.parent(v);
    if (node.getI2(rankK) == rank ||
        (node.getD2(minRankK) ?? double.nan) <= rank && rank <= (node.getD2(maxRankK) ?? double.nan)) {
      result.setNode(v);
      result.setParent(v, parent ?? root);
      List<Edge> tmpList = (ship == Relationship.inEdges ? g.inEdges(v) : g.outEdges(v)) ?? [];

      for (var e in tmpList) {
        String u = e.v == v ? e.w : e.v;
        Props? edge = result.edgeNull(u, v);
        num weight = edge?.getD2(weightK) ?? 0;

        Props ep = Props();
        ep[weightK] = (g.edge2(e)).getD(weightK) + weight;
        result.setEdge2(u, v, value: ep);
      }
      if (node.hasOwn(minRankK)) {
        Props ps = Props();
        ps[borderLeftK] = [node.get<List<dynamic>>(borderLeftK)[rank]];
        ps[borderRightK] = [node.get<List<dynamic>>(borderRightK)[rank]];
        result.setNode(v, ps);
      }
    }
  }
  return result;
}

String _createRootNode(Graph g) {
  String v = uniqueId('_root');
  while (g.hasNode(v)) {
    v = uniqueId('_root');
  }
  return v;
}

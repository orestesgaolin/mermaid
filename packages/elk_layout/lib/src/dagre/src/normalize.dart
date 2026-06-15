import 'package:elk_layout/src/dagre/src/graph/graph.dart';
import 'package:elk_layout/src/dagre/src/model/enums/dummy.dart';
import 'package:elk_layout/src/dagre/src/model/props.dart';
import 'package:elk_layout/src/dagre/src/util.dart' as util;
import 'model/graph_point.dart';

void run(Graph g) {
  g.label[dummyChainsK] = <String>[];
  for (var edge in g.edges) {
    _normalizeEdge(g, edge);
  }
}

void _normalizeEdge(Graph g, Edge e) {
  var v = e.v;
  int vRank = g.node(v).getI(rankK);
  var w = e.w;
  int wRank = g.node(w).getI(rankK);
  var name = e.id;
  var edgeLabel = g.edge2(e);
  var labelRank = edgeLabel.getI2(labelRankK);
  if (wRank == vRank + 1) return;
  g.removeEdge2(e);

  // elk_layout extension: propagate the target node's model (declaration)
  // order onto the edge's dummy chain, so init_order can keep siblings in
  // model order even though the real successor sits behind label-rank dummies.
  final wModelOrder = g.node(w).getD2(modelOrderK);

  String dummy;
  Props attrs;
  int i = 0;
  for (++vRank; vRank < wRank; ++i, ++vRank) {
    edgeLabel[pointsK] = <GraphPoint>[];
    attrs = {widthK: 0, heightK: 0, edgeLabelK: edgeLabel, edgeObjK: e, rankK: vRank}.toProps;
    if (wModelOrder != null) attrs[modelOrderK] = wModelOrder;
    dummy = util.addDummyNode(g, Dummy.edge, attrs, "_d");
    if (vRank == labelRank) {
      attrs['width'] = edgeLabel.getD('width');
      attrs['height'] = edgeLabel.getD('height');
      // Vendored fix: dagre.js assigns the constant "edge-label" here; the
      // original port incorrectly read (the nonexistent) edgeLabel.dummy.
      attrs[dummyK] = Dummy.edgeLabel;
      attrs[labelPosK] = edgeLabel.get2(labelPosK);
    }
    g.setEdge2(v, dummy, name: name, value: {weightK: edgeLabel[weightK]}.toProps);
    if (i == 0) {
      g.label.getL<String>(dummyChainsK).add(dummy);
    }
    v = dummy;
  }
  g.setEdge2(v, w, name: name, value: {weightK: edgeLabel[weightK]}.toProps);
}

void undo(Graph g) {
  for (var v in g.label.getL<String>(dummyChainsK)) {
    Props? node = g.node(v);
    Props origLabel = node.get(edgeLabelK);
    g.setEdge(node.get(edgeObjK), origLabel);
    while (node != null && node[dummyK] != null) {
      var w = g.successors(v)![0];
      g.removeNode(v);
      origLabel.getL<GraphPoint>(pointsK).add(GraphPoint(node.getD(xK), node.getD(yK)));
      if (node[dummyK] == Dummy.edgeLabel) {
        origLabel[xK] = node[xK];
        origLabel[yK] = node[yK];
        origLabel[widthK] = node[widthK];
        origLabel[heightK] = node[heightK];
      }
      v = w;
      node = g.node(v);
    }
  }
}

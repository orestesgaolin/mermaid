import 'package:mermaid_core/src/vendor/dagre/src/graph/graph.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/enums/rank_dir.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/graph_point.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/props.dart';

void adjust(Graph g) {
  var rankDir = g.label2?.rankDir;
  if (rankDir ==RankDir.ltr || rankDir ==RankDir.rtl) {
    _swapWidthHeight(g);
  }
}

void undo(Graph g) {
  var rankDir = g.label2?.rankDir;
  if (rankDir == RankDir.btt || rankDir ==RankDir.rtl) {
    _reverseY(g);
  }

  if (rankDir ==RankDir.ltr || rankDir ==RankDir.rtl) {
    _swapXY(g);
    _swapWidthHeight(g);
  }
}

void _swapWidthHeight(Graph g) {
  for (var v in g.nodesIterable) {
    _swapWidthHeightOne(g.node(v));
  }
  for (var e in g.edgesIterable) {
    _swapWidthHeightOne(g.edge2(e));
  }
}

void _swapWidthHeightOne(Props attrs) {
  // Vendored fix: tolerate nodes without width/height (e.g. compound border
  // dummies); dagre.js swaps `undefined` without error.
  var w = attrs.getD2(widthK);
  attrs[widthK] = attrs.getD2(heightK);
  attrs[heightK] = w;
}

void _reverseY(Graph g) {
  for (var v in g.nodesIterable) {
    Props np = g.node(v);
    np[yK] = -np.getD(yK);
  }
  for (var e in g.edgesIterable) {
    var edge = g.edge2(e);
    for (var p in edge.get<List<GraphPoint>>(pointsK)) {
      p.y=-p.y;
    }
    var vv=edge.getD2(yK);
    if(vv!=null&&vv!=0){
      edge[yK] = -vv;
    }
  }
}

void _swapXY(Graph g) {
  for (var v in g.nodesIterable) {
    _swapXYOne(g.node(v));
  }

  for (var e in g.edgesIterable) {
    var edge = g.edge2(e);
    // Vendored fix: keep the points list typed as List<GraphPoint>.
    edge[pointsK]=List<GraphPoint>.from(edge.get<List<GraphPoint>>(pointsK).map((e) => GraphPoint(e.y, e.x)));
    var vv=edge.getD2(xK);
    if(vv!=null&&vv!=0){
      edge[xK] = edge[yK];
      edge[yK]=vv;
    }
  }
}

void _swapXYOne(Props attrs) {
  var vv = attrs[xK];
  attrs[xK] = attrs[yK];
  attrs[yK] = vv;
}

import 'package:elk/src/dagre/src/model/props.dart';
import '../graph/graph.dart';
import '../util.dart' as util;
import '../util/list_util.dart';
import 'bk.dart';

void position(Graph g2) {
  Graph g = util.asNonCompoundGraph(g2);
  positionY(g);
  Map<String,double> list = positionX(g);
  for(var item in list.entries){
    var x=item.key;
    var v=item.value;
    g.node(x)[xK] = v;
  }
}

void positionY(Graph g) {
  List<List<String>> layering = util.buildLayerMatrix(g);
  var rankSep = g.label.rankSep;
  num prevY = 0;
  for (var layer in layering) {
    var maxHeight = max<num>(List.from(layer.map((v) {
          return g.node(v).getD(heightK);
        }))) ??
        0;

    for (var v in layer) {
      g.node(v)[yK] = prevY + maxHeight / 2;
    }
    prevY += maxHeight + rankSep;
  }
}

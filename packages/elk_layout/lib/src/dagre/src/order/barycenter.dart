import 'package:elk/src/dagre/src/model/props.dart';

import '../graph/graph.dart';
import '../model/tmp/order_inner_result.dart';

List<OrderInnerResult> barycenter(Graph g, List<String> movable) {
return List.from(movable.map((v) {
    List<Edge> inV = g.inEdges(v)??[];
    if (inV.isEmpty) {
      return OrderInnerResult(v);
    }

      Map<String, num> acc = {'sum': 0, 'weight': 0};
      for (int i = 0; i < inV.length; i++) {
        var tt = inV[i];
        Props edge = g.edge(tt.v, tt.w, tt.id);
        Props nodeU = g.node(inV[i].v);
        num sum = acc['sum']! + (edge.getD(weightK) * nodeU.getD(orderK));
        num weight = acc['weight']! + edge.getD(weightK);
        acc = {'sum': sum, 'weight': weight};
      }

      OrderInnerResult p = OrderInnerResult(v);
      p.barycenter = acc['sum']! / acc['weight']!;
      p.weight = acc['weight']!;
      return p;
  }));
}

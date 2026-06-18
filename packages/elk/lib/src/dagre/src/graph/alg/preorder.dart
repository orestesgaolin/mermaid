import 'package:elk/src/dagre/src/model/enums/dfs_order.dart';

import 'dfs.dart';
import '../graph.dart';

List<String> preorder(Graph g, List<String> vs) {
  return dfs(g, vs, DFSOrder.pre);
}

import '../../model/enums/dfs_order.dart';
import '../graph.dart';
import 'dfs.dart';

List<String> postorder(Graph g,List<String> vs) {
  return dfs(g, vs, DFSOrder.post);
}

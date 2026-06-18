import '../../model/enums/dfs_order.dart';
import '../graph.dart';

// List<String> dfs(Graph g, List<String> vs,DFSOrder order) {
//   var navigation = (g.isDirected ? g.successors : g.neighbors);
//
//   ///nodeId
//   List<String> acc = [];
//
//   ///存储已遍历过的nodeId
//   Map<String, bool> visited = {};
//
//   for (var v in vs) {
//     if (!g.hasNode(v)) {
//       throw StateError("Graph does not have node: $v");
//     }
//     _doDfs(g, v, order ==DFSOrder.post, visited, navigation, acc);
//   }
//   return acc;
// }
//
// void _doDfs(Graph g, String v, bool postorder, Map<String, bool> visited, navigation, List<String> acc) {
//   if (!visited.containsKey(v)) {
//     visited[v] = true;
//     if (!postorder) {
//       acc.add(v);
//     }
//     navigation(v).forEach((w) {
//       _doDfs(g, w, postorder, visited, navigation, acc);
//     });
//     if (postorder) {
//       acc.add(v);
//     }
//   }
// }

List<String> dfs(Graph g, List<String> vs, DFSOrder order) {
  var navigation = g.isDirected ? (String v) => g.successors(v) : (String v) => g.neighbors(v);
  var orderFunc = order == DFSOrder.post ? _postOrderDfs : _preOrderDfs;
  List<String> acc = [];
  Map<String, bool> visited = {};
  for (var v in vs) {
    if (!g.hasNode(v)) {
      throw UnsupportedError("Graph does not have node: $v");
    }
    orderFunc(v, navigation, visited, acc);
  }
  return acc;
}

void _postOrderDfs(String v, List<String>? Function(String) navigation, Map<String, bool> visited, List<String> acc) {
  List<dynamic> stack = [
    [v, false]
  ];
  while (stack.isNotEmpty) {
    var curr = stack.removeLast();
    if (curr[1]) {
      acc.add(curr[0]);
    } else {
      if (visited[curr[0]] != true) {
        visited[curr[0]] = true;
        stack.add([curr[0], true]);
        _forEachRight(navigation(curr[0]), (w) {
          stack.add([w, false]);
        });
      }
    }
  }
}

void _preOrderDfs(String v, List<String>? Function(String) navigation, Map<String, bool> visited, List<String> acc) {
  var stack = [v];
  while (stack.isNotEmpty) {
    var curr = stack.removeLast();
    // Vendored fix: the original port checked `visited[curr[0]]` (the first
    // character of the node id), causing an infinite loop for ids longer
    // than one character.
    if (visited[curr] != true) {
      visited[curr] = true;
      acc.add(curr);
      _forEachRight(navigation(curr), (w) => stack.add(w));
    }
  }
}

List<String>? _forEachRight(List<String>? array, void Function(String) fun) {
  if (array == null) {
    return array;
  }
  var length = array.length - 1;
  for (int i = length; i >= 0; i--) {
    fun(array[i]);
  }
  return array;
}

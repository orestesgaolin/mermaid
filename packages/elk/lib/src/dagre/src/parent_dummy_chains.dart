import 'dart:math' as math;

import 'package:elk/src/dagre/src/graph/graph.dart';
import 'package:elk/src/dagre/src/model/props.dart';
import 'package:elk/src/dagre/src/util/list_util.dart';

void parentDummyChains(Graph g) {
  Map<String, _InnerResult2> postorderNums = _postorder(g);
  for (var v in g.label.getL<String>(dummyChainsK)) {
    var node = g.node(v);
    var edgeObj = node.get<Edge>(edgeObjK);
    _InnerResult pathData = _findPath(g, postorderNums, edgeObj.v, edgeObj.w);
    var path = pathData.path;
    var lca = pathData.lca;
    var pathIdx = 0;
    var pathV = path[pathIdx];
    var ascending = true;

    while (v != edgeObj.w) {
      node = g.node(v);

      if (ascending) {
        while ((pathV = path[pathIdx]) != lca && g.node(pathV!).getD(maxRankK) < node.getD(rankK)) {
          pathIdx++;
        }

        if (pathV == lca) {
          ascending = false;
        }
      }

      if (!ascending) {
        while (pathIdx < path.length - 1 && g.node((pathV = path[pathIdx + 1])!).getD(minRankK) <= node.getD(rankK)) {
          pathIdx++;
        }
        pathV = path[pathIdx];
      }

      g.setParent(v, pathV);
      v = g.successors(v)![0];
    }
  }
}

// Find a path from v to w through the lowest common ancestor (LCA). Return the
// full path and the LCA.
_InnerResult _findPath(Graph g, Map<String, _InnerResult2> postorderNums, String v, String w) {
  List<String?> vPath = [];
  List<String> wPath = [];
  var low = math.min(postorderNums[v]!.low, postorderNums[w]!.low);
  var lim = math.max(postorderNums[v]!.lim, postorderNums[w]!.lim);
  String? parent;
  String? lca;

  // Traverse up from v to find the LCA
  parent = v;
  do {
    parent = g.parent(parent!);
    vPath.add(parent);
  } while (parent != null && (postorderNums[parent]!.low > low || lim > postorderNums[parent]!.lim));
  lca = parent;

  // Traverse from w to LCA
  parent = w;
  while ((parent = g.parent(parent!)) != lca) {
    wPath.add(parent!);
  }

  _InnerResult result = _InnerResult();
  result.path = vPath.concat(wPath.reversed);
  result.lca = lca;
  return result;
}

Map<String, _InnerResult2> _postorder(Graph g) {
  Map<String, _InnerResult2> result = {};
  var lim = 0;
 void dfs(String v) {
    var low = lim;
    g.children(v)?.forEach(dfs);
    _InnerResult2 result2 = _InnerResult2();
    result2.low = low;
    result2.lim = lim++;
    result[v] = result2;
  }

  g.children()?.forEach(dfs);
  return result;
}

class _InnerResult {
  List<String?> path = [];
  String? lca;
}

class _InnerResult2 {
  late int low;
  late int lim;
}

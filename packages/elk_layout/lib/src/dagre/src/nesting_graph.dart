import 'package:elk_layout/src/dagre/src/graph/graph.dart';
import 'package:elk_layout/src/dagre/src/model/enums/dummy.dart';
import 'package:elk_layout/src/dagre/src/model/props.dart';
import 'package:elk_layout/src/dagre/src/util.dart' as util;
import 'package:elk_layout/src/dagre/src/util/list_util.dart';


void run(Graph g) {
  var root = util.addDummyNode(g, Dummy.root, Props(), "_root");
  Map<String, int> depths = _treeDepths(g);
  double height = max(depths.values)! - 1;
  double nodeSep = 2 * height + 1;
  g.label[nestingRootK] = root;

  for (var e in g.edgesIterable) {
    var p = g.edge2(e);
    p[minLenK] = p.getD(minLenK) * nodeSep;
  }
  double weight = _sumWeights(g) + 1;
  g.children()?.forEach((child) {
    _dfs(g, root, nodeSep, weight, height, depths, child);
  });

  g.label[nodeRankFactorK] = nodeSep;
}

void _dfs(Graph g, String root, double nodeSep, double weight, double height, Map<String, int> depths, String v) {
  var children = g.children(v);
  if (children == null || children.isEmpty) {
    if (v != root) {
      g.setEdge2(root, v, value: {"weight": 0, "minLen": nodeSep}.toProps);
    }
    return;
  }

  var top = util.addBorderNode(g, "_bt");
  var bottom = util.addBorderNode(g, "_bb");
  var label = g.node(v);

  g.setParent(top, v);
  label[borderTopK] = top;
  g.setParent(bottom, v);
  label[borderBottomK] = bottom;

  for (var child in children) {
    _dfs(g, root, nodeSep, weight, height, depths, child);
    var childNode = g.node(child);
    String childTop = childNode[borderTopK] ?? child;
    String childBottom = childNode[borderBottomK] ?? child;
    var thisWeight = childNode[borderTopK] != null ? weight : 2 * weight;
    double minlen = childTop != childBottom ? 1 : (height - depths[v]! + 1);
    g.setEdge2(top, childTop, value: ({weightK: thisWeight, minLenK: minlen, nestingEdgeK: true}.toProps));
    g.setEdge2(
      childBottom,
      bottom,
      value: {weightK: thisWeight, minLenK: minlen, nestingEdgeK: true}.toProps,
    );
  }

  if (g.parent(v) == null) {
    g.setEdge2(root, top, value: {weightK: 0, minLenK: height + depths[v]!}.toProps);
  }
}

Map<String, int> _treeDepths(Graph g) {
  Map<String, int> depths = {};
  List<String>? children=g.children();
  int depth=1;
  while (children != null && children.isNotEmpty) {
    List<String> next=[];
    for(var item in children){
      depths[item]=depth;
      List<String>? tmp = g.children(item);
      if (tmp != null) {
        next.addAll(tmp);
      }
    }
    children=next;
    depth+=1;
  }
  return depths;
}

num _sumWeights(Graph g) {
  return g.edges.reduce2<num>((acc, e) {
    return e + (g.edge2(acc).getD(weightK));
  }, 0);
}

void cleanup(Graph g) {
  var graphLabel = g.label;
  g.removeNode(graphLabel.getS(nestingRootK));
  graphLabel.remove(nestingRootK);

  for (var e in g.edges) {
    var edge = g.edge2(e);
    if (edge.get2(nestingEdgeK) == true) {
      g.removeEdge2(e);
    }
  }
}

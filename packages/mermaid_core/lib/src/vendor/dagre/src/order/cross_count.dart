
import 'package:mermaid_core/src/vendor/dagre/src/model/props.dart';

import '../graph/graph.dart';

int crossCount(Graph g, List<List<String>> layering) {
  int cc = 0;
  for (var i = 1; i < layering.length; ++i) {
    cc += _twoLayerCrossCount(g, layering[i - 1], layering[i]);
  }
  return cc;
}

int _twoLayerCrossCount(Graph g, List<String> northLayer, List<String> southLayer) {
  Map<String, int> southPos = {};
  for (int i = 0; i < southLayer.length; i++) {
    southPos[southLayer[i]] = i;
  }
  List<_InnerResult> southEntries = [];
  for (var ele in northLayer) {
    List<_InnerResult> v = List.from((g.outEdges(ele)??[]).map((e) {
      int pos = southPos[e.w]!;
      num weight = g.edge2(e)[weightK];
      return _InnerResult(pos, weight);
    }));
    southEntries.addAll(v);
  }
  southEntries.sort((a, b) {
    return a.pos.compareTo(b.pos);
  });

  // Build the accumulator tree
  int firstIndex = 1;
  while (firstIndex < southLayer.length) {
    firstIndex <<= 1;
  }
  var treeSize = 2 * firstIndex - 1;
  firstIndex -= 1;
  List<num> tree = List.filled(treeSize, 0);

  // Calculate the weighted crossings
  int cc = 0;
  for (var entry in southEntries) {
    int index = (entry.pos + firstIndex);
    tree[index] += entry.weight;
    num weightSum = 0;
    while (index > 0) {
      if ((index % 2) != 0) {
        weightSum += tree[index + 1];
      }
      index = (index - 1) >> 1;
      tree[index] += entry.weight;
    }
    cc += (entry.weight * weightSum).toInt();
  }
  return cc;
}

class _InnerResult {
  int pos;
  num weight;

  _InnerResult(this.pos, this.weight);
}

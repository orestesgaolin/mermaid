import 'dart:math' as math;

import 'package:mermaid_core/src/vendor/dagre/src/graph/graph.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/array.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/graph_point.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/graph_rect.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/props.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/list_util.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/util.dart';

import 'model/tmp/split.dart' as sp;
import 'model/enums/dummy.dart';

String addDummyNode(Graph g, Dummy type, Props attrs, String? name) {
  String v;
  do {
    v = uniqueId(name ?? '');
  } while (g.hasNode(v));
  attrs[dummyK] = type;
  g.setNode(v, attrs);
  return v;
}

Graph simplify(Graph g) {
  var simplified = Graph()..label = g.label;
  for (var v in g.nodes) {
    simplified.setNode(v,g.node(v));
  }

  for (var e in g.edges) {
    var simpleLabel = simplified.edgeNull(e.v, e.w) ?? {weightK: 0, minLenK: 1}.toProps;
    var label = g.edge2(e);

    var p = {
      weightK: simpleLabel.getD(weightK) + label.getD(weightK),
      minLenK: math.max(
        simpleLabel.getD(minLenK),
        label.getD(minLenK))
    };
    simplified.setEdge2(e.v, e.w, value: p.toProps);
  }
  return simplified;
}

Graph asNonCompoundGraph(Graph g) {
  var simplified = Graph(isMultiGraph: g.isMultiGraph);
  simplified.label = g.label;
  for (var v in g.nodes) {
    var children=g.children(v);
    if (children == null || children.isEmpty) {
      simplified.setNode(v, g.node(v));
    }
  }
  for (var e in g.edges) {
    simplified.setEdge(e, g.edge2(e));
  }
  return simplified;
}

Map<String, Map<String, double>> successorWeights(Graph g) {
  var weightMap = g.nodes.map((v) {
    Map<String, double> sucs = {};
    g.outEdges(v)?.forEach((e) {
      var v = sucs[e.w] ?? 0;
      sucs[e.w] = v + g.edge2(e).getD(weightK);
    });
    return sucs;
  }).toList();
  return zipObject(g.nodes, weightMap);
}

Map<String, Map<String, double>> predecessorWeights(Graph g) {
  var weightMap = g.nodes.map((v) {
    Map<String, double> preds = {};
    g.inEdges(v)?.forEach((e) {
      var v = preds[e.v] ?? 0;
      preds[e.v] = v + g.edge2(e).getD(weightK);
    });
    return preds;
  }).toList();
  return zipObject(g.nodes, weightMap);
}

GraphPoint intersectRect(GraphRect rect, GraphPoint point) {
  var x = rect.x;
  var y = rect.y;
  var dx = point.x - x;
  var dy = point.y - y;
  var w = rect.width / 2;
  var h = rect.height / 2;

  if (dx==0 && dy==0) {
    throw StateError("Not possible to find intersection inside of the rectangle");
  }

  double sx, sy;
  if (dy.abs() * w > dx.abs() * h) {
    if (dy < 0) {
      h = -h;
    }
    sx = h * dx / dy;
    sy = h;
  } else {
    if (dx < 0) {
      w = -w;
    }
    sx = w;
    sy = w * dy / dx;
  }
  return GraphPoint(x + sx, y + sy);
}

List<List<String>> buildLayerMatrix(Graph g) {
  List<Array<String>> layering = [];
  int v =maxRank(g)! +1;
  for (int i = 0; i < v; i++) {
    layering.add(Array());
  }
  for (var v in g.nodes) {
    var node = g.node(v);
    int? rank = node.getI2(rankK);
    if (rank != null) {
      layering[rank][node.getI(orderK)] = v;
    }
  }
  List<List<String>> rl = [];
  for (var element in layering) {
    rl.add(element.toList());
  }
  return rl;
}

void normalizeRanks(Graph g) {
  var nodeRanks = g.nodes.map((v) {
    var rank = g.node(v).getD2(rankK);
    if (rank == null) {
      return double.maxFinite;
    }
    return rank;
  }).toList();

  var minV = min(nodeRanks)!;
  for (var v in g.nodesIterable) {
    var node = g.node(v);
    if (node.hasOwn(rankK)) {
      node[rankK] = node.getD(rankK) - minV;
    }
  }
}

void removeEmptyRanks(Graph g) {
  // Vendored fix: compound (cluster) parent nodes never receive a rank.
  // dagre.js silently skips them here (lodash/JS NaN semantics); the
  // original Dart port crashed on the null rank instead.
  List<int> rankList = [
    for (var v in g.nodes)
      if (g.node(v).getI2(rankK) != null) g.node(v).getI(rankK)
  ];
  int offset = (min(rankList) ?? 0).toInt();
  Array<List<String>> layers = Array();
  for (var v in g.nodes) {
    var rankValue = g.node(v).getI2(rankK);
    if (rankValue == null) {
      continue;
    }
    var rank = rankValue - offset;
    if (!layers.has(rank)) {
      layers[rank] = [];
    }
    layers[rank]!.add(v);
  }

  var delta = 0;
  var nodeRankFactor = g.label.getD(nodeRankFactorK);

  layers.forEach((vs, i) {
    if ((vs == null||vs.isEmpty) && i % nodeRankFactor != 0) {
      --delta;
    } else if ((vs!=null&&vs.isNotEmpty)&&delta != 0) {
      for (var v in vs) {
        var p = g.node(v);
        p[rankK] = p.getD(rankK) + delta;
      }
    }
  });
}

String addBorderNode(Graph g, [String? prefix, int? rank, int? order]) {
  var np = {widthK: 0, heightK: 0}.toProps;
  if (rank != null) {
    np[rankK] = rank;
  }
  if (order != null) {
    np[orderK] = order;
  }
  return addDummyNode(g, Dummy.border, np, prefix);
}

int? maxRank(Graph g) {
  return max(g.nodes.map2((v, i) {
    var r = g.node(v).getD2(rankK);
    r ??= double.minPositive;
    return r;
  }))?.toInt();
}

sp.Split<T> partition<T>(List<T> collection, bool Function(T) fn) {
  sp.Split<T> split = sp.Split();
  for (var value in collection) {
    if (fn(value)) {
      split.lhs.add(value);
    } else {
      split.rhs.add(value);
    }
  }
  return split;
}

Map<String, Map<String, double>> zipObject(List<String> props, List<Map<String, double>> values) {
  Map<String, Map<String, double>> result = {};
  int i = 0;
  for (var item in props) {
    result[item] = values[i];
    i++;
  }
  return result;
}


void printGraph(Graph g) {
  for (var v in g.nodes) {
    print("Node $v: ${g.node(v)}");
  }
  for (var e in g.edges) {
    print("Edge ${e.v}->${e.w}: ${g.edge2(e)}");
  }
}
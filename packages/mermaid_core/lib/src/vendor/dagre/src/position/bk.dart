import 'dart:math' as math;
import 'package:mermaid_core/src/vendor/dagre/src/model/enums/align.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/enums/dummy.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/enums/label_pos.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/list_util.dart';

import '../graph/graph.dart';
import '../model/props.dart';
import '../util/util.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util.dart' as util;

Map<String, Map<String, bool>> _findType1Conflicts(Graph g, List<List<String>> layering) {
  Map<String, Map<String, bool>> conflicts = {};
  visitLayer(prevLayer, List<String> layer) {
    int k0 = 0;
    int scanPos = 0;
    int prevLayerLength = prevLayer.length;
    var lastNode = layer.last;
    layer.each((v, i) {
      String? w = _findOtherInnerSegmentNode(g, v);
      int k1 = w != null ? g.node(w).getI(orderK) : prevLayerLength;
      if (w != null || v == lastNode) {
        layer.sublist(scanPos, i + 1).forEach((scanNode) {
          g.predecessors(scanNode)?.forEach((u) {
            var uLabel = g.node(u);
            var uPos = uLabel.getD(orderK);
            if ((uPos < k0 || k1 < uPos) && uLabel.get(dummyK) != null && g.node(scanNode).get(dummyK) != null) {
              _addConflict(conflicts, u, scanNode);
            }
          });
        });
        scanPos = i + 1;
        k0 = k1;
      }
    });
    return layer;
  }

  if (layering.isNotEmpty) {
    layering.reduce(visitLayer);
  }
  return conflicts;
}

Map<String, Map<String, bool>> _findType2Conflicts(Graph g, List<List<String>> layering) {
  Map<String, Map<String, bool>> conflicts = {};
  scan(List<String> south, int southPos, int southEnd, num prevNorthBorder, num nextNorthBorder) {
    String v;
    range(southPos, southEnd).forEach((i) {
      v = south[i];
      if (g.node(v)[dummyK] != null) {
        g.predecessors(v)?.forEach((u) {
          var uNode = g.node(u);
          if (uNode[dummyK] != null && (uNode.getD(orderK) < prevNorthBorder || uNode.getD(orderK) > nextNorthBorder)) {
            _addConflict(conflicts, u, v);
          }
        });
      }
    });
  }

  visitLayer(List<String> north, List<String> south) {
    int prevNorthPos = -1;
    int? nextNorthPos;
    int southPos = 0;
    south.each((v, southLookahead) {
      if (Dummy.border == g.node(v)[dummyK]) {
        var predecessors = g.predecessors(v);
        if (predecessors != null && predecessors.isNotEmpty) {
          nextNorthPos = g.node(predecessors[0]).getI(orderK);
          scan(south, southPos, southLookahead, prevNorthPos, nextNorthPos!);
          southPos = southLookahead;
          prevNorthPos = nextNorthPos!;
        }
      }
      scan(south, southPos, south.length, nextNorthPos ?? double.nan, north.length);
    });
    return south;
  }

  if (layering.isNotEmpty) {
    layering.reduce2(visitLayer);
  }
  return conflicts;
}

String? _findOtherInnerSegmentNode(Graph g, String v) {
  var dummy = g.node(v).get2(dummyK);
  if (dummy != null) {
    return g.predecessors(v)!.find((u) {
      return g.node(u)[dummyK] != null;
    });
  }
  return null;
}

void _addConflict(Map<String, Map<String, bool>> conflicts, String v, String w) {
  int t = v.compareTo(w);
  if (t > 0) {
    var tmp = v;
    v = w;
    w = tmp;
  }
  var conflictsV = conflicts[v];
  if (conflictsV == null) {
    conflicts[v] = conflictsV = {};
  }
  conflictsV[w] = true;
}

bool _hasConflict(Map<String,Map<String,bool>> conflicts, String v, String w) {
  int t = v.compareTo(w);
  if (t > 0) {
    var tmp = v;
    v = w;
    w = tmp;
  }
  return conflicts[v]!=null&&conflicts[v]!.containsKey(w);
}

_InnerResult _verticalAlignment(
  Graph g,
  List<List<String>> layering,
  Map<String, Map<String, bool>> conflicts,
  List<String>? Function(String) neighborFn,
) {
  Map<String, String> root = {}, align = {};
  Map<String, int> pos = {};
  for (var layer in layering) {
    layer.each((v, order) {
      root[v] = v;
      align[v] = v;
      pos[v] = order;
    });
  }

  for (var layer in layering) {
    var prevIdx = -1;
    for (var v in layer) {
      List<String> ws = neighborFn(v) ?? [];
      if (ws.isNotEmpty) {
        ws.sort((a,b){
          return pos[a]!.compareTo(pos[b]!);
        });

        num mp = (ws.length - 1) / 2;
        for (int i = mp.floor(), il = mp.ceil(); i <= il; ++i) {
          var w = ws[i];
          if (align[v] == v &&
              prevIdx < pos[w]! &&
              !_hasConflict(conflicts, v, w)) {
            align[w] = v;
            align[v] = root[v] = root[w]!;
            prevIdx = pos[w]!;
          }
        }
      }
    }
  }
  _InnerResult result = _InnerResult();
  result.root = root;
  result.align = align;
  return result;
}

Map<String, double> _horizontalCompaction(
  Graph g,
  List<List<String>> layering,
  Map<String, String> root,
  Map<String, String> align,
  bool reverseSep,
) {
  Map<String, double> xs = {};
  Graph blockG = _buildBlockGraph(g, layering, root, reverseSep);
  String borderType = reverseSep ? "borderLeft" : "borderRight";

  iterate(void Function(String) setXsFunc,bool predecessors) {
    var stack = blockG.nodes;
    Map<String, bool> visited = {};

    String? elem = stack.removeLastOrNull();
    while (elem != null) {
      if ((visited[elem] ?? false)) {
        setXsFunc.call(elem);
      } else {
        visited[elem] = true;
        stack.add(elem);
        if(predecessors){
          stack.addAll(blockG.predecessors(elem) ?? []);
        }else{
          stack.addAll(blockG.successors(elem)??[]);
        }
      }
      elem = stack.removeLastOrNull();
    }
  }

  // First pass, assign smallest coordinates
  pass1(String elem) {
    List<Edge> lp = blockG.inEdges(elem) ?? [];
    xs[elem] = lp.reduce2<num>((e, acc) {
      return math.max(acc, (xs[e.v]! + blockG.edge2(e).getD(valueK)));
    }, 0).toDouble();
  }

  // Second pass, assign greatest coordinates
  pass2(String elem) {
    num minv = blockG.outEdges(elem)!.reduce2((e, acc) {
      return math.min(acc, xs[e.w]! - blockG.edge2(e).getD(valueK));
    }, double.maxFinite);

    var node = g.node(elem);
    if (minv != double.maxFinite && node[borderTypeK] != borderType) {
      xs[elem] = math.max(xs[elem] as num, minv).toDouble();
    }
  }

  iterate(pass1, true);
  iterate(pass2, false);

  for(var v in align.keys){
    xs[v] = xs[root[v]]!;
  }
  return xs;
}

Graph _buildBlockGraph(Graph g, List<List<String>> layering, Map<String, String> root, bool reverseSep) {
  Graph blockGraph = Graph();
  var graphLabel = g.label;
  var sepFn = _sep(graphLabel.nodeSep, graphLabel.edgeSep, reverseSep);
  for (var layer in layering) {
    String? u;
    for (var v in layer) {
      var vRoot = root[v]!;
      blockGraph.setNode(vRoot);
      if (u != null) {
        var uRoot = root[u]!;
        num prevMax = blockGraph.edgeNull(uRoot, vRoot)?[valueK] ?? 0;

        Props props = Props();
        props[valueK] = math.max(sepFn.call(g, v, u), prevMax);
        blockGraph.setEdge2(uRoot, vRoot, value: props);
      }
      u = v;
    }
  }
  return blockGraph;
}


Map<String, double> _findSmallestWidthAlignment(Graph g, Map<GraphAlign, Map<String, double>> xss) {
  List<dynamic> initValue=[double.infinity,null];
  for(var item in xss.values){
    double max = double.minPositive;
    double min = double.maxFinite;
    for(var child in item.entries){
      var halfWidth = _width(g, child.key) / 2;
      max = math.max(child.value + halfWidth, max);
      min = math.min(child.value - halfWidth, min);
    }
    var newMin = max - min;
    if (newMin < initValue[0]) {
      initValue = [newMin, item];
    }
  }
  return (initValue[1] as Map<String,double>?)??{};

}

void _alignCoordinates(Map<GraphAlign, Map<String, double>> xss, Map<String, double> alignTo) {
  List<double> alignToVals = List.from(alignTo.values);
  double alignToMin = min(alignToVals)!.toDouble(), alignToMax = max(alignToVals)! .toDouble();
  for (var vert in ["u", "d"]) {
    for (var horiz in ["l", "r"]) {
      GraphAlign alignment = fromStr('${vert}t$horiz');
      Map<String, double> xs = xss[alignment]!;
      double delta;
      if (xs == alignTo){
        continue;
      }

      List<double> xsVals = List.from(xs.values);
      delta=alignToMin - min(xsVals)!;
      if(horiz!="l"){
        delta=alignToMax - max(xsVals)!;
      }
      if (delta!=0) {
        Map<String, double> rm = {};
        xs.forEach((key, value) {
          rm[key] = value + delta;
        });
        xss[alignment] = rm;
      }
    }
  }
}

Map<String, double> _balance(Map<GraphAlign, Map<String, double>> xss, GraphAlign? align) {
  Map<String, double> ulMap = xss[GraphAlign.utl]??{};
  Map<String, double> map = {};
  for (var key in ulMap.keys) {
    double d;
    if (align != null) {
      d = xss[align]![key]!;
    } else {
      List<double> xs=[];
      for(var ve in xss.values){
        xs.add(ve[key]!);
      }
      xs.sort();
      d = (xs[1] + xs[2]) / 2;
    }
    map[key] = d;
  }
  return map;
}

Map<String, double> positionX(Graph g) {
  List<List<String>> layering = util.buildLayerMatrix(g);
  Map<String, Map<String, bool>> conflicts =_mergeMap( _findType1Conflicts(g, layering), _findType2Conflicts(g, layering));
  Map<GraphAlign, Map<String, double>> xss = {};
  List<List<String>> adjustedLayering;
  for (var vert in ["u", "d"]) {
    adjustedLayering = vert == "u" ? layering : layering.reverseSelf();
    for (var horiz in ["l", "r"]) {
      if (horiz == "r") {
        adjustedLayering = List.from(adjustedLayering.map((inner) {
          return inner.reverse2();
        }));
      }
      List<String>? Function(String) neighborFn = (vert == "u" ? g.predecessors : g.successors);

      _InnerResult align = _verticalAlignment(g, adjustedLayering, conflicts, neighborFn);
      Map<String, double> xs = _horizontalCompaction(g, adjustedLayering, align.root, align.align, horiz == "r");
      if (horiz == "r") {
        Map<String, double> rm = {};
        xs.forEach((key, value) {
          rm[key] = -value;
        });
        xs = rm;
      }
      xss[fromStr('${vert}t$horiz')] = xs;
    }
  }
  var smallestWidth = _findSmallestWidthAlignment(g, xss);
  _alignCoordinates(xss, smallestWidth);
  return _balance(xss, g.label.align);
}

num Function(Graph, String, String) _sep(num nodeSep, num edgeSep, bool reverseSep) {
  return (Graph g, String v, String w) {
    Props vLabel = g.node(v);
    Props wLabel = g.node(w);
    num sum = 0;
    num delta = 0;
    sum += vLabel.getD(widthK) / 2;
    if (vLabel[labelPosK] == LabelPosition.left) {
      delta = -vLabel.getD(widthK) / 2;
    } else if (vLabel[labelPosK] == LabelPosition.right) {
      delta = vLabel.getD(widthK) / 2;
    }

    if (delta != 0) {
      sum += reverseSep ? delta : -delta;
    }

    delta = 0;
    sum += (vLabel[dummyK] != null ? edgeSep : nodeSep) / 2;
    sum += (wLabel[dummyK] != null ? edgeSep : nodeSep) / 2;
    sum += wLabel.getD(widthK) / 2;

    var lab = wLabel[labelPosK];
    if (lab == LabelPosition.left) {
      delta = wLabel.getD(widthK) / 2;
    } else if (lab == LabelPosition.right) {
      delta = -wLabel.getD(widthK) / 2;
    }
    if (delta != 0) {
      sum += reverseSep ? delta : -delta;
    }

    delta = 0;
    return sum;
  };
}

num _width(Graph g, String v) {
  return g.node(v).getD(widthK);
}

Map<String, Map<String, bool>> _mergeMap(Map<String, Map<String, bool>> m1,Map<String, Map<String, bool>> m2){
  Map<String, Map<String, bool>> map={};
  map.addAll(m1);
  m2.forEach((key, value) {
    Map<String,bool> cm=map[key]??{};
    map[key]=cm;
    cm.addAll(value);
  });
  return map;
}

class _InnerResult {
  Map<String, String> root = {};
  Map<String, String> align = {};
}


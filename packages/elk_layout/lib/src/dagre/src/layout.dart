import 'dart:math' as math;
import 'package:elk_layout/src/dagre/dart_dagre.dart';
import 'package:elk_layout/src/dagre/src/graph/graph.dart';
import 'package:elk_layout/src/dagre/src/model/enums/dummy.dart';
import 'package:elk_layout/src/dagre/src/model/graph_label.dart';
import 'package:elk_layout/src/dagre/src/model/graph_rect.dart';
import 'package:elk_layout/src/dagre/src/model/props.dart';
import 'package:elk_layout/src/dagre/src/model/tmp/self_edge_data.dart';
import 'package:elk_layout/src/dagre/src/parent_dummy_chains.dart';
import 'package:elk_layout/src/dagre/src/position/index.dart';
import 'package:elk_layout/src/dagre/src/util.dart';
import 'package:elk_layout/src/dagre/src/util.dart' as util;
import 'package:elk_layout/src/dagre/src/util/list_util.dart';
import 'package:elk_layout/src/dagre/src/acyclic.dart' as acyclic;
import 'package:elk_layout/src/dagre/src/nesting_graph.dart' as nesting_graph;
import 'package:elk_layout/src/dagre/src/rank/index.dart';
import 'package:elk_layout/src/dagre/src/normalize.dart' as normalize;
import 'package:elk_layout/src/dagre/src/coordinate_system.dart' as coordinate_system;

import 'add_border_segments.dart';
import 'model/graph_point.dart';
import 'order/index.dart';

void layout(Graph g, DagreConfig config) {
  var layoutGraph = _buildLayoutGraph(g);
  _runLayout(layoutGraph,config);
  _updateInputGraph(g, layoutGraph);
}

Graph _buildLayoutGraph(Graph inputGraph) {
  var g = Graph(isMultiGraph: true, isCompound: true);
  var graph = inputGraph.label.copy();
  GraphLabel label = GraphLabel(rankSep: 50, edgeSep: 20, nodeSep: 50, rankDir: RankDir.ttb);
  label.nodeSep = graph.nodeSep;
  label.edgeSep = graph.edgeSep;
  label.rankSep = graph.rankSep;
  label.marginX = graph.marginX;
  label.marginY = graph.marginY;
  label.acyclicer = graph.acyclicer;
  label.ranker = graph.ranker;
  label.rankDir = graph.rankDir;
  label.align = graph.align;
  // elk_layout extension: preserve the model-order flag across the internal
  // graph rebuild (it is dropped otherwise, since only known label fields are
  // copied above).
  if (graph[useModelOrderK] == true) {
    label[useModelOrderK] = true;
  }
  g.label = label;

  for (var v in inputGraph.nodes) {
    var node = inputGraph.nodeNull(v) ?? Props();
    var np = Props();
    np[widthK] = node.get(widthK);
    np[heightK] = node.get(heightK);
    if (!np.hasOwn(widthK)) {
      np[widthK] = 0;
    }
    if (!np.hasOwn(heightK)) {
      np[heightK] = 0;
    }
    // elk_layout extension: carry the per-node model-order index across the
    // rebuild so init_order can use it.
    final mo = node.getD2(modelOrderK);
    if (mo != null) {
      np[modelOrderK] = mo;
    }

    g.setNode(v, np);
    g.setParent(v, inputGraph.parent(v));
  }

  for (var e in inputGraph.edges) {
    Props? edge = inputGraph.edgeNull(e.v, e.w, e.id);
    var ep = {
      minLenK: 1,
      widthK: 0,
      heightK: 0,
      weightK: 1,
      labelOffsetK: 10,
      labelPosK: LabelPosition.right,
    };
    if (edge != null) {
      if (edge[minLenK] != null) {
        ep[minLenK] = edge[minLenK];
      }
      if (edge[weightK] != null) {
        ep[weightK] = edge[weightK];
      }
      if (edge[widthK] != null) {
        ep[widthK] = edge[widthK];
      }
      if (edge[heightK] != null) {
        ep[heightK] = edge[heightK];
      }
      if (edge[labelOffsetK] != null) {
        ep[labelOffsetK] = edge[labelOffsetK];
      }
      if (edge[labelPosK] != null) {
        ep[labelPosK] = edge[labelPosK];
      }
    }
    g.setEdge(e, ep.toProps);
  }

  return g;
}

void _runLayout(Graph g, DagreConfig config) {
  _makeSpaceForEdgeLabels(g);
  _removeSelfEdges(g);
  acyclic.run(g);
  nesting_graph.run(g);
  rankFun(util.asNonCompoundGraph(g));
  _injectEdgeLabelProxies(g);
  removeEmptyRanks(g);
  nesting_graph.cleanup(g);
  normalizeRanks(g);
  _assignRankMinMax(g);
  _removeEdgeLabelProxies(g);
  normalize.run(g);
  parentDummyChains(g);
  addBorderSegments(g);
  order(g,config);
  _insertSelfEdges(g);
  coordinate_system.adjust(g);
  position(g);
  _positionSelfEdges(g);
  _removeBorderNodes(g);
  normalize.undo(g);
  _fixupEdgeLabelCoords(g);
  coordinate_system.undo(g);
  _translateGraph(g);
  _assignNodeIntersects(g);
  _reversePointsForReversedEdges(g);
  acyclic.undo(g);
}

void _updateInputGraph(Graph inputGraph, Graph layoutGraph) {
  for (var v in inputGraph.nodes) {
    var inputLabel = inputGraph.nodeNull(v);
    var layoutLabel = layoutGraph.node(v);

    if (inputLabel != null) {
      inputLabel[xK] = layoutLabel[xK];
      inputLabel[yK] = layoutLabel[yK];
      inputLabel[rankK] = layoutLabel[rankK];
      var children = layoutGraph.children(v);
      if (children != null && children.isNotEmpty) {
        inputLabel[widthK] = layoutLabel[widthK];
        inputLabel[heightK] = layoutLabel[heightK];
      }
    }
  }
  for (var e in inputGraph.edges) {
    var inputLabel = inputGraph.edge2(e);
    var layoutLabel = layoutGraph.edge2(e);

    inputLabel[pointsK] = layoutLabel[pointsK];
    if (layoutLabel.get2(xK) != null) {
      inputLabel[xK] = layoutLabel[xK];
      inputLabel[yK] = layoutLabel[yK];
    }
  }
  inputGraph.label.width = layoutGraph.label.width;
  inputGraph.label.height = layoutGraph.label.height;
}

void _makeSpaceForEdgeLabels(Graph g) {
  var graph = g.label;
  graph.rankSep /= 2;
  g.edges.each((e, p1) {
    var edge = g.edge2(e);
    edge[minLenK] = edge.getD(minLenK) * 2;
    if (edge.get2(labelPosK) != LabelPosition.center) {
      if (graph.rankDir == RankDir.ttb || graph.rankDir == RankDir.btt) {
        edge[widthK] = edge.getD(widthK) + edge.getD(labelOffsetK);
      } else {
        edge[heightK] = edge.getD(heightK) + edge.getD(labelOffsetK);
      }
    }
  });
}

void _injectEdgeLabelProxies(Graph g) {
  for (var e in g.edgesIterable) {
    var edge = g.edge2(e);
    bool bw = edge.hasOwn(widthK) && edge.getI(widthK) != 0;
    bool bh = edge.hasOwn(heightK) && edge.getI(heightK) != 0;
    if (bw && bh) {
      var v = g.node(e.v);
      var w = g.node(e.w);
      var label = {rankK: (w.getD(rankK) - v.getD(rankK)) / 2 + v.getD(rankK), eK: e};
      util.addDummyNode(g, Dummy.edgeProxy, label.toProps, "_ep");
    }
  }
}

void _assignRankMinMax(Graph g) {
  double maxRank = 0;
  for (var v in g.nodesIterable) {
    var node = g.node(v);
    var value = node.getS2(borderTopK);
    if (value != null) {
      node[minRankK] = g.node(value)[rankK];
      node[maxRankK] = g.node(node.getS(borderBottomK))[rankK];
      maxRank = math.max(maxRank, node.getD(maxRankK));
    }
  }
  g.label[maxRankK] = maxRank;
}

void _removeEdgeLabelProxies(Graph g) {
  for (var v in g.nodes) {
    var node = g.node(v);
    if (node[dummyK] == Dummy.edgeProxy) {
      g.edge2(node.get(eK))[labelRankK] = node[rankK];
      g.removeNode(v);
    }
  }
}

void _translateGraph(Graph g) {
  var minX = double.maxFinite;
  double maxX = 0;
  var minY = double.maxFinite;
  double maxY = 0;
  var graphLabel = g.label;
  var marginX =graphLabel.marginX;
  var marginY =graphLabel.marginY;

  ///attrs is NodeProps or EdgeProps
  getExtremes(Props attrs) {
    double x = attrs.getD(xK);
    double y = attrs.getD(yK);
    double w = attrs[widthK];
    double h = attrs[heightK];
    minX = math.min(minX, x - w / 2);
    maxX = math.max(maxX, (x + w / 2));
    minY = math.min(minY, y - h / 2);
    maxY = math.max(maxY, (y + h / 2));
  }

  for (var v in g.nodesIterable) {
    getExtremes(g.node(v));
  }

  for (var e in g.edgesIterable) {
    var edge = g.edge2(e);
    if (edge.hasOwn(xK)) {
      getExtremes(edge);
    }
  }

  minX -= marginX;
  minY -= marginY;

  for (var v in g.nodesIterable) {
    var node = g.node(v);
    node[xK] = node.getD(xK) - minX;
    node[yK] = node.getD(yK) - minY;
  }

  for (var e in g.edgesIterable) {
    var edge = g.edge2(e);
    edge.getL<GraphPoint>(pointsK).each((p, p1) {
      p.x -= minX;
      p.y -= minY;
    });
    if (edge.hasOwn(xK)) {
      edge[xK] = edge.getD(xK) - minX;
    }
    if (edge.hasOwn(yK)) {
      edge[yK] = edge.getD(yK) - minY;
    }
  }
  graphLabel.width = maxX - minX + marginX;
  graphLabel.height = maxY - minY + marginY;
}

void _assignNodeIntersects(Graph g) {
  for (var e in g.edgesIterable) {
    var edge = g.edge2(e);
    var nodeV = g.node(e.v);
    var nodeW = g.node(e.w);
    GraphPoint p1, p2;
    List<dynamic>? points = edge.get2(pointsK);
    if (points == null || points.isEmpty) {
      p1 = GraphPoint(nodeW.getD(xK), nodeW.getD(yK));
      p2 = GraphPoint(nodeV.getD(xK), nodeV.getD(yK));
    } else {
      p1 = points[0];
      p2 = points.last;
    }
    points?.insert(
        0, util.intersectRect(GraphRect(nodeV.getD(xK), nodeV.getD(yK), nodeV.getD(widthK), nodeV.getD(heightK)), p1));
    points?.add(
        util.intersectRect(GraphRect(nodeW.getD(xK), nodeW.getD(yK), nodeW.getD(widthK), nodeW.getD(heightK)), p2));
  }
}

void _fixupEdgeLabelCoords(Graph g) {
  for (var e in g.edgesIterable) {
    var edge = g.edge2(e);
    var xValue = edge.getD2(xK);
    if (xValue != null) {
      if (edge.get2(labelPosK) == LabelPosition.left || edge.get2(labelPosK) == LabelPosition.right) {
        edge[widthK] = edge.getD(widthK) - edge.getD(labelOffsetK);
      }

      LabelPosition lp = edge.get2(labelPosK);
      if (lp == LabelPosition.left) {
        edge[xK] = xValue - (edge.getD(widthK) / 2 + edge.getD(labelOffsetK));
      } else if (lp == LabelPosition.right) {
        edge[xK] = xValue + (edge.getD(widthK) / 2 + edge.getD(labelOffsetK));
      }
    }
  }
}

void _reversePointsForReversedEdges(Graph g) {
  for (var e in g.edgesIterable) {
    var edge = g.edge2(e);
    if (edge[reversedK] == true) {
      edge[pointsK] = edge.getL<GraphPoint>(pointsK).reverse2();
    }
  }
}

void _removeBorderNodes(Graph g) {
  for (var v in g.nodesIterable) {
    var cl = g.children(v);
    if (cl != null && cl.isNotEmpty) {
      var node = g.node(v);
      var t = g.node(node.getS(borderTopK));
      var b = g.node(node.getS(borderBottomK));
      var l = g.node(node.getL<String>(borderLeftK).last);
      var r = g.node(node.getL<String>(borderRightK).last);
      node[widthK] = (r.getD(xK) - l.getD(xK)).abs();
      node[heightK] = (b.getD(yK) - t.getD(yK)).abs();
      node[xK] = l.getD(xK) + node.getD(widthK) / 2;
      node[yK] = t.getD(yK) + node.getD(heightK) / 2;
    }
  }

  for (var v in g.nodes) {
    if (g.node(v)[dummyK] == Dummy.border) {
      g.removeNode(v);
    }
  }
}

void _removeSelfEdges(Graph g) {
  for (var e in g.edges) {
    if (e.v == e.w) {
      var node = g.node(e.v);
      node.get<List<SelfEdgeData>>(selfEdgesK).add(SelfEdgeData(e, g.edge2(e)));
      g.removeEdge2(e);
    }
  }
}

void _insertSelfEdges(Graph g) {
  var layers = util.buildLayerMatrix(g);
  for (var layer in layers) {
    var orderShift = 0;
    layer.each((v, i) {
      var node = g.node(v);
      node[orderK] = i + orderShift;
      for (SelfEdgeData selfEdge in (node[selfEdgesK] ?? [])) {
        Props np = Props();
        np[widthK] = selfEdge.data.getD(widthK);
        np[heightK] = selfEdge.data.getD(heightK);
        np[rankK] = node.get(rankK);
        np[orderK] = i + (++orderShift);
        np[eK] = selfEdge.e;
        np[labelK] = selfEdge.data;
        util.addDummyNode(g, Dummy.selfEdge, np, "_se");
      }
      node.remove(selfEdgesK);
    });

  }
}

void _positionSelfEdges(Graph g) {
  for (var v in g.nodes) {
    var node = g.node(v);
    if (node.get2(dummyK) == Dummy.selfEdge) {
      var selfNode = g.node(node.get<Edge>(eK).v);
      var x = selfNode.getD(xK) + selfNode.getD(widthK) / 2;
      var y = selfNode.getD(yK);
      var dx = node.getD(xK) - x;
      var dy = selfNode.getD(heightK) / 2;
      g.setEdge(node.get<Edge>(eK), node.get(labelK));
      g.removeNode(v);
      node.get<Props>(labelK)[pointsK] = <GraphPoint>[
        GraphPoint(x + 2 * dx / 3, y - dy),
        GraphPoint(x + 5 * dx / 6, y - dy),
        GraphPoint(x + dx, y),
        GraphPoint(x + 5 * dx / 6, y + dy),
        GraphPoint(x + 2 * dx / 3, y + dy)
      ];
      node.get<Props>(labelK)[xK] = node.get(xK);
      node.get<Props>(labelK)[yK] = node.get(yK);
    }
  }
}

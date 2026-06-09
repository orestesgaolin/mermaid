import 'dart:math' as math;
import 'package:mermaid_core/src/vendor/dagre/src/graph/graph.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/props.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/list_util.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/util.dart';

double Function(Edge) defaultWeightFun = (a) {
  return 1;
};

List<Edge> greedyFAS(Graph g, double Function(Edge)? weightFn) {
  if (g.nodeCount <= 1) {
    return [];
  }
  _InnerResult2 state = _buildState(g, weightFn??defaultWeightFun);

  List<Edge> results = _doGreedyFAS(state.graph, state.buckets, state.zeroIdx);

  List<Edge> rl = [];
  for (var e in results) {
    rl.addAll(g.outEdges(e.v, e.w) ?? []);
  }
  return rl;
}

List<Edge> _doGreedyFAS(Graph g, List<List<Props>> buckets, int zeroIdx) {
  List<Edge> results = [];
  var sources = buckets[buckets.length - 1];
  var sinks = buckets[0];
  Props? entry;
  while (g.nodeCount > 0) {
    while (sinks.isNotEmpty) {
      entry=sinks.removeAt(0);
      _removeNode(g, buckets, zeroIdx, entry, false);
    }
    while (sources.isNotEmpty) {
      entry = sources.removeAt(0);
      _removeNode(g, buckets, zeroIdx, entry, false);
    }
    if (g.nodeCount > 0) {
      for (var i = buckets.length - 2; i > 0; --i) {
        var bl=buckets[i];
        entry = bl.isNotEmpty?bl.removeAt(0):null;
        if (entry != null) {
          results = results.concat(_removeNode(g, buckets, zeroIdx, entry, true));
          break;
        }
      }
    }
  }
  return results;
}

List<Edge>? _removeNode(Graph g, List<List<Props>> buckets, int zeroIdx, Props entry,
    [bool collectPredecessors = false]) {
  List<Edge>? results = collectPredecessors ? [] : null;
  g.inEdges(entry.getS(vK))?.forEach((e) {
    var weight = g.edge2(e).getD(valueK);
    var uEntry = g.node(e.v);
    results?.add(Edge(v: e.v, w: e.w));
    uEntry[outK] = uEntry.getD(outK) - weight;
    _assignBucket(buckets, zeroIdx, uEntry);
  });

  g.outEdges(entry.getS(vK))?.forEach((e) {
    var weight = g.edge2(e).getD(valueK);
    var w = e.w;
    var wEntry = g.node(w);
    wEntry[innerK] = wEntry.getD(innerK) - weight;
    _assignBucket(buckets, zeroIdx, wEntry);
  });
  g.removeNode(entry.getS(vK));
  return results;
}

_InnerResult2 _buildState(Graph g, double Function(Edge) weightFn) {
  var fasGraph = Graph();
  double maxIn = 0;
  double maxOut = 0;
  for (var v in g.nodesIterable) {
    Props p = Props();
    p[vK] = v;
    p[innerK] = 0;
    p[outK] = 0;
    fasGraph.setNode(v, p);
  }

  for (var e in g.edgesIterable) {
    var prevWeight = fasGraph.edgeNull(e.v, e.w, e.id)?.getD(valueK) ?? 0;
    double weight = weightFn.call(e);
    var edgeWeight = prevWeight + weight;

    fasGraph.setEdge2(e.v, e.w, value: {valueK: edgeWeight}.toProps);

    var p1 = fasGraph.node(e.v);
    p1[outK] = p1.getD(outK) + weight;
    maxOut = math.max(maxOut, p1.getD(outK));

    p1 = fasGraph.node(e.w);
    p1[innerK] = p1.getD(innerK) + weight;
    maxIn = math.max(maxIn, p1.getD(innerK));
  }

  List<List<Props>> buckets = List.from(range(0, (maxOut + maxIn + 3).toInt()).map((e) {
    return <Props>[];
  }));
  var zeroIdx = (maxIn + 1).toInt();

  for (var v in fasGraph.nodes) {
    _assignBucket(buckets, zeroIdx, fasGraph.node(v));
  }
  _InnerResult2 result2 = _InnerResult2();
  result2.graph = fasGraph;
  result2.buckets = buckets;
  result2.zeroIdx = zeroIdx;
  return result2;
}

void _assignBucket(List<List<Props>> buckets, int zeroIdx, Props entry) {
  if (!entry.hasOwn(outK)) {
    buckets[0].insert(0,entry);
  } else if (!entry.hasOwn(innerK)) {
    buckets[buckets.length - 1].insert(0,entry);
  } else {
    buckets[(entry.getD(outK) - entry.getD(innerK) + zeroIdx).toInt()].insert(0, entry);
  }
}

class _InnerResult2 {
  late Graph graph;
  late List<List<Props>> buckets;
  late int zeroIdx;
}

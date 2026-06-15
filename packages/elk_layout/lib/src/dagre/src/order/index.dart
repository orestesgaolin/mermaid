import 'package:elk_layout/src/dagre/dart_dagre.dart';
import 'package:elk_layout/src/dagre/src/model/enums/relationship.dart';
import 'package:elk_layout/src/dagre/src/model/props.dart';
import 'package:elk_layout/src/dagre/src/order/sort_subgraph.dart';
import 'package:elk_layout/src/dagre/src/util/list_util.dart';
import '../graph/graph.dart';
import '../model/tmp/resolve_conflicts_result.dart';
import '../util.dart' as util;
import '../util/util.dart';
import 'add_subgraph_constraints.dart';
import 'cross_count.dart';
import 'init_order.dart';
import 'build_layer_graph.dart';

void order(Graph g, DagreConfig config) {
  var fun = config.customOrder;
  if (fun != null) {
    fun.call(g);
    return;
  }

  var maxRank = util.maxRank(g)!;
  List<Graph> downLayerGraphs = _buildLayerGraphs(g, range(1, maxRank + 1), Relationship.inEdges);
  List<Graph> upLayerGraphs = _buildLayerGraphs(g, range(maxRank - 1, -1, -1), Relationship.outEdges);

  List<List<String>> layering = initOrder(g);
  _assignOrder(g, layering);

  /// https://github.com/dagrejs/dagre/pull/335/files
  /// TODO 暂时修复
  ///
  /// Vendored fix: this early-out must not apply to compound graphs. Cluster
  /// border nodes are only moved to the correct side of their siblings by the
  /// sortSubgraph sweeps below, so skipping them breaks cluster layout.
  var isCompoundLayout = g.nodes.any((v) {
    var ch = g.children(v);
    return ch != null && ch.isNotEmpty;
  });
  if (!isCompoundLayout && crossCount(g, layering) == 0) {
    return;
  }

  if (config.disableOptimalOrderHeuristic) {
    return;
  }
  num bestCC = double.infinity;
  List<List<String>> best = [];
  for (int i = 0, lastBest = 0; lastBest < 4; ++i, ++lastBest) {
    _sweepLayerGraphs((i % 2)!=0 ? downLayerGraphs : upLayerGraphs, i % 4 >= 2);
    layering = util.buildLayerMatrix(g);
    var cc = crossCount(g, layering);
    if (cc < bestCC) {
      lastBest = 0;
      best = _copyList(layering);
      bestCC = cc;
    }
  }
  _assignOrder(g, best);
}

List<Graph> _buildLayerGraphs(Graph g, List<int> ranks, Relationship ship) {
  return List.from(ranks.map((rank) {
    return buildLayerGraph(g, rank, ship);
  }));
}

void _sweepLayerGraphs(List<Graph> layerGraphs,bool biasRight) {
  var cg = Graph();
  for (var lg in layerGraphs) {
    String root = lg.label[rootK];
    ResolveConflictsResult sorted = sortSubgraph(lg, root, cg, biasRight);
    sorted.vs.each((v, i) {
      lg.node(v)[orderK] = i;
    });
    addSubgraphConstraints(lg, cg, sorted.vs);
  }
}

void _assignOrder(Graph g, List<List<String>> layering) {
  for (var layer in layering) {
    layer.each((v, i) {
      g.node(v)[orderK] = i;
    });
  }
}

List<List<String>> _copyList(List<List<String>> list) {
  List<List<String>> rl = [];
  for (var ele in list) {
    rl.add(List.from(ele));
  }
  return rl;
}

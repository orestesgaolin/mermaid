import 'package:elk_layout/src/dagre/src/model/props.dart';
import 'package:elk_layout/src/dagre/src/order/resolve_conflicts.dart';
import 'package:elk_layout/src/dagre/src/order/sort.dart';
import 'package:elk_layout/src/dagre/src/util/list_util.dart';
import '../graph/graph.dart';
import '../model/tmp/resolve_conflicts_result.dart';
import 'barycenter.dart';
import '../model/tmp/order_inner_result.dart';

ResolveConflictsResult sortSubgraph(Graph g, String v, Graph cg, bool biasRight) {
  List<String> movable = g.children(v)??[];
  Props? node = g.nodeNull(v);
  // Vendored fix: dagre.js reads node.borderLeft as `undefined` when absent;
  // Props.get throws instead, so use the null-tolerant accessor.
  String? bl;
  var blList = node?.get2<List<dynamic>>(borderLeftK);
  if (blList != null && blList.isNotEmpty) {
    bl = blList.first as String;
  }
  String? br;
  var brList = node?.get2<List<dynamic>>(borderRightK);
  if (brList != null && brList.isNotEmpty) {
    br = brList.first as String;
  }

  Map<String, ResolveConflictsResult> subgraphs = {};

  if (bl != null) {
    movable = movable.filter((w) {
      return w != bl && w != br;
    });
  }

  List<OrderInnerResult> barycenters = barycenter(g, movable);
  for (var entry in barycenters) {
    var list=g.children(entry.v);
    if (list!=null&&list.isNotEmpty) {
      var subgraphResult = sortSubgraph(g, entry.v, cg, biasRight);
      subgraphs[entry.v] = subgraphResult;
      if (subgraphResult.barycenter != null) {
        _mergeBarycenters(entry, subgraphResult);
      }
    }
  }

  List<ResolveConflictsResult> entries = resolveConflicts(barycenters, cg);
  _expandSubgraphs(entries, subgraphs);
  ResolveConflictsResult result = sort(entries, biasRight);
  if (bl != null) {
    result.vs = [bl, ...result.vs, br!];
    if ((g.predecessors(bl)??[]).isNotEmpty) {
      Props blPred = g.node(g.predecessors(bl)![0]);
      Props brPred = g.node(g.predecessors(br)![0]);
      if (result.barycenter == null) {
        result.barycenter = 0;
        result.weight = 0;
      }
      result.barycenter = (result.barycenter! * result.weight + blPred.getD(orderK) + brPred.getD(orderK)) / (result.weight + 2);

      result.weight = result.weight + 2;
    }
  }
  return result;
}

void _expandSubgraphs(List<ResolveConflictsResult> entries, Map<String, ResolveConflictsResult> subgraphs) {
  for (var entry in entries) {
    List<String> rl = [];
    for (var v in entry.vs) {
      if (subgraphs[v] != null) {
        rl.addAll(subgraphs[v]!.vs);
      } else {
        rl.add(v);
      }
    }
    entry.vs = rl;
  }
}

void _mergeBarycenters(OrderInnerResult target, ResolveConflictsResult other) {
  if (target.barycenter != null) {
    target.barycenter = (target.barycenter! * target.weight! +
        other.barycenter! * other.weight) /
        (target.weight! + other.weight);
    target.weight = target.weight! + other.weight;
  } else {
    target.barycenter = other.barycenter;
    target.weight = other.weight;
  }
}

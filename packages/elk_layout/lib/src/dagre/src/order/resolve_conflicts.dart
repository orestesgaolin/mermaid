import 'dart:math' as math;
import 'package:elk/src/dagre/src/model/tmp/resolve_conflicts_result.dart';
import 'package:elk/src/dagre/src/util/list_util.dart';
import '../graph/graph.dart';
import '../model/tmp/conflict_info.dart';
import '../model/tmp/order_inner_result.dart';

List<ResolveConflictsResult> resolveConflicts(List<OrderInnerResult> entries, Graph cg) {
  Map<String, ConflictInfo> mappedEntries = {};
  entries.each((entry, i) {
    ConflictInfo tmp = ConflictInfo();
    tmp.inDegree = 0;
    tmp.vs=[entry.v];
    tmp.i = i;
    mappedEntries[entry.v] = tmp;
    if (entry.barycenter!=null) {
      tmp.barycenter = entry.barycenter!;
      tmp.weight = entry.weight!;
    }
  });

  for (var e in cg.edges) {
    var entryV = mappedEntries[e.v];
    var entryW = mappedEntries[e.w];
    if (entryV != null && entryW != null) {
      entryW.inDegree+=1;
      entryV.out.add(entryW);
    }
  }

  List<ConflictInfo> sourceSet = List.from(mappedEntries.values.where((entry) {
    return entry.inDegree == 0;
  }));
  return _doResolveConflicts(sourceSet);
}

List<ResolveConflictsResult> _doResolveConflicts(List<ConflictInfo> sourceSet) {
  List<ConflictInfo> entries = [];
  handleIn(ConflictInfo vEntry) {
    return (ConflictInfo uEntry) {
      if (uEntry.merged) {
        return;
      }
      if (uEntry.barycenter == null || vEntry.barycenter == null || uEntry.barycenter! >= vEntry.barycenter!) {
        _mergeEntries(vEntry, uEntry);
      }
    };
  }

  handleOut(ConflictInfo vEntry) {
    return (ConflictInfo wEntry) {
      wEntry.inner.add(vEntry);
      if (--wEntry.inDegree == 0) {
        sourceSet.add(wEntry);
      }
    };
  }

  while (sourceSet.isNotEmpty) {
    var entry = sourceSet.removeLast();
    entries.add(entry);
    entry.inner.reversed.forEach(handleIn(entry));
    entry.out.forEach(handleOut(entry));
  }

  return List.from(entries.filter((entry) {
    return !entry.merged;
  }).map((entry) {
    ResolveConflictsResult result = ResolveConflictsResult();
    result.vs = entry.vs;
    result.i = entry.i;
    result.barycenter = entry.barycenter;
    result.weight = entry.weight;
    return result;
  }));
}

void _mergeEntries(ConflictInfo target, ConflictInfo source) {
  num sum = 0;
  num weight = 0;

  if (target.weight!=0) {
    sum += target.barycenter! * target.weight;
    weight += target.weight;
  }

  if (source.weight!=0) {
    sum += source.barycenter! * source.weight;
    weight += source.weight;
  }

  target.vs = source.vs.concat(target.vs);
  target.barycenter = sum / weight;
  target.weight = weight;
  target.i = math.min(source.i, target.i);
  source.merged = true;
}

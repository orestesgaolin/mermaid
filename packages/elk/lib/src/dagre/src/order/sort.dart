import 'package:elk/src/dagre/src/model/tmp/split.dart';
import '../model/tmp/resolve_conflicts_result.dart';
import 'package:elk/src/dagre/src/util.dart' as util;

ResolveConflictsResult sort(List<ResolveConflictsResult> entries, bool biasRight) {
  Split<ResolveConflictsResult> parts = util.partition<ResolveConflictsResult>(entries, (entry) {
    return entry.barycenter != null;
  });
  List<ResolveConflictsResult> sortable = parts.lhs;
  List<ResolveConflictsResult> unsortable=parts.rhs;
  unsortable.sort((a,b){
    return (b.i).compareTo(a.i);
  });

  List<String> vs = [];
  num sum = 0, weight = 0;
  int vsIndex = 0;
  sortable.sort(_compareWithBias(biasRight));
  vsIndex = _consumeUnsortable(vs, unsortable, vsIndex);
  for (var entry in sortable) {
    vsIndex += entry.vs.length;
    vs.addAll(entry.vs);
    sum += entry.barycenter! * entry.weight;
    weight += entry.weight;
    vsIndex = _consumeUnsortable(vs, unsortable, vsIndex);
  }
  ResolveConflictsResult result = ResolveConflictsResult();
  result.vs = List.from(vs);
  if (weight!=0) {
    result.barycenter = sum / weight;
    result.weight = weight;
  }
  return result;
}

int _consumeUnsortable(List<String> vs, List<ResolveConflictsResult> unsortable, int index) {
  ResolveConflictsResult last;
  while (unsortable.isNotEmpty && (last = unsortable.last).i <= index) {
    unsortable.removeLast();
    vs.addAll(last.vs);
    index++;
  }
  return index;
}

int Function(ResolveConflictsResult, ResolveConflictsResult) _compareWithBias(bool bias) {
  return (entryV, entryW) {
    if (entryV.barycenter! < entryW.barycenter!) {
      return -1;
    } else if (entryV.barycenter! > entryW.barycenter!) {
      return 1;
    }
    return !bias ? entryV.i - entryW.i : entryW.i - entryV.i;
  };
}

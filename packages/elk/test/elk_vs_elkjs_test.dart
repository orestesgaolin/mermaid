// Parity tests: our faithful ELK engine vs **real elkjs 0.9.3**, on a set of
// graphs from simple (a chain) to complex (ELK's own layered example), driven
// by the shared `tool/validation/graphs.json`. elkjs's output is captured as a
// committed golden (`tool/validation/elkjs_golden.json`, produced by
// `node tool/validation/run_elkjs.mjs`) so this runs under `dart test` without
// Node.
//
// Exact coordinates can't match across implementations, so we assert the
// structural parity guarantees: both engines assign every node to the same
// layer (flow-axis order), our layout has no overlaps, and the overall
// proportions are in the same ballpark. The richer per-graph diff (side-by-side
// SVGs) is produced by `dart run tool/validation/compare.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:elk/elk.dart';
import 'package:test/test.dart';

class _R {
  _R(this.x, this.y, this.w, this.h);
  final double x, y, w, h;
  double get cx => x + w / 2;
  double get cy => y + h / 2;
}

void main() {
  final graphsFile = File('tool/validation/graphs.json');
  final goldenFile = File('tool/validation/elkjs_golden.json');

  group('elk vs elkjs 0.9.3 (structural parity)', () {
    if (!graphsFile.existsSync() || !goldenFile.existsSync()) {
      test('golden present', () {}, skip: 'run tool/validation/run_elkjs.mjs');
      return;
    }
    final cases = (jsonDecode(graphsFile.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final golden =
        (jsonDecode(goldenFile.readAsStringSync()) as Map).cast<String, dynamic>();

    for (final c in cases) {
      final name = c['name'] as String;
      final graphJson = (c['graph'] as Map).cast<String, dynamic>();

      test(name, () {
        final res = const ElkLayered().layout(ElkGraph.fromJson(graphJson));
        final ours = <String, _R>{};
        res.nodesById.forEach(
            (id, p) => ours[id] = _R(p.x, p.y, p.width, p.height));

        final theirsRaw =
            ((golden[name] as Map)['nodes'] as Map).cast<String, dynamic>();
        final theirs = <String, _R>{
          for (final e in theirsRaw.entries)
            e.key: _R(
              (e.value['x'] as num).toDouble(),
              (e.value['y'] as num).toDouble(),
              (e.value['width'] as num).toDouble(),
              (e.value['height'] as num).toDouble(),
            ),
        };

        final dir = '${(graphJson['layoutOptions'] as Map?)?['elk.direction']}'
            .toUpperCase();
        final vertical = dir != 'RIGHT' && dir != 'LEFT';
        final ids = _leafIds(graphJson)
            .where((id) => ours.containsKey(id) && theirs.containsKey(id))
            .toList();

        // 1. Layer assignment matches elkjs exactly (every leaf pair is ordered
        //    the same way along the flow axis).
        expect(_flowOrderAgreement(ids, ours, theirs, vertical), 1.0,
            reason: 'flow-axis (layer) order must match elkjs');

        // 2. Our layout has no node overlaps.
        expect(_overlaps(ours.values.toList()), 0, reason: 'no overlaps');

        // 3. No more edge crossings than elkjs (it produces crossing-free
        //    layouts on these graphs; so must we). This counts geometric
        //    crossings of the routed polylines — the crossings a viewer sees,
        //    including those from long edges routed through dummy layers.
        final oursPolys = [
          for (final e in res.edges)
            [for (final p in e.sections.first.points) (p.x, p.y)],
        ];
        final elkPolys = [
          for (final e in ((golden[name] as Map)['edges'] as List? ?? const []))
            [
              for (final p in (e as List))
                ((p['x'] as num).toDouble(), (p['y'] as num).toDouble())
            ],
        ];
        expect(_geoCrossings(oursPolys), lessThanOrEqualTo(_geoCrossings(elkPolys)),
            reason: 'edge crossings must not exceed elkjs');

        // 4. Overall proportions are in the same ballpark as elkjs.
        final ar = _aspect(ours.values), arElk = _aspect(theirs.values);
        if (arElk > 0 && ar > 0) {
          expect(ar / arElk, inInclusiveRange(0.45, 2.2),
              reason: 'aspect ratio within ~2x of elkjs');
        }
      });
    }
  });
}

double _flowOrderAgreement(
    List<String> ids, Map<String, _R> a, Map<String, _R> b, bool vertical) {
  double coord(_R r) => vertical ? r.cy : r.cx;
  var agree = 0, total = 0;
  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      final ai = coord(a[ids[i]]!), aj = coord(a[ids[j]]!);
      final bi = coord(b[ids[i]]!), bj = coord(b[ids[j]]!);
      if ((ai - aj).abs() < 4 || (bi - bj).abs() < 4) continue;
      total++;
      if ((ai < aj) == (bi < bj)) agree++;
    }
  }
  return total == 0 ? 1.0 : agree / total;
}

int _overlaps(List<_R> rs) {
  var n = 0;
  for (var i = 0; i < rs.length; i++) {
    for (var j = i + 1; j < rs.length; j++) {
      final a = rs[i], b = rs[j];
      if (a.x < b.x + b.w &&
          b.x < a.x + a.w &&
          a.y < b.y + b.h &&
          b.y < a.y + a.h) {
        n++;
      }
    }
  }
  return n;
}

/// Number of edge pairs whose routed polylines geometrically cross.
int _geoCrossings(List<List<(double, double)>> polys) {
  bool segsCross((double, double) p1, (double, double) p2, (double, double) q1,
      (double, double) q2) {
    double cr((double, double) a, (double, double) b, (double, double) c) =>
        (b.$1 - a.$1) * (c.$2 - a.$2) - (b.$2 - a.$2) * (c.$1 - a.$1);
    final d1 = cr(q1, q2, p1), d2 = cr(q1, q2, p2);
    final d3 = cr(p1, p2, q1), d4 = cr(p1, p2, q2);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  var n = 0;
  for (var i = 0; i < polys.length; i++) {
    for (var j = i + 1; j < polys.length; j++) {
      final a = polys[i], b = polys[j];
      var hit = false;
      for (var x = 0; x + 1 < a.length && !hit; x++) {
        for (var y = 0; y + 1 < b.length && !hit; y++) {
          if (segsCross(a[x], a[x + 1], b[y], b[y + 1])) hit = true;
        }
      }
      if (hit) n++;
    }
  }
  return n;
}

double _aspect(Iterable<_R> rs) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final r in rs) {
    minX = r.x < minX ? r.x : minX;
    minY = r.y < minY ? r.y : minY;
    maxX = r.x + r.w > maxX ? r.x + r.w : maxX;
    maxY = r.y + r.h > maxY ? r.y + r.h : maxY;
  }
  final h = maxY - minY;
  return h == 0 ? 0 : (maxX - minX) / h;
}

List<String> _leafIds(Map<String, dynamic> graph) {
  final out = <String>[];
  void walk(Object? children) {
    if (children is! List) return;
    for (final c in children) {
      if (c is! Map) continue;
      final kids = c['children'];
      if (kids is List && kids.isNotEmpty) {
        walk(kids);
      } else {
        out.add(c['id'].toString());
      }
    }
  }

  walk(graph['children']);
  return out;
}

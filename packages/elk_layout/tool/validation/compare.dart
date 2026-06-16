// Compares the elk_layout Dart port against real elkjs on the shared graph
// set. Run from the package root (after `cd tool/validation && npm install &&
// node run_elkjs.mjs`):
//
//   dart run tool/validation/compare.dart
//
// Exact coordinates will never match (different implementations), so this
// scores STRUCTURAL agreement: do both engines agree on the relative ordering
// of nodes along the flow axis (layering) and across it (within-layer order),
// do neither overlap, and are the aspect ratios comparable?
import 'dart:convert';
import 'dart:io';

import 'package:elk_layout/elk_layout.dart';

void main() {
  final dir = File(Platform.script.toFilePath()).parent.path;
  final cases = (jsonDecode(File('$dir/graphs.json').readAsStringSync())
      as List).cast<Map<String, dynamic>>();
  final elkjsFile = File('$dir/elkjs_golden.json');
  if (!elkjsFile.existsSync()) {
    stderr.writeln('Missing elkjs_golden.json — run `cd $dir && npm install && '
        'node run_elkjs.mjs` first.');
    exit(1);
  }
  final elkjs = (jsonDecode(elkjsFile.readAsStringSync()) as Map)
      .cast<String, dynamic>();

  final outDir = Directory('$dir/output')..createSync(recursive: true);

  print('Structural agreement: elk_layout (Dart) vs elkjs 0.9.3\n');
  print('${'graph'.padRight(26)}  flow-order  cross-order  '
      'overlaps(us/elk)  aspect(us/elk)');
  print('-' * 92);

  var flowSum = 0.0, crossSum = 0.0, n = 0;
  for (final c in cases) {
    final name = c['name'] as String;
    final graphJson = (c['graph'] as Map).cast<String, dynamic>();
    final vertical = '${(graphJson['layoutOptions'] as Map?)?['elk.direction']}'
            .toUpperCase() !=
        'RIGHT' &&
        '${(graphJson['layoutOptions'] as Map?)?['elk.direction']}'
                .toUpperCase() !=
            'LEFT';

    // Our layout.
    final res = const ElkLayered().layout(ElkGraph.fromJson(graphJson));
    final ours = <String, _R>{};
    res.nodesById.forEach((id, p) =>
        ours[id] = _R(p.x, p.y, p.width, p.height));

    // elkjs layout (absolute rects).
    final theirsRaw = ((elkjs[name] as Map)['nodes'] as Map)
        .cast<String, dynamic>();
    final theirs = <String, _R>{
      for (final e in theirsRaw.entries)
        e.key: _R(
          (e.value['x'] as num).toDouble(),
          (e.value['y'] as num).toDouble(),
          (e.value['width'] as num).toDouble(),
          (e.value['height'] as num).toDouble(),
        ),
    };

    // Compare over leaf ids present in both (leaves = no children in JSON).
    final leafIds = _leafIds(graphJson)
        .where((id) => ours.containsKey(id) && theirs.containsKey(id))
        .toList();

    final flow = _orderAgreement(leafIds, ours, theirs, alongFlow: true, vertical: vertical);
    final cross = _orderAgreement(leafIds, ours, theirs, alongFlow: false, vertical: vertical);
    final ovUs = _overlaps(ours.values.toList());
    final ovElk = _overlaps(theirs.values.toList());
    final arUs = _aspect(ours.values);
    final arElk = _aspect(theirs.values);
    flowSum += flow;
    crossSum += cross;
    n++;

    print('${name.padRight(26)}  '
        '${_pct(flow).padRight(10)}  '
        '${_pct(cross).padRight(11)}  '
        '${'$ovUs / $ovElk'.padRight(16)}  '
        '${arUs.toStringAsFixed(2)} / ${arElk.toStringAsFixed(2)}');

    // --- Visual diff: write a side-by-side SVG (ours | elkjs). ---
    final clusterIds =
        ours.keys.where((id) => !_leafIds(graphJson).contains(id)).toSet();
    final oursEdges = [
      for (final e in res.edges)
        if (e.sections.isNotEmpty)
          [for (final p in e.sections.first.points) (p.x, p.y)],
    ];
    final elkEdges = [
      for (final e in ((elkjs[name] as Map)['edges'] as List? ?? const []))
        [for (final p in (e as List)) ((p['x'] as num).toDouble(), (p['y'] as num).toDouble())],
    ];
    final svg = _sideBySideSvg(
      ours: ours, oursEdges: oursEdges,
      theirs: theirs, theirsEdges: elkEdges,
      clusters: clusterIds,
    );
    final slug = name.replaceAll(RegExp(r'[^a-z0-9]+'), '_').toLowerCase();
    File('${outDir.path}/$slug.svg').writeAsStringSync(svg);
  }
  print('-' * 92);
  print('mean flow-order agreement:  ${_pct(flowSum / n)}');
  print('mean cross-order agreement: ${_pct(crossSum / n)}');
  print('\nflow-order = % of leaf pairs both engines order the same along the '
      'flow axis (layering).\ncross-order = same, across the flow axis '
      '(within-layer order). overlaps should be 0/0.');
  print('\nSide-by-side SVGs (ours | elkjs) written to ${outDir.path}/');
}

/// Renders both layouts side by side into one SVG: elk_layout on the left,
/// elkjs on the right, each with its own nodes + edge routes.
String _sideBySideSvg({
  required Map<String, _R> ours,
  required List<List<(double, double)>> oursEdges,
  required Map<String, _R> theirs,
  required List<List<(double, double)>> theirsEdges,
  required Set<String> clusters,
}) {
  const pad = 24.0, gap = 80.0, titleH = 28.0;
  final lw = _spanW(ours.values), lh = _spanH(ours.values);
  final rw = _spanW(theirs.values);
  final h = titleH + pad + (lh > _spanH(theirs.values) ? lh : _spanH(theirs.values)) + pad;
  final w = pad + lw + gap + rw + pad;
  final b = StringBuffer();
  b.writeln('<svg viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg" '
      'style="background:white" font-family="Inter,sans-serif">');
  b.writeln('<text x="$pad" y="18" font-size="14" font-weight="600" '
      'fill="#4a3a8a">elk_layout (ours)</text>');
  b.writeln('<text x="${pad + lw + gap}" y="18" font-size="14" '
      'font-weight="600" fill="#888">elkjs 0.9.3</text>');
  b.write(_panel(ours, oursEdges, clusters, pad, titleH));
  b.write(_panel(theirs, theirsEdges, clusters, pad + lw + gap, titleH));
  b.writeln('</svg>');
  return b.toString();
}

String _panel(Map<String, _R> nodes, List<List<(double, double)>> edges,
    Set<String> clusters, double ox, double oy) {
  // Normalize so the panel's own min is at (ox, oy).
  final minX = nodes.values.map((r) => r.x).reduce((a, b) => a < b ? a : b);
  final minY = nodes.values.map((r) => r.y).reduce((a, b) => a < b ? a : b);
  final dx = ox - minX, dy = oy - minY;
  final b = StringBuffer();
  // Clusters behind leaves.
  for (final e in nodes.entries.where((e) => clusters.contains(e.key))) {
    final r = e.value;
    b.writeln('<rect x="${r.x + dx}" y="${r.y + dy}" width="${r.w}" '
        'height="${r.h}" rx="4" fill="#eef0fb" stroke="#b9c0e8"/>');
    b.writeln('<text x="${r.x + dx + 6}" y="${r.y + dy + 14}" font-size="11" '
        'fill="#6a6a9a">${_esc(e.key)}</text>');
  }
  for (final e in nodes.entries.where((e) => !clusters.contains(e.key))) {
    final r = e.value;
    b.writeln('<rect x="${r.x + dx}" y="${r.y + dy}" width="${r.w}" '
        'height="${r.h}" rx="3" fill="#c9cef0" stroke="#5b63b0"/>');
    b.writeln('<text x="${r.x + dx + r.w / 2}" y="${r.y + dy + r.h / 2 + 4}" '
        'font-size="11" text-anchor="middle" fill="#22224a">'
        '${_esc(e.key)}</text>');
  }
  for (final poly in edges) {
    if (poly.length < 2) continue;
    final pts = poly.map((p) => '${p.$1 + dx},${p.$2 + dy}').join(' ');
    b.writeln('<polyline points="$pts" fill="none" stroke="#444" '
        'stroke-width="1.3"/>');
  }
  return b.toString();
}

double _spanW(Iterable<_R> rs) {
  final minX = rs.map((r) => r.x).reduce((a, b) => a < b ? a : b);
  final maxX = rs.map((r) => r.x + r.w).reduce((a, b) => a > b ? a : b);
  return maxX - minX;
}

double _spanH(Iterable<_R> rs) {
  final minY = rs.map((r) => r.y).reduce((a, b) => a < b ? a : b);
  final maxY = rs.map((r) => r.y + r.h).reduce((a, b) => a > b ? a : b);
  return maxY - minY;
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

class _R {
  _R(this.x, this.y, this.w, this.h);
  final double x, y, w, h;
  double get cx => x + w / 2;
  double get cy => y + h / 2;
}

/// % of unordered leaf pairs whose relative order along the chosen axis agrees
/// between the two layouts (ties within 4px ignored on either side).
double _orderAgreement(List<String> ids, Map<String, _R> a, Map<String, _R> b,
    {required bool alongFlow, required bool vertical}) {
  double coord(_R r, bool flow) =>
      (flow == vertical) ? r.cy : r.cx; // flow axis is Y when vertical
  var agree = 0, total = 0;
  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      final ai = coord(a[ids[i]]!, alongFlow), aj = coord(a[ids[j]]!, alongFlow);
      final bi = coord(b[ids[i]]!, alongFlow), bj = coord(b[ids[j]]!, alongFlow);
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
      if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h) {
        n++;
      }
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
  final h = (maxY - minY);
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

String _pct(double v) => '${(v * 100).toStringAsFixed(0)}%';

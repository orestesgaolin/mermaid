/// Treemap (`treemap-beta`): nested rectangles sized by value. Indentation
/// builds the hierarchy; leaves carry `: value`, branches sum their children.
/// Uses a squarified layout (Bruls/Huizing/van Wijk). Reference: upstream
/// treemap.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

class TreemapNode {
  TreemapNode(this.label, this.value);
  final String label;
  double value; // own value for leaves; summed for branches
  final children = <TreemapNode>[];
  bool get isLeaf => children.isEmpty;
  double get total => isLeaf ? value : children.fold(0.0, (a, c) => a + c.total);
}

class Treemap {
  const Treemap(this.roots, this.title);
  final List<TreemapNode> roots;
  final String? title;
}

Treemap parseTreemap(String source) {
  final title = frontmatterTitle(source);
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final roots = <TreemapNode>[];
  final stack = <(int, TreemapNode)>[];
  var seenHeader = false;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c);
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*treemap(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "treemap" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    final indent = line.length - line.trimLeft().length;
    final content = line.trim();
    // "Label": value   |   "Label"
    final m = RegExp(r'^"([^"]*)"\s*(?::\s*([\d.]+))?\s*$').firstMatch(content) ??
        RegExp(r'^([^:]+?)\s*(?::\s*([\d.]+))?\s*$').firstMatch(content);
    if (m == null) continue;
    final label = m.group(1)!.trim();
    final value = m.group(2) != null ? double.parse(m.group(2)!) : 0.0;
    final node = TreemapNode(label, value);
    while (stack.isNotEmpty && indent <= stack.last.$1) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.$2.children.add(node);
    }
    stack.add((indent, node));
  }
  if (!seenHeader) throw const MermaidParseException('empty treemap source');
  return Treemap(roots, title);
}

const _palette = <Color>[
  Color(0xff5b8ff9),
  Color(0xff61ddaa),
  Color(0xff65789b),
  Color(0xfff6bd16),
  Color(0xff7262fd),
  Color(0xff78d3f8),
  Color(0xff9661bc),
  Color(0xfff6903d),
  Color(0xff008685),
  Color(0xfff08bb4),
];

RenderScene layoutTreemap(
  Treemap map, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.85);
  final nodes = <SceneNode>[];
  const w = 720.0, h = 460.0;
  var titleH = 0.0;
  if (map.title != null && map.title!.isNotEmpty) titleH = 30;

  // A synthetic root holds all top-level nodes.
  final root = TreemapNode('', 0)..children.addAll(map.roots);
  var colorIndex = 0;

  // Squarified treemap (Bruls/Huizing/van Wijk): pack children into rows laid
  // out along the shorter side, choosing rows that minimize the worst aspect
  // ratio of their rectangles. Produces near-square cells instead of slices.
  List<Rect> squarify(List<TreemapNode> children, Rect rect) {
    final placed = List<Rect?>.filled(children.length, null);
    final totalV =
        children.fold(0.0, (a, c) => a + math.max(c.total, 0.0001));
    final area = math.max(rect.width, 0.0) * math.max(rect.height, 0.0);
    if (area <= 0 || totalV <= 0) {
      return [for (var i = 0; i < children.length; i++) Rect.fromLTWH(rect.left, rect.top, 0, 0)];
    }
    // Scale each child's value to an area in the rect.
    final areas = [
      for (final c in children) math.max(c.total, 0.0001) / totalV * area
    ];

    // Worst aspect ratio for a row of given areas laid along length `length`.
    double worst(List<double> row, double length) {
      if (row.isEmpty) return double.infinity;
      var sum = 0.0, maxA = 0.0, minA = double.infinity;
      for (final a in row) {
        sum += a;
        if (a > maxA) maxA = a;
        if (a < minA) minA = a;
      }
      final s2 = sum * sum;
      final l2 = length * length;
      return math.max(l2 * maxA / s2, s2 / (l2 * minA));
    }

    // Free sub-rectangle we are filling, advances as rows are committed.
    var x = rect.left, y = rect.top, w = rect.width, hgt = rect.height;
    var index = 0;

    // Lay a finished row across the shorter side of the free rect, then shrink.
    void commitRow(List<int> rowIdx, List<double> rowAreas) {
      final rowSum = rowAreas.fold(0.0, (a, b) => a + b);
      if (w >= hgt) {
        // Vertical row occupying a column of width `rw` on the left.
        final rw = rowSum / hgt;
        var cy = y;
        for (var k = 0; k < rowIdx.length; k++) {
          final ch = rowAreas[k] / rowSum * hgt;
          placed[rowIdx[k]] = Rect.fromLTWH(x, cy, rw, ch);
          cy += ch;
        }
        x += rw;
        w -= rw;
      } else {
        // Horizontal row occupying a strip of height `rh` on the top.
        final rh = rowSum / w;
        var cx = x;
        for (var k = 0; k < rowIdx.length; k++) {
          final cw = rowAreas[k] / rowSum * w;
          placed[rowIdx[k]] = Rect.fromLTWH(cx, y, cw, rh);
          cx += cw;
        }
        y += rh;
        hgt -= rh;
      }
    }

    while (index < areas.length) {
      final shortest = math.min(w, hgt);
      final rowIdx = <int>[index];
      final rowAreas = <double>[areas[index]];
      var i = index + 1;
      while (i < areas.length) {
        final cur = worst(rowAreas, shortest);
        final next = worst([...rowAreas, areas[i]], shortest);
        if (next > cur) break;
        rowAreas.add(areas[i]);
        rowIdx.add(i);
        i++;
      }
      commitRow(rowIdx, rowAreas);
      index = i;
    }

    return [for (final r in placed) r ?? Rect.fromLTWH(rect.left, rect.top, 0, 0)];
  }

    // [groupColor] is the top-level group's base hue; leaves share it
    // (lightened), like upstream which colors a section and tints its leaves.
    void layout(TreemapNode node, Rect rect, int depth, Color? groupColor) {
    final kids = node.children;
    if (kids.isEmpty) return;
    final rects = squarify(kids, rect);
    for (var ki = 0; ki < kids.length; ki++) {
      final child = kids[ki];
      // Top-level children seed a group color; descendants inherit it.
      final color = groupColor ?? _palette[colorIndex++ % _palette.length];
      final cellRect = rects[ki];

      if (child.isLeaf) {
        final fill = _lighten(color, 0.45);
        final r = Rect.fromLTWH(cellRect.left + 1, cellRect.top + 1,
            math.max(0, cellRect.width - 2), math.max(0, cellRect.height - 2));
        nodes.add(SceneShape(
          geometry: RectGeometry(r, rx: 2, ry: 2),
          fill: Fill(fill),
          stroke: Stroke(color: theme.background, width: 1),
        ));
        final ts = measurer.measure(child.label, baseStyle, maxWidth: r.width);
        if (r.width > ts.width * 0.6 && r.height > 24) {
          // Name (bold) + value, centered like upstream.
          nodes.add(SceneText(
            text: '${child.label}\n${_fmt(child.value)}',
            bounds: Rect.fromLTWH(r.left + 2, r.center.y - 16,
                math.max(0, r.width - 4), 32),
            style: baseStyle.copyWith(fontWeight: 700),
            color: const Color(0xff1f1f1f),
          ));
        }
      } else {
        // Branch: a coloured header strip in the group hue + recurse below.
        const head = 20.0;
        if (cellRect.height > head + 6 && cellRect.width > 20) {
          nodes.add(SceneShape(
            geometry: RectGeometry(Rect.fromLTWH(cellRect.left + 1,
                cellRect.top + 1, math.max(0, cellRect.width - 2), head)),
            fill: Fill(color),
          ));
          nodes.add(SceneText(
            text: child.label,
            bounds: Rect.fromLTWH(cellRect.left + 6, cellRect.top + 3,
                math.max(0, cellRect.width - 12), 14),
            style: baseStyle.copyWith(fontWeight: 700),
            color: const Color(0xffffffff),
            align: TextAlignH.left,
          ));
          layout(
              child,
              Rect.fromLTWH(cellRect.left + 2, cellRect.top + head,
                  math.max(0, cellRect.width - 4),
                  math.max(0, cellRect.height - head - 2)),
              depth + 1,
              color);
        } else {
          layout(child, cellRect, depth + 1, color);
        }
      }
    }
  }

  layout(root, Rect.fromLTWH(0, titleH, w, h), 0, null);

  if (titleH > 0) {
    final ts = measurer.measure(map.title!, baseStyle.copyWith(fontWeight: 700));
    nodes.add(SceneText(
      text: map.title!,
      bounds: Rect.fromLTWH(w / 2 - ts.width / 2, 4, ts.width, ts.height),
      style: baseStyle.copyWith(fontWeight: 700),
      color: theme.titleColor,
    ));
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, w, h);
  const m = 12.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final n in nodes) translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// Mixes [c] toward white by [amount] (0..1).
Color _lighten(Color c, double amount) => Color.fromARGB(
      255,
      (c.red + (255 - c.red) * amount).round(),
      (c.green + (255 - c.green) * amount).round(),
      (c.blue + (255 - c.blue) * amount).round(),
    );

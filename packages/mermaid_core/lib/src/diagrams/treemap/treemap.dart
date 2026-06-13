/// Treemap (`treemap-beta`): nested rectangles sized by value. Indentation
/// builds the hierarchy; leaves carry `: value`, branches sum their children.
/// Uses a squarified-ish slice layout. Reference: upstream treemap.
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

  void layout(TreemapNode node, Rect rect, int depth) {
    final kids = node.children;
    if (kids.isEmpty) return;
    final totalV = kids.fold(0.0, (a, c) => a + math.max(c.total, 0.0001));
    // Slice-and-dice alternating by depth.
    final horizontal = depth.isEven;
    var offset = horizontal ? rect.left : rect.top;
    for (final child in kids) {
      final frac = math.max(child.total, 0.0001) / totalV;
      final cellRect = horizontal
          ? Rect.fromLTWH(offset, rect.top, frac * rect.width, rect.height)
          : Rect.fromLTWH(rect.left, offset, rect.width, frac * rect.height);
      offset += horizontal ? frac * rect.width : frac * rect.height;

      if (child.isLeaf) {
        final color = _palette[colorIndex++ % _palette.length];
        final r = Rect.fromLTWH(cellRect.left + 1, cellRect.top + 1,
            math.max(0, cellRect.width - 2), math.max(0, cellRect.height - 2));
        nodes.add(SceneShape(
          geometry: RectGeometry(r, rx: 2, ry: 2),
          fill: Fill(color),
          stroke: Stroke(color: theme.background, width: 1),
        ));
        final text = '${child.label}\n${_fmt(child.value)}';
        final ts = measurer.measure(child.label, baseStyle, maxWidth: r.width);
        if (r.width > ts.width * 0.6 && r.height > 24) {
          nodes.add(SceneText(
            text: text,
            bounds: Rect.fromLTWH(r.left + 4, r.top + 4,
                math.max(0, r.width - 8), math.min(r.height - 8, 40)),
            style: baseStyle,
            color: const Color(0xffffffff),
            align: TextAlignH.left,
          ));
        }
      } else {
        // Branch: a header strip + recurse into the remaining area.
        const head = 18.0;
        if (cellRect.height > head + 6 && cellRect.width > 20) {
          nodes.add(SceneText(
            text: child.label,
            bounds: Rect.fromLTWH(cellRect.left + 4, cellRect.top + 2,
                math.max(0, cellRect.width - 8), 14),
            style: baseStyle.copyWith(fontWeight: 700),
            color: theme.textColor,
            align: TextAlignH.left,
          ));
          layout(
              child,
              Rect.fromLTWH(cellRect.left + 2, cellRect.top + head,
                  math.max(0, cellRect.width - 4),
                  math.max(0, cellRect.height - head - 2)),
              depth + 1);
        } else {
          layout(child, cellRect, depth + 1);
        }
      }
    }
  }

  layout(root, Rect.fromLTWH(0, titleH, w, h), 0);

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

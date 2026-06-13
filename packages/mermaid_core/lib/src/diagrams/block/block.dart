/// Block diagram (`block-beta`): a column-grid of blocks (with spans and
/// nested groups) plus flowchart-style edges. Reference: upstream block db /
/// blockRenderer. Layout gives the author explicit control via `columns`,
/// so this is a row-major grid fill rather than an automatic graph layout.
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

enum BlockShape { rect, rounded, stadium, circle, diamond, cylinder, space }

sealed class BlockItem {
  const BlockItem();
  int get span;
}

class BlockNode extends BlockItem {
  BlockNode(this.id, this.label, this.shape, this.span, this.styles);
  final String id;
  final String label;
  final BlockShape shape;
  @override
  final int span;
  Map<String, String> styles;
}

class BlockGroup extends BlockItem {
  BlockGroup(this.id, this.label, this.span, this.columns, this.children);
  final String id;
  final String label;
  @override
  final int span;
  int columns; // -1 = auto; set by a `columns N` line inside the group
  final List<BlockItem> children;
}

class BlockEdge {
  const BlockEdge(this.from, this.to, this.label, this.arrowTo, this.arrowFrom);
  final String from;
  final String to;
  final String label;
  final bool arrowTo;
  final bool arrowFrom;
}

class BlockDiagram {
  const BlockDiagram(this.root, this.columns, this.edges);
  final List<BlockItem> root;
  final int columns;
  final List<BlockEdge> edges;
}

BlockDiagram parseBlock(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final edges = <BlockEdge>[];
  // Scope stack; root has a null group. `columns N` sets the current group's
  // columns (or rootColumns at the top level).
  final scopes = <({List<BlockItem> items, BlockGroup? group})>[
    (items: [], group: null)
  ];
  var rootColumns = -1;
  final styleById = <String, Map<String, String>>{};
  final allNodes = <String, BlockNode>{};
  var seenHeader = false;

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^block(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "block" header', line: i + 1);
      }
      seenHeader = true;
      final rest = line.replaceFirst(RegExp(r'^block(-beta)?\s*'), '');
      if (rest.trim().isEmpty) continue;
      line = rest.trim();
    }

    if (line == 'end') {
      if (scopes.length > 1) scopes.removeLast();
      continue;
    }
    final colM = RegExp(r'^columns\s+(-?\d+)$').firstMatch(line);
    if (colM != null) {
      final n = int.parse(colM.group(1)!);
      if (scopes.last.group != null) {
        scopes.last.group!.columns = n;
      } else {
        rootColumns = n;
      }
      continue;
    }
    // style id k:v,...
    final styleM = RegExp(r'^style\s+(\S+)\s+(.+)$').firstMatch(line);
    if (styleM != null) {
      styleById[styleM.group(1)!] = _parseStyles(styleM.group(2)!);
      continue;
    }
    // Edge: A --> B, A -- "label" --> B (kept simple).
    if (RegExp(r'(?<![<>-])--+>|<--+(?![->])|--+').hasMatch(line) &&
        line.contains(RegExp(r'-->|---|<--'))) {
      _parseEdges(line, edges);
      continue;
    }
    // block:id[:span] [columns N] — opens a group.
    final grpM = RegExp(r'^block:([^\s:]+)(?::(\d+))?\s*$').firstMatch(line);
    if (grpM != null) {
      final group = BlockGroup(grpM.group(1)!, '', int.parse(grpM.group(2) ?? '1'),
          -1, []);
      scopes.last.items.add(group);
      scopes.add((items: group.children, group: group));
      continue;
    }
    // Anonymous nested block: `block` then children until end.
    if (line == 'block') {
      final group = BlockGroup('', '', 1, -1, []);
      scopes.last.items.add(group);
      scopes.add((items: group.children, group: group));
      continue;
    }
    // Otherwise: one or more block specs on the line.
    for (final spec in _tokenizeBlocks(line)) {
      final node = _parseNode(spec);
      scopes.last.items.add(node);
      if (node.shape != BlockShape.space) allNodes[node.id] = node;
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty block source');

  // Apply styles.
  styleById.forEach((id, st) {
    allNodes[id]?.styles = st;
  });

  return BlockDiagram(scopes.first.items, rootColumns, edges);
}

/// Splits a line into block specs, respecting bracket/quote groups.
List<String> _tokenizeBlocks(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var inQuote = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') inQuote = !inQuote;
    if (!inQuote) {
      if ('([{'.contains(ch)) depth++;
      if (')]}'.contains(ch)) depth--;
      if (ch == ' ' && depth <= 0) {
        if (buf.isNotEmpty) out.add(buf.toString());
        buf.clear();
        continue;
      }
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

BlockNode _parseNode(String spec) {
  // optional :span suffix (outside brackets)
  var span = 1;
  final spanM = RegExp(r':(\d+)$').firstMatch(spec);
  if (spanM != null && !spec.substring(0, spanM.start).endsWith('"')) {
    span = int.parse(spanM.group(1)!);
    spec = spec.substring(0, spanM.start);
  }
  if (spec == 'space') return BlockNode('', '', BlockShape.space, span, {});
  final m = RegExp(r'^([^\s([{]+)\s*'
          r'(\(\(|\(\[|\[\(|\(|\[|\{)(.*?)(\)\)|\]\)|\)\]|\)|\]|\})?\s*$')
      .firstMatch(spec);
  if (m == null) {
    return BlockNode(spec, spec, BlockShape.rect, span, {});
  }
  final id = m.group(1)!;
  final open = m.group(2);
  var label = (m.group(3) ?? '').trim();
  if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
    label = label.substring(1, label.length - 1);
  }
  if (label.isEmpty) label = id;
  final shape = switch (open) {
    '((' => BlockShape.circle,
    '([' => BlockShape.stadium,
    '[(' => BlockShape.cylinder,
    '(' => BlockShape.rounded,
    '{' => BlockShape.diamond,
    _ => BlockShape.rect,
  };
  return BlockNode(id, label, shape, span, {});
}

void _parseEdges(String line, List<BlockEdge> edges) {
  // Token walk over `A --> B --> C` (edge operators are whitespace-separated).
  final tokens = line.split(RegExp(r'\s+'));
  String? prev;
  String? op;
  for (final tok in tokens) {
    if (RegExp(r'^<?-{2,}>?$').hasMatch(tok)) {
      op = tok;
      continue;
    }
    final id = tok.replaceAll(RegExp(r'["\[\](){}]'), '');
    if (id.isEmpty) continue;
    if (prev != null && op != null) {
      edges.add(
          BlockEdge(prev, id, '', op.endsWith('>'), op.startsWith('<')));
    }
    prev = id;
    op = null;
  }
}

Map<String, String> _parseStyles(String s) {
  final out = <String, String>{};
  for (final pair in s.split(',')) {
    final i = pair.indexOf(':');
    if (i > 0) out[pair.substring(0, i).trim()] = pair.substring(i + 1).trim();
  }
  return out;
}

// --- layout ----------------------------------------------------------------

const _cellGap = 8.0;
const _pad = 14.0;

class _Sized {
  _Sized(this.item, this.width, this.height, [this.childLayout]);
  final BlockItem item;
  double width;
  double height;
  final _GridLayout? childLayout;
  Point center = Point.zero;
}

class _GridLayout {
  _GridLayout(this.cells, this.width, this.height);
  final List<_Sized> cells;
  final double width;
  final double height;
}

RenderScene layoutBlock(
  BlockDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final centers = <String, Point>{};
  final sizes = <String, _Sized>{};

  _Sized measure(BlockItem item) {
    if (item is BlockGroup) {
      final grid = _layoutGrid(item.children, item.columns, measure);
      final s = _Sized(item, grid.width + 2 * _pad,
          grid.height + 2 * _pad + (item.label.isEmpty ? 0 : 16), grid);
      return s;
    }
    final n = item as BlockNode;
    if (n.shape == BlockShape.space) return _Sized(item, 60, 40);
    final ls = measurer.measure(n.label, baseStyle, maxWidth: 200);
    final w = n.shape == BlockShape.circle || n.shape == BlockShape.diamond
        ? math.max(ls.width, ls.height) + 40
        : ls.width + 2 * _pad;
    final h = n.shape == BlockShape.circle || n.shape == BlockShape.diamond
        ? math.max(ls.width, ls.height) + 40
        : ls.height + 2 * _pad;
    return _Sized(item, w, h);
  }

  final root = _layoutGrid(diagram.root, diagram.columns, measure);

  final nodes = <SceneNode>[];
  void place(_GridLayout grid, double ox, double oy) {
    for (final s in grid.cells) {
      final cx = ox + s.center.x;
      final cy = oy + s.center.y;
      final item = s.item;
      if (item is BlockGroup) {
        final rect = Rect.fromCenter(Point(cx, cy), s.width, s.height);
        nodes.add(SceneShape(
          geometry: RectGeometry(rect, rx: 6, ry: 6),
          fill: Fill(theme.clusterBkg),
          stroke: Stroke(color: theme.clusterBorder),
        ));
        if (item.label.isNotEmpty) {
          final ls = measurer.measure(item.label, baseStyle);
          nodes.add(SceneText(
            text: item.label,
            bounds: Rect.fromLTWH(
                cx - ls.width / 2, rect.top + 4, ls.width, ls.height),
            style: baseStyle,
            color: theme.textColor,
          ));
        }
        place(s.childLayout!, rect.left + _pad,
            rect.top + _pad + (item.label.isEmpty ? 0 : 16));
      } else {
        final n = item as BlockNode;
        if (n.shape == BlockShape.space) continue;
        centers[n.id] = Point(cx, cy);
        sizes[n.id] = s..center = Point(cx, cy);
        nodes.addAll(_drawNode(n, Point(cx, cy), s.width, s.height,
            measurer, baseStyle, theme));
      }
    }
  }

  place(root, 0, 0);

  // Edges (straight, clipped to rects).
  for (final e in diagram.edges) {
    final a = centers[e.from], b = centers[e.to];
    if (a == null || b == null) continue;
    final sa = sizes[e.from], sb = sizes[e.to];
    final from = sa != null ? _clip(a, sa.width, sa.height, b) : a;
    final to = sb != null ? _clip(b, sb.width, sb.height, a) : b;
    final dir = _unit(from, to);
    final end = e.arrowTo ? to - dir * 8 : to;
    nodes.add(SceneShape(
      geometry: PathGeometry([MoveTo(from), LineTo(end)]),
      stroke: Stroke(color: theme.lineColor, width: 1.5),
    ));
    if (e.arrowTo) nodes.addAll(_arrow(to, dir, theme.lineColor));
    if (e.arrowFrom) nodes.addAll(_arrow(from, _unit(to, from), theme.lineColor));
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  const m = 16.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, m - bounds.left, m - bounds.top)],
  );
}

/// Row-major grid fill. [columns] -1 ⇒ one row of all items.
_GridLayout _layoutGrid(
    List<BlockItem> items, int columns, _Sized Function(BlockItem) measure) {
  final sized = [for (final it in items) measure(it)];
  final cols = columns > 0 ? columns : math.max(1, sized.fold(0, (a, s) => a + s.item.span));
  // Column width = max single-cell width across items (item width / span).
  var cellW = 40.0;
  var rowH = 30.0;
  for (final s in sized) {
    cellW = math.max(cellW, s.width / s.item.span);
    rowH = math.max(rowH, s.height);
  }
  // Place row by row.
  var col = 0;
  var x = 0.0;
  var y = 0.0;
  var maxX = 0.0;
  // Per-row height (allow tall groups).
  final rows = <List<_Sized>>[[]];
  for (final s in sized) {
    if (col + s.item.span > cols && col > 0) {
      rows.add([]);
      col = 0;
    }
    rows.last.add(s);
    col += s.item.span;
  }
  for (final row in rows) {
    var rx = 0.0;
    final rh = row.fold(rowH, (a, s) => math.max(a, s.height));
    col = 0;
    for (final s in row) {
      final spanW = s.item.span * cellW + (s.item.span - 1) * _cellGap;
      s.center = Point(rx + spanW / 2, y + rh / 2);
      rx += spanW + _cellGap;
      col += s.item.span;
    }
    maxX = math.max(maxX, rx - _cellGap);
    y += rh + _cellGap;
  }
  x = maxX;
  return _GridLayout(sized, x, y - _cellGap);
}

List<SceneNode> _drawNode(BlockNode n, Point c, double w, double h,
    TextMeasurer measurer, TextStyleSpec style, MermaidTheme theme) {
  final fill = Color.tryParse(n.styles['fill'] ?? '') ?? theme.mainBkg;
  final stroke = Color.tryParse(n.styles['stroke'] ?? '') ?? theme.nodeBorder;
  final rect = Rect.fromCenter(c, w, h);
  final st = Stroke(color: stroke, width: 1);
  final shape = switch (n.shape) {
    BlockShape.circle =>
      SceneShape(geometry: CircleGeometry(c, w / 2), fill: Fill(fill), stroke: st),
    BlockShape.stadium => SceneShape(
        geometry: RectGeometry(rect, rx: h / 2, ry: h / 2),
        fill: Fill(fill),
        stroke: st),
    BlockShape.rounded =>
      SceneShape(geometry: RectGeometry(rect, rx: 6, ry: 6), fill: Fill(fill), stroke: st),
    BlockShape.diamond => SceneShape(
        geometry: PolygonGeometry([
          Point(c.x, rect.top),
          Point(rect.right, c.y),
          Point(c.x, rect.bottom),
          Point(rect.left, c.y),
        ]),
        fill: Fill(fill),
        stroke: st),
    BlockShape.cylinder => SceneShape(
        geometry: RectGeometry(rect, rx: 8, ry: 8), fill: Fill(fill), stroke: st),
    _ => SceneShape(geometry: RectGeometry(rect), fill: Fill(fill), stroke: st),
  };
  final ls = measurer.measure(n.label, style, maxWidth: 200);
  return [
    SceneGroup(id: n.id, semanticLabel: n.label, children: [
      shape,
      SceneText(
        text: n.label,
        bounds: Rect.fromCenter(c, ls.width, ls.height),
        style: style,
        color: Color.tryParse(n.styles['color'] ?? '') ?? theme.textColor,
      ),
    ]),
  ];
}

Point _clip(Point c, double w, double h, Point toward) {
  final dx = toward.x - c.x, dy = toward.y - c.y;
  if (dx == 0 && dy == 0) return c;
  final hw = w / 2, hh = h / 2;
  double sx, sy;
  if (dy.abs() * hw > dx.abs() * hh) {
    sy = dy < 0 ? -hh : hh;
    sx = dx * sy / dy;
  } else {
    sx = dx < 0 ? -hw : hw;
    sy = dy * sx / dx;
  }
  return Point(c.x + sx, c.y + sy);
}

Point _unit(Point a, Point b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final len = math.sqrt(dx * dx + dy * dy);
  return len == 0 ? const Point(1, 0) : Point(dx / len, dy / len);
}

List<SceneNode> _arrow(Point tip, Point dir, Color color) {
  final perp = Point(-dir.y, dir.x);
  return [
    SceneShape(
      geometry: PolygonGeometry(
          [tip, tip - dir * 9 + perp * 4, tip - dir * 9 - perp * 4]),
      fill: Fill(color),
    ),
  ];
}

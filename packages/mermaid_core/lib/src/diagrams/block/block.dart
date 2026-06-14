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

enum BlockShape {
  rect,
  rounded,
  stadium,
  circle,
  diamond,
  cylinder,
  space,
  blockArrow,
}

/// Directions a block arrow can point. A set is used so `(left, right)` /
/// `(x)` (= left+right) / `(y)` (= up+down) can point both ways.
enum BlockArrowDir { left, right, up, down }

sealed class BlockItem {
  const BlockItem();
  int get span;
}

class BlockNode extends BlockItem {
  BlockNode(this.id, this.label, this.shape, this.span, this.styles,
      {this.arrowDirs = const {}});
  final String id;
  final String label;
  final BlockShape shape;
  @override
  final int span;
  Map<String, String> styles;

  /// For [BlockShape.blockArrow]: the direction(s) the arrow points.
  final Set<BlockArrowDir> arrowDirs;
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
  // Block arrow: id<["label"]>(dir[, dir]) — a fat arrow polygon.
  final arrowM =
      RegExp(r'^([^\s<]+)<\[(.*?)\]>\(([^)]*)\)$').firstMatch(spec);
  if (arrowM != null) {
    final id = arrowM.group(1)!;
    var label = arrowM.group(2)!.trim();
    if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
      label = label.substring(1, label.length - 1);
    }
    label = label.replaceAll('&nbsp;', ' ').trim();
    final dirs = <BlockArrowDir>{};
    for (final d in arrowM.group(3)!.split(',')) {
      switch (d.trim().toLowerCase()) {
        case 'left':
          dirs.add(BlockArrowDir.left);
        case 'right':
          dirs.add(BlockArrowDir.right);
        case 'up':
          dirs.add(BlockArrowDir.up);
        case 'down':
          dirs.add(BlockArrowDir.down);
        case 'x':
          dirs..add(BlockArrowDir.left)..add(BlockArrowDir.right);
        case 'y':
          dirs..add(BlockArrowDir.up)..add(BlockArrowDir.down);
      }
    }
    if (dirs.isEmpty) dirs.add(BlockArrowDir.right);
    return BlockNode(id, label, BlockShape.blockArrow, span, {},
        arrowDirs: dirs);
  }
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
  // Each segment is `<id> <link> <id>` where <link> may carry a label, in
  // either `A-- "x" -->B` / `A -- x --> B` (split arrow) or `A-->|x|B`
  // (piped) form. We walk match-by-match so chains `A-->B-->C` work and the
  // tail of one edge is reused as the head of the next.
  // link forms:
  //   --> --- <-->  (no label)
  //   -- label -->  /  -- label ---  (label between two halves)
  //   -->|label|    (piped label)
  // Split on link operators while capturing the operator + label.
  final ids = <String>[];
  final ops = <({bool to, bool from, String label})>[];
  var pos = 0;
  final whole = line;
  // Find link operators (the dashes). A link operator always contains `--`.
  final dashRe = RegExp(r'-{2,}>?|<?-{2,}>?');
  while (pos < whole.length) {
    final m = dashRe.firstMatch(whole.substring(pos));
    if (m == null) {
      final tail = whole.substring(pos).trim();
      if (tail.isNotEmpty) ids.add(_cleanEdgeId(tail));
      break;
    }
    final start = pos + m.start;
    final head = whole.substring(pos, start).trim();
    // Determine if this is a two-part link (label between halves) by scanning
    // forward: `--` [label] `-->` . We greedily consume a following dash run.
    var opStr = m.group(0)!;
    var after = pos + m.end;
    var label = '';
    final rest = whole.substring(after);
    // A label can sit between two halves only when this leading operator does
    // not already terminate the arrow (no `>`); otherwise `G-->H-->I` would
    // mistake the node `H` for a label.
    final openHalf = !opStr.contains('>');
    // pattern: optional `"label"` or bare label then another dash run
    final twoPart = openHalf
        ? RegExp(r'^\s*(?:"([^"]*)"|([^<>|"-][^<>|]*?))\s*(-{1,}>?)')
            .firstMatch(rest)
        : null;
    if (twoPart != null) {
      label = (twoPart.group(1) ?? twoPart.group(2) ?? '').trim();
      opStr = opStr + twoPart.group(3)!;
      after = after + twoPart.end;
    } else {
      // piped label: `-->|label|`
      final piped = RegExp(r'^\s*\|\s*(?:"([^"]*)"|([^|]*))\|').firstMatch(rest);
      if (piped != null) {
        label = (piped.group(1) ?? piped.group(2) ?? '').trim();
        after = after + piped.end;
      }
    }
    if (head.isNotEmpty) ids.add(_cleanEdgeId(head));
    ops.add((
      to: opStr.contains('>'),
      from: opStr.startsWith('<'),
      label: label.replaceAll('&nbsp;', ' ').trim(),
    ));
    pos = after;
  }

  for (var i = 0; i + 1 < ids.length; i++) {
    if (i >= ops.length) break;
    final op = ops[i];
    if (ids[i].isEmpty || ids[i + 1].isEmpty) continue;
    edges.add(BlockEdge(ids[i], ids[i + 1], op.label, op.to, op.from));
  }
}

String _cleanEdgeId(String tok) =>
    tok.split(RegExp(r'[\s"\[\](){}]')).firstWhere((s) => s.isNotEmpty,
        orElse: () => '');

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

/// Depth of a block-arrow's triangular head (how far it extends past the body).
const _arrowHead = 18.0;

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
    if (n.shape == BlockShape.blockArrow) {
      // Reserve room for the arrow head(s) on whichever axis they point.
      final horiz = n.arrowDirs.contains(BlockArrowDir.left) ||
          n.arrowDirs.contains(BlockArrowDir.right);
      final vert = n.arrowDirs.contains(BlockArrowDir.up) ||
          n.arrowDirs.contains(BlockArrowDir.down);
      final w =
          math.max(ls.width + 2 * _pad, 60.0) + (horiz ? 2 * _arrowHead : 0);
      final h =
          math.max(ls.height + 2 * _pad, 40.0) + (vert ? 2 * _arrowHead : 0);
      return _Sized(item, w, h);
    }
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
    // Edge label at the midpoint, on a small background chip.
    if (e.label.isNotEmpty) {
      final ls = measurer.measure(e.label, baseStyle, maxWidth: 200);
      final mid = Point((from.x + to.x) / 2, (from.y + to.y) / 2);
      const lp = 3.0;
      nodes.add(SceneShape(
        geometry: RectGeometry(
            Rect.fromCenter(mid, ls.width + 2 * lp, ls.height + 2 * lp)),
        fill: Fill(theme.edgeLabelBackground),
      ));
      nodes.add(SceneText(
        text: e.label,
        bounds: Rect.fromCenter(mid, ls.width, ls.height),
        style: baseStyle,
        color: theme.textColor,
      ));
    }
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
    BlockShape.blockArrow => SceneShape(
        geometry: PolygonGeometry(_blockArrowPoints(rect, n.arrowDirs)),
        fill: Fill(fill),
        stroke: st),
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

/// Builds the polygon for a fat block arrow filling [rect]. The body is a
/// rectangle inset by [_arrowHead] on each side that carries an arrow head; a
/// triangular point extends out to the rect edge on each of those sides. The
/// head width is half the cross-axis so the point looks like a wide arrow.
List<Point> _blockArrowPoints(Rect rect, Set<BlockArrowDir> dirs) {
  final left = dirs.contains(BlockArrowDir.left);
  final right = dirs.contains(BlockArrowDir.right);
  final up = dirs.contains(BlockArrowDir.up);
  final down = dirs.contains(BlockArrowDir.down);
  // Body edges: inset wherever there is a head.
  final bl = rect.left + (left ? _arrowHead : 0);
  final br = rect.right - (right ? _arrowHead : 0);
  final bt = rect.top + (up ? _arrowHead : 0);
  final bb = rect.bottom - (down ? _arrowHead : 0);
  final cx = (bl + br) / 2;
  final cy = (bt + bb) / 2;
  // Head half-spans (perpendicular to the point) — wider than the body wall.
  final hHalf = (bb - bt) / 2 * 0.9; // for left/right heads
  final vHalf = (br - bl) / 2 * 0.9; // for up/down heads
  final pts = <Point>[];
  // Walk the outline clockwise starting top-left of the body.
  pts.add(Point(bl, bt));
  if (up) {
    pts
      ..add(Point(cx - vHalf, bt))
      ..add(Point(cx, rect.top))
      ..add(Point(cx + vHalf, bt));
  }
  pts.add(Point(br, bt));
  if (right) {
    pts
      ..add(Point(br, cy - hHalf))
      ..add(Point(rect.right, cy))
      ..add(Point(br, cy + hHalf));
  }
  pts.add(Point(br, bb));
  if (down) {
    pts
      ..add(Point(cx + vHalf, bb))
      ..add(Point(cx, rect.bottom))
      ..add(Point(cx - vHalf, bb));
  }
  pts.add(Point(bl, bb));
  if (left) {
    pts
      ..add(Point(bl, cy + hHalf))
      ..add(Point(rect.left, cy))
      ..add(Point(bl, cy - hHalf));
  }
  return pts;
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

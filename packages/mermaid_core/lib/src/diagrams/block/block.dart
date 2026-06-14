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
  hexagon,
  subroutine,
  doubleCircle,
  ellipse,
  leanRight,
  leanLeft,
  trapezoid,
  invTrapezoid,
  odd,
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

/// Endpoint marker shapes (mirrors upstream `point`/`circle`/`cross`).
enum BlockMarker { none, point, circle, cross }

class BlockEdge {
  const BlockEdge(
    this.from,
    this.to,
    this.label,
    this.arrowTo,
    this.arrowFrom, {
    this.thick = false,
    this.dotted = false,
    this.markerTo = BlockMarker.point,
    this.markerFrom = BlockMarker.point,
  });
  final String from;
  final String to;
  final String label;
  final bool arrowTo;
  final bool arrowFrom;

  /// `==` thick link.
  final bool thick;

  /// `.-` dotted link pattern.
  final bool dotted;

  /// Marker shape at the `to`/`from` end (when [arrowTo]/[arrowFrom]).
  final BlockMarker markerTo;
  final BlockMarker markerFrom;
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
  // classDef name -> parsed styles; class id(s) -> applied class names.
  final classDefs = <String, Map<String, String>>{};
  final classByNode = <String, List<String>>{};
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
    // classDef name fill:#f96,stroke:#333,...
    final classDefM =
        RegExp(r'^classDef\s+(\S+)\s+(.+)$').firstMatch(line);
    if (classDefM != null) {
      classDefs[classDefM.group(1)!] = _parseStyles(classDefM.group(2)!);
      continue;
    }
    // class id1,id2 className
    final classM =
        RegExp(r'^class\s+([^\s]+)\s+(\S+)\s*$').firstMatch(line);
    if (classM != null) {
      final cls = classM.group(2)!;
      for (final id in classM.group(1)!.split(',')) {
        final t = id.trim();
        if (t.isEmpty) continue;
        (classByNode[t] ??= <String>[]).add(cls);
      }
      continue;
    }
    // style id k:v,...
    final styleM = RegExp(r'^style\s+(\S+)\s+(.+)$').firstMatch(line);
    if (styleM != null) {
      styleById[styleM.group(1)!] = _parseStyles(styleM.group(2)!);
      continue;
    }
    // Edge: A --> B, A -- "label" --> B, A ==> B, A -.- B, A --o B, A --x B.
    if (line.contains(RegExp(r'-->|---|<--|==|-\.|\.-|--[ox]|[ox]--'))) {
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

  // Apply class styles first (lower precedence), then inline `style` overrides.
  classByNode.forEach((id, classNames) {
    final node = allNodes[id];
    if (node == null) return;
    final merged = <String, String>{};
    for (final cls in classNames) {
      final def = classDefs[cls];
      if (def != null) merged.addAll(def);
    }
    if (merged.isNotEmpty) node.styles = {...merged, ...node.styles};
  });
  styleById.forEach((id, st) {
    final node = allNodes[id];
    if (node != null) node.styles = {...node.styles, ...st};
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
  // Opening delimiters, longest first so `(((` wins over `((` etc. The id is
  // any run of non-delimiter chars. `>` opens the `odd` (`id>label]`) shape.
  final m = RegExp(r'^([^\s([{>]+)\s*'
          r'(\(\(\(|\(\(|\(\[|\[\(|\{\{|\[\[|\[/|\[\\|\(|\[|\{|>)'
          r'(.*?)'
          r'(\)\)\)|\)\)|\]\)|\)\]|\}\}|\]\]|/\]|\\\]|\)|\]|\})?\s*$')
      .firstMatch(spec);
  if (m == null) {
    return BlockNode(spec, spec, BlockShape.rect, span, {});
  }
  final id = m.group(1)!;
  final open = m.group(2);
  final close = m.group(3) != null ? (m.group(4) ?? '') : '';
  var label = (m.group(3) ?? '').trim();
  if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
    label = label.substring(1, label.length - 1);
  }
  if (label.isEmpty) label = id;
  // Mirror upstream `typeStr2Type` keyed on the open+close delimiter pair.
  final shape = switch (open) {
    '(((' => BlockShape.doubleCircle,
    '((' => BlockShape.circle,
    '([' => BlockShape.stadium,
    '[(' => BlockShape.cylinder,
    '{{' => BlockShape.hexagon,
    '[[' => BlockShape.subroutine,
    '[/' => close == r'\]' ? BlockShape.trapezoid : BlockShape.leanRight,
    '[\\' => close == '/]' ? BlockShape.invTrapezoid : BlockShape.leanLeft,
    '(' => BlockShape.rounded,
    '{' => BlockShape.diamond,
    '>' => BlockShape.odd,
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
  final ops =
      <({bool to, bool from, String label, bool thick, bool dotted, BlockMarker mTo, BlockMarker mFrom})>[];
  var pos = 0;
  final whole = line;
  // A link operator: an optional leading marker (`<`/`o`/`x`), a body of
  // `-`/`=`/`.` (at least two chars), and an optional trailing marker
  // (`>`/`o`/`x`). An embedded `=` => thick, an embedded `.` => dotted.
  final dashRe = RegExp(r'[<ox]?[-=][-=.]*[-=](?:[>ox])?');
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
    // forward: `--` [label] `-->` . We greedily consume a following link body.
    var opStr = m.group(0)!;
    var after = pos + m.end;
    var label = '';
    final rest = whole.substring(after);
    // A label can sit between two halves only when this leading operator does
    // not already terminate the arrow (no trailing marker); otherwise
    // `G-->H-->I` would mistake the node `H` for a label.
    final openHalf = !RegExp(r'[>ox]$').hasMatch(opStr);
    // pattern: optional `"label"` or bare label then another link body
    final twoPart = openHalf
        ? RegExp(r'^\s*(?:"([^"]*)"|([^<>|"=.-][^<>|]*?))\s*([-=][-=.]*(?:[>ox])?)')
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
    final lastCh = opStr.isEmpty ? '' : opStr[opStr.length - 1];
    final firstCh = opStr.isEmpty ? '' : opStr[0];
    ops.add((
      to: lastCh == '>' || lastCh == 'o' || lastCh == 'x',
      from: firstCh == '<' || firstCh == 'o' || firstCh == 'x',
      label: label.replaceAll('&nbsp;', ' ').trim(),
      thick: opStr.contains('='),
      dotted: opStr.contains('.'),
      mTo: _markerFor(lastCh),
      mFrom: _markerFor(firstCh),
    ));
    pos = after;
  }

  for (var i = 0; i + 1 < ids.length; i++) {
    if (i >= ops.length) break;
    final op = ops[i];
    if (ids[i].isEmpty || ids[i + 1].isEmpty) continue;
    edges.add(BlockEdge(
      ids[i],
      ids[i + 1],
      op.label,
      op.to,
      op.from,
      thick: op.thick,
      dotted: op.dotted,
      markerTo: op.mTo,
      markerFrom: op.mFrom,
    ));
  }
}

BlockMarker _markerFor(String ch) => switch (ch) {
      'o' => BlockMarker.circle,
      'x' => BlockMarker.cross,
      _ => BlockMarker.point,
    };

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
// Upstream layout default padding is `config.block.padding ?? 8`.
const _pad = 8.0;

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
    switch (n.shape) {
      case BlockShape.circle:
      case BlockShape.doubleCircle:
      case BlockShape.diamond:
        final s = math.max(ls.width, ls.height) + 40;
        return _Sized(item, s, s);
      case BlockShape.ellipse:
        return _Sized(item, ls.width + 4 * _pad, ls.height + 2 * _pad);
      case BlockShape.hexagon:
        // hexagon reserves m = h/4 of horizontal slant on each side.
        final h = ls.height + 2 * _pad;
        return _Sized(item, ls.width + 2 * _pad + h / 2, h);
      case BlockShape.subroutine:
        return _Sized(item, ls.width + 2 * _pad + 16, ls.height + 2 * _pad);
      case BlockShape.leanRight:
      case BlockShape.leanLeft:
      case BlockShape.trapezoid:
      case BlockShape.invTrapezoid:
        // Parallelogram/trapezoid slant adds ~h of horizontal extent.
        final h = ls.height + 2 * _pad;
        return _Sized(item, ls.width + 2 * _pad + h, h);
      case BlockShape.odd:
        return _Sized(item, ls.width + 2 * _pad + 10, ls.height + 2 * _pad);
      default:
        return _Sized(item, ls.width + 2 * _pad, ls.height + 2 * _pad);
    }
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
        // Upstream `.node .cluster` fills with fade(clusterBkg, 0.5) and
        // strokes with fade(clusterBorder, 0.2); composite rx is 0.
        nodes.add(SceneShape(
          geometry: RectGeometry(rect),
          fill: Fill(theme.clusterBkg.withOpacity(0.5)),
          stroke: Stroke(color: theme.clusterBorder.withOpacity(0.2)),
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
    // Pull the line back from a filled point head so it doesn't poke through.
    final end =
        (e.arrowTo && e.markerTo == BlockMarker.point) ? to - dir * 8 : to;
    // Upstream `.edgePath .path` stroke is 2.0px; `==` => thick (3.5px),
    // `.-` => dotted dash pattern.
    final width = e.thick ? 3.5 : 2.0;
    nodes.add(SceneShape(
      geometry: PathGeometry([MoveTo(from), LineTo(end)]),
      stroke: Stroke(
        color: theme.lineColor,
        width: width,
        dash: e.dotted ? const [3, 3] : null,
      ),
    ));
    if (e.arrowTo) {
      nodes.addAll(_marker(e.markerTo, to, dir, theme.lineColor, width));
    }
    if (e.arrowFrom) {
      nodes.addAll(
          _marker(e.markerFrom, from, _unit(to, from), theme.lineColor, width));
    }
    // Edge label at the midpoint, on a small background chip.
    if (e.label.isNotEmpty) {
      final ls = measurer.measure(e.label, baseStyle, maxWidth: 200);
      final mid = Point((from.x + to.x) / 2, (from.y + to.y) / 2);
      const lp = 3.0;
      // Upstream edge-label rect is opacity 0.5.
      nodes.add(SceneShape(
        geometry: RectGeometry(
            Rect.fromCenter(mid, ls.width + 2 * lp, ls.height + 2 * lp)),
        fill: Fill(theme.edgeLabelBackground.withOpacity(0.5)),
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
      // Upstream `setBlockSizes` equalizes every sibling leaf to the uniform
      // cell size; groups keep their own (already laid-out) extent.
      if (s.item is BlockNode) {
        s.width = spanW;
        s.height = rh;
      }
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
  final f = Fill(fill);
  final shapes = switch (n.shape) {
    BlockShape.circle =>
      [SceneShape(geometry: CircleGeometry(c, w / 2), fill: f, stroke: st)],
    BlockShape.doubleCircle => [
        SceneShape(geometry: CircleGeometry(c, w / 2), fill: f, stroke: st),
        SceneShape(
            geometry: CircleGeometry(c, math.max(w / 2 - 5, 1)),
            fill: const Fill(Color.transparent),
            stroke: st),
      ],
    BlockShape.ellipse => [
        SceneShape(
            geometry: EllipseGeometry(c, w / 2, h / 2), fill: f, stroke: st)
      ],
    BlockShape.stadium => [
        SceneShape(
            geometry: RectGeometry(rect, rx: h / 2, ry: h / 2),
            fill: f,
            stroke: st)
      ],
    BlockShape.rounded => [
        SceneShape(geometry: RectGeometry(rect, rx: 5, ry: 5), fill: f, stroke: st)
      ],
    BlockShape.diamond => [
        SceneShape(
            geometry: PolygonGeometry([
              Point(c.x, rect.top),
              Point(rect.right, c.y),
              Point(c.x, rect.bottom),
              Point(rect.left, c.y),
            ]),
            fill: f,
            stroke: st)
      ],
    BlockShape.hexagon => [
        SceneShape(
            geometry: PolygonGeometry(_hexagonPoints(rect)),
            fill: f,
            stroke: st)
      ],
    BlockShape.leanRight => [
        SceneShape(
            geometry: PolygonGeometry(_parallelogramPoints(rect, lean: true)),
            fill: f,
            stroke: st)
      ],
    BlockShape.leanLeft => [
        SceneShape(
            geometry: PolygonGeometry(_parallelogramPoints(rect, lean: false)),
            fill: f,
            stroke: st)
      ],
    BlockShape.trapezoid => [
        SceneShape(
            geometry: PolygonGeometry(_trapezoidPoints(rect, inverted: false)),
            fill: f,
            stroke: st)
      ],
    BlockShape.invTrapezoid => [
        SceneShape(
            geometry: PolygonGeometry(_trapezoidPoints(rect, inverted: true)),
            fill: f,
            stroke: st)
      ],
    BlockShape.odd => [
        SceneShape(
            geometry: PolygonGeometry(_oddPoints(rect)), fill: f, stroke: st)
      ],
    BlockShape.subroutine => _subroutineShapes(rect, f, st),
    BlockShape.cylinder => [
        SceneShape(
            geometry: PathGeometry(_cylinderPath(rect)), fill: f, stroke: st)
      ],
    BlockShape.blockArrow => [
        SceneShape(
            geometry: PolygonGeometry(_blockArrowPoints(rect, n.arrowDirs)),
            fill: f,
            stroke: st)
      ],
    _ => [SceneShape(geometry: RectGeometry(rect), fill: f, stroke: st)],
  };
  final ls = measurer.measure(n.label, style, maxWidth: 200);
  return [
    SceneGroup(id: n.id, semanticLabel: n.label, children: [
      ...shapes,
      SceneText(
        text: n.label,
        bounds: Rect.fromCenter(c, ls.width, ls.height),
        style: style,
        color: Color.tryParse(n.styles['color'] ?? '') ?? theme.textColor,
      ),
    ]),
  ];
}

/// Hexagon outline filling [rect], with a horizontal slant of `m = h/4` on
/// each side (mirrors flowchart `hexagon.ts`).
List<Point> _hexagonPoints(Rect rect) {
  final m = rect.height / 4;
  final cy = (rect.top + rect.bottom) / 2;
  return [
    Point(rect.left + m, rect.top),
    Point(rect.right - m, rect.top),
    Point(rect.right, cy),
    Point(rect.right - m, rect.bottom),
    Point(rect.left + m, rect.bottom),
    Point(rect.left, cy),
  ];
}

/// Parallelogram outline. [lean] true ⇒ `lean_right` (`[/  /]`), false ⇒
/// `lean_left` (`[\\  \\]`). The slant width equals the rect height.
List<Point> _parallelogramPoints(Rect rect, {required bool lean}) {
  final s = rect.height;
  if (lean) {
    return [
      Point(rect.left + s, rect.top),
      Point(rect.right, rect.top),
      Point(rect.right - s, rect.bottom),
      Point(rect.left, rect.bottom),
    ];
  }
  return [
    Point(rect.left, rect.top),
    Point(rect.right - s, rect.top),
    Point(rect.right, rect.bottom),
    Point(rect.left + s, rect.bottom),
  ];
}

/// Trapezoid outline. [inverted] false ⇒ `trapezoid` (`[/  \]`, wide bottom),
/// true ⇒ `inv_trapezoid` (`[\  /]`, wide top). Slant width = rect height.
List<Point> _trapezoidPoints(Rect rect, {required bool inverted}) {
  final s = rect.height;
  if (inverted) {
    return [
      Point(rect.left, rect.top),
      Point(rect.right, rect.top),
      Point(rect.right - s, rect.bottom),
      Point(rect.left + s, rect.bottom),
    ];
  }
  return [
    Point(rect.left + s, rect.top),
    Point(rect.right - s, rect.top),
    Point(rect.right, rect.bottom),
    Point(rect.left, rect.bottom),
  ];
}

/// `odd` / `rect_left_inv_arrow` (`id>label]`): a rectangle with a notch cut
/// into the left edge (depth h/4), mirrors flowchart `rectLeftInvArrow.ts`.
List<Point> _oddPoints(Rect rect) {
  final notch = rect.height / 4;
  final cy = (rect.top + rect.bottom) / 2;
  return [
    Point(rect.left, rect.top),
    Point(rect.left + notch, cy),
    Point(rect.left, rect.bottom),
    Point(rect.right, rect.bottom),
    Point(rect.right, rect.top),
  ];
}

/// Subroutine (`[[  ]]`): a rect with an extra vertical rule near each side.
List<SceneNode> _subroutineShapes(Rect rect, Fill fill, Stroke st) {
  const inset = 8.0;
  return [
    SceneShape(geometry: RectGeometry(rect), fill: fill, stroke: st),
    SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(rect.left + inset, rect.top)),
          LineTo(Point(rect.left + inset, rect.bottom)),
        ]),
        stroke: st),
    SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(rect.right - inset, rect.top)),
          LineTo(Point(rect.right - inset, rect.bottom)),
        ]),
        stroke: st),
  ];
}

/// True database cylinder filling [rect]: an elliptical cap at the top and a
/// bulged base, mirroring flowchart `cylinder.ts` bezier construction.
List<PathCommand> _cylinderPath(Rect rect) {
  const kappa = 0.5522847498;
  final rx = rect.width / 2;
  // Cap depth proportional to width, clamped so it never exceeds the body.
  final ry =
      math.min(rect.height / 4, rx / (2.5 + rect.width / 50));
  final cx = (rect.left + rect.right) / 2;
  final top = rect.top;
  final bottom = rect.bottom;
  final left = rect.left;
  final right = rect.right;
  final k = kappa;
  final topMid = top + ry;
  final bottomMid = bottom - ry;
  return [
    MoveTo(Point(left, topMid)),
    // Lower half of the top ellipse.
    CubicTo(Point(left, topMid + k * ry), Point(cx - k * rx, top + 2 * ry),
        Point(cx, top + 2 * ry)),
    CubicTo(Point(cx + k * rx, top + 2 * ry), Point(right, topMid + k * ry),
        Point(right, topMid)),
    // Upper half of the top ellipse (back to start).
    CubicTo(Point(right, topMid - k * ry), Point(cx + k * rx, top),
        Point(cx, top)),
    CubicTo(Point(cx - k * rx, top), Point(left, topMid - k * ry),
        Point(left, topMid)),
    // Left wall.
    LineTo(Point(left, bottomMid)),
    // Bottom bulge.
    CubicTo(Point(left, bottomMid + k * ry), Point(cx - k * rx, bottom),
        Point(cx, bottom)),
    CubicTo(Point(cx + k * rx, bottom), Point(right, bottomMid + k * ry),
        Point(right, bottomMid)),
    // Right wall.
    LineTo(Point(right, topMid)),
    const ClosePath(),
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

/// Endpoint marker at [tip] pointing along [dir]. Mirrors upstream
/// `insertMarkers` (`point` filled triangle, `circle`, `cross`).
List<SceneNode> _marker(
    BlockMarker marker, Point tip, Point dir, Color color, double width) {
  final perp = Point(-dir.y, dir.x);
  switch (marker) {
    case BlockMarker.circle:
      const r = 5.0;
      final c = tip - dir * r;
      return [
        SceneShape(
          geometry: CircleGeometry(c, r),
          fill: Fill(color),
          stroke: Stroke(color: color, width: width),
        ),
      ];
    case BlockMarker.cross:
      const r = 5.0;
      final c = tip - dir * r;
      final a1 = c + dir * r + perp * r;
      final a2 = c - dir * r - perp * r;
      final b1 = c + dir * r - perp * r;
      final b2 = c - dir * r + perp * r;
      return [
        SceneShape(
          geometry: PathGeometry([MoveTo(a1), LineTo(a2)]),
          stroke: Stroke(color: color, width: width),
        ),
        SceneShape(
          geometry: PathGeometry([MoveTo(b1), LineTo(b2)]),
          stroke: Stroke(color: color, width: width),
        ),
      ];
    case BlockMarker.point:
    case BlockMarker.none:
      return [
        SceneShape(
          geometry: PolygonGeometry(
              [tip, tip - dir * 9 + perp * 4, tip - dir * 9 - perp * 4]),
          fill: Fill(color),
        ),
      ];
  }
}

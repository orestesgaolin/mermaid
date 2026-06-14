/// Sankey diagram: model, parser and layout — one file.
///
/// Reference: upstream sankeyDB / sankeyRenderer (which uses d3-sankey). The
/// syntax is CSV: each line is `source,target,value` (fields may be
/// double-quoted, `""` escapes a quote). Layout is a faithful port of
/// d3-sankey: nodes are placed in columns by longest path, aligned with the
/// configured `nodeAlignment` (default `justify`, which pulls sinks to the
/// right edge), then their vertical positions are refined with iterative
/// left/right relaxation and collision resolution. Links are drawn as bezier
/// ribbons (visually identical to d3's stroked horizontal links) whose width
/// is proportional to value.
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

class SankeyLink {
  const SankeyLink(this.source, this.target, this.value);
  final String source;
  final String target;
  final double value;
}

class Sankey {
  const Sankey({required this.links, required this.nodes});
  final List<SankeyLink> links;

  /// Unique node names in first-seen order.
  final List<String> nodes;
}

Sankey parseSankey(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  var seenHeader = false;
  final links = <SankeyLink>[];
  final nodes = <String>[];
  void touch(String n) {
    if (!nodes.contains(n)) nodes.add(n);
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*sankey(-beta)?\s*$').hasMatch(line)) {
        throw MermaidParseException('expected "sankey" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    final fields = _csv(line);
    if (fields.length < 3) {
      throw MermaidParseException(
          'sankey line needs source,target,value', line: i + 1);
    }
    final value = double.tryParse(fields[2].trim());
    if (value == null) {
      throw MermaidParseException(
          'invalid sankey value "${fields[2]}"', line: i + 1);
    }
    final src = fields[0].trim();
    final tgt = fields[1].trim();
    touch(src);
    touch(tgt);
    links.add(SankeyLink(src, tgt, value));
  }
  if (!seenHeader) throw const MermaidParseException('empty sankey source');
  return Sankey(links: links, nodes: nodes);
}

/// Splits one CSV line, honoring `"`-quoted fields (`""` → literal `"`).
List<String> _csv(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString());
  return out;
}

/// Node fill palette (d3 `schemeTableau10`, cycled by node first-seen order;
/// d3 keys the ordinal scale by node id but assigns colors in encounter
/// order, which equals first-seen node order here). Links inherit a gradient
/// from their source to their target color.
const _palette = <Color>[
  Color(0xff4e79a7),
  Color(0xfff28e2c),
  Color(0xffe15759),
  Color(0xff76b7b2),
  Color(0xff59a14f),
  Color(0xffedc949),
  Color(0xffaf7aa1),
  Color(0xffff9da7),
  Color(0xff9c755f),
  Color(0xffbab0ab),
];

/// Node-alignment strategies, mirroring d3-sankey's `sankeyLeft/Right/Center/
/// Justify`. `justify` is upstream's default.
enum SankeyNodeAlignment { left, right, center, justify }

SankeyNodeAlignment _alignmentFromName(String? name) {
  switch (name) {
    case 'left':
      return SankeyNodeAlignment.left;
    case 'right':
      return SankeyNodeAlignment.right;
    case 'center':
      return SankeyNodeAlignment.center;
    case 'justify':
    default:
      return SankeyNodeAlignment.justify;
  }
}

class _Link {
  _Link(this.source, this.target, this.value);
  final _Node source;
  final _Node target;
  final double value;
  double width = 0;
  // Vertical center of the link at each endpoint.
  double y0 = 0;
  double y1 = 0;
}

class _Node {
  _Node(this.name, this.index, this.color);
  final String name;
  final int index; // first-seen order; used as a stable tie-break
  final Color color;
  int depth = 0; // distance from a source (left layer)
  int height = 0; // distance to a sink (used by justify alignment)
  int layer = 0; // resolved column index
  double value = 0;
  double x0 = 0;
  double x1 = 0;
  double y0 = 0;
  double y1 = 0;
  final sourceLinks = <_Link>[]; // links where this is the source
  final targetLinks = <_Link>[]; // links where this is the target
}

const _kSankeyIterations = 6;

RenderScene layoutSankey(
  Sankey diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
  // Upstream `SankeyDiagramConfig` defaults (config.schema.yaml). Note
  // sankeyRenderer.ts uses `height ?? defaultSankeyConfig.width`, so the
  // default canvas is square (600×600) — matching that keeps our aspect ratio
  // identical to mermaid.js so a contain-fit embed renders at the same width.
  double width = 600,
  double height = 600,
  double nodeWidth = 10,
  double nodePadding = 12,
  String nodeAlignment = 'justify',
  bool showValues = true,
  String prefix = '',
  String suffix = '',
  String labelStyle = 'legacy',
  Map<String, Color> nodeColors = const {},
}) {
  final align = _alignmentFromName(nodeAlignment);
  // d3-sankey: nodePadding(nodePadding + (showValues ? 15 : 0)).
  final py = nodePadding + (showValues ? 15.0 : 0.0);
  const labelFontSize = 14.0;
  final labelTextStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: labelFontSize);

  // Build nodes (first-seen order) and links wired to node objects.
  final nodes = <String, _Node>{};
  final nodeList = <_Node>[];
  for (var i = 0; i < diagram.nodes.length; i++) {
    final name = diagram.nodes[i];
    final color = nodeColors[name] ?? _palette[i % _palette.length];
    final n = _Node(name, i, color);
    nodes[name] = n;
    nodeList.add(n);
  }
  final links = <_Link>[];
  for (final l in diagram.links) {
    final link = _Link(nodes[l.source]!, nodes[l.target]!, l.value);
    links.add(link);
    link.source.sourceLinks.add(link);
    link.target.targetLinks.add(link);
  }

  if (nodeList.isEmpty) {
    return RenderScene(
      size: Size(width, height),
      background: theme.background,
      nodes: const [],
    );
  }

  // --- d3-sankey: computeNodeValues -------------------------------------
  for (final n in nodeList) {
    final out = n.sourceLinks.fold(0.0, (a, l) => a + l.value);
    final inc = n.targetLinks.fold(0.0, (a, l) => a + l.value);
    n.value = math.max(out, inc);
  }

  // --- d3-sankey: computeNodeDepths (BFS from sources) ------------------
  _computeNodeDepths(nodeList, (n) => n.sourceLinks.map((l) => l.target),
      (n, d) => n.depth = d);
  // computeNodeHeights (BFS from sinks)
  _computeNodeDepths(nodeList, (n) => n.targetLinks.map((l) => l.source),
      (n, d) => n.height = d);

  final maxDepth = nodeList.fold(0, (a, n) => math.max(a, n.depth));
  final maxHeight = nodeList.fold(0, (a, n) => math.max(a, n.height));
  // d3-sankey computeNodeLayers: the number of columns is `max(depth) + 1`,
  // and the horizontal scale spreads those columns across the full extent so
  // the last column's right edge lands on `width`:
  //   const x  = max(nodes, d => d.depth) + 1;
  //   const kx = (x1 - x0 - dx) / (x - 1);
  // Dividing by `columnCount - 1` (== maxDepth) makes a node placed in the
  // final column sit at `(columnCount - 1) * kx == width - nodeWidth`, so the
  // diagram occupies the full configured width — not ~half of it.
  final columnCount = maxDepth + 1;
  final kx = columnCount > 1 ? (width - nodeWidth) / (columnCount - 1) : 0.0;

  // --- d3-sankey: nodeAlign + x assignment ------------------------------
  // Clamp the resolved column into `[0, columnCount - 1]` exactly as upstream
  // (`Math.max(0, Math.min(x - 1, Math.floor(align(...))))`), so every
  // alignment (left/right/center/justify) keeps the rightmost column flush
  // with the right edge.
  for (final n in nodeList) {
    final col = _alignLayer(n, align, maxDepth, maxHeight)
        .clamp(0, columnCount - 1);
    n.layer = col;
    n.x0 = col * kx;
    n.x1 = n.x0 + nodeWidth;
  }

  // Group nodes into columns by resolved layer.
  final maxLayer = nodeList.fold(0, (a, n) => math.max(a, n.layer));
  final columns = List.generate(maxLayer + 1, (_) => <_Node>[]);
  for (final n in nodeList) {
    columns[n.layer].add(n);
  }
  // Within each column, sort by first-seen order (stable initial breadth).
  for (final col in columns) {
    col.sort((a, b) => a.index.compareTo(b.index));
  }

  // --- d3-sankey: computeNodeBreadths -----------------------------------
  // ky: largest vertical scale that fits every column inside `height`.
  var ky = double.infinity;
  for (final col in columns) {
    if (col.isEmpty) continue;
    final sumV = col.fold(0.0, (a, n) => a + n.value);
    final avail = height - (col.length - 1) * py;
    if (sumV > 0) ky = math.min(ky, avail / sumV);
  }
  if (!ky.isFinite || ky <= 0) ky = 1;

  // initializeNodeBreadths: stack each column from the top.
  for (final col in columns) {
    var y = 0.0;
    for (final n in col) {
      n.y0 = y;
      n.y1 = y + n.value * ky;
      y = n.y1 + py;
      for (final l in n.sourceLinks) {
        l.width = l.value * ky;
      }
    }
  }
  // initial computeLinkBreadths
  _computeLinkBreadths(columns);

  // Iterative relaxation, matching d3-sankey's default iteration loop:
  // alpha decays by 0.99 per pass and scales the weighted-position move.
  for (var i = 0; i < _kSankeyIterations; i++) {
    final alpha = math.pow(0.99, i).toDouble();
    _relaxRightToLeft(columns, alpha);
    _resolveCollisions(columns, height, py);
    _relaxLeftToRight(columns, alpha);
    _resolveCollisions(columns, height, py);
    _computeLinkBreadths(columns);
  }

  // --- Smart label positioning anchor (central node layer) --------------
  var centralNodeLayer = 0;
  var maxVal = 0.0;
  for (final n in nodeList) {
    if (n.value > maxVal) {
      maxVal = n.value;
      centralNodeLayer = n.layer;
    }
  }

  final ribbons = <SceneNode>[];
  final nodeShapes = <SceneNode>[];
  final labelLayer = <SceneNode>[];

  // --- Links: bezier ribbons (the filled area of a thick stroked path) ---
  for (final l in links) {
    final w = math.max(1.0, l.width);
    final half = w / 2;
    final x0 = l.source.x1;
    final x1 = l.target.x0;
    final cx = (x0 + x1) / 2;
    final sy = l.y0;
    final ty = l.y1;
    // Upstream strokes a horizontal cubic centerline at `w`; the visible band
    // is the area between the top and bottom edges of that stroke.
    ribbons.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(x0, sy - half)),
        CubicTo(Point(cx, sy - half), Point(cx, ty - half), Point(x1, ty - half)),
        LineTo(Point(x1, ty + half)),
        CubicTo(Point(cx, ty + half), Point(cx, sy + half), Point(x0, sy + half)),
        const ClosePath(),
      ]),
      // Full-opacity gradient stops + a 0.5 fill opacity, matching upstream's
      // `stroke-opacity:0.5` over full-color gradient stops.
      fill: Fill(
        l.source.color.withOpacity(0.5),
        gradient: SceneGradient(
          Point(x0, 0),
          Point(x1, 0),
          [l.source.color, l.target.color],
        ),
      ),
    ));
  }

  // --- Node rects -------------------------------------------------------
  for (final n in nodeList) {
    nodeShapes.add(SceneShape(
      geometry: RectGeometry(
          Rect.fromLTWH(n.x0, n.y0, n.x1 - n.x0, math.max(0, n.y1 - n.y0))),
      fill: Fill(n.color),
    ));
  }

  // --- Labels -----------------------------------------------------------
  final outlined = labelStyle == 'outlined';
  for (final n in nodeList) {
    final value = math.max(
      n.sourceLinks.fold(0.0, (a, l) => a + l.value),
      n.targetLinks.fold(0.0, (a, l) => a + l.value),
    );
    final text = showValues
        ? '${n.name}\n$prefix${_fmtValue(value)}$suffix'
        : n.name;

    // Label position. legacy: position-based (x0 < width/2). outlined:
    // layer-based relative to the central node. Offset 6 either side.
    final bool onRight;
    if (outlined) {
      onRight = n.layer >= centralNodeLayer;
    } else {
      onRight = n.x0 < width / 2;
    }

    final labelSize = measurer.measure(text, labelTextStyle, maxWidth: 400);
    final cy = (n.y0 + n.y1) / 2;
    // dy: 0.35em when no values (single baseline), 0 otherwise.
    final dy = showValues ? 0.0 : labelFontSize * 0.35;
    final lx = onRight
        ? n.x1 + 6 + labelSize.width / 2
        : n.x0 - 6 - labelSize.width / 2;

    SceneText makeText(Color color) => SceneText(
          text: text,
          bounds: Rect.fromCenter(
              Point(lx, cy + dy), labelSize.width, labelSize.height),
          style: labelTextStyle,
          color: color,
        );

    if (outlined) {
      // Upstream draws a 4px background-colored stroke copy under the
      // foreground text for readability. SceneText has no stroke, so we
      // approximate by laying a background-colored copy beneath the
      // foreground copy (the closest expressible halo). The halo color is
      // `.sankey-label-bg` = `mainBkg || background || #fff` (styles.js).
      labelLayer.add(makeText(theme.mainBkg));
      labelLayer.add(makeText(theme.textColor));
    } else {
      labelLayer.add(makeText(theme.textColor));
    }
  }

  final all = [...ribbons, ...nodeShapes, ...labelLayer];
  final bounds = sceneBounds(all) ?? const Rect.fromLTWH(0, 0, 100, 100);
  const pad = 12.0;
  final dx = pad - bounds.left;
  final dyOff = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in all) translateSceneNode(n, dx, dyOff)],
  );
}

/// `Math.round(v*100)/100` rendered like JS: drop a trailing `.0` so
/// integers print as `23`, not `23.0`.
String _fmtValue(double v) {
  final rounded = (v * 100).round() / 100;
  if (rounded == rounded.truncateToDouble()) {
    return rounded.toInt().toString();
  }
  return rounded.toString();
}

/// BFS layering (d3-sankey computeNodeDepths/Heights). [next] yields the
/// neighbours to advance to; [assign] records the BFS distance.
void _computeNodeDepths(
  List<_Node> nodes,
  Iterable<_Node> Function(_Node) next,
  void Function(_Node, int) assign,
) {
  // Sources for the forward pass are nodes with no incoming links of the
  // traversed direction; d3 uses the full node set and relaxes by BFS layers.
  var current = <_Node>{...nodes};
  var x = 0;
  while (current.isNotEmpty) {
    final nextSet = <_Node>{};
    for (final n in current) {
      assign(n, x);
      for (final m in next(n)) {
        nextSet.add(m);
      }
    }
    if (++x > nodes.length) break; // cycle guard
    current = nextSet;
  }
}

int _alignLayer(
    _Node n, SankeyNodeAlignment align, int maxDepth, int maxHeight) {
  switch (align) {
    case SankeyNodeAlignment.left:
      return n.depth;
    case SankeyNodeAlignment.right:
      return maxDepth - n.height;
    case SankeyNodeAlignment.center:
      // d3 sankeyCenter: sources keep depth; others = min target depth - 1.
      if (n.targetLinks.isEmpty && n.sourceLinks.isNotEmpty) {
        return n.sourceLinks
            .map((l) => l.target.depth)
            .reduce(math.min) - 1;
      }
      return n.depth;
    case SankeyNodeAlignment.justify:
      // Sinks pulled to the right edge; others keep their depth.
      return n.sourceLinks.isEmpty ? maxDepth : n.depth;
  }
}

void _computeLinkBreadths(List<List<_Node>> columns) {
  for (final col in columns) {
    for (final n in col) {
      // Source endpoints stacked top→bottom in the node's source order.
      n.sourceLinks.sort((a, b) => a.target.y0.compareTo(b.target.y0));
      n.targetLinks.sort((a, b) => a.source.y0.compareTo(b.source.y0));
    }
  }
  for (final col in columns) {
    for (final n in col) {
      var y0 = n.y0;
      var y1 = n.y0;
      for (final l in n.sourceLinks) {
        l.y0 = y0 + l.width / 2;
        y0 += l.width;
      }
      for (final l in n.targetLinks) {
        l.y1 = y1 + l.width / 2;
        y1 += l.width;
      }
    }
  }
}

double _weightedSource(_Node n) {
  var sumW = 0.0, sum = 0.0;
  for (final l in n.targetLinks) {
    sum += (l.source.y0 + l.source.y1) / 2 * l.value;
    sumW += l.value;
  }
  return sumW > 0 ? sum / sumW : (n.y0 + n.y1) / 2;
}

double _weightedTarget(_Node n) {
  var sumW = 0.0, sum = 0.0;
  for (final l in n.sourceLinks) {
    sum += (l.target.y0 + l.target.y1) / 2 * l.value;
    sumW += l.value;
  }
  return sumW > 0 ? sum / sumW : (n.y0 + n.y1) / 2;
}

void _relaxLeftToRight(List<List<_Node>> columns, double alpha) {
  for (var i = 1; i < columns.length; i++) {
    for (final n in columns[i]) {
      if (n.targetLinks.isEmpty) continue;
      final v = _weightedSource(n);
      final dy = (v - (n.y0 + n.y1) / 2) * alpha;
      n.y0 += dy;
      n.y1 += dy;
    }
  }
}

void _relaxRightToLeft(List<List<_Node>> columns, double alpha) {
  for (var i = columns.length - 2; i >= 0; i--) {
    for (final n in columns[i]) {
      if (n.sourceLinks.isEmpty) continue;
      final v = _weightedTarget(n);
      final dy = (v - (n.y0 + n.y1) / 2) * alpha;
      n.y0 += dy;
      n.y1 += dy;
    }
  }
}

void _resolveCollisions(
    List<List<_Node>> columns, double height, double py) {
  for (final col in columns) {
    if (col.isEmpty) continue;
    col.sort((a, b) => a.y0.compareTo(b.y0));
    // Push nodes that overlap downward (resolveCollisionsTopToBottom).
    var y = 0.0;
    for (final n in col) {
      final dy = y - n.y0;
      if (dy > 0) {
        n.y0 += dy;
        n.y1 += dy;
      }
      y = n.y1 + py;
    }
    // If they overflow the bottom, push back up (bottomToTop).
    y = height;
    for (var i = col.length - 1; i >= 0; i--) {
      final n = col[i];
      final dy = n.y1 - y;
      if (dy > 0) {
        n.y0 -= dy;
        n.y1 -= dy;
      }
      y = n.y0 - py;
    }
  }
}

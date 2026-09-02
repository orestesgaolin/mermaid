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
import '../../directives.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

/// Typed values from `config.sankey`.
///
/// [useMaxWidth] controls responsive SVG sizing in Mermaid.js. A [RenderScene]
/// has an intrinsic logical size instead, so this backend records the option
/// but does not change layout geometry. `MermaidView` contain-fits that scene
/// and therefore preserves the configured [width]/[height] aspect ratio.
class SankeyConfig {
  const SankeyConfig({
    this.width = 600,
    this.height = 600,
    this.nodeWidth = 10,
    this.nodePadding = 12,
    this.nodeAlignment = 'justify',
    this.linkColor = 'gradient',
    this.showValues = true,
    this.prefix = '',
    this.suffix = '',
    this.labelStyle = 'legacy',
    this.useMaxWidth = false,
    this.nodeColors = const {},
  });

  final double width;
  final double height;
  final double nodeWidth;
  final double nodePadding;
  final String nodeAlignment;

  /// `source`, `target`, `gradient`, or a CSS color.
  final String linkColor;
  final bool showValues;
  final String prefix;
  final String suffix;
  final String labelStyle;
  final bool useMaxWidth;
  final Map<String, Color> nodeColors;

  /// Resolves frontmatter first, then applies init directives in order.
  /// Invalid values use the renderer's documented defaults.
  factory SankeyConfig.fromSource(String source) {
    final values = resolveDiagramConfig(source, 'sankey');

    double positive(String key, double fallback) {
      final value = values[key];
      if (value is num) {
        final resolved = value.toDouble();
        if (resolved.isFinite && resolved > 0) return resolved;
      }
      return fallback;
    }

    double nonNegative(String key, double fallback) {
      final value = values[key];
      if (value is num) {
        final resolved = value.toDouble();
        if (resolved.isFinite && resolved >= 0) return resolved;
      }
      return fallback;
    }

    String oneOf(String key, Set<String> supported, String fallback) {
      final value = values[key];
      return value is String && supported.contains(value) ? value : fallback;
    }

    var linkColor = values['linkColor'];
    if (linkColor is! String ||
        (linkColor != 'source' &&
            linkColor != 'target' &&
            linkColor != 'gradient' &&
            Color.tryParse(linkColor) == null)) {
      linkColor = 'gradient';
    }

    final nodeColors = <String, Color>{};
    final rawNodeColors = values['nodeColors'];
    if (rawNodeColors is Map) {
      for (final entry in rawNodeColors.entries) {
        final rawColor = entry.value;
        final color = rawColor is String ? Color.tryParse(rawColor) : null;
        if (color != null) nodeColors['${entry.key}'] = color;
      }
    }

    return SankeyConfig(
      width: positive('width', 600),
      height: positive('height', 600),
      nodeWidth: positive('nodeWidth', 10),
      nodePadding: nonNegative('nodePadding', 12),
      nodeAlignment: oneOf('nodeAlignment', const {
        'left',
        'right',
        'center',
        'justify',
      }, 'justify'),
      linkColor: linkColor,
      showValues: values['showValues'] is bool
          ? values['showValues']! as bool
          : true,
      prefix: values['prefix'] is String ? values['prefix']! as String : '',
      suffix: values['suffix'] is String ? values['suffix']! as String : '',
      labelStyle: oneOf('labelStyle', const {'legacy', 'outlined'}, 'legacy'),
      useMaxWidth: values['useMaxWidth'] is bool
          ? values['useMaxWidth']! as bool
          : false,
      nodeColors: Map.unmodifiable(nodeColors),
    );
  }
}

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
        'sankey line needs source,target,value',
        line: i + 1,
      );
    }
    final value = double.tryParse(fields[2].trim());
    if (value == null) {
      throw MermaidParseException(
        'invalid sankey value "${fields[2]}"',
        line: i + 1,
      );
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
  _Link(this.source, this.target, this.value, this.index);
  final _Node source;
  final _Node target;
  final double value;
  final int index;
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
  String linkColor = 'gradient',
  bool showValues = true,
  String prefix = '',
  String suffix = '',
  String labelStyle = 'legacy',
  Map<String, Color> nodeColors = const {},
}) {
  final align = _alignmentFromName(nodeAlignment);
  // d3-sankey: nodePadding(nodePadding + (showValues ? 15 : 0)).
  var py = nodePadding + (showValues ? 15.0 : 0.0);
  const labelFontSize = 14.0;
  final labelTextStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: labelFontSize,
  );

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
  for (var i = 0; i < diagram.links.length; i++) {
    final l = diagram.links[i];
    final link = _Link(nodes[l.source]!, nodes[l.target]!, l.value, i);
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
  _computeNodeDepths(
    nodeList,
    (n) => n.sourceLinks.map((l) => l.target),
    (n, d) => n.depth = d,
  );
  // computeNodeHeights (BFS from sinks)
  _computeNodeDepths(
    nodeList,
    (n) => n.targetLinks.map((l) => l.source),
    (n, d) => n.height = d,
  );

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
    final col = _alignLayer(
      n,
      align,
      maxDepth,
      maxHeight,
    ).clamp(0, columnCount - 1);
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
  // Keep the largest column within the vertical extent even when callers
  // request more padding than the configured height can hold.
  final maxColumnLength = columns.fold<int>(
    0,
    (largest, column) => math.max(largest, column.length),
  );
  if (maxColumnLength > 1) {
    py = math.min(py, height / (maxColumnLength - 1));
  }

  // ky: largest vertical scale that fits every column inside `height`.
  var ky = double.infinity;
  for (final col in columns) {
    if (col.isEmpty) continue;
    final sumV = col.fold(0.0, (a, n) => a + n.value);
    final avail = height - (col.length - 1) * py;
    if (sumV > 0) ky = math.min(ky, avail / sumV);
  }
  if (!ky.isFinite || ky < 0) ky = 0;

  // initializeNodeBreadths: stack each column, distribute its unused space
  // evenly above, between, and below nodes, then order links by the opposite
  // endpoint. This is d3-sankey's initial breadth state before relaxation.
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
    final gap = (height - y + py) / (col.length + 1);
    for (var i = 0; i < col.length; i++) {
      col[i].y0 += gap * (i + 1);
      col[i].y1 += gap * (i + 1);
    }
    _reorderLinks(col);
  }

  // Iterative relaxation, matching d3-sankey's default iteration loop:
  for (var i = 0; i < _kSankeyIterations; i++) {
    final alpha = math.pow(0.99, i).toDouble();
    final beta = math.max(1 - alpha, (i + 1) / _kSankeyIterations);
    _relaxRightToLeft(columns, alpha, beta, height, py);
    _relaxLeftToRight(columns, alpha, beta, height, py);
  }
  _computeLinkBreadths(columns);

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

  // --- Links: thick horizontal cubic strokes ----------------------------
  for (final l in links) {
    final w = math.max(1.0, l.width);
    final x0 = l.source.x1;
    final x1 = l.target.x0;
    final cx = (x0 + x1) / 2;
    final sy = l.y0;
    final ty = l.y1;
    // Upstream strokes a horizontal cubic centerline at `w`; the visible band
    // is the area between the top and bottom edges of that stroke.
    final customLinkColor = Color.tryParse(linkColor);
    final solidColor = switch (linkColor) {
      'target' => l.target.color,
      'source' => l.source.color,
      _ => customLinkColor ?? l.source.color,
    };
    final gradient = linkColor == 'gradient'
        ? SceneGradient(Point(x0, 0), Point(x1, 0), [
            _linkColor(l.source.color),
            _linkColor(l.target.color),
          ])
        : null;
    ribbons.add(
      SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(x0, sy)),
          CubicTo(Point(cx, sy), Point(cx, ty), Point(x1, ty)),
        ]),
        stroke: Stroke(
          color: _linkColor(solidColor),
          width: w,
          gradient: gradient,
        ),
        // Mermaid.js applies `mix-blend-mode:multiply` to each link group.
        // This keeps crossings legible instead of allowing the later lane to
        // visually erase the earlier one.
        blendMode: SceneBlendMode.multiply,
      ),
    );
  }

  // --- Node rects -------------------------------------------------------
  for (final n in nodeList) {
    nodeShapes.add(
      SceneShape(
        geometry: RectGeometry(
          Rect.fromLTWH(n.x0, n.y0, n.x1 - n.x0, math.max(0, n.y1 - n.y0)),
        ),
        fill: Fill(n.color),
      ),
    );
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
        Point(lx, cy + dy),
        labelSize.width,
        labelSize.height,
      ),
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

/// Applies Mermaid's 0.5 link opacity without replacing configured alpha.
Color _linkColor(Color color) => Color.fromARGB(
  (color.alpha * 0.5).round(),
  color.red,
  color.green,
  color.blue,
);

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
  _Node n,
  SankeyNodeAlignment align,
  int maxDepth,
  int maxHeight,
) {
  switch (align) {
    case SankeyNodeAlignment.left:
      return n.depth;
    case SankeyNodeAlignment.right:
      return maxDepth - n.height;
    case SankeyNodeAlignment.center:
      // d3 sankeyCenter: sources keep depth; others = min target depth - 1.
      if (n.targetLinks.isEmpty && n.sourceLinks.isNotEmpty) {
        return n.sourceLinks.map((l) => l.target.depth).reduce(math.min) - 1;
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

int _ascendingTargetBreadth(_Link a, _Link b) {
  final breadth = a.target.y0.compareTo(b.target.y0);
  return breadth != 0 ? breadth : a.index.compareTo(b.index);
}

int _ascendingSourceBreadth(_Link a, _Link b) {
  final breadth = a.source.y0.compareTo(b.source.y0);
  return breadth != 0 ? breadth : a.index.compareTo(b.index);
}

int _ascendingNodeBreadth(_Node a, _Node b) {
  final breadth = a.y0.compareTo(b.y0);
  return breadth != 0 ? breadth : a.index.compareTo(b.index);
}

void _reorderLinks(List<_Node> nodes) {
  for (final node in nodes) {
    node.sourceLinks.sort(_ascendingTargetBreadth);
    node.targetLinks.sort(_ascendingSourceBreadth);
  }
}

void _reorderNodeLinks(_Node node) {
  for (final link in node.targetLinks) {
    link.source.sourceLinks.sort(_ascendingTargetBreadth);
  }
  for (final link in node.sourceLinks) {
    link.target.targetLinks.sort(_ascendingSourceBreadth);
  }
}

void _relaxLeftToRight(
  List<List<_Node>> columns,
  double alpha,
  double beta,
  double height,
  double py,
) {
  for (var i = 1; i < columns.length; i++) {
    final column = columns[i];
    for (final target in column) {
      var y = 0.0;
      var weight = 0.0;
      for (final link in target.targetLinks) {
        final v = link.value * (target.layer - link.source.layer);
        y += _targetTop(link.source, target, py) * v;
        weight += v;
      }
      if (!(weight > 0)) continue;
      final dy = (y / weight - target.y0) * alpha;
      target.y0 += dy;
      target.y1 += dy;
      _reorderNodeLinks(target);
    }
    column.sort(_ascendingNodeBreadth);
    _resolveCollisions(column, beta, height, py);
  }
}

void _relaxRightToLeft(
  List<List<_Node>> columns,
  double alpha,
  double beta,
  double height,
  double py,
) {
  for (var i = columns.length - 2; i >= 0; i--) {
    final column = columns[i];
    for (final source in column) {
      var y = 0.0;
      var weight = 0.0;
      for (final link in source.sourceLinks) {
        final v = link.value * (link.target.layer - source.layer);
        y += _sourceTop(source, link.target, py) * v;
        weight += v;
      }
      if (!(weight > 0)) continue;
      final dy = (y / weight - source.y0) * alpha;
      source.y0 += dy;
      source.y1 += dy;
      _reorderNodeLinks(source);
    }
    column.sort(_ascendingNodeBreadth);
    _resolveCollisions(column, beta, height, py);
  }
}

void _resolveCollisions(
  List<_Node> nodes,
  double alpha,
  double height,
  double py,
) {
  if (nodes.isEmpty) return;
  final middle = nodes.length >> 1;
  final subject = nodes[middle];
  _resolveBottomToTop(nodes, subject.y0 - py, middle - 1, alpha, py);
  _resolveTopToBottom(nodes, subject.y1 + py, middle + 1, alpha, py);
  _resolveBottomToTop(nodes, height, nodes.length - 1, alpha, py);
  _resolveTopToBottom(nodes, 0, 0, alpha, py);
}

void _resolveTopToBottom(
  List<_Node> nodes,
  double y,
  int start,
  double alpha,
  double py,
) {
  for (var i = start; i < nodes.length; i++) {
    final node = nodes[i];
    final dy = (y - node.y0) * alpha;
    if (dy > 1e-6) {
      node.y0 += dy;
      node.y1 += dy;
    }
    y = node.y1 + py;
  }
}

void _resolveBottomToTop(
  List<_Node> nodes,
  double y,
  int start,
  double alpha,
  double py,
) {
  for (var i = start; i >= 0; i--) {
    final node = nodes[i];
    final dy = (node.y1 - y) * alpha;
    if (dy > 1e-6) {
      node.y0 -= dy;
      node.y1 -= dy;
    }
    y = node.y0 - py;
  }
}

double _targetTop(_Node source, _Node target, double py) {
  var y = source.y0 - (source.sourceLinks.length - 1) * py / 2;
  for (final link in source.sourceLinks) {
    if (identical(link.target, target)) break;
    y += link.width + py;
  }
  for (final link in target.targetLinks) {
    if (identical(link.source, source)) break;
    y -= link.width;
  }
  return y;
}

double _sourceTop(_Node source, _Node target, double py) {
  var y = target.y0 - (target.targetLinks.length - 1) * py / 2;
  for (final link in target.targetLinks) {
    if (identical(link.source, source)) break;
    y += link.width + py;
  }
  for (final link in source.sourceLinks) {
    if (identical(link.target, target)) break;
    y -= link.width;
  }
  return y;
}

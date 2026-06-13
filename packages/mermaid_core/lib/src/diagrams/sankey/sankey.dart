/// Sankey diagram: model, parser and layout — one file.
///
/// Reference: upstream sankeyDB / sankeyRenderer (which uses d3-sankey). The
/// syntax is CSV: each line is `source,target,value` (fields may be
/// double-quoted, `""` escapes a quote). Layout is a left-to-right layered
/// flow: nodes are placed in columns by longest path, sized by their larger
/// of in/out flow, and links are drawn as filled bezier ribbons whose width
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

/// Node fill palette (cycled); links inherit their source node's color.
const _palette = <Color>[
  Color(0xff4e79a7),
  Color(0xfff28e2b),
  Color(0xffe15759),
  Color(0xff76b7b2),
  Color(0xff59a14f),
  Color(0xffedc948),
  Color(0xffb07aa1),
  Color(0xffff9da7),
  Color(0xff9c755f),
  Color(0xffbab0ac),
];

class _Node {
  _Node(this.name, this.color);
  final String name;
  final Color color;
  int layer = 0;
  double value = 0;
  double x = 0;
  double y = 0;
  double height = 0;
  // Running stack offsets for link endpoints.
  double srcOffset = 0;
  double tgtOffset = 0;
}

RenderScene layoutSankey(
  Sankey diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const nodeWidth = 16.0;
  const colGap = 130.0; // horizontal distance between columns
  const nodePad = 14.0; // vertical gap between nodes in a column
  const targetHeight = 420.0;
  final labelStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize - 2);

  final nodes = <String, _Node>{};
  for (var i = 0; i < diagram.nodes.length; i++) {
    nodes[diagram.nodes[i]] =
        _Node(diagram.nodes[i], _palette[i % _palette.length]);
  }

  // Incoming/outgoing links per node.
  final outLinks = <String, List<SankeyLink>>{};
  final inLinks = <String, List<SankeyLink>>{};
  for (final l in diagram.links) {
    (outLinks[l.source] ??= []).add(l);
    (inLinks[l.target] ??= []).add(l);
  }

  // Layer = longest path from a source. Iterate to a fixpoint (cycles capped).
  for (var iter = 0; iter < nodes.length + 1; iter++) {
    var changed = false;
    for (final l in diagram.links) {
      final s = nodes[l.source]!, t = nodes[l.target]!;
      if (t.layer < s.layer + 1) {
        t.layer = s.layer + 1;
        changed = true;
      }
    }
    if (!changed) break;
  }

  // Node value = max(total in, total out).
  for (final n in nodes.values) {
    final out = (outLinks[n.name] ?? []).fold(0.0, (a, l) => a + l.value);
    final inc = (inLinks[n.name] ?? []).fold(0.0, (a, l) => a + l.value);
    n.value = math.max(out, inc);
  }

  // Group by layer (column).
  final maxLayer = nodes.values.fold(0, (a, n) => math.max(a, n.layer));
  final columns = List.generate(maxLayer + 1, (_) => <_Node>[]);
  for (final n in nodes.values) {
    columns[n.layer].add(n);
  }

  // Vertical scale: pick the largest ky that still fits every column.
  var ky = double.infinity;
  for (final col in columns) {
    if (col.isEmpty) continue;
    final sumV = col.fold(0.0, (a, n) => a + n.value);
    if (sumV <= 0) continue;
    final avail = targetHeight - nodePad * (col.length - 1);
    ky = math.min(ky, avail / sumV);
  }
  if (!ky.isFinite || ky <= 0) ky = 1;

  // Place nodes: stack within each column, centered vertically.
  for (var layer = 0; layer < columns.length; layer++) {
    final col = columns[layer]
      ..sort((a, b) => diagram.nodes
          .indexOf(a.name)
          .compareTo(diagram.nodes.indexOf(b.name)));
    final colHeight = col.fold(0.0, (a, n) => a + n.value * ky) +
        nodePad * (col.length - 1);
    var y = (targetHeight - colHeight) / 2;
    for (final n in col) {
      n.x = layer * (nodeWidth + colGap);
      n.height = n.value * ky;
      n.y = y;
      n.srcOffset = y;
      n.tgtOffset = y;
      y += n.height + nodePad;
    }
  }

  final nodeShapes = <SceneNode>[];
  final ribbons = <SceneNode>[];

  // Ribbons: order each node's links by the other end's vertical position so
  // bands stack without crossing more than necessary.
  for (final n in nodes.values) {
    (outLinks[n.name] ?? []).sort((a, b) =>
        nodes[a.target]!.y.compareTo(nodes[b.target]!.y));
  }
  for (final n in nodes.values) {
    (inLinks[n.name] ?? []).sort(
        (a, b) => nodes[a.source]!.y.compareTo(nodes[b.source]!.y));
  }

  for (final n in nodes.values) {
    for (final l in outLinks[n.name] ?? <SankeyLink>[]) {
      final s = nodes[l.source]!, t = nodes[l.target]!;
      final lh = l.value * ky;
      final sy = s.srcOffset;
      final ty = t.tgtOffset;
      s.srcOffset += lh;
      t.tgtOffset += lh;
      final x0 = s.x + nodeWidth;
      final x1 = t.x;
      final cx = (x0 + x1) / 2;
      // Filled band: top edge L→R, down the right, bottom edge R→L, close.
      ribbons.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(x0, sy)),
          CubicTo(Point(cx, sy), Point(cx, ty), Point(x1, ty)),
          LineTo(Point(x1, ty + lh)),
          CubicTo(Point(cx, ty + lh), Point(cx, sy + lh), Point(x0, sy + lh)),
          const ClosePath(),
        ]),
        fill: Fill(s.color.withOpacity(0.4)),
      ));
    }
  }

  // Node rects + labels.
  for (final n in nodes.values) {
    nodeShapes.add(SceneShape(
      geometry: RectGeometry(Rect.fromLTWH(n.x, n.y, nodeWidth, n.height)),
      fill: Fill(n.color),
    ));
    final labelSize = measurer.measure(n.name, labelStyle, maxWidth: 200);
    // Label outside the node: to the right, except the last column → left.
    final onLeft = n.layer == maxLayer && maxLayer > 0;
    final lx = onLeft
        ? n.x - 4 - labelSize.width / 2
        : n.x + nodeWidth + 4 + labelSize.width / 2;
    nodeShapes.add(SceneText(
      text: n.name,
      bounds: Rect.fromCenter(
          Point(lx, n.y + n.height / 2), labelSize.width, labelSize.height),
      style: labelStyle,
      color: theme.textColor,
    ));
  }

  final all = [...ribbons, ...nodeShapes];
  final bounds = sceneBounds(all) ?? const Rect.fromLTWH(0, 0, 100, 100);
  const pad = 12.0;
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in all) translateSceneNode(n, dx, dy)],
  );
}

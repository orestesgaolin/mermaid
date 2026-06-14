/// Treemap (`treemap-beta`): nested rectangles sized by value. Indentation
/// builds the hierarchy; leaves carry `: value`, branches sum their children.
/// Uses a squarified layout (Bruls/Huizing/van Wijk) with a d3-style padding
/// model (header + inner/outer gaps). Reference: upstream treemap renderer.
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
  TreemapNode(this.label, this.value, {this.isLeafNode = false, this.cssClass});

  final String label;
  double value; // own value for leaves; summed for branches
  final children = <TreemapNode>[];

  /// True when the source line carried `: value` (i.e. parsed as a `Leaf`).
  /// Upstream decides leaf-vs-section by item type, not by child count.
  final bool isLeafNode;

  /// `:::class` selector applied to this node, if any.
  final String? cssClass;

  bool get isLeaf => isLeafNode || children.isEmpty;
  double get total =>
      isLeaf ? value : children.fold(0.0, (a, c) => a + c.total);
}

/// Style overrides from a `classDef`. Only the properties upstream consumes
/// for treemap nodes are kept (`fill`, `stroke`, `color`).
class TreemapClass {
  const TreemapClass({this.fill, this.stroke, this.color});
  final Color? fill;
  final Color? stroke;
  final Color? color;
}

class Treemap {
  const Treemap(this.roots, this.title, {this.classes = const {}});
  final List<TreemapNode> roots;
  final String? title;
  final Map<String, TreemapClass> classes;
}

Treemap parseTreemap(String source) {
  var title = frontmatterTitle(source);
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final roots = <TreemapNode>[];
  final classes = <String, TreemapClass>{};
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

    // classDef <name> <styles>[;]
    final cd = RegExp(r'^classDef\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*(.*?);?\s*$')
        .firstMatch(content);
    if (cd != null) {
      classes[cd.group(1)!] = _parseClass(cd.group(2) ?? '');
      continue;
    }

    // `title <text>` directive (body) sets the diagram title when frontmatter
    // didn't already provide one. accTitle/accDescr are accepted and ignored.
    final tm = RegExp(r'^title(?:\s+(.*))?$').firstMatch(content);
    if (tm != null) {
      final t = tm.group(1)?.trim();
      if ((title == null || title.isEmpty) && t != null && t.isNotEmpty) {
        title = t;
      }
      continue;
    }
    if (RegExp(r'^(accTitle|accDescr)\b').hasMatch(content)) continue;

    final parsed = _parseItem(content);
    if (parsed == null) continue;
    final node = parsed;
    while (stack.isNotEmpty && indent <= stack.last.$1) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.$2.children.add(node);
    }
    // Only sections can have children; don't push leaves on the stack.
    if (!node.isLeafNode) stack.add((indent, node));
  }
  if (!seenHeader) throw const MermaidParseException('empty treemap source');
  return Treemap(roots, title, classes: classes);
}

/// Parses one treemap row into a node, or null if it doesn't match.
///
/// Grammar (Langium): `Section = STRING (:::ID)?`,
/// `Leaf = STRING (':'|',') NUMBER (:::ID)?`. STRING is quoted; NUMBER allows
/// digits, `_`, `.`, `,`.
TreemapNode? _parseItem(String content) {
  // "name" or 'name', optional ': value' / ', value', optional ':::class'.
  final m = RegExp(
    r'''^(?:"([^"]*)"|'([^']*)')\s*(?:(?:[:,])\s*([0-9_.,]+))?\s*(?::::([a-zA-Z_][a-zA-Z0-9_]*))?\s*$''',
  ).firstMatch(content);
  if (m == null) {
    // Tolerate an unquoted bare label (lenient fallback for our hand parser).
    final bare = RegExp(
      r'''^([^:,]+?)\s*(?:(?:[:,])\s*([0-9_.,]+))?\s*(?::::([a-zA-Z_][a-zA-Z0-9_]*))?\s*$''',
    ).firstMatch(content);
    if (bare == null) return null;
    final hasValue = bare.group(2) != null;
    return TreemapNode(
      bare.group(1)!.trim(),
      hasValue ? _parseNumber(bare.group(2)!) : 0.0,
      isLeafNode: hasValue,
      cssClass: bare.group(3),
    );
  }
  final label = m.group(1) ?? m.group(2) ?? '';
  final valueStr = m.group(3);
  final hasValue = valueStr != null;
  return TreemapNode(
    label,
    hasValue ? _parseNumber(valueStr) : 0.0,
    isLeafNode: hasValue,
    cssClass: m.group(4),
  );
}

/// Upstream `NUMBER2 = /[0-9_\.\,]+/`; thousands separators and underscores are
/// stripped before parsing.
double _parseNumber(String s) {
  final cleaned = s.replaceAll(',', '').replaceAll('_', '');
  return double.tryParse(cleaned) ?? 0.0;
}

/// Parses a classDef style string (`fill:#f00,stroke:#000,color:#fff`).
TreemapClass _parseClass(String styleText) {
  Color? fill, stroke, color;
  for (final part in styleText.split(RegExp('[,;]'))) {
    final kv = part.split(':');
    if (kv.length < 2) continue;
    final key = kv[0].trim().toLowerCase();
    final value = kv.sublist(1).join(':').trim();
    final parsed = Color.tryParse(value);
    if (parsed == null) continue;
    switch (key) {
      case 'fill':
        fill = parsed;
      case 'stroke':
        stroke = parsed;
      case 'color':
        color = parsed;
    }
  }
  return TreemapClass(fill: fill, stroke: stroke, color: color);
}

// --- Theme color scales ---------------------------------------------------
// Built from the shared MermaidTheme ordinal palette so non-default themes
// (dark/forest/neutral) adapt automatically. Default-theme values equal the
// previously-inlined constants for the fills, so default rendering is
// preserved.
//
// colorScale range = [transparent, cScale0..cScale11] (leaf/section fills).
List<Color?> _scaleRange(MermaidTheme theme) => <Color?>[null, ...theme.cScale];

// colorScalePeer range = [transparent, cScalePeer0..11] (border colors).
List<Color?> _peerRange(MermaidTheme theme) =>
    <Color?>[null, ...theme.cScalePeer];

// colorScaleLabel range = [cScaleLabel0..11] (section/leaf text colors).
List<Color> _labelRange(MermaidTheme theme) => theme.cScaleLabel;

/// d3 `scaleOrdinal`: assigns range entries to domain keys in first-seen order,
/// cycling through the range.
class _OrdinalScale {
  _OrdinalScale(this.range);
  final List<Color?> range;
  final _index = <String, int>{};
  var _next = 0;

  Color? operator [](String key) {
    final i = _index.putIfAbsent(key, () => _next++);
    return range[i % range.length];
  }
}

/// Thousands-grouped integer/decimal formatting (d3 default `,`).
String _fmt(double v) {
  final isInt = v == v.roundToDouble();
  if (isInt) return _group(v.round().toString());
  // Keep up to a few decimals, group the integer part.
  var s = v.toString();
  final dot = s.indexOf('.');
  if (dot < 0) return _group(s);
  return '${_group(s.substring(0, dot))}${s.substring(dot)}';
}

String _group(String intPart) {
  final neg = intPart.startsWith('-');
  var digits = neg ? intPart.substring(1) : intPart;
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return neg ? '-$buf' : buf.toString();
}

const _sectionHeaderHeight = 25.0;
const _sectionInnerPadding = 10.0;
const _innerPadding = 10.0;

RenderScene layoutTreemap(
  Treemap map, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final nodes = <SceneNode>[];
  const w = 960.0, h = 500.0;
  var titleH = 0.0;
  if (map.title != null && map.title!.isNotEmpty) titleH = 30;

  // A synthetic root holds all top-level nodes (upstream `getRoot`).
  final root = TreemapNode('', 0)..children.addAll(map.roots);

  // Sort every node's children by total value, descending (d3 `.sort`).
  void sortTree(TreemapNode n) {
    n.children.sort((a, b) => b.total.compareTo(a.total));
    for (final c in n.children) {
      sortTree(c);
    }
  }

  sortTree(root);

  final colorScale = _OrdinalScale(_scaleRange(theme));
  final peerScale = _OrdinalScale(_peerRange(theme));
  // colorScaleLabel keyed the same way (first-seen order), no leading slot.
  final labelRange = _labelRange(theme);
  final labelIndex = <String, int>{};
  var labelNext = 0;
  Color labelColor(String name) {
    final i = labelIndex.putIfAbsent(name, () => labelNext++);
    return labelRange[i % labelRange.length];
  }

  // Prime the ordinal scales in upstream's first-seen (pre-order) order so the
  // synthetic root's empty name takes the leading `transparent` slot and the
  // first real section maps to cScale0/cScalePeer0/cScaleLabel0.
  void primeColors(TreemapNode n) {
    colorScale[n.label];
    peerScale[n.label];
    labelColor(n.label);
    for (final c in n.children) {
      primeColors(c);
    }
  }

  primeColors(root);

  // Count leaves to pick the font-fit regime (upstream `isComplexTreemap`).
  var leafCount = 0;
  void countLeaves(TreemapNode n) {
    if (n.isLeaf) {
      leafCount++;
    } else {
      for (final c in n.children) {
        countLeaves(c);
      }
    }
  }

  countLeaves(root);
  final isComplex = leafCount > 20;
  final baseLabelFont = isComplex ? 16.0 : 38.0;
  final baseValueFont = isComplex ? 14.0 : 28.0;
  final minLabelFont = isComplex ? 4.0 : 8.0;
  final minValueFont = isComplex ? 4.0 : 6.0;
  final labelPad = isComplex ? 2.0 : 4.0;
  final minDisplay = isComplex ? 8.0 : 10.0;
  final spacing = isComplex ? 1.0 : 2.0;

  // Squarified treemap (Bruls/Huizing/van Wijk): pack children into rows laid
  // out along the shorter side, choosing rows that minimize the worst aspect
  // ratio. Produces near-square cells. [gap] is the inner padding between cells.
  List<Rect> squarify(List<TreemapNode> children, Rect rect, double gap) {
    final n = children.length;
    final placed = List<Rect?>.filled(n, null);
    if (n == 0) return const [];
    final totalV = children.fold(0.0, (a, c) => a + math.max(c.total, 0.0001));
    final area = math.max(rect.width, 0.0) * math.max(rect.height, 0.0);
    if (area <= 0 || totalV <= 0) {
      return [for (var i = 0; i < n; i++) Rect.fromLTWH(rect.left, rect.top, 0, 0)];
    }
    final areas = [
      for (final c in children) math.max(c.total, 0.0001) / totalV * area
    ];

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

    var x = rect.left, y = rect.top, fw = rect.width, fh = rect.height;
    var index = 0;

    void commitRow(List<int> rowIdx, List<double> rowAreas) {
      final rowSum = rowAreas.fold(0.0, (a, b) => a + b);
      if (fw >= fh) {
        final rw = rowSum / fh;
        var cy = y;
        for (var k = 0; k < rowIdx.length; k++) {
          final ch = rowAreas[k] / rowSum * fh;
          placed[rowIdx[k]] = Rect.fromLTWH(x, cy, rw, ch);
          cy += ch;
        }
        x += rw;
        fw -= rw;
      } else {
        final rh = rowSum / fw;
        var cx = x;
        for (var k = 0; k < rowIdx.length; k++) {
          final cw = rowAreas[k] / rowSum * fw;
          placed[rowIdx[k]] = Rect.fromLTWH(cx, y, cw, rh);
          cx += cw;
        }
        y += rh;
        fh -= rh;
      }
    }

    while (index < areas.length) {
      final shortest = math.min(fw, fh);
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

    // Apply the inner gap by shrinking each cell symmetrically by gap/2,
    // approximating d3's paddingInner spacing between siblings.
    final half = gap / 2;
    return [
      for (final r0 in placed)
        if (r0 == null)
          Rect.fromLTWH(rect.left, rect.top, 0, 0)
        else
          Rect.fromLTWH(
            r0.left + half,
            r0.top + half,
            math.max(0, r0.width - gap),
            math.max(0, r0.height - gap),
          )
    ];
  }

  // Draws one node's children into [rect]. [rect] is the area available to the
  // node's children (header already removed for sections by the caller).
  void layout(TreemapNode node, Rect rect, int depth) {
    final kids = node.children;
    if (kids.isEmpty) return;
    final rects = squarify(kids, rect, _innerPadding);
    for (var ki = 0; ki < kids.length; ki++) {
      final child = kids[ki];
      final cellRect = rects[ki];
      final cls = child.cssClass != null ? map.classes[child.cssClass] : null;

      if (child.isLeaf) {
        // Leaves inherit the parent section's color (colorScale(parent.name)).
        final base = colorScale[node.label] ?? Color.transparent;
        final fillColor = cls?.fill ?? base.withOpacity(0.3);
        final strokeColor = cls?.stroke ?? base;
        nodes.add(SceneShape(
          geometry: RectGeometry(cellRect),
          fill: Fill(fillColor),
          stroke: Stroke(color: strokeColor, width: 3),
        ));
        _drawLeafText(
          nodes: nodes,
          measurer: measurer,
          theme: theme,
          rect: cellRect,
          label: child.label,
          value: child.value,
          textColor: cls?.color ?? labelColor(child.label),
          baseLabelFont: baseLabelFont,
          baseValueFont: baseValueFont,
          minLabelFont: minLabelFont,
          minValueFont: minValueFont,
          labelPad: labelPad,
          minDisplay: minDisplay,
          spacing: spacing,
        );
      } else {
        // Section: body rect (colorScale @0.6 + peer stroke @0.4) under a
        // header band carrying a bold label and a right-aligned italic value.
        final base = colorScale[child.label] ?? Color.transparent;
        final peer = peerScale[child.label] ?? Color.transparent;
        final bodyFill = cls?.fill ?? base.withOpacity(0.6);
        final bodyStroke = cls?.stroke ?? peer.withOpacity(0.4);
        nodes.add(SceneShape(
          geometry: RectGeometry(cellRect),
          fill: Fill(bodyFill),
          stroke: Stroke(color: bodyStroke, width: 2),
        ));

        final lblColor = cls?.color ?? labelColor(child.label);
        _drawSectionHeader(
          nodes: nodes,
          measurer: measurer,
          theme: theme,
          rect: cellRect,
          label: child.label,
          value: child.total,
          labelColor: lblColor,
        );

        // Recurse into the inner rect: remove header + section padding
        // (paddingTop = 35, paddingLeft/Right/Bottom = 10).
        const top = _sectionHeaderHeight + _sectionInnerPadding;
        final inner = Rect.fromLTWH(
          cellRect.left + _sectionInnerPadding,
          cellRect.top + top,
          math.max(0, cellRect.width - 2 * _sectionInnerPadding),
          math.max(0, cellRect.height - top - _sectionInnerPadding),
        );
        if (inner.width > 0 && inner.height > 0) {
          layout(child, inner, depth + 1);
        }
      }
    }
  }

  layout(root, Rect.fromLTWH(0, titleH, w, h), 0);

  if (titleH > 0) {
    final titleStyle = TextStyleSpec(fontFamily: theme.fontFamily, fontSize: 14);
    final ts = measurer.measure(map.title!, titleStyle);
    nodes.add(SceneText(
      text: map.title!,
      bounds: Rect.fromLTWH(w / 2 - ts.width / 2, titleH / 2 - ts.height / 2,
          ts.width, ts.height),
      style: titleStyle,
      color: theme.titleColor,
    ));
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, w, h);
  const m = 8.0; // diagramPadding default
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final n in nodes)
        translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

/// Draws a section header: bold label (12px, clipped/truncated) at x=6 and a
/// right-aligned italic value (10px) at x=w-10, both vertically centered in the
/// 25px header band.
void _drawSectionHeader({
  required List<SceneNode> nodes,
  required TextMeasurer measurer,
  required MermaidTheme theme,
  required Rect rect,
  required String label,
  required double value,
  required Color labelColor,
}) {
  if (rect.width <= 0 || rect.height <= 0) return;
  final headerH = math.min(_sectionHeaderHeight, rect.height);
  final centerY = rect.top + headerH / 2;

  final valueStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: 10, italic: true);
  final valueText = _fmt(value);
  final valueSize = measurer.measure(valueText, valueStyle);
  final showValue = value != 0;

  // Space available for the label (mirrors upstream's estimate).
  final totalW = rect.width;
  const labelX = 6.0;
  double spaceForLabel;
  if (showValue) {
    final valueEndsAt = totalW - 10;
    const estValueW = 30.0;
    const gap = 10.0;
    spaceForLabel = (valueEndsAt - estValueW - gap) - labelX;
  } else {
    spaceForLabel = totalW - labelX - 6;
  }
  spaceForLabel = math.max(15.0, spaceForLabel);

  final labelStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: 12, fontWeight: 700);
  var shown = label;
  var lw = measurer.measure(shown, labelStyle).width;
  if (lw > spaceForLabel) {
    // Truncate with an ellipsis until it fits.
    var cut = label;
    while (cut.isNotEmpty) {
      cut = cut.substring(0, cut.length - 1);
      final candidate = '$cut...';
      if (measurer.measure(candidate, labelStyle).width <= spaceForLabel) {
        shown = candidate;
        break;
      }
      if (cut.isEmpty) {
        shown = measurer.measure('...', labelStyle).width <= spaceForLabel
            ? '...'
            : '';
      }
    }
    lw = measurer.measure(shown, labelStyle).width;
  }
  if (shown.isNotEmpty) {
    final lh = measurer.measure(shown, labelStyle).height;
    nodes.add(SceneText(
      text: shown,
      bounds: Rect.fromLTWH(rect.left + labelX, centerY - lh / 2, lw, lh),
      style: labelStyle,
      color: labelColor,
      align: TextAlignH.left,
    ));
  }

  if (showValue && valueSize.width <= totalW) {
    nodes.add(SceneText(
      text: valueText,
      bounds: Rect.fromLTWH(rect.left + totalW - 10 - valueSize.width,
          centerY - valueSize.height / 2, valueSize.width, valueSize.height),
      style: valueStyle,
      color: labelColor,
      align: TextAlignH.right,
    ));
  }
}

/// Ports upstream's leaf label/value auto-fit: shrink the label font to fit the
/// cell width, then the combined label+value height; hide if too small. Value
/// font is `round(label*0.6)` clamped to `[minValue, baseValue]`.
void _drawLeafText({
  required List<SceneNode> nodes,
  required TextMeasurer measurer,
  required MermaidTheme theme,
  required Rect rect,
  required String label,
  required double value,
  required Color textColor,
  required double baseLabelFont,
  required double baseValueFont,
  required double minLabelFont,
  required double minValueFont,
  required double labelPad,
  required double minDisplay,
  required double spacing,
}) {
  final availW = rect.width - 2 * labelPad;
  final availH = rect.height - 2 * labelPad;
  if (availW < minDisplay || availH < minDisplay) return;
  if (label.isEmpty) return;

  var labelFont = baseLabelFont;
  TextStyleSpec labelStyle() =>
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: labelFont);

  double measureLabelW() => measurer.measure(label, labelStyle()).width;

  // 1. Shrink to fit width.
  while (measureLabelW() > availW && labelFont > minLabelFont) {
    labelFont--;
  }

  double valueFont() => math.max(
      minValueFont, math.min(baseValueFont, (labelFont * 0.6).roundToDouble()));

  // 2. Shrink to fit combined height.
  var combined = labelFont + spacing + valueFont();
  while (combined > availH && labelFont > minLabelFont) {
    labelFont--;
    final vf = valueFont();
    if (vf < minValueFont && labelFont == minLabelFont) break;
    combined = labelFont + spacing + vf;
  }

  // 3. Visibility checks. `isComplexTreemap` (>20 leaves) uses base label 16;
  // the simple regime uses 38. Complex ignores width overflow; simple hides on
  // overflow (faithful to upstream's two branches).
  final tooNarrow = measureLabelW() > availW;
  final isComplexRegime = baseLabelFont <= 20;
  final hide = isComplexRegime
      ? (labelFont < minLabelFont || availH < minLabelFont)
      : (tooNarrow || labelFont < minLabelFont || availH < labelFont);
  if (hide) return;

  final labelMetrics = measurer.measure(label, labelStyle());
  final centerY = rect.top + rect.height / 2;
  nodes.add(SceneText(
    text: label,
    bounds: Rect.fromLTWH(
        rect.left + (rect.width - labelMetrics.width) / 2,
        centerY - labelFont / 2,
        labelMetrics.width,
        labelFont),
    style: labelStyle(),
    color: textColor,
  ));

  // Value below the label (dominant-baseline: hanging in upstream).
  final vf = valueFont();
  final valueText = _fmt(value);
  final valueStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: vf);
  final vm = measurer.measure(valueText, valueStyle);
  final valueTop = centerY + labelFont / 2 + spacing;
  final maxBottom = rect.bottom - 4;
  if (value != 0 &&
      vm.width <= availW &&
      valueTop + vf <= maxBottom &&
      vf >= minValueFont) {
    nodes.add(SceneText(
      text: valueText,
      bounds: Rect.fromLTWH(
          rect.left + (rect.width - vm.width) / 2, valueTop, vm.width, vf),
      style: valueStyle,
      color: textColor,
    ));
  }
}

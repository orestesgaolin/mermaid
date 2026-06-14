/// Venn diagram (`venn-beta`): named sets drawn as overlapping translucent
/// circles sized area-proportionally from per-subset weights, with optional
/// union intersection labels, free text nodes and per-target style overrides.
///
/// This is a pragmatic port of mermaid.js' `vennRenderer.ts` (which delegates
/// circle packing to `@upsetjs/venn.js`). We reimplement the area-proportional
/// layout analytically: radii derive from `sqrt(size/pi)`, pairwise distances
/// are solved so the circular lens area matches the requested overlap size, and
/// 3+ set configurations are placed with a small constraint relaxation pass.
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

/// A single subset entry: one or more member set ids, an area weight and an
/// optional label. Mirrors upstream `VennData`.
class VennSubset {
  const VennSubset(this.sets, this.size, this.label);

  /// Sorted member set ids. Length 1 ⇒ a base set; length ≥2 ⇒ a union region.
  final List<String> sets;

  /// Area weight driving the proportional layout.
  final double size;

  /// Optional region label (`union A,B["label"]`).
  final String? label;

  String get key => sets.join('|');
}

/// A free text node attached to a region (`text A,B id["label"]`).
class VennTextNode {
  const VennTextNode(this.sets, this.id, this.label);
  final List<String> sets;
  final String id;
  final String? label;

  String get key => sets.join('|');
}

/// A `style` directive: target region keys → CSS-like declarations.
class VennStyle {
  const VennStyle(this.targets, this.styles);
  final List<String> targets;
  final Map<String, String> styles;

  String get key => targets.join('|');
}

class VennDiagram {
  const VennDiagram(
    this.sets,
    this.subsets,
    this.textNodes,
    this.styles,
    this.title,
  );

  /// Declared base set ids, in declaration order.
  final List<String> sets;

  /// All subset entries (base sets + unions), in declaration order.
  final List<VennSubset> subsets;
  final List<VennTextNode> textNodes;
  final List<VennStyle> styles;
  final String? title;

  /// Backwards-compatible view: union member-csv → label (non-empty labels).
  Map<String, String> get unions {
    final m = <String, String>{};
    for (final s in subsets) {
      if (s.sets.length >= 2) m[s.sets.join(',')] = s.label ?? '';
    }
    return m;
  }
}

String _normalizeText(String text) {
  final trimmed = text.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

/// Splits a comma-separated identifier list, honoring optional quotes.
List<String> _parseIdentifierList(String raw) {
  return raw.split(',').map((s) => _normalizeText(s)).where((s) => s.isNotEmpty).toList();
}

VennDiagram parseVenn(String source) {
  final title0 = frontmatterTitle(source);
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final sets = <String>[];
  final knownSets = <String>{};
  final subsets = <VennSubset>[];
  final textNodes = <VennTextNode>[];
  final styles = <VennStyle>[];
  String? title = title0;
  var seenHeader = false;
  // The most recently declared set/union, for indented `text` attachment.
  List<String>? currentSets;
  var indentMode = false;

  // Captures an optional `["label"]` then optional `:NUMERIC` tail.
  const labelSize = r'(?:\s*\[(?:"([^"]*)"|([^\]]*))\])?\s*(?::\s*([+-]?(?:\d+(?:\.\d+)?|\.\d+)))?';

  for (var i = 0; i < lines.length; i++) {
    final rawLine = lines[i];
    var line = rawLine.trim();
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c).trim();
    if (line.isEmpty) continue;

    if (!seenHeader) {
      if (!RegExp(r'^venn-beta\b').hasMatch(line)) {
        throw MermaidParseException('expected "venn-beta" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }

    // Indented `text` line: attach to the most recent set/union.
    final indented = rawLine.isNotEmpty && (rawLine[0] == ' ' || rawLine[0] == '\t');
    if (indentMode && indented) {
      final tm = RegExp('^text\\s+(.+)\$').firstMatch(line);
      if (tm != null) {
        final cs = currentSets;
        if (cs == null) {
          throw MermaidParseException('text requires a set', line: i + 1);
        }
        final id = _parseTextId(tm.group(1)!);
        textNodes.add(VennTextNode(cs, id.id, id.label));
        continue;
      }
    }

    var m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      title = _normalizeText(m.group(1)!);
      continue;
    }

    m = RegExp('^set\\s+(\\S+?)$labelSize\\s*\$').firstMatch(line);
    if (m != null) {
      final id = _normalizeText(m.group(1)!);
      final label = m.group(2) ?? m.group(3);
      final size = m.group(4) != null ? double.parse(m.group(4)!) : 10.0;
      final list = [id];
      sets.add(id);
      knownSets.add(id);
      subsets.add(VennSubset(list, size, label == null ? null : _normalizeText(label)));
      currentSets = list;
      indentMode = true;
      continue;
    }

    m = RegExp('^union\\s+([\\w,"\\s]+?)$labelSize\\s*\$').firstMatch(line);
    if (m != null) {
      final list = _parseIdentifierList(m.group(1)!)..sort();
      if (list.length < 2) {
        throw MermaidParseException('union requires multiple identifiers', line: i + 1);
      }
      final unknown = list.where((s) => !knownSets.contains(s)).toList();
      if (unknown.isNotEmpty) {
        throw MermaidParseException(
            'unknown set identifier: ${unknown.join(', ')}', line: i + 1);
      }
      final label = m.group(2) ?? m.group(3);
      final size = m.group(4) != null
          ? double.parse(m.group(4)!)
          : 10.0 / math.pow(list.length, 2);
      subsets.add(VennSubset(list, size, label == null ? null : _normalizeText(label)));
      currentSets = list;
      indentMode = true;
      continue;
    }

    // Non-indented `text <sets> id["label"]`.
    m = RegExp(r'^text\s+([\w,"\s]+?)\s+(\S.*)$').firstMatch(line);
    if (m != null) {
      final targets = _parseIdentifierList(m.group(1)!)..sort();
      final id = _parseTextId(m.group(2)!);
      textNodes.add(VennTextNode(targets, id.id, id.label));
      continue;
    }

    // `style <targets> key:value, key:value`.
    m = RegExp(r'^style\s+([\w,"\s]+?)\s+(\S.*)$').firstMatch(line);
    if (m != null) {
      final targets = _parseIdentifierList(m.group(1)!)..sort();
      final decls = _parseStyleDeclarations(m.group(2)!);
      styles.add(VennStyle(targets, decls));
      continue;
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty venn source');
  return VennDiagram(sets, subsets, textNodes, styles, title);
}

class _TextId {
  const _TextId(this.id, this.label);
  final String id;
  final String? label;
}

_TextId _parseTextId(String raw) {
  final m = RegExp(r'^(.+?)\s*\[(?:"([^"]*)"|([^\]]*))\]\s*$').firstMatch(raw.trim());
  if (m != null) {
    return _TextId(_normalizeText(m.group(1)!), _normalizeText(m.group(2) ?? m.group(3) ?? ''));
  }
  return _TextId(_normalizeText(raw), null);
}

Map<String, String> _parseStyleDeclarations(String raw) {
  final out = <String, String>{};
  for (final part in raw.split(',')) {
    final idx = part.indexOf(':');
    if (idx < 0) continue;
    final k = part.substring(0, idx).trim();
    final v = _normalizeText(part.substring(idx + 1));
    if (k.isNotEmpty) out[k] = v;
  }
  return out;
}

// --- HSL helpers mirroring khroma's adjust/darken/lighten -------------------

class _Hsl {
  _Hsl(this.h, this.s, this.l);
  double h; // 0..360
  double s; // 0..1
  double l; // 0..1
}

_Hsl _toHsl(Color c) {
  final r = c.red / 255, g = c.green / 255, b = c.blue / 255;
  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  final l = (max + min) / 2;
  var h = 0.0, s = 0.0;
  final d = max - min;
  if (d != 0) {
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h *= 60;
  }
  return _Hsl(h, s, l);
}

double _hue2rgb(double p, double q, double t) {
  if (t < 0) t += 1;
  if (t > 1) t -= 1;
  if (t < 1 / 6) return p + (q - p) * 6 * t;
  if (t < 1 / 2) return q;
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
  return p;
}

Color _fromHsl(_Hsl c, int alpha) {
  final h = (c.h % 360) / 360, s = c.s.clamp(0.0, 1.0), l = c.l.clamp(0.0, 1.0);
  if (s == 0) {
    final v = (l * 255).round();
    return Color.fromARGB(alpha, v, v, v);
  }
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  final r = _hue2rgb(p, q, h + 1 / 3);
  final g = _hue2rgb(p, q, h);
  final b = _hue2rgb(p, q, h - 1 / 3);
  return Color.fromARGB(alpha, (r * 255).round(), (g * 255).round(), (b * 255).round());
}

/// khroma `darken(c, amount)` — lightness minus `amount` percentage points.
Color _darken(Color c, double amount) {
  final hsl = _toHsl(c);
  hsl.l = (hsl.l - amount / 100).clamp(0.0, 1.0);
  return _fromHsl(hsl, c.alpha);
}

/// khroma `lighten(c, amount)`.
Color _lighten(Color c, double amount) {
  final hsl = _toHsl(c);
  hsl.l = (hsl.l + amount / 100).clamp(0.0, 1.0);
  return _fromHsl(hsl, c.alpha);
}

bool _isDark(Color c) {
  // khroma isDark: relative luminance < 0.5 (perceived).
  final lum = (0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue) / 255;
  return lum < 0.5;
}

// --- Layout geometry --------------------------------------------------------

class _Circle {
  _Circle(this.x, this.y, this.radius);
  double x;
  double y;
  double radius;
}

/// Synthesizes the missing pairwise (2-set) intersections for any union with
/// ≥3 members, so 3+ way overlaps render a visible shared region. Mirrors
/// upstream `ensurePairwiseSubsets`. Returns a new list; never mutates input.
List<VennSubset> _ensurePairwiseSubsets(List<VennSubset> subsets) {
  final existing = subsets.map((s) => s.key).toSet();
  final singleSizes = <String, double>{};
  for (final s in subsets) {
    if (s.sets.length == 1) singleSizes[s.sets[0]] = s.size;
  }
  final synthetic = <VennSubset>[];
  for (final s in subsets) {
    if (s.sets.length < 3) continue;
    final members = [...s.sets]..sort();
    for (var i = 0; i < members.length - 1; i++) {
      for (var j = i + 1; j < members.length; j++) {
        final pair = [members[i], members[j]];
        final key = pair.join('|');
        if (existing.contains(key)) continue;
        existing.add(key);
        final a = singleSizes[pair[0]];
        final b = singleSizes[pair[1]];
        final size = (a != null && b != null) ? math.min(a, b) / 4 : 2.5;
        synthetic.add(VennSubset(pair, size, ''));
      }
    }
  }
  return synthetic.isEmpty ? subsets : [...subsets, ...synthetic];
}

/// Area of a circular lens where two circles of radii r1,r2 are distance d apart.
double _lensArea(double r1, double r2, double d) {
  if (d <= (r1 - r2).abs()) {
    return math.pi * math.min(r1, r2) * math.min(r1, r2);
  }
  if (d >= r1 + r2) return 0;
  final r1sq = r1 * r1, r2sq = r2 * r2;
  final a1 = r1sq * math.acos(((d * d + r1sq - r2sq) / (2 * d * r1)).clamp(-1.0, 1.0));
  final a2 = r2sq * math.acos(((d * d + r2sq - r1sq) / (2 * d * r2)).clamp(-1.0, 1.0));
  final a3 = 0.5 *
      math.sqrt(math.max(
          0, (-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2)));
  return a1 + a2 - a3;
}

/// Solves the centre distance so the lens area between r1,r2 equals [target].
double _distanceForOverlap(double r1, double r2, double target) {
  final maxOverlap = math.pi * math.min(r1, r2) * math.min(r1, r2);
  if (target <= 0) return r1 + r2;
  if (target >= maxOverlap) return (r1 - r2).abs();
  var lo = (r1 - r2).abs();
  var hi = r1 + r2;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    final area = _lensArea(r1, r2, mid);
    if (area > target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Computes per-set circles (in layout-space units, centred near origin) that
/// honor the requested sizes/overlaps. Analytic for 1–2 sets; constraint
/// relaxation for ≥3.
Map<String, _Circle> _layoutCircles(List<String> setIds, List<VennSubset> subsets) {
  final radii = <String, double>{};
  for (final id in setIds) {
    final s = subsets.firstWhere(
      (e) => e.sets.length == 1 && e.sets[0] == id,
      orElse: () => VennSubset([id], 10, null),
    );
    radii[id] = math.sqrt(s.size / math.pi);
  }
  final circles = <String, _Circle>{
    for (final id in setIds) id: _Circle(0, 0, radii[id]!),
  };

  if (setIds.isEmpty) return circles;
  if (setIds.length == 1) return circles;

  // Desired pairwise distances from the union sizes (default overlap if absent).
  double pairDistance(String a, String b) {
    final key = ([a, b]..sort()).join('|');
    final sub = subsets.where((e) => e.key == key && e.sets.length == 2).toList();
    final ra = radii[a]!, rb = radii[b]!;
    final overlap = sub.isNotEmpty ? sub.first.size : math.min(ra, rb) * math.min(ra, rb) * 0.5;
    return _distanceForOverlap(ra, rb, overlap);
  }

  if (setIds.length == 2) {
    final d = pairDistance(setIds[0], setIds[1]);
    circles[setIds[0]] = _Circle(-d / 2, 0, radii[setIds[0]]!);
    circles[setIds[1]] = _Circle(d / 2, 0, radii[setIds[1]]!);
    return circles;
  }

  // ≥3: seed on a ring, then relax toward the desired pairwise distances.
  final avgR = radii.values.reduce((a, b) => a + b) / radii.length;
  for (var i = 0; i < setIds.length; i++) {
    final a = -math.pi / 2 + 2 * math.pi * i / setIds.length;
    circles[setIds[i]] = _Circle(
      avgR * 1.2 * math.cos(a),
      avgR * 1.2 * math.sin(a),
      radii[setIds[i]]!,
    );
  }
  for (var iter = 0; iter < 200; iter++) {
    for (var i = 0; i < setIds.length; i++) {
      for (var j = i + 1; j < setIds.length; j++) {
        final ca = circles[setIds[i]]!, cb = circles[setIds[j]]!;
        final target = pairDistance(setIds[i], setIds[j]);
        var dx = cb.x - ca.x, dy = cb.y - ca.y;
        var dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 1e-6) {
          dx = 1;
          dy = 0;
          dist = 1;
        }
        final adjust = (target - dist) / 2 * 0.5;
        final ux = dx / dist, uy = dy / dist;
        ca.x -= ux * adjust;
        ca.y -= uy * adjust;
        cb.x += ux * adjust;
        cb.y += uy * adjust;
      }
    }
  }
  return circles;
}

// --- Rendering --------------------------------------------------------------

RenderScene layoutVenn(
  VennDiagram d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  // Match upstream viewBox: 800×450, scale = width / 1600.
  const svgWidth = 800.0;
  const svgHeight = 450.0;
  const scale = svgWidth / 1600.0;
  const padding = 15.0;
  final titleHeight = (d.title != null && d.title!.isNotEmpty) ? 48.0 * scale : 0.0;

  final themeDark = _isDark(theme.background);
  // Upstream intersection/text-node fill = `vennSetTextColor`.
  final setTextColor = theme.vennSetTextColor;
  final vennColors = theme.venn;

  final styleByKey = <String, Map<String, String>>{};
  for (final s in d.styles) {
    styleByKey.putIfAbsent(s.key, () => <String, String>{}).addAll(s.styles);
  }

  final renderSubsets = _ensurePairwiseSubsets(d.subsets);

  // Compute circle geometry in layout units, then fit into the viewport.
  final raw = _layoutCircles(d.sets, renderSubsets);
  final fitted = _fitCircles(
    raw,
    width: svgWidth - 2 * padding,
    height: svgHeight - titleHeight - 2 * padding,
    offsetX: padding,
    offsetY: padding + titleHeight,
  );

  final nodes = <SceneNode>[];

  // Background fill rect so the diagram has a stable canvas size.
  // (We rely on RenderScene.size; no explicit rect needed.)

  // Set circles.
  for (var i = 0; i < d.sets.length; i++) {
    final id = d.sets[i];
    final circle = fitted[id];
    if (circle == null) continue;
    final custom = styleByKey[id];
    final baseColor = _resolveColor(custom?['fill']) ?? vennColors[i % vennColors.length];
    final fillOpacity = _parseOpacity(custom?['fill-opacity']) ?? 0.1;
    final strokeColor = _resolveColor(custom?['stroke']) ?? baseColor;
    final strokeWidth = _parseNum(custom?['stroke-width']) ?? (5 * scale);

    nodes.add(SceneShape(
      geometry: CircleGeometry(Point(circle.x, circle.y), circle.radius),
      fill: Fill(baseColor.withOpacity(fillOpacity)),
      stroke: Stroke(color: strokeColor.withOpacity(0.95), width: strokeWidth),
    ));

    // Set label: font 48*scale, colored darken/lighten(baseColor,30).
    final labelColor = _resolveColor(custom?['color']) ??
        (themeDark ? _lighten(baseColor, 30) : _darken(baseColor, 30));
    final labelText = _setLabel(d.subsets, id);
    final labelStyle = TextStyleSpec(
      fontFamily: theme.fontFamily,
      fontSize: 48 * scale,
    );
    final ls = measurer.measure(labelText, labelStyle);
    // venn.js seats the set label at the top of the circle.
    final lp = Point(circle.x, circle.y - circle.radius + ls.height * 0.7);
    nodes.add(SceneText(
      text: labelText,
      bounds: Rect.fromCenter(lp, ls.width, ls.height),
      style: labelStyle,
      color: labelColor,
    ));
  }

  // Intersection (union) regions: label seated at the overlap centroid, font
  // 48*scale, fill `vennSetTextColor` (fallback primaryText). Region path is
  // only filled when a custom `fill` style is present (upstream fill-opacity 0).
  for (final sub in d.subsets) {
    if (sub.sets.length < 2) continue;
    final memberCircles =
        sub.sets.map((s) => fitted[s]).whereType<_Circle>().toList();
    if (memberCircles.length != sub.sets.length) continue;
    final centroid = _intersectionCentroid(memberCircles);
    final custom = styleByKey[sub.key];

    final customFill = _resolveColor(custom?['fill']);
    if (customFill != null) {
      // Approximate the shared region with a circle at the centroid sized to
      // the smallest member, so a styled intersection has a visible fill.
      final r = memberCircles.map((c) => c.radius).reduce(math.min) * 0.5;
      nodes.add(SceneShape(
        geometry: CircleGeometry(centroid, r),
        fill: Fill(customFill),
      ));
    }

    final label = sub.label;
    if (label != null && label.isNotEmpty) {
      final color = _resolveColor(custom?['color']) ?? setTextColor;
      final style = TextStyleSpec(fontFamily: theme.fontFamily, fontSize: 48 * scale);
      final ls = measurer.measure(label, style);
      nodes.add(SceneText(
        text: label,
        bounds: Rect.fromCenter(centroid, ls.width, ls.height),
        style: style,
        color: color,
      ));
    }
  }

  // Free text nodes: grid placement inside each region (font 40*scale).
  _placeTextNodes(d, fitted, styleByKey, scale, measurer, theme, setTextColor, nodes);

  final children = <SceneNode>[...nodes];

  // Title: 32*scale centered at y=32*scale (within the reserved header band).
  if (d.title != null && d.title!.isNotEmpty) {
    final style = TextStyleSpec(fontFamily: theme.fontFamily, fontSize: 32 * scale);
    final ts = measurer.measure(d.title!, style);
    children.add(SceneText(
      text: d.title!,
      bounds: Rect.fromCenter(Point(svgWidth / 2, 32 * scale), ts.width, ts.height),
      style: style,
      color: theme.vennTitleTextColor,
    ));
  }

  final bounds = sceneBounds(children) ?? const Rect.fromLTWH(0, 0, svgWidth, svgHeight);
  // Use the upstream viewBox size, expanded if any content overflows it.
  final right = math.max(svgWidth, bounds.right);
  final bottom = math.max(svgHeight, bounds.bottom);
  final left = math.min(0.0, bounds.left);
  final top = math.min(0.0, bounds.top);
  return RenderScene(
    size: Size(right - left, bottom - top),
    background: theme.background,
    nodes: [for (final nd in children) translateSceneNode(nd, -left, -top)],
  );
}

String _setLabel(List<VennSubset> subsets, String id) {
  for (final s in subsets) {
    if (s.sets.length == 1 && s.sets[0] == id) {
      final l = s.label;
      if (l != null && l.isNotEmpty) return l;
    }
  }
  return id;
}

/// Centroid of the overlap region: the average of the two nearest boundary
/// midpoints, approximated as the size-weighted mean of member centres.
Point _intersectionCentroid(List<_Circle> circles) {
  var sx = 0.0, sy = 0.0;
  for (final c in circles) {
    sx += c.x;
    sy += c.y;
  }
  return Point(sx / circles.length, sy / circles.length);
}

/// Scales+translates layout-space circles to fit a [width]×[height] box,
/// preserving aspect ratio and centering, offset by [offsetX]/[offsetY].
Map<String, _Circle> _fitCircles(
  Map<String, _Circle> circles, {
  required double width,
  required double height,
  required double offsetX,
  required double offsetY,
}) {
  if (circles.isEmpty) return circles;
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final c in circles.values) {
    minX = math.min(minX, c.x - c.radius);
    minY = math.min(minY, c.y - c.radius);
    maxX = math.max(maxX, c.x + c.radius);
    maxY = math.max(maxY, c.y + c.radius);
  }
  final w = maxX - minX, h = maxY - minY;
  final sx = w > 0 ? width / w : 1.0;
  final sy = h > 0 ? height / h : 1.0;
  final s = math.min(sx, sy);
  final drawnW = w * s, drawnH = h * s;
  final dx = offsetX + (width - drawnW) / 2;
  final dy = offsetY + (height - drawnH) / 2;
  return {
    for (final e in circles.entries)
      e.key: _Circle(
        (e.value.x - minX) * s + dx,
        (e.value.y - minY) * s + dy,
        e.value.radius * s,
      ),
  };
}

void _placeTextNodes(
  VennDiagram d,
  Map<String, _Circle> fitted,
  Map<String, Map<String, String>> styleByKey,
  double scale,
  TextMeasurer measurer,
  MermaidTheme theme,
  Color setTextColor,
  List<SceneNode> out,
) {
  if (d.textNodes.isEmpty) return;
  final byArea = <String, List<VennTextNode>>{};
  for (final n in d.textNodes) {
    byArea.putIfAbsent(n.key, () => <VennTextNode>[]).add(n);
  }
  for (final entry in byArea.entries) {
    final memberIds = entry.key.split('|');
    final memberCircles = memberIds.map((s) => fitted[s]).whereType<_Circle>().toList();
    if (memberCircles.length != memberIds.length) continue;
    final center = _intersectionCentroid(memberCircles);
    final minR = memberCircles.map((c) => c.radius).reduce(math.min);
    var innerRadius = double.infinity;
    for (final c in memberCircles) {
      final dist = math.sqrt(
          (center.x - c.x) * (center.x - c.x) + (center.y - c.y) * (center.y - c.y));
      innerRadius = math.min(innerRadius, c.radius - dist);
    }
    if (!innerRadius.isFinite || innerRadius <= 0) innerRadius = minR * 0.6;

    final nodes = entry.value;
    final innerWidth = math.max(80 * scale, innerRadius * 2 * 0.95);
    final innerHeight = math.max(60 * scale, innerRadius * 2 * 0.95);
    // Offset down if the region carries its own union label.
    final hasLabel = d.subsets.any((s) =>
        s.key == entry.key && (s.label?.isNotEmpty ?? false));
    final labelOffsetBase = hasLabel ? math.min(32 * scale, innerRadius * 0.25) : 0.0;
    final labelOffset = labelOffsetBase + (nodes.length <= 2 ? 30 * scale : 0.0);
    final startX = center.x - innerWidth / 2;
    final startY = center.y - innerHeight / 2 + labelOffset;
    final cols = math.max(1, math.sqrt(nodes.length).ceil());
    final rows = math.max(1, (nodes.length / cols).ceil());
    final cellW = innerWidth / cols;
    final cellH = innerHeight / rows;

    final style = TextStyleSpec(fontFamily: theme.fontFamily, fontSize: 40 * scale);
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final col = i % cols;
      final row = i ~/ cols;
      final x = startX + cellW * (col + 0.5);
      final y = startY + cellH * (row + 0.5);
      final text = (node.label != null && node.label!.isNotEmpty) ? node.label! : node.id;
      final color = _resolveColor(styleByKey[node.id]?['color']) ?? setTextColor;
      final ts = measurer.measure(text, style);
      out.add(SceneText(
        text: text,
        bounds: Rect.fromCenter(Point(x, y), ts.width, ts.height),
        style: style,
        color: color,
      ));
    }
  }
}

Color? _resolveColor(String? css) {
  if (css == null || css.trim().isEmpty) return null;
  return Color.tryParse(css.trim());
}

double? _parseNum(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(RegExp(r'[^0-9.\-]'), ''));
}

double? _parseOpacity(String? s) {
  if (s == null) return null;
  return double.tryParse(s.trim());
}

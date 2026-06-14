/// Cynefin framework (`cynefin-beta`): five domains (clear, complicated,
/// complex, chaotic, plus a central confusion/disorder) each listing items,
/// with optional transitions between domains.
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

/// A transition `from --> to (: "label")?` between two domains.
class CynefinTransition {
  const CynefinTransition(this.from, this.to, this.label);
  final String from;
  final String to;
  final String? label;
}

class CynefinDiagram {
  const CynefinDiagram(
    this.domains,
    this.title, {
    this.transitions = const [],
    this.accTitle,
    this.accDescription,
  });
  final Map<String, List<String>> domains;
  final String? title;
  final List<CynefinTransition> transitions;
  final String? accTitle;
  final String? accDescription;
}

String _canonicalDomain(String name) =>
    name == 'disorder' ? 'confusion' : name;

CynefinDiagram parseCynefin(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final domains = <String, List<String>>{};
  final transitions = <CynefinTransition>[];
  String? title;
  String? accTitle;
  String? accDescription;
  var seenHeader = false;
  String? current;
  final transitionRe = RegExp(
    r'^(clear|complicated|complex|chaotic|confusion|disorder)\s*-->\s*'
    r'(clear|complicated|complex|chaotic|confusion|disorder)'
    r'(?:\s*:\s*"?(.+?)"?)?$',
  );
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c);
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*cynefin(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "cynefin" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    final t = line.trim();
    final tm = RegExp(r'^title\s+(.+)$').firstMatch(t);
    if (tm != null) {
      title = tm.group(1)!.trim();
      continue;
    }
    final atm = RegExp(r'^accTitle\s*:\s*(.+)$').firstMatch(t);
    if (atm != null) {
      accTitle = atm.group(1)!.trim();
      continue;
    }
    final adm = RegExp(r'^accDescr\s*:\s*(.+)$').firstMatch(t);
    if (adm != null) {
      accDescription = adm.group(1)!.trim();
      continue;
    }
    final trm = transitionRe.firstMatch(t);
    if (trm != null) {
      final from = _canonicalDomain(trm.group(1)!);
      final to = _canonicalDomain(trm.group(2)!);
      // Self-loop transitions are not meaningful and are filtered out.
      if (from != to) {
        final label = trm.group(3)?.trim();
        transitions.add(CynefinTransition(
          from,
          to,
          (label == null || label.isEmpty) ? null : label,
        ));
      }
      continue;
    }
    final dm = RegExp(r'^(clear|complicated|complex|chaotic|confusion|disorder)$')
        .firstMatch(t);
    if (dm != null) {
      current = _canonicalDomain(dm.group(1)!);
      domains.putIfAbsent(current, () => []);
      continue;
    }
    // Quoted item under the current domain.
    var item = t;
    if (item.length >= 2 && item.startsWith('"') && item.endsWith('"')) {
      item = item.substring(1, item.length - 1);
    }
    if (current != null) domains[current]!.add(item);
  }
  if (!seenHeader) throw const MermaidParseException('empty cynefin source');
  return CynefinDiagram(
    domains,
    title,
    transitions: transitions,
    accTitle: accTitle,
    accDescription: accDescription,
  );
}

// Canvas geometry (mermaid defaults: width 800, height 600, padding 40).
const _width = 800.0, _height = 600.0, _padding = 40.0;
const _boundaryAmplitude = 8.0;
const _showDomainDescriptions = true;

// Per-domain background colors (theme-default.js cynefin block).
const _domainFills = {
  'complex': Color(0xffE8F5E9),
  'complicated': Color(0xffE3F2FD),
  'clear': Color(0xffFFF8E1),
  'chaotic': Color(0xffFBE9E7),
  'confusion': Color(0xffF3E5F5),
};

// Decision model + practice subtitles per domain.
const _domainMeta = {
  'complex': ['Probe → Sense → Respond', 'Emergent Practices'],
  'complicated': ['Sense → Analyse → Respond', 'Good Practices'],
  'clear': ['Sense → Categorise → Respond', 'Best Practices'],
  'chaotic': ['Act → Sense → Respond', 'Novel Practices'],
  'confusion': ['', 'Disorder'],
};

const _maxConfusionItems = 3;

class _DomainLayout {
  const _DomainLayout(this.cx, this.cy, this.x, this.y, this.w, this.h);
  final double cx, cy, x, y, w, h;
}

/// Deterministic pseudo-random number generator (mulberry32),
/// ported from cynefinBoundaries.ts:seededRandom.
double _seededRandom(int seed) {
  var t = (seed + 0x6d2b79f5) | 0;
  t = _imul(t ^ (t >>> 15), t | 1);
  t ^= t + _imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296.0;
}

/// 32-bit integer multiply matching JS Math.imul.
int _imul(int a, int b) {
  final aHi = (a >>> 16) & 0xffff;
  final aLo = a & 0xffff;
  final bHi = (b >>> 16) & 0xffff;
  final bLo = b & 0xffff;
  return (aLo * bLo + (((aHi * bLo + aLo * bHi) << 16) & 0xffffffff)).toSigned(32);
}

/// Simple string hash for seeding the PRNG (cynefinBoundaries.ts:hashString).
int _hashString(String str) {
  var hash = 0;
  for (var i = 0; i < str.length; i++) {
    final ch = str.codeUnitAt(i);
    hash = (((hash << 5) - hash + ch)).toSigned(32);
  }
  return hash;
}

Map<String, _DomainLayout> _getDomainLayouts(double width, double height) {
  final hw = width / 2;
  final hh = height / 2;
  return {
    'complex': _DomainLayout(hw / 2, hh / 2, 0, 0, hw, hh),
    'complicated': _DomainLayout(hw + hw / 2, hh / 2, hw, 0, hw, hh),
    'chaotic': _DomainLayout(hw / 2, hh + hh / 2, 0, hh, hw, hh),
    'clear': _DomainLayout(hw + hw / 2, hh + hh / 2, hw, hh, hw, hh),
    'confusion':
        _DomainLayout(hw, hh, hw * 0.7, hh * 0.7, hw * 0.6, hh * 0.6),
  };
}

/// Port of generateFoldPath: vertical wavy "fold" through the center.
PathGeometry _foldPath(double width, double height, int seed, double amplitude) {
  final cx = width / 2;
  const segments = 7;
  final segHeight = height / segments;
  final points = <Point>[];
  for (var i = 0; i <= segments; i++) {
    final jitter = _seededRandom(seed + i * 17) * amplitude * 2 - amplitude;
    points.add(Point(cx + jitter, i * segHeight));
  }
  final commands = <PathCommand>[MoveTo(points[0])];
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = points[i];
    final p1 = points[i + 1];
    final midY = (p0.y + p1.y) / 2;
    final dir = i % 2 == 0 ? 1 : -1;
    final offset = amplitude * 1.5 * dir * _seededRandom(seed + i * 31 + 7);
    commands.add(CubicTo(
      Point(p0.x + offset, midY),
      Point(p1.x - offset, midY),
      p1,
    ));
  }
  return PathGeometry(commands);
}

/// Port of generateHorizontalBoundary: horizontal wavy line through the center.
PathGeometry _horizontalBoundary(
    double width, double height, int seed, double amplitude) {
  final cy = height / 2;
  const segments = 7;
  final segWidth = width / segments;
  final points = <Point>[];
  for (var i = 0; i <= segments; i++) {
    final jitter = _seededRandom(seed + i * 23) * amplitude * 2 - amplitude;
    points.add(Point(i * segWidth, cy + jitter));
  }
  final commands = <PathCommand>[MoveTo(points[0])];
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = points[i];
    final p1 = points[i + 1];
    final midX = (p0.x + p1.x) / 2;
    final dir = i % 2 == 0 ? 1 : -1;
    final offset = amplitude * 1.5 * dir * _seededRandom(seed + i * 37 + 11);
    commands.add(CubicTo(
      Point(midX, p0.y + offset),
      Point(midX, p1.y - offset),
      p1,
    ));
  }
  return PathGeometry(commands);
}

/// Port of generateCliffPath: thick S-curve between Clear and Chaotic.
PathGeometry _cliffPath(double width, double height) {
  final cx = width / 2;
  final topY = height * 0.5;
  final bottomY = height;
  final amplitude = width * 0.03;
  final span = bottomY - topY;
  return PathGeometry([
    MoveTo(Point(cx, topY)),
    CubicTo(
      Point(cx + amplitude, topY + span * 0.2),
      Point(cx - amplitude * 1.5, topY + span * 0.55),
      Point(cx + amplitude * 0.5, topY + span * 0.75),
    ),
    CubicTo(
      Point(cx - amplitude, topY + span * 0.85),
      Point(cx + amplitude * 0.3, topY + span * 0.95),
      Point(cx, bottomY),
    ),
  ]);
}

RenderScene layoutCynefin(
  CynefinDiagram d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  // Theme-default cynefin block values (inlined defaults).
  const labelColor = Color(0xff333333); // primaryTextColor (default invert)
  final textColor = theme.textColor;
  final boundaryColor = theme.lineColor;
  const cliffColor = Color(0xff8B0000);
  final arrowColor = theme.lineColor;

  const domainFontSize = 16.0;
  const itemFontSize = 12.0;
  const subtitleFontSize = itemFontSize - 1; // 11

  final labelStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: domainFontSize,
    fontWeight: 700,
  );
  final subtitleStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: subtitleFontSize,
    italic: true,
  );
  final itemStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: itemFontSize,
  );
  final titleStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: domainFontSize + 2,
    fontWeight: 700,
  );

  final layouts = _getDomainLayouts(_width, _height);
  // Seed derived from a stable id (we have no svg id; use a fixed string so
  // boundaries are deterministic across renders).
  final seed = _hashString('cynefin');

  final nodes = <SceneNode>[];
  const quadrantDomains = ['complex', 'complicated', 'chaotic', 'clear'];

  // 1. Domain background rectangles (fill-opacity 0.4, no stroke).
  for (final name in quadrantDomains) {
    final l = layouts[name]!;
    nodes.add(SceneShape(
      geometry: RectGeometry(Rect.fromLTWH(l.x, l.y, l.w, l.h)),
      fill: Fill(_domainFills[name]!.withOpacity(0.4)),
    ));
  }

  // 2. Wavy boundaries (dashed 6 3).
  final boundaryStroke = Stroke(color: boundaryColor, width: 2, dash: const [6, 3]);
  nodes.add(SceneShape(
    geometry: _foldPath(_width, _height, seed, _boundaryAmplitude),
    stroke: boundaryStroke,
  ));
  nodes.add(SceneShape(
    geometry:
        _horizontalBoundary(_width, _height, seed + 100, _boundaryAmplitude),
    stroke: boundaryStroke,
  ));

  // 3. The cliff (thick dark-red S-curve between Clear and Chaotic).
  nodes.add(SceneShape(
    geometry: _cliffPath(_width, _height),
    stroke: const Stroke(color: cliffColor, width: 4),
  ));

  // 4. Confusion ellipse (center overlay), dashed stroke, 0.5 fill opacity.
  final confusionRx = _width * 0.15;
  final confusionRy = _height * 0.15;
  nodes.add(SceneShape(
    geometry: EllipseGeometry(
      const Point(_width / 2, _height / 2),
      confusionRx,
      confusionRy,
    ),
    fill: Fill(_domainFills['confusion']!.withOpacity(0.5)),
    stroke: Stroke(color: boundaryColor, width: 1.5, dash: const [4, 2]),
  ));

  // 5 & 6. Domain labels + subtitles.
  void addCenteredText(String text, double cx, double cy, TextStyleSpec style,
      Color color) {
    if (text.isEmpty) return;
    final s = measurer.measure(text, style);
    nodes.add(SceneText(
      text: text,
      bounds: Rect.fromCenter(Point(cx, cy), s.width, s.height),
      style: style,
      color: color,
      align: TextAlignH.center,
    ));
  }

  for (final name in quadrantDomains) {
    final l = layouts[name]!;
    final labelY = _showDomainDescriptions ? l.cy - 30 : l.cy;
    addCenteredText(
      name[0].toUpperCase() + name.substring(1),
      l.cx,
      labelY,
      labelStyle,
      labelColor,
    );
    if (_showDomainDescriptions) {
      final meta = _domainMeta[name]!;
      addCenteredText(meta[0], l.cx, l.cy - 10, subtitleStyle, textColor);
      addCenteredText(meta[1], l.cx, l.cy + 5, subtitleStyle, textColor);
    }
  }

  // Confusion label + subtitle.
  addCenteredText(
    'Confusion',
    _width / 2,
    _showDomainDescriptions ? _height / 2 - 10 : _height / 2,
    labelStyle,
    labelColor,
  );
  if (_showDomainDescriptions) {
    addCenteredText(
      _domainMeta['confusion']![1],
      _width / 2,
      _height / 2 + 8,
      subtitleStyle,
      textColor,
    );
  }

  // 7. Items as rounded badges.
  const itemHeight = 26.0;
  const itemPaddingX = 10.0;
  const allDomains = ['complex', 'complicated', 'chaotic', 'clear', 'confusion'];

  void addBadge(
    String label,
    double cx,
    double y,
    Color fillColor,
    double fillOpacity, {
    List<double>? dash,
  }) {
    final s = measurer.measure(label, itemStyle);
    final badgeWidth = s.width + itemPaddingX * 2;
    final x = cx - badgeWidth / 2;
    nodes.add(SceneShape(
      geometry: RectGeometry(
        Rect.fromLTWH(x, y, badgeWidth, itemHeight),
        rx: 4,
        ry: 4,
      ),
      fill: Fill(fillColor.withOpacity(fillOpacity)),
      stroke: Stroke(color: boundaryColor, dash: dash),
    ));
    nodes.add(SceneText(
      text: label,
      bounds: Rect.fromLTWH(x, y + (itemHeight - s.height) / 2, badgeWidth, s.height),
      style: itemStyle,
      color: textColor,
      align: TextAlignH.center,
    ));
  }

  for (final name in allDomains) {
    final items = d.domains[name];
    if (items == null || items.isEmpty) continue;
    final l = layouts[name]!;
    final isConfusion = name == 'confusion';

    var itemsToRender = items;
    var overflowCount = 0;
    if (isConfusion && items.length > _maxConfusionItems) {
      overflowCount = items.length - _maxConfusionItems;
      itemsToRender = items.sublist(0, _maxConfusionItems);
    }

    final double startY;
    if (isConfusion) {
      final labelOffset = _showDomainDescriptions ? 22.0 : 14.0;
      startY = l.cy + labelOffset;
    } else {
      startY = l.cy + (_showDomainDescriptions ? 25.0 : 15.0);
    }

    for (var idx = 0; idx < itemsToRender.length; idx++) {
      final itemY = startY + idx * (itemHeight + 4);
      addBadge(itemsToRender[idx], l.cx, itemY, _domainFills[name]!, 0.95);
    }

    if (overflowCount > 0) {
      final overflowY = startY + itemsToRender.length * (itemHeight + 4);
      addBadge(
        '+$overflowCount more',
        l.cx,
        overflowY,
        _domainFills[name]!,
        0.6,
        dash: const [3, 2],
      );
    }
  }

  // 8. Transition arrows between domain centers.
  for (final tr in d.transitions) {
    final from = layouts[tr.from];
    final to = layouts[tr.to];
    if (from == null || to == null || tr.from == tr.to) continue;

    final x1 = from.cx, y1 = from.cy, x2 = to.cx, y2 = to.cy;
    final mx = (x1 + x2) / 2;
    final my = (y1 + y2) / 2;
    final dx = x2 - x1;
    final dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) continue;
    final offsetAmount = len * 0.15;
    final nx = -dy / len;
    final ny = dx / len;
    final cpx = mx + nx * offsetAmount;
    final cpy = my + ny * offsetAmount;

    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(x1, y1)),
        QuadTo(Point(cpx, cpy), Point(x2, y2)),
      ]),
      stroke: Stroke(color: arrowColor, width: 2),
    ));

    // Arrowhead (filled triangle) oriented along the curve's end tangent.
    // Tangent of a quadratic bezier at t=1 is (P2 - control).
    final tdx = x2 - cpx;
    final tdy = y2 - cpy;
    final tlen = math.sqrt(tdx * tdx + tdy * tdy);
    if (tlen > 0) {
      final ux = tdx / tlen;
      final uy = tdy / tlen;
      const ah = 10.0; // arrowhead length
      const aw = 4.0; // half-width
      final baseX = x2 - ux * ah;
      final baseY = y2 - uy * ah;
      // perpendicular
      final px = -uy;
      final py = ux;
      nodes.add(SceneShape(
        geometry: PolygonGeometry([
          Point(x2, y2),
          Point(baseX + px * aw, baseY + py * aw),
          Point(baseX - px * aw, baseY - py * aw),
        ]),
        fill: Fill(arrowColor),
      ));
    }

    if (tr.label != null) {
      final s = measurer.measure(tr.label!, subtitleStyle);
      nodes.add(SceneText(
        text: tr.label!,
        bounds: Rect.fromCenter(Point(cpx, cpy - 6 - s.height / 2), s.width, s.height),
        style: subtitleStyle,
        color: textColor,
        align: TextAlignH.center,
      ));
    }
  }

  // Translate everything by padding so the canvas origin matches upstream's
  // root <g transform="translate(padding, padding)">.
  final body = [
    for (final n in nodes) translateSceneNode(n, _padding, _padding)
  ];

  final children = <SceneNode>[...body];

  // Title centered at the top (y = -padding/2 in root coords → padding/2 here).
  if (d.title != null && d.title!.isNotEmpty) {
    final ts = measurer.measure(d.title!, titleStyle);
    children.add(SceneText(
      text: d.title!,
      bounds: Rect.fromCenter(
        Point(_width / 2 + _padding, _padding / 2),
        ts.width,
        ts.height,
      ),
      style: titleStyle,
      color: labelColor,
      align: TextAlignH.center,
    ));
  }

  return RenderScene(
    size: const Size(_width + 2 * _padding, _height + 2 * _padding),
    background: theme.background,
    nodes: children,
  );
}

/// Mindmap: model, parser and layout — one file.
///
/// Reference: upstream mindmap langium grammar + mindmapRenderer. Upstream
/// lays out with cytoscape cose-bilkent; this port uses a deterministic
/// radial tree (angular sectors proportional to leaf count), which settles
/// to roughly the same organic look without a force simulation.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../icons/icon_registry.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

enum MindmapShape { plain, rect, rounded, circle, bang, cloud, hexagon }

class MindmapNode {
  MindmapNode({
    required this.label,
    required this.shape,
    required this.depth,
  });

  final String label;
  final MindmapShape shape;
  final int depth;
  final children = <MindmapNode>[];

  /// `::icon(...)` decoration — the icon reference (e.g. `icon:cog`), or null.
  String? icon;

  /// `:::className` decorations applied to this node.
  final cssClasses = <String>[];
}

class Mindmap {
  const Mindmap({required this.root, this.classDefs = const {}});

  final MindmapNode root;

  /// `classDef <name> fill:#xxx,stroke:#yyy,color:#zzz` declarations, keyed by
  /// class name. Each value maps style property → raw value (e.g. `'#f00'`).
  final Map<String, Map<String, String>> classDefs;
}

Mindmap parseMindmap(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  MindmapNode? root;
  // (indent, node) stack from root to current.
  final stack = <(int, MindmapNode)>[];
  final classDefs = <String, Map<String, String>>{};
  var seenHeader = false;

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    var line = raw.trimRight();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trimRight();
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*mindmap\b').hasMatch(line)) {
        throw MermaidParseException('expected "mindmap" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    final indent = line.length - line.trimLeft().length;
    final content = line.trim();
    // `classDef <name[,name...]> prop:val,prop:val` — diagram-level styles.
    final classDefM =
        RegExp(r'^classDef\s+([^\s]+)\s+(.+)$').firstMatch(content);
    if (classDefM != null) {
      final styles = <String, String>{};
      for (final decl in classDefM.group(2)!.split(',')) {
        final c = decl.indexOf(':');
        if (c < 0) continue;
        styles[decl.substring(0, c).trim()] = decl.substring(c + 1).trim();
      }
      for (final name in classDefM.group(1)!.split(',')) {
        final n = name.trim();
        if (n.isNotEmpty) (classDefs[n] ??= {}).addAll(styles);
      }
      continue;
    }
    // Decorations attach to the most-recent node.
    final iconM = RegExp(r'^::icon\(\s*(.+?)\s*\)$').firstMatch(content);
    if (iconM != null) {
      if (stack.isNotEmpty) stack.last.$2.icon = iconM.group(1);
      continue;
    }
    if (content.startsWith(':::')) {
      if (stack.isNotEmpty) {
        stack.last.$2.cssClasses
            .addAll(content.substring(3).trim().split(RegExp(r'\s+')));
      }
      continue;
    }

    final (shape, label) = _parseNodeText(content, i + 1);
    if (root == null) {
      root = MindmapNode(label: label, shape: shape, depth: 0);
      stack.add((indent, root));
      continue;
    }
    while (stack.isNotEmpty && indent <= stack.last.$1) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      throw MermaidParseException(
          'multiple roots are not allowed in a mindmap', line: i + 1);
    }
    final parent = stack.last.$2;
    final node =
        MindmapNode(label: label, shape: shape, depth: parent.depth + 1);
    parent.children.add(node);
    stack.add((indent, node));
  }
  if (!seenHeader || root == null) {
    throw const MermaidParseException('empty mindmap source');
  }
  return Mindmap(root: root, classDefs: classDefs);
}

/// Normalizes an `::icon(...)` reference to a registry `prefix:name` lookup.
///
/// - `icon:cog` (already `prefix:name`) is returned unchanged.
/// - FontAwesome / MDI style refs like `fa fa-book` or `mdi mdi-skull-outline`
///   carry a leading pack word; we treat that word as the pack prefix and the
///   remainder as the icon name, i.e. `fa fa-book` → `fa:fa-book`. If no such
///   pack is registered, [renderIcon] resolves to nothing and the glyph is
///   silently skipped (never throws).
String _resolveIconRef(String ref) {
  final trimmed = ref.trim();
  if (trimmed.contains(':')) return trimmed; // already prefix:name
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length < 2) return trimmed;
  return '${parts.first}:${parts.sublist(1).join(' ')}';
}

(MindmapShape, String) _parseNodeText(String content, int line) {
  String normalize(String s) => s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .trim();
  // id((label)) etc — the leading id is optional and unused for layout.
  final m = RegExp(r'^([\wÀ-￿-]*)\s*'
          r'(\(\(|\)\)|\(-|\)|\(|\[|\{\{)(.*?)(\)\)|\(\(|-\)|\(|\)|\]|\}\})\s*$')
      .firstMatch(content);
  if (m == null) return (MindmapShape.plain, normalize(content));
  final open = m.group(2)!;
  final close = m.group(4)!;
  final label = normalize(m.group(3)!);
  // Mirror upstream `mindmapDb.getType(startStr, endStr)`:
  //  '['            -> RECT
  //  '('            -> ROUNDED_RECT if closed by ')', else CLOUD (e.g. `(-…-)`)
  //  '(('           -> CIRCLE
  //  ')'            -> CLOUD
  //  '))'           -> BANG
  //  '{{'           -> HEXAGON
  return switch (open) {
    '((' => (MindmapShape.circle, label),
    '))' => (MindmapShape.bang, label),
    '(-' => (MindmapShape.cloud, label),
    ')' => (MindmapShape.cloud, label),
    '(' => (close == ')'
        ? (MindmapShape.rounded, label)
        : (MindmapShape.cloud, label)),
    '[' => (MindmapShape.rect, label),
    '{{' => (MindmapShape.hexagon, label),
    _ => (MindmapShape.plain, label),
  };
}

/// Section fill colors (`cScale1..11` cycling), default mermaid theme.
///
/// Upstream `styles.genSections` paints `.section-<i>` with `cScale<i+1>`; the
/// default theme derives these from `primaryColor #ECECFF` (hue-rotated) and
/// then darkens every entry by 10% — yielding pale/pastel fills, not the
/// saturated palette we used before. Section index = `branchIndex % 11`
/// (`MAX_SECTIONS - 1`). Index 0 here corresponds to upstream `cScale1`.
/// Values precomputed from khroma (`darken(adjust(primaryColor,{h}), 10)`).
const _sectionFills = <Color>[
  Color(0xffffffab), // cScale1 (secondaryColor #ffffde)
  Color(0xffe9ffb9), // cScale2 (tertiaryColor)
  Color(0xffdeb9ff), // cScale3  adjust h+30
  Color(0xffffb9ff), // cScale4  adjust h+60
  Color(0xffffb9de), // cScale5  adjust h+90
  Color(0xffffb9b9), // cScale6  adjust h+120
  Color(0xffffdeb9), // cScale7  adjust h+150
  Color(0xffdeffb9), // cScale8  adjust h+210
  Color(0xffb9ffde), // cScale9  adjust h+270
  Color(0xffb9ffff), // cScale10 adjust h+300
  Color(0xffb9deff), // cScale11 adjust h+330
];

/// Underline / section-line stroke colors (`cScaleInv1..11`), default theme.
/// Upstream `.section-<i> line { stroke: cScaleInv<i+1>; stroke-width: 3 }`.
const _sectionLines = <Color>[
  Color(0xffababff), // cScaleInv1
  Color(0xffcfb9ff), // cScaleInv2
  Color(0xffdaffb9), // cScaleInv3
  Color(0xffb9ffb9), // cScaleInv4
  Color(0xffb9ffda), // cScaleInv5
  Color(0xffb9ffff), // cScaleInv6
  Color(0xffb9daff), // cScaleInv7
  Color(0xffdab9ff), // cScaleInv8
  Color(0xffffb9da), // cScaleInv9
  Color(0xffffb9b9), // cScaleInv10
  Color(0xffffdab9), // cScaleInv11
];

/// Root node fill = `git0` (default theme: `darken(primaryColor, 25)`).
const _rootFill = Color(0xff6d6dff);

/// Root text color = `gitBranchLabel0` = `invert(labelTextColor=black)` = white.
const _rootText = Color(0xffffffff);

/// Section text fill = `cScaleLabel<i>` = `invert(labelTextColor)` for i==0,
/// else `labelTextColor` (black `#333`). Branches use the dark label.
const _sectionText = Color(0xff333333);

/// Perceived luminance, for choosing readable text on a fill.
double _luminance(Color c) =>
    (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) / 255;

/// Approximate one SVG relative elliptical arc (`a rx ry 0 0 sweep dx dy`,
/// large-arc-flag always 0 as in upstream cloud/bang paths) as cubic Béziers,
/// appending the segments to [out] starting at [from]. Returns the end point.
///
/// The IR has no arc command, so we subdivide the arc into <=90° pieces and
/// emit a cubic per piece — visually indistinguishable from the SVG arc.
Point _arcTo(
  List<PathCommand> out,
  Point from,
  double rx,
  double ry,
  int sweep,
  double dx,
  double dy,
) {
  final end = Point(from.x + dx, from.y + dy);
  rx = rx.abs();
  ry = ry.abs();
  if (rx == 0 || ry == 0) {
    out.add(LineTo(end));
    return end;
  }
  // Endpoint -> center parameterization (xAxisRotation = 0, largeArc = 0).
  final x1 = from.x, y1 = from.y, x2 = end.x, y2 = end.y;
  final dx2 = (x1 - x2) / 2, dy2 = (y1 - y2) / 2;
  var rxs = rx * rx, rys = ry * ry;
  final px = dx2 * dx2, py = dy2 * dy2;
  final radiiCheck = px / rxs + py / rys;
  if (radiiCheck > 1) {
    final s = math.sqrt(radiiCheck);
    rx *= s;
    ry *= s;
    rxs = rx * rx;
    rys = ry * ry;
  }
  var sign = (sweep == 0) ? 1.0 : -1.0; // largeArc==sweep -> 0; differ -> sign
  var num = rxs * rys - rxs * py - rys * px;
  if (num < 0) num = 0;
  var den = rxs * py + rys * px;
  final coef = (den == 0) ? 0.0 : sign * math.sqrt(num / den);
  final cxp = coef * (rx * dy2 / ry);
  final cyp = coef * -(ry * dx2 / rx);
  final cx = cxp + (x1 + x2) / 2;
  final cy = cyp + (y1 + y2) / 2;
  double angle(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    var a = math.acos((dot / len).clamp(-1.0, 1.0));
    if (ux * vy - uy * vx < 0) a = -a;
    return a;
  }

  final theta1 = angle(1, 0, (dx2 - cxp) / rx, (dy2 - cyp) / ry);
  var dtheta = angle((dx2 - cxp) / rx, (dy2 - cyp) / ry,
      (-dx2 - cxp) / rx, (-dy2 - cyp) / ry);
  if (sweep == 0 && dtheta > 0) dtheta -= 2 * math.pi;
  if (sweep == 1 && dtheta < 0) dtheta += 2 * math.pi;

  final segments = math.max(1, (dtheta.abs() / (math.pi / 2)).ceil());
  final delta = dtheta / segments;
  final t = 4 / 3 * math.tan(delta / 4);
  var th = theta1;
  var startX = x1, startY = y1;
  for (var i = 0; i < segments; i++) {
    final thNext = th + delta;
    final cosTh = math.cos(th), sinTh = math.sin(th);
    final cosNext = math.cos(thNext), sinNext = math.sin(thNext);
    final ex = cx + rx * cosNext, ey = cy + ry * sinNext;
    final c1 = Point(
      startX + (-rx * sinTh) * t,
      startY + (ry * cosTh) * t,
    );
    final c2 = Point(
      ex - (-rx * sinNext) * t,
      ey - (ry * cosNext) * t,
    );
    out.add(CubicTo(c1, c2, Point(ex, ey)));
    startX = ex;
    startY = ey;
    th = thNext;
  }
  return end;
}

/// Builds the cloud-shape path (port of `svgDraw.cloudBkg`). [pt] maps a
/// local point (origin at node top-left) to scene coordinates; [w]/[h] are
/// the node size. Relative SVG arcs are approximated with cubic Béziers.
List<PathCommand> _cloudPath(Point Function(double, double) pt, double w, double h) {
  final r1 = 0.15 * w;
  final r2 = 0.25 * w;
  final r3 = 0.35 * w;
  final r4 = 0.2 * w;
  // Walk in local coords, emitting commands via a local->scene wrapper.
  final out = <PathCommand>[];
  var cur = const Point(0, 0);
  out.add(MoveTo(pt(cur.x, cur.y)));
  // Local arc helper: appends to a temporary list in local coords, then we
  // remap. Simpler: build a local list, then translate at the end.
  final local = <PathCommand>[];
  Point arc(Point from, double rx, double ry, int sweep, double dx, double dy) =>
      _arcTo(local, from, rx, ry, sweep, dx, dy);
  cur = arc(cur, r1, r1, 1, w * 0.25, -w * 0.1);
  cur = arc(cur, r3, r3, 1, w * 0.4, -w * 0.1);
  cur = arc(cur, r2, r2, 1, w * 0.35, w * 0.2);
  cur = arc(cur, r1, r1, 1, w * 0.15, h * 0.35);
  cur = arc(cur, r4, r4, 1, -w * 0.15, h * 0.65);
  cur = arc(cur, r2, r1, 1, -w * 0.25, w * 0.15);
  cur = arc(cur, r3, r3, 1, -w * 0.5, 0);
  cur = arc(cur, r1, r1, 1, -w * 0.25, -w * 0.15);
  cur = arc(cur, r1, r1, 1, -w * 0.1, -h * 0.35);
  cur = arc(cur, r4, r4, 1, w * 0.1, -h * 0.65);
  local.add(LineTo(Point(0, cur.y))); // H0
  local.add(const LineTo(Point(0, 0))); // V0
  local.add(const ClosePath());
  out.addAll(_remap(local, pt));
  return out;
}

/// Builds the bang-shape path (port of `svgDraw.bangBkg`).
List<PathCommand> _bangPath(Point Function(double, double) pt, double w, double h) {
  final r = 0.15 * w;
  final out = <PathCommand>[];
  out.add(MoveTo(pt(0, 0)));
  final local = <PathCommand>[];
  var cur = const Point(0, 0);
  Point arc(Point from, double rx, double ry, int sweep, double dx, double dy) =>
      _arcTo(local, from, rx, ry, sweep, dx, dy);
  cur = arc(cur, r, r, 0, w * 0.25, -h * 0.1);
  cur = arc(cur, r, r, 0, w * 0.25, 0);
  cur = arc(cur, r, r, 0, w * 0.25, 0);
  cur = arc(cur, r, r, 0, w * 0.25, h * 0.1);
  cur = arc(cur, r, r, 0, w * 0.15, h * 0.33);
  cur = arc(cur, r * 0.8, r * 0.8, 0, 0, h * 0.34);
  cur = arc(cur, r, r, 0, -w * 0.15, h * 0.33);
  cur = arc(cur, r, r, 0, -w * 0.25, h * 0.15);
  cur = arc(cur, r, r, 0, -w * 0.25, 0);
  cur = arc(cur, r, r, 0, -w * 0.25, 0);
  cur = arc(cur, r, r, 0, -w * 0.25, -h * 0.15);
  cur = arc(cur, r, r, 0, -w * 0.1, -h * 0.33);
  cur = arc(cur, r * 0.8, r * 0.8, 0, 0, -h * 0.34);
  cur = arc(cur, r, r, 0, w * 0.1, -h * 0.33);
  local.add(LineTo(Point(0, cur.y))); // H0
  local.add(const LineTo(Point(0, 0))); // V0
  local.add(const ClosePath());
  out.addAll(_remap(local, pt));
  return out;
}

/// Remaps local-coordinate path commands through [pt] into scene coordinates.
List<PathCommand> _remap(
    List<PathCommand> local, Point Function(double, double) pt) {
  Point m(Point p) => pt(p.x, p.y);
  return [
    for (final c in local)
      switch (c) {
        MoveTo() => MoveTo(m(c.p)),
        LineTo() => LineTo(m(c.p)),
        CubicTo() => CubicTo(m(c.c1), m(c.c2), m(c.p)),
        QuadTo() => QuadTo(m(c.c), m(c.p)),
        ClosePath() => const ClosePath(),
      }
  ];
}

class _PlacedMind {
  _PlacedMind(this.node, this.size);

  final MindmapNode node;
  final Size size;
  Point center = Point.zero;
  double subtreeExtent = 0;

  /// Section index for this node (`branchIndex % 11`), or -1 for the root.
  int section = -1;

  /// Resolved fill color (section fill / root fill).
  Color color = _rootFill;
}

RenderScene layoutMindmap(
  Mindmap map, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const siblingGap = 14.0;
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final nodes = <SceneNode>[];
  final placed = <MindmapNode, _PlacedMind>{};

  // Merge the classDefs attached to a node (later classes win), returning the
  // resolved fill/stroke/text colors — any of which may be null if unset.
  ({Color? fill, Color? stroke, Color? text})? classStyle(MindmapNode n) {
    if (n.cssClasses.isEmpty || map.classDefs.isEmpty) return null;
    final merged = <String, String>{};
    var matched = false;
    for (final cls in n.cssClasses) {
      final def = map.classDefs[cls];
      if (def != null) {
        merged.addAll(def);
        matched = true;
      }
    }
    if (!matched) return null;
    return (
      fill: merged['fill'] != null ? Color.tryParse(merged['fill']!) : null,
      stroke:
          merged['stroke'] != null ? Color.tryParse(merged['stroke']!) : null,
      text: merged['color'] != null ? Color.tryParse(merged['color']!) : null,
    );
  }

  _PlacedMind measure(MindmapNode n) {
    final style = n.depth == 0 ? baseStyle.copyWith(fontWeight: 700) : baseStyle;
    // Upstream: maxNodeWidth 200, padding 10 (doubled for rect/rounded/hexagon).
    final labelSize = measurer.measure(n.label, style, maxWidth: 200);
    final padding = switch (n.shape) {
      MindmapShape.rect ||
      MindmapShape.rounded ||
      MindmapShape.hexagon =>
        20.0,
      _ => 10.0,
    };
    // svgDraw.drawNode: width = bbox.w + 2*padding,
    //                   height = bbox.h + fontSize*1.1*0.5 + padding.
    var w = labelSize.width + 2 * padding;
    var h = labelSize.height + theme.fontSize * 1.1 * 0.5 + padding;
    if (n.icon != null) {
      // Icon foreignObject: CIRCLE adds +50 w/h, others +50 w and min height 60.
      if (n.shape == MindmapShape.circle) {
        w += 50;
        h += 50;
      } else {
        w += 50;
        h = math.max(h, 60);
      }
    }
    if (n.shape == MindmapShape.circle) {
      // circleBkg: r = width/2 — square the box so the diameter encloses text.
      final d = math.max(w, h);
      w = d;
      h = d;
    }
    final p = _PlacedMind(n, Size(w, h));
    placed[n] = p;
    var extent = 0.0;
    for (final c in n.children) {
      extent += measure(c).subtreeExtent + siblingGap;
    }
    extent = math.max(extent - siblingGap, h);
    p.subtreeExtent = extent;
    return p;
  }

  measure(map.root);

  // Radial layout, like upstream's settled force simulation: each branch
  // gets an angular sector proportional to its leaf count, nodes sit at a
  // radius that grows with depth (stretched horizontally because labels
  // are wide).
  int leaves(MindmapNode n) => n.children.isEmpty
      ? 1
      : n.children.fold(0, (a, c) => a + leaves(c));

  final rootP = placed[map.root]!;
  rootP.center = Point.zero;

  void placeRadial(MindmapNode n, double a0, double a1, int depth) {
    final p = placed[n]!;
    if (depth > 0) {
      final angle = (a0 + a1) / 2;
      final r = 92.0 * depth + 15.0 * (depth - 1);
      // Wide labels need extra horizontal reach.
      p.center = Point(
        math.cos(angle) * (r * 1.3 + p.size.width / 2),
        math.sin(angle) * r,
      );
    }
    final total = leaves(n);
    var a = a0;
    for (final c in n.children) {
      final span = (a1 - a0) * leaves(c) / total;
      placeRadial(c, a, a + span, depth + 1);
      a += span;
    }
  }

  // Start at the upper right and walk clockwise, mirroring the typical
  // upstream result.
  placeRadial(map.root, -math.pi / 3, 2 * math.pi - math.pi / 3, 0);

  // Sections: each first-level child gets `section = index % 11`; descendants
  // inherit it (upstream `assignSections`). Section drives fill + edge stroke.
  void tint(MindmapNode n, int section) {
    final p = placed[n]!;
    p.section = section;
    p.color = _sectionFills[section % _sectionFills.length];
    for (final c in n.children) {
      tint(c, section);
    }
  }

  const maxSections = 11; // MAX_SECTIONS - 1
  for (var i = 0; i < map.root.children.length; i++) {
    tint(map.root.children[i], i % maxSections);
  }

  // Edges: cubic from parent edge to child edge.
  void edges(MindmapNode n) {
    final p = placed[n]!;
    for (final c in n.children) {
      final cp = placed[c]!;
      // Center-to-center; nodes paint on top, hiding the covered ends.
      // Upstream `.edge-depth-<d> { stroke-width: 17 - 3*d }` (d = edge depth =
      // parent.level + 1), so root edges are thick (~17) and thin with depth.
      final edgeDepth = cp.node.depth;
      final width = math.max(1.0, 17.0 - 3.0 * edgeDepth);
      nodes.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(p.center),
          CubicTo(
            Point(p.center.x + (cp.center.x - p.center.x) * 0.55,
                p.center.y + (cp.center.y - p.center.y) * 0.1),
            Point(p.center.x + (cp.center.x - p.center.x) * 0.9,
                p.center.y + (cp.center.y - p.center.y) * 0.85),
            cp.center,
          ),
        ]),
        stroke: Stroke(color: cp.color, width: width),
      ));
      edges(c);
    }
  }

  edges(map.root);

  // Nodes on top.
  void draw(MindmapNode n) {
    final p = placed[n]!;
    final style =
        n.depth == 0 ? baseStyle.copyWith(fontWeight: 700) : baseStyle;
    final labelSize = measurer.measure(n.label, style, maxWidth: 200);
    final rect = Rect.fromCenter(p.center, p.size.width, p.size.height);
    final w = p.size.width;
    final h = p.size.height;
    // Local-coordinate origin = node top-left corner; upstream shape paths are
    // authored in that frame (`M0 0` etc).
    final ox = rect.left;
    final oy = rect.top;
    Point pt(double x, double y) => Point(ox + x, oy + y);
    final isRoot = n.depth == 0;
    // A `:::class` mapped to a classDef overrides the section palette fill.
    final cls = classStyle(n);
    final fill = cls?.fill ?? (isRoot ? _rootFill : p.color);
    final stroke = cls?.stroke;
    // Text color: explicit classDef `color:` wins; otherwise the default theme
    // paints root text `gitBranchLabel0` (white) and section text the dark
    // label color `#333` (cScaleLabel for i>0).
    final textColor = cls?.text ??
        (cls?.fill != null
            ? (_luminance(cls!.fill!) < 0.5
                ? const Color(0xffffffff)
                : const Color(0xff333333))
            : (isRoot ? _rootText : _sectionText));
    final children = <SceneNode>[];
    final nodeStroke = stroke != null ? Stroke(color: stroke, width: 2) : null;
    switch (n.shape) {
      case MindmapShape.circle:
        children.add(SceneShape(
          geometry: CircleGeometry(p.center, p.size.width / 2),
          fill: Fill(fill),
          stroke: nodeStroke,
        ));
      case MindmapShape.rect:
        children.add(SceneShape(
          geometry: RectGeometry(rect),
          fill: Fill(fill),
          stroke: nodeStroke,
        ));
      case MindmapShape.hexagon:
        // Upstream hexagonBkg: m = h/4.
        final m = h / 4;
        children.add(SceneShape(
          geometry: PolygonGeometry([
            pt(m, 0),
            pt(w - m, 0),
            pt(w, h / 2),
            pt(w - m, h),
            pt(m, h),
            pt(0, h / 2),
          ]),
          fill: Fill(fill),
          stroke: nodeStroke,
        ));
      case MindmapShape.cloud:
        children.add(SceneShape(
          geometry: PathGeometry(_cloudPath(pt, w, h)),
          fill: Fill(fill),
          stroke: nodeStroke,
        ));
      case MindmapShape.bang:
        children.add(SceneShape(
          geometry: PathGeometry(_bangPath(pt, w, h)),
          fill: Fill(fill),
          stroke: nodeStroke,
        ));
      case MindmapShape.rounded:
        // roundedRectBkg: rx/ry = padding (=20 for rounded).
        children.add(SceneShape(
          geometry: RectGeometry(rect, rx: 20, ry: 20),
          fill: Fill(fill),
          stroke: nodeStroke,
        ));
      case MindmapShape.plain:
        // defaultBkg: a rounded-top path (rd=5) with a flat bottom, plus a
        // thick horizontal underline at the bottom (`node-line`, width 3,
        // stroke cScaleInv<section>). The signature mindmap look.
        const rd = 5.0;
        children.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(pt(0, h - rd)),
            LineTo(pt(0, rd)),
            QuadTo(pt(0, 0), pt(rd, 0)),
            LineTo(pt(w - rd, 0)),
            QuadTo(pt(w, 0), pt(w, rd)),
            LineTo(pt(w, h)),
            LineTo(pt(0, h)),
            const ClosePath(),
          ]),
          fill: Fill(fill),
          stroke: nodeStroke,
        ));
        final lineColor = isRoot
            ? _sectionLines[0]
            : _sectionLines[p.section % _sectionLines.length];
        children.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(pt(0, h)),
            LineTo(pt(w, h)),
          ]),
          stroke: Stroke(color: lineColor, width: 3),
        ));
    }
    children.add(SceneText(
      text: n.label,
      bounds:
          Rect.fromCenter(p.center, labelSize.width, labelSize.height),
      style: style,
      // Default theme: root text white (`gitBranchLabel0`), section text dark
      // `#333` (`cScaleLabel`). A classDef `color:`/`fill:` overrides (see
      // [textColor] above).
      color: textColor,
    ));
    // `::icon(...)` glyph above the node, if it resolves in a registered pack.
    if (n.icon != null) {
      ensureBuiltinIconPacks();
      final glyph = renderIcon(
        _resolveIconRef(n.icon!),
        Rect.fromCenter(Point(p.center.x, rect.top - 12), 20, 20),
        textColor,
      );
      children.addAll(glyph);
    }
    nodes.add(SceneGroup(
        id: 'mind_${n.label}', semanticLabel: n.label, children: children));
    n.children.forEach(draw);
  }

  draw(map.root);

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  const pad = 16.0;
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

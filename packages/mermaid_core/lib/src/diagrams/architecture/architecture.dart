/// Architecture diagram (`architecture-beta`): services (with icons) and
/// junctions grouped into boxes, connected by edges that attach to a named
/// side (L/R/T/B) of each endpoint. Reference: upstream architecture.
///
/// Placement honours the edge port directions (the "layout tuning" knobs):
/// `a:R -- L:b` puts `b` to the right of `a`, `a:B -- T:b` puts it below, etc.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../detect.dart';
import '../../geometry.dart';
import '../../icons/icon_registry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

class ArchService {
  ArchService(this.id, this.icon, this.label, this.group, this.isJunction,
      {this.iconText});
  final String id;
  final String? icon;
  final String label;
  final String? group;
  final bool isJunction;

  /// Inline icon text from the `service id(("AB"))` form: renders a blank icon
  /// box with the centered text instead of a glyph.
  final String? iconText;
}

/// An `align row|column a b c ...` directive: places the listed members along a
/// shared axis (same y for `row`, same x for `column`).
class ArchAlignment {
  ArchAlignment(this.row, this.members);

  /// True for `row` (horizontal alignment), false for `column` (vertical).
  final bool row;
  final List<String> members;
}

class ArchGroup {
  ArchGroup(this.id, this.icon, this.label, this.parent);
  final String id;
  final String? icon;
  final String label;
  final String? parent;
}

class ArchEdge {
  ArchEdge(this.from, this.fromSide, this.to, this.toSide, this.arrowFrom,
      this.arrowTo,
      {this.label, this.fromGroup = false, this.toGroup = false});
  final String from;
  final String fromSide; // L/R/T/B
  final String to;
  final String toSide;
  final bool arrowFrom;
  final bool arrowTo;

  /// Optional edge label (from `-[label]-` syntax).
  final String? label;

  /// When true, the `from` endpoint references the enclosing group of the
  /// service (`server{group}:B`), so the edge attaches at the group box edge.
  final bool fromGroup;

  /// When true, the `to` endpoint references the enclosing group of the
  /// service (`T:subnet{group}`).
  final bool toGroup;
}

class ArchitectureDiagram {
  const ArchitectureDiagram(this.services, this.groups, this.edges,
      {this.alignments = const []});
  final List<ArchService> services;
  final List<ArchGroup> groups;
  final List<ArchEdge> edges;
  final List<ArchAlignment> alignments;
}

String _bracketLabel(String? s, String id) {
  if (s == null || s.isEmpty) return id;
  return _unquote(s);
}

/// Strips a single layer of surrounding matched quotes (single or double).
String _unquote(String s) {
  if (s.length >= 2 &&
      ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'")))) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

ArchitectureDiagram parseArchitecture(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final services = <ArchService>[];
  final groups = <ArchGroup>[];
  final edges = <ArchEdge>[];
  final alignments = <ArchAlignment>[];
  var seenHeader = false;

  // group id(icon)[Label] [in parent]
  final groupRe = RegExp(
      r'^group\s+(\w+)\s*(?:\((\w+)\))?\s*(?:\[([^\]]*)\])?\s*(?:in\s+(\w+))?\s*$');
  // service id(("iconText"))[Label] [in group] — blank icon box with centered
  // text (upstream `(("AB"))` form). Checked before the plain icon form.
  final svcIconTextRe = RegExp(
      r'^service\s+(\w+)\s*\(\(\s*(?:"([^"]*)"|' "'([^']*)'" r'|([^)]*?))\s*\)\)\s*(?:\[([^\]]*)\])?\s*(?:in\s+(\w+))?\s*$');
  // service id(icon)[Label] [in group]
  final svcRe = RegExp(
      r'^service\s+(\w+)\s*(?:\((\w+)\))?\s*(?:\[([^\]]*)\])?\s*(?:in\s+(\w+))?\s*$');
  final junctionRe = RegExp(r'^junction\s+(\w+)\s*(?:in\s+(\w+))?\s*$');
  // align row|column a b c ... (at least two members)
  final alignRe =
      RegExp(r'^align\s+(row|column)\s+(\w+(?:\s+\w+)+)\s*$');
  // Edge syntax (mirrors the upstream langium grammar):
  //   lhsId {group}? : Dir  <?  ('--' | '-[label]-')  >?  Dir : rhsId {group}?
  // Examples:
  //   a:R -- L:b      a:R --> L:b       a:R <--> L:b
  //   server{group}:B --> T:subnet{group}
  //   db:R -[uses]- L:server
  final edgeRe = RegExp(
      r'^(\w+)(\{group\})?:([LRTB])\s*'
      r'(<?)(?:--|-\[([^\]]*)\]-)(>?)\s*'
      r'([LRTB]):(\w+)(\{group\})?\s*$');

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^architecture(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "architecture" header',
            line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    var m = groupRe.firstMatch(line);
    if (m != null) {
      groups.add(ArchGroup(m.group(1)!, m.group(2),
          _bracketLabel(m.group(3), m.group(1)!), m.group(4)));
      continue;
    }
    m = svcIconTextRe.firstMatch(line);
    if (m != null) {
      final iconText = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      services.add(ArchService(
          m.group(1)!,
          null,
          _bracketLabel(m.group(5), m.group(1)!),
          m.group(6),
          false,
          iconText: iconText));
      continue;
    }
    m = svcRe.firstMatch(line);
    if (m != null) {
      services.add(ArchService(m.group(1)!, m.group(2),
          _bracketLabel(m.group(3), m.group(1)!), m.group(4), false));
      continue;
    }
    m = junctionRe.firstMatch(line);
    if (m != null) {
      services.add(ArchService(m.group(1)!, null, '', m.group(2), true));
      continue;
    }
    m = alignRe.firstMatch(line);
    if (m != null) {
      final members =
          m.group(2)!.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (members.length >= 2) {
        alignments.add(ArchAlignment(m.group(1) == 'row', members));
      }
      continue;
    }
    m = edgeRe.firstMatch(line);
    if (m != null) {
      final arrowFrom = m.group(4) == '<';
      final arrowTo = m.group(6) == '>';
      final rawLabel = m.group(5);
      edges.add(ArchEdge(
        m.group(1)!,
        m.group(3)!,
        m.group(8)!,
        m.group(7)!,
        arrowFrom,
        arrowTo,
        label: (rawLabel == null || rawLabel.isEmpty)
            ? null
            : _unquote(rawLabel),
        fromGroup: m.group(2) != null,
        toGroup: m.group(9) != null,
      ));
      continue;
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty architecture source');
  return ArchitectureDiagram(services, groups, edges, alignments: alignments);
}

// Upstream architecture config defaults (config.schema.yaml:1010-1018):
//   iconSize: 80, padding: 40, fontSize: 16.
const _iconSize = 80.0;
const _padding = 40.0;
const _archFontSize = 16.0;

// Grid cell pitch. Upstream spaces nodes with fcose (idealEdgeLength =
// iconSize * 1.5 plus nodeSeparation 75); we approximate that on a fixed grid
// by pitching cells at iconSize + nodeSeparation so neighbouring icons get
// comparable breathing room to upstream.
const _cell = _iconSize + 75.0;

(int, int) _sideDelta(String side) => switch (side) {
      'R' => (1, 0),
      'L' => (-1, 0),
      'B' => (0, 1),
      'T' => (0, -1),
      _ => (0, 0),
    };

RenderScene layoutArchitecture(
  ArchitectureDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  ensureBuiltinIconPacks();
  // Architecture uses its own fontSize (config default 16), not the global one.
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: _archFontSize);
  final nodes = <SceneNode>[];

  // Map service id -> group id (services only; groups are boxed separately).
  final serviceGroup = <String, String?>{
    for (final s in diagram.services) s.id: s.group,
  };

  // Grid placement: BFS using edge port directions.
  final pos = <String, (int, int)>{};
  final occupied = <(int, int)>{};
  final adjacency = <String, List<(String, (int, int))>>{};
  for (final e in diagram.edges) {
    // Group-anchored endpoints route relative to the service, so they still
    // participate in placement adjacency.
    final d = _sideDelta(e.fromSide);
    adjacency.putIfAbsent(e.from, () => []).add((e.to, d));
    adjacency
        .putIfAbsent(e.to, () => [])
        .add((e.from, (-d.$1, -d.$2)));
  }

  void place(String id, int x, int y) {
    pos[id] = (x, y);
    occupied.add((x, y));
  }

  var nextRow = 0;
  for (final s in diagram.services) {
    if (pos.containsKey(s.id)) continue;
    place(s.id, 0, nextRow);
    final queue = [s.id];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      final cp = pos[cur]!;
      for (final (next, delta)
          in adjacency[cur] ?? const <(String, (int, int))>[]) {
        if (pos.containsKey(next)) continue;
        var nx = cp.$1 + delta.$1, ny = cp.$2 + delta.$2;
        // Prefer placing same-group neighbours adjacent, but never share a
        // cell. When the target cell is taken, slide outward along the edge's
        // axis (so nested-group members fan out instead of stacking onto the
        // parent group's other members).
        final stepX = delta.$1 != 0 ? (delta.$1 > 0 ? 1 : -1) : 1;
        final stepY = delta.$2 != 0 ? (delta.$2 > 0 ? 1 : -1) : 0;
        while (occupied.contains((nx, ny))) {
          nx += stepX;
          ny += stepY;
        }
        place(next, nx, ny);
        queue.add(next);
      }
    }
    // Advance to a fresh row band for the next disconnected component.
    nextRow = (pos.values.map((p) => p.$2).fold(0, math.max)) + 2;
  }

  // Apply `align row|column` hints: snap the listed members onto a shared axis,
  // spreading them along the other axis to avoid overlaps. Mirrors upstream's
  // alignment constraints (services co-located on a row share y, a column
  // shares x).
  for (final a in diagram.alignments) {
    final members = a.members.where(pos.containsKey).toList();
    if (members.length < 2) continue;
    if (a.row) {
      final sharedY = members.map((m) => pos[m]!.$2).reduce(math.min);
      // Order members by their current x so the row keeps a sensible sequence.
      members.sort((p, q) => pos[p]!.$1.compareTo(pos[q]!.$1));
      var x = members.map((m) => pos[m]!.$1).reduce(math.min);
      for (final m in members) {
        occupied.remove(pos[m]!);
        while (occupied.contains((x, sharedY))) {
          x++;
        }
        place(m, x, sharedY);
        x++;
      }
    } else {
      final sharedX = members.map((m) => pos[m]!.$1).reduce(math.min);
      members.sort((p, q) => pos[p]!.$2.compareTo(pos[q]!.$2));
      var y = members.map((m) => pos[m]!.$2).reduce(math.min);
      for (final m in members) {
        occupied.remove(pos[m]!);
        while (occupied.contains((sharedX, y))) {
          y++;
        }
        place(m, sharedX, y);
        y++;
      }
    }
  }

  Point centerOf(String id) {
    final p = pos[id] ?? (0, 0);
    return Point(p.$1 * _cell, p.$2 * _cell);
  }

  // ----- Group boxes (behind services) -----
  // Groups can nest (`group sub(cloud)[Sub] in parent`). A group's box must
  // encompass both its member services AND the boxes of its child groups, so
  // we compute rects recursively from the leaves up. Inner boxes are inset a
  // little more (per nesting depth) so they read as nested.
  final groupById = {for (final g in diagram.groups) g.id: g};
  final childGroups = <String, List<ArchGroup>>{};
  for (final g in diagram.groups) {
    if (g.parent != null && groupById.containsKey(g.parent)) {
      childGroups.putIfAbsent(g.parent!, () => []).add(g);
    }
  }

  final svcById = {for (final s in diagram.services) s.id: s};

  // Service-icon bounding box (the painted rect, not just the center).
  // Junctions are an invisible iconSize anchor upstream, so they occupy the
  // same footprint for group-rect purposes.
  Rect serviceRect(String id) {
    final c = centerOf(id);
    return Rect.fromCenter(Point(c.x, c.y - 6), _iconSize, _iconSize);
  }

  // Depth of a group in the nesting tree (top-level == 0).
  int depthOf(String id) {
    var d = 0;
    var cur = groupById[id]?.parent;
    final seen = <String>{};
    while (cur != null && groupById.containsKey(cur) && seen.add(cur)) {
      d++;
      cur = groupById[cur]!.parent;
    }
    return d;
  }

  final groupRects = <String, Rect>{};

  // Recursively compute (and cache) a group's box.
  Rect computeGroupRect(String id, Set<String> visiting) {
    final cached = groupRects[id];
    if (cached != null) return cached;
    if (!visiting.add(id)) {
      // Cycle guard: fall back to an empty box at origin.
      return const Rect.fromLTWH(0, 0, _cell, _cell);
    }
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    void include(Rect r) {
      minX = math.min(minX, r.left);
      minY = math.min(minY, r.top);
      maxX = math.max(maxX, r.right);
      maxY = math.max(maxY, r.bottom);
    }

    for (final s in diagram.services) {
      if (s.group == id) include(serviceRect(s.id));
    }
    for (final child in childGroups[id] ?? const <ArchGroup>[]) {
      include(computeGroupRect(child.id, visiting));
    }
    visiting.remove(id);

    if (minX == double.infinity) {
      // Empty group: give it a small placeholder so it is still visible.
      final c = const Point(0, 0);
      minX = c.x - _cell / 2;
      minY = c.y - _cell / 2;
      maxX = c.x + _cell / 2;
      maxY = c.y + _cell / 2;
    }
    // Upstream uses a uniform padding of 40 around group contents; the top gets
    // extra room for the group icon/label header.
    const pad = _padding;
    const titleSpace = 18.0;
    final rect = Rect.fromLTRB(
        minX - pad, minY - pad - titleSpace, maxX + pad, maxY + pad);
    groupRects[id] = rect;
    return rect;
  }

  for (final g in diagram.groups) {
    computeGroupRect(g.id, <String>{});
  }

  // Draw outermost groups first so nested boxes paint on top of their parents.
  final drawOrder = [...diagram.groups]
    ..sort((a, b) => depthOf(a.id).compareTo(depthOf(b.id)));
  for (final g in drawOrder) {
    final rect = groupRects[g.id];
    if (rect == null) continue;
    // Upstream `.node-bkg`: fill:none, stroke primaryBorderColor,
    // stroke-width:2, stroke-dasharray:8 (i.e. 8 on / 8 off).
    nodes.add(SceneShape(
      geometry: RectGeometry(rect, rx: 10, ry: 10),
      stroke: Stroke(
          color: theme.primaryBorderColor, width: 2, dash: const [8, 8]),
    ));
    final ts = measurer.measure(g.label, baseStyle.copyWith(fontWeight: 700));
    final children = <SceneNode>[];
    // Group icon size = padding * 0.75 (upstream `groupIconSize`).
    const groupIconSize = _padding * 0.75;
    final labelX = rect.left + 8 + (g.icon != null ? groupIconSize + 4 : 0);
    if (g.icon != null) {
      children.addAll(renderIcon(
          _iconRef(g.icon!),
          Rect.fromLTWH(rect.left + 8, rect.top + 6, groupIconSize, groupIconSize),
          theme.textColor));
    }
    nodes.add(SceneText(
      text: g.label,
      bounds: Rect.fromLTWH(labelX, rect.top + 6 + (groupIconSize - ts.height) / 2,
          ts.width, ts.height),
      style: baseStyle.copyWith(fontWeight: 700),
      color: theme.textColor,
      align: TextAlignH.left,
    ));
    nodes.addAll(children);
  }

  // Resolve an edge endpoint: when the `{group}` modifier is present the edge
  // attaches at the enclosing group box edge (adjacent to the service);
  // otherwise it attaches at the service/junction port.
  Point endpoint(String id, String side, bool useGroup) {
    final isJunction = svcById[id]?.isJunction ?? false;
    if (useGroup) {
      final groupId = serviceGroup[id];
      final rect = groupId != null ? groupRects[groupId] : null;
      if (rect != null) return _rectPort(rect, centerOf(id), side);
    }
    return _port(centerOf(id), side, junction: isJunction);
  }

  // Edges (under service icons). Upstream: edge stroke-width 3, arrow size
  // iconSize/6; XY (bend) edges turn at a 90° corner; X/Y edges are direct.
  const arrowSize = _iconSize / 6;
  bool isX(String side) => side == 'L' || side == 'R';
  for (final e in diagram.edges) {
    final from = endpoint(e.from, e.fromSide, e.fromGroup);
    final to = endpoint(e.to, e.toSide, e.toGroup);

    // Axis classification mirrors upstream: a mixed X/Y pair bends; otherwise
    // the edge runs straight along its shared axis.
    final fromX = isX(e.fromSide);
    final toX = isX(e.toSide);
    final isBend = fromX != toX;

    // 90° corner at the perpendicular port projection: the bend takes the x of
    // the vertical (T/B) endpoint and the y of the horizontal (L/R) endpoint.
    final Point bend;
    if (isBend) {
      if (fromX) {
        // from is L/R (horizontal), to is T/B (vertical).
        bend = Point(to.x, from.y);
      } else {
        bend = Point(from.x, to.y);
      }
    } else {
      // Same axis: keep a mid bend so non-aligned ports still connect cleanly.
      bend = fromX
          ? Point(from.x + (to.x - from.x) / 2, from.y)
          : Point(from.x, from.y + (to.y - from.y) / 2);
    }

    final List<PathCommand> cmds;
    if (isBend) {
      cmds = [MoveTo(from), LineTo(bend), LineTo(to)];
    } else if (fromX && from.y == to.y) {
      cmds = [MoveTo(from), LineTo(to)];
    } else if (!fromX && from.x == to.x) {
      cmds = [MoveTo(from), LineTo(to)];
    } else {
      cmds = [
        MoveTo(from),
        LineTo(bend),
        LineTo(fromX ? Point(bend.x, to.y) : Point(to.x, bend.y)),
        LineTo(to),
      ];
    }
    nodes.add(SceneShape(
      geometry: PathGeometry(cmds),
      stroke: Stroke(color: theme.lineColor, width: 3),
    ));
    if (e.arrowTo) nodes.addAll(_arrow(to, e.toSide, theme.lineColor, arrowSize));
    if (e.arrowFrom) {
      nodes.addAll(_arrow(from, e.fromSide, theme.lineColor, arrowSize));
    }
    final label = e.label;
    if (label != null && label.isNotEmpty) {
      // Midpoint of the edge (the bend for XY edges, otherwise the segment mid).
      final mid = isBend
          ? bend
          : Point(from.x + (to.x - from.x) / 2, from.y + (to.y - from.y) / 2);
      final ts = measurer.measure(label, baseStyle);
      // Upstream: text drawn directly over the edge (no background chip).
      // Rotation: -90° for vertical (Y) edges, ±45° for XY (bend) edges.
      double rotation = 0;
      if (isBend) {
        // Bend direction: T/B vs L/R combination yields a ±45° tilt.
        final vertSide = fromX ? e.toSide : e.fromSide;
        final horizSide = fromX ? e.fromSide : e.toSide;
        final x = horizSide == 'L' ? -1 : 1;
        final y = vertSide == 'T' ? -1 : 1;
        rotation = -45.0 * x * y;
      } else if (!fromX) {
        rotation = -90;
      }
      nodes.add(SceneText(
        text: label,
        bounds: Rect.fromCenter(mid, ts.width, ts.height),
        style: baseStyle,
        color: theme.textColor,
        align: TextAlignH.center,
        rotation: rotation,
      ));
    }
  }

  // Services (icon + label).
  for (final s in diagram.services) {
    final c = centerOf(s.id);
    // Junctions are an invisible iconSize anchor upstream — no visible glyph.
    if (s.isJunction) continue;

    final iconRect =
        Rect.fromCenter(Point(c.x, c.y - 6), _iconSize, _iconSize);
    final hasGlyph = s.icon != null || s.iconText != null;
    if (!hasGlyph) {
      // Upstream `.node-bkg` background: top-two-corners rounded path (radius 5)
      // with fill:none (border only).
      nodes.add(SceneShape(
        geometry: PathGeometry(_topRoundedRect(iconRect, 5)),
        stroke: Stroke(color: theme.primaryBorderColor),
      ));
    }
    if (s.icon != null) {
      // The architecture pack glyph paints its own #087ebf box + white line
      // art, so no separate border is drawn (matches upstream `getIconSVG`).
      nodes.addAll(renderIcon(
          _iconRef(s.icon!), iconRect, theme.textColor));
    } else if (s.iconText != null) {
      // Upstream renders the `blank` architecture glyph (the filled #087ebf
      // box) and overlays the centered text in white (`.node-icon-text > div`
      // uses `color: #fff`).
      nodes.addAll(renderIcon(
          'mermaid-architecture:blank', iconRect, theme.textColor));
      final it = s.iconText!;
      final its = measurer.measure(it, baseStyle, maxWidth: _iconSize - 4);
      nodes.add(SceneText(
        text: it,
        bounds: Rect.fromCenter(iconRect.center, its.width, its.height),
        style: baseStyle,
        color: Color.white,
        align: TextAlignH.center,
      ));
    }
    if (s.label.isEmpty) continue;
    // Label below the icon, wrapped at iconSize*1.5 (upstream).
    final ts = measurer.measure(s.label, baseStyle, maxWidth: _iconSize * 1.5);
    nodes.add(SceneText(
      text: s.label,
      bounds: Rect.fromLTWH(
          c.x - ts.width / 2, c.y + _iconSize / 2 - 2, ts.width, ts.height),
      style: baseStyle,
      color: theme.textColor,
      align: TextAlignH.center,
    ));
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  const m = 20.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final n in nodes) translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

/// Architecture icon names mapped to the upstream `mermaid-architecture` pack
/// (the default `#087ebf` box + white glyph). Upstream ships exactly
/// cloud/database/disk/internet/server/blank; an unqualified name that is not
/// one of those falls back to the pack's `unknown`-style blank box (matching
/// upstream's `fallbackPrefix` behaviour). An explicit `prefix:name` ref is
/// honoured as-is so registered iconify packs keep working.
String _iconRef(String name) {
  if (name.contains(':')) return name; // already a pack-qualified ref
  const arch = 'mermaid-architecture:';
  return switch (name.toLowerCase()) {
    'database' || 'db' || 'sql' || 'postgresql' || 'mysql' => '${arch}database',
    'cloud' => '${arch}cloud',
    'internet' || 'web' || 'globe' => '${arch}internet',
    'disk' || 'storage' || 'drive' => '${arch}disk',
    'server' || 'compute' || 'vm' || 'host' => '${arch}server',
    _ => '${arch}blank',
  };
}

/// Builds a rect path with only the top two corners rounded (radius [r]),
/// mirroring upstream's service `.node-bkg` path
/// `M0,h V r Q0,0 r,0 H w-r Q w,0 w,r V h Z`.
List<PathCommand> _topRoundedRect(Rect rect, double r) {
  final l = rect.left, t = rect.top, b = rect.bottom, rt = rect.right;
  return [
    MoveTo(Point(l, b)),
    LineTo(Point(l, t + r)),
    QuadTo(Point(l, t), Point(l + r, t)),
    LineTo(Point(rt - r, t)),
    QuadTo(Point(rt, t), Point(rt, t + r)),
    LineTo(Point(rt, b)),
    const ClosePath(),
  ];
}

/// Attachment point on a service icon's side. Junctions are an invisible
/// iconSize anchor; upstream shifts the endpoint inward by halfIconSize so the
/// edge meets at the junction's center.
Point _port(Point c, String side, {bool junction = false}) {
  // c is the icon center; for non-junctions the port sits on the icon-box edge.
  // Junctions collapse to the center (box edge shifted inward by halfIconSize).
  if (junction) {
    return Point(c.x, c.y - 6);
  }
  const half = _iconSize / 2;
  return switch (side) {
    'R' => Point(c.x + half, c.y - 6),
    'L' => Point(c.x - half, c.y - 6),
    'T' => Point(c.x, c.y - 6 - half),
    'B' => Point(c.x, c.y - 6 + half),
    _ => c,
  };
}

/// Attachment point on a group box edge, aligned with the member service's
/// center along the perpendicular axis (used by the `{group}` edge modifier).
Point _rectPort(Rect rect, Point memberCenter, String side) {
  return switch (side) {
    'R' => Point(rect.right, memberCenter.y - 6),
    'L' => Point(rect.left, memberCenter.y - 6),
    'T' => Point(memberCenter.x, rect.top),
    'B' => Point(memberCenter.x, rect.bottom),
    _ => Point(rect.left, rect.top),
  };
}

List<SceneNode> _arrow(Point tip, String side, Color color, double size) {
  final dir = switch (side) {
    'R' => const Point(1, 0),
    'L' => const Point(-1, 0),
    'T' => const Point(0, -1),
    _ => const Point(0, 1),
  };
  final perp = Point(-dir.y, dir.x);
  return [
    SceneShape(
      geometry: PolygonGeometry([
        tip,
        tip - dir * size + perp * (size / 2),
        tip - dir * size - perp * (size / 2),
      ]),
      fill: Fill(color),
    ),
  ];
}

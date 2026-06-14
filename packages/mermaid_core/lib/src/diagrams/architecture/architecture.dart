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
  ArchService(this.id, this.icon, this.label, this.group, this.isJunction);
  final String id;
  final String? icon;
  final String label;
  final String? group;
  final bool isJunction;
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
  const ArchitectureDiagram(this.services, this.groups, this.edges);
  final List<ArchService> services;
  final List<ArchGroup> groups;
  final List<ArchEdge> edges;
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
  var seenHeader = false;

  // group id(icon)[Label] [in parent]
  final groupRe = RegExp(
      r'^group\s+(\w+)\s*(?:\((\w+)\))?\s*(?:\[([^\]]*)\])?\s*(?:in\s+(\w+))?\s*$');
  // service id(icon)[Label] [in group]
  final svcRe = RegExp(
      r'^service\s+(\w+)\s*(?:\((\w+)\))?\s*(?:\[([^\]]*)\])?\s*(?:in\s+(\w+))?\s*$');
  final junctionRe = RegExp(r'^junction\s+(\w+)\s*(?:in\s+(\w+))?\s*$');
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
  return ArchitectureDiagram(services, groups, edges);
}

const _cell = 90.0;
const _iconSize = 44.0;

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
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.8);
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
  Rect serviceRect(String id) {
    final c = centerOf(id);
    if (svcById[id]?.isJunction ?? false) {
      return Rect.fromCenter(c, 12, 12);
    }
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
    const pad = 28.0;
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
    nodes.add(SceneShape(
      geometry: RectGeometry(rect, rx: 10, ry: 10),
      fill: Fill(theme.clusterBkg),
      stroke: Stroke(color: theme.clusterBorder, dash: const [4, 3]),
    ));
    final ts = measurer.measure(g.label, baseStyle.copyWith(fontWeight: 700));
    final children = <SceneNode>[];
    if (g.icon != null) {
      children.addAll(renderIcon(_iconRef(g.icon!),
          Rect.fromLTWH(rect.left + 8, rect.top + 6, 16, 16), theme.textColor));
    }
    nodes.add(SceneText(
      text: g.label,
      bounds: Rect.fromLTWH(rect.left + (g.icon != null ? 28 : 8), rect.top + 6,
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

  // Edges (under service icons).
  for (final e in diagram.edges) {
    final from = endpoint(e.from, e.fromSide, e.fromGroup);
    final to = endpoint(e.to, e.toSide, e.toGroup);
    final midX = from.x + (to.x - from.x) / 2;
    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(from),
        LineTo(Point(midX, from.y)),
        LineTo(Point(midX, to.y)),
        LineTo(to),
      ]),
      stroke: Stroke(color: theme.lineColor, width: 1.5),
    ));
    if (e.arrowTo) nodes.addAll(_arrow(to, e.toSide, theme.lineColor));
    if (e.arrowFrom) nodes.addAll(_arrow(from, e.fromSide, theme.lineColor));
    final label = e.label;
    if (label != null && label.isNotEmpty) {
      final mid = Point(midX, from.y + (to.y - from.y) / 2);
      final ts = measurer.measure(label, baseStyle);
      // Small background chip so the label stays legible over the edge line.
      nodes.add(SceneShape(
        geometry: RectGeometry(
            Rect.fromCenter(mid, ts.width + 8, ts.height + 4),
            rx: 3,
            ry: 3),
        fill: Fill(theme.background),
      ));
      nodes.add(SceneText(
        text: label,
        bounds: Rect.fromCenter(mid, ts.width, ts.height),
        style: baseStyle,
        color: theme.textColor,
        align: TextAlignH.center,
      ));
    }
  }

  // Services (icon + label).
  for (final s in diagram.services) {
    final c = centerOf(s.id);
    if (s.isJunction) {
      nodes.add(SceneShape(
        geometry: CircleGeometry(c, 5),
        fill: Fill(theme.lineColor),
      ));
      continue;
    }
    final iconRect =
        Rect.fromCenter(Point(c.x, c.y - 6), _iconSize, _iconSize);
    nodes.add(SceneShape(
      geometry: RectGeometry(iconRect, rx: 8, ry: 8),
      fill: Fill(theme.mainBkg),
      stroke: Stroke(color: theme.nodeBorder),
    ));
    if (s.icon != null) {
      nodes.addAll(renderIcon(
          _iconRef(s.icon!),
          Rect.fromCenter(Point(c.x, c.y - 6), _iconSize - 14, _iconSize - 14),
          theme.textColor));
    }
    final ts = measurer.measure(s.label, baseStyle, maxWidth: 90);
    nodes.add(SceneText(
      text: s.label,
      bounds:
          Rect.fromLTWH(c.x - ts.width / 2, c.y + _iconSize / 2 - 2, ts.width, ts.height),
      style: baseStyle,
      color: theme.textColor,
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

/// Architecture icon names (cloud/database/disk/server/internet) mapped to our
/// built-in pack; unknown names fall back to a generic box glyph.
String _iconRef(String name) => switch (name) {
      'database' || 'db' => 'icon:database',
      'cloud' || 'internet' => 'icon:cloud',
      'disk' || 'server' => 'icon:database',
      _ => 'icon:cog',
    };

/// Attachment point on a service icon's side. Junctions have no icon box, so
/// the edge attaches at (or just outside) the junction dot's center.
Point _port(Point c, String side, {bool junction = false}) {
  if (junction) {
    const r = 5.0;
    return switch (side) {
      'R' => Point(c.x + r, c.y),
      'L' => Point(c.x - r, c.y),
      'T' => Point(c.x, c.y - r),
      'B' => Point(c.x, c.y + r),
      _ => c,
    };
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

List<SceneNode> _arrow(Point tip, String side, Color color) {
  final dir = switch (side) {
    'R' => const Point(1, 0),
    'L' => const Point(-1, 0),
    'T' => const Point(0, -1),
    _ => const Point(0, 1),
  };
  final perp = Point(-dir.y, dir.x);
  return [
    SceneShape(
      geometry: PolygonGeometry(
          [tip, tip - dir * 8 + perp * 4, tip - dir * 8 - perp * 4]),
      fill: Fill(color),
    ),
  ];
}

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
      this.arrowTo);
  final String from;
  final String fromSide; // L/R/T/B
  final String to;
  final String toSide;
  final bool arrowFrom;
  final bool arrowTo;
}

class ArchitectureDiagram {
  const ArchitectureDiagram(this.services, this.groups, this.edges);
  final List<ArchService> services;
  final List<ArchGroup> groups;
  final List<ArchEdge> edges;
}

String _bracketLabel(String? s, String id) {
  if (s == null || s.isEmpty) return id;
  var l = s;
  if (l.length >= 2 && l.startsWith('"') && l.endsWith('"')) {
    l = l.substring(1, l.length - 1);
  }
  return l;
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
  // a:R -- L:b   |  a:R --> L:b  |  a:R <--> L:b  (also single '-')
  final edgeRe = RegExp(
      r'^(\w+)\{?\}?:([LRTB])\s*(<?-{1,2}>?)\s*([LRTB]):(\w+)\s*$');

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
      final op = m.group(3)!;
      edges.add(ArchEdge(m.group(1)!, m.group(2)!, m.group(5)!, m.group(4)!,
          op.startsWith('<'), op.endsWith('>')));
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

  // Grid placement: BFS using edge port directions.
  final pos = <String, (int, int)>{};
  final adjacency = <String, List<(String, (int, int))>>{};
  for (final e in diagram.edges) {
    final d = _sideDelta(e.fromSide);
    adjacency.putIfAbsent(e.from, () => []).add((e.to, d));
    adjacency
        .putIfAbsent(e.to, () => [])
        .add((e.from, (-d.$1, -d.$2)));
  }
  var nextRow = 0;
  for (final s in diagram.services) {
    if (pos.containsKey(s.id)) continue;
    pos[s.id] = (0, nextRow);
    final queue = [s.id];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      final cp = pos[cur]!;
      for (final (next, delta)
          in adjacency[cur] ?? const <(String, (int, int))>[]) {
        if (pos.containsKey(next)) continue;
        var nx = cp.$1 + delta.$1, ny = cp.$2 + delta.$2;
        // Avoid overlap: nudge along the row if taken.
        while (pos.values.contains((nx, ny))) {
          nx += 1;
        }
        pos[next] = (nx, ny);
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

  // Group boxes (behind services): bounding box of members.
  for (final g in diagram.groups) {
    final members =
        diagram.services.where((s) => s.group == g.id).map((s) => centerOf(s.id));
    if (members.isEmpty) continue;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final c in members) {
      minX = math.min(minX, c.x);
      minY = math.min(minY, c.y);
      maxX = math.max(maxX, c.x);
      maxY = math.max(maxY, c.y);
    }
    const pad = 40.0;
    final rect = Rect.fromLTRB(
        minX - pad, minY - pad - 8, maxX + pad, maxY + pad);
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

  // Edges (under service icons).
  for (final e in diagram.edges) {
    final a = centerOf(e.from), b = centerOf(e.to);
    final from = _port(a, e.fromSide);
    final to = _port(b, e.toSide);
    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(from),
        LineTo(Point(from.x + (to.x - from.x) / 2, from.y)),
        LineTo(Point(from.x + (to.x - from.x) / 2, to.y)),
        LineTo(to),
      ]),
      stroke: Stroke(color: theme.lineColor, width: 1.5),
    ));
    if (e.arrowTo) nodes.addAll(_arrow(to, e.toSide, theme.lineColor));
    if (e.arrowFrom) nodes.addAll(_arrow(from, e.fromSide, theme.lineColor));
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

Point _port(Point c, String side) {
  const half = _iconSize / 2;
  return switch (side) {
    'R' => Point(c.x + half, c.y - 6),
    'L' => Point(c.x - half, c.y - 6),
    'T' => Point(c.x, c.y - 6 - half),
    'B' => Point(c.x, c.y - 6 + half),
    _ => c,
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

/// Requirement diagram: model, parser and layout — one file.
///
/// Reference: upstream requirementDiagram jison grammar + requirementDb.
library;

import 'dart:math' as math;

import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';
import '../../vendor/dagre/dart_dagre.dart' as dagre;

class RequirementDiagram {
  const RequirementDiagram({
    required this.nodes,
    required this.relations,
    this.title,
  });

  /// Requirements and elements, keyed by id, first-mention order.
  final Map<String, ReqNode> nodes;
  final List<ReqRelation> relations;
  final String? title;
}

class ReqNode {
  const ReqNode({
    required this.id,
    required this.kind,
    this.fields = const [],
  });

  final String id;

  /// `requirement`, `functionalRequirement`, ..., or `element`.
  final String kind;

  /// (label, value) rows like (`id`, `1.1`), (`text`, ...), (`risk`, High).
  final List<(String, String)> fields;
}

class ReqRelation {
  const ReqRelation({required this.from, required this.to, required this.label});

  final String from;
  final String to;

  /// contains / copies / derives / satisfies / verifies / refines / traces.
  final String label;
}

const _kinds = {
  'requirement',
  'functionalRequirement',
  'interfaceRequirement',
  'performanceRequirement',
  'physicalRequirement',
  'designConstraint',
  'element',
};

/// Maps a requirement keyword to its mermaid display name (see
/// `requirementDb.ts` `RequirementType`). Elements use the literal `Element`.
const _kindDisplay = {
  'requirement': 'Requirement',
  'functionalRequirement': 'Functional Requirement',
  'interfaceRequirement': 'Interface Requirement',
  'performanceRequirement': 'Performance Requirement',
  'physicalRequirement': 'Physical Requirement',
  'designConstraint': 'Design Constraint',
  'element': 'Element',
};

/// Maps a raw field key to its mermaid body-row prefix (see `requirementBox.ts`).
const _fieldPrefix = {
  'id': 'ID',
  'text': 'Text',
  'risk': 'Risk',
  'verifyMethod': 'Verification',
  'type': 'Type',
  'docRef': 'Doc Ref',
};

/// Risk keyword -> display value (`requirementDb.ts` `RiskLevel`).
const _riskDisplay = {
  'low': 'Low',
  'medium': 'Medium',
  'high': 'High',
};

/// Verify-method keyword -> display value (`requirementDb.ts` `VerifyType`).
const _verifyDisplay = {
  'analysis': 'Analysis',
  'demonstration': 'Demonstration',
  'inspection': 'Inspection',
  'test': 'Test',
};

/// Applies upstream value normalization for risk/verify keywords. Other field
/// values pass through unchanged.
String _displayFieldValue(String key, String value) {
  switch (key) {
    case 'risk':
      return _riskDisplay[value.toLowerCase()] ?? value;
    case 'verifyMethod':
      return _verifyDisplay[value.toLowerCase()] ?? value;
    default:
      return value;
  }
}

RequirementDiagram parseRequirementDiagram(String source) {
  final frontTitle = frontmatterTitle(source);
  final text = stripMetadata(source);
  final nodes = <String, ReqNode>{};
  final relations = <ReqRelation>[];
  String? title = frontTitle;
  var seenHeader = false;
  (String, String, List<(String, String)>)? open; // kind, id, fields

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^requirementDiagram\b').hasMatch(line)) {
        throw MermaidParseException('expected "requirementDiagram" header',
            line: i + 1);
      }
      seenHeader = true;
      continue;
    }

    if (open != null) {
      if (line == '}') {
        nodes[open.$2] =
            ReqNode(id: open.$2, kind: open.$1, fields: open.$3);
        open = null;
        continue;
      }
      final m = RegExp(r'^([\w]+)\s*:\s*(.+)$').firstMatch(line);
      if (m != null) {
        var key = m.group(1)!.toLowerCase();
        key = switch (key) {
          'verifymethod' => 'verifyMethod',
          'docref' => 'docRef',
          _ => key,
        };
        var value = m.group(2)!.trim();
        // Upstream string tokens strip surrounding double quotes.
        if (value.length >= 2 &&
            value.startsWith('"') &&
            value.endsWith('"')) {
          value = value.substring(1, value.length - 1);
        }
        open.$3.add((key, value));
        continue;
      }
      throw MermaidParseException('unrecognized field "$line"', line: i + 1);
    }

    Match? m;
    m = RegExp(r'^(\w+)\s+(.+?)\s*\{$').firstMatch(line);
    if (m != null && _kinds.contains(m.group(1))) {
      open = (m.group(1)!, m.group(2)!, []);
      continue;
    }
    // a - label -> b   |   a <- label - b  (names may contain spaces)
    const relWords = 'contains|copies|derives|satisfies|verifies|refines|traces';
    m = RegExp('^(.+?)\\s*-\\s*($relWords)\\s*->\\s*(.+?)\$').firstMatch(line);
    if (m != null) {
      relations.add(ReqRelation(
          from: m.group(1)!, to: m.group(3)!, label: m.group(2)!));
      _ensure(nodes, m.group(1)!);
      _ensure(nodes, m.group(3)!);
      continue;
    }
    m = RegExp('^(.+?)\\s*<-\\s*($relWords)\\s*-\\s*(.+?)\$').firstMatch(line);
    if (m != null) {
      relations.add(ReqRelation(
          from: m.group(3)!, to: m.group(1)!, label: m.group(2)!));
      _ensure(nodes, m.group(1)!);
      _ensure(nodes, m.group(3)!);
      continue;
    }
    m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      continue;
    }
    if (RegExp(r'^(acc(Title|Descr)\s*[:{]|direction\s)').hasMatch(line)) {
      continue;
    }
    // Tolerate styling/interaction directives. Full styling (classDef/class/
    // style -> per-node cssStyles + colorIndex cycling) is not yet applied —
    // upstream's default theme has no `borderColorArray`, so the common case
    // (no explicit styles) is unaffected. We skip these rather than throw so
    // valid diagrams still render.
    if (RegExp(r'^(classDef|class|style|click|callback|link)\b')
        .hasMatch(line)) {
      continue;
    }
    throw MermaidParseException('unrecognized statement "$line"', line: i + 1);
  }
  if (!seenHeader) {
    throw const MermaidParseException('empty requirement diagram source');
  }
  return RequirementDiagram(nodes: nodes, relations: relations, title: title);
}

void _ensure(Map<String, ReqNode> nodes, String id) {
  nodes.putIfAbsent(id, () => ReqNode(id: id, kind: 'element'));
}

RenderScene layoutRequirementDiagram(
  RequirementDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  // Upstream `requirementRenderer` uses SVG padding of 8.
  const pad = 8.0;
  // Upstream node padding/gap (`requirementBox.ts`): padding 20, gap 20.
  const boxPadding = 20.0;
  const gap = 20.0;
  // Upstream node text uses the full configured font size (no shrink).
  final baseStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final titleStyle = baseStyle.copyWith(fontWeight: 700);

  // Measure boxes: «Type» line, bold name, gap, divider, prefixed field rows.
  // The bool flag marks the row after which a gap is inserted (the name row).
  final boxes =
      <String, (Size, List<(String, TextStyleSpec, Size, bool)>)>{};
  for (final n in diagram.nodes.values) {
    final lines = <(String, TextStyleSpec, Size, bool)>[];
    void add(String text, TextStyleSpec style, {bool gapAfter = false}) {
      lines.add(
          (text, style, measurer.measure(text, style, maxWidth: 240), gapAfter));
    }

    final display = _kindDisplay[n.kind] ?? n.kind;
    add('«$display»', baseStyle.copyWith(italic: true));
    add(n.id, titleStyle, gapAfter: true);
    for (final (k, v) in n.fields) {
      if (v.isEmpty) continue;
      final value = _displayFieldValue(k, v);
      final prefix = _fieldPrefix[k];
      add(prefix != null ? '$prefix: $value' : '$k: $value', baseStyle);
    }
    var w = 0.0, h = boxPadding;
    for (final (_, _, s, gapAfter) in lines) {
      w = w > s.width ? w : s.width;
      h += s.height + 4;
      if (gapAfter) h += gap;
    }
    boxes[n.id] = (Size(w + boxPadding, h), lines);
  }

  final g = dagre.DagreGraph();
  // Use first relation appearance as Dagre's stable tie-break order. This is
  // the order upstream's relationship graph exposes to Dagre and keeps source
  // siblings on the same side as their targets, avoiding avoidable crossings.
  final nodeOrder = <String>{};
  for (final relation in diagram.relations) {
    nodeOrder.add(relation.from);
    nodeOrder.add(relation.to);
  }
  nodeOrder.addAll(boxes.keys);
  for (final id in nodeOrder) {
    final b = boxes[id]!;
    g.addNode(dagre.DagreNode(id, width: b.$1.width, height: b.$1.height));
  }
  final labelSizes = <int, Size>{};
  for (var i = 0; i < diagram.relations.length; i++) {
    final r = diagram.relations[i];
    final size = measurer.measure('«${r.label}»', baseStyle);
    labelSizes[i] = size;
    g.addEdge(dagre.DagreEdge(r.from, r.to,
        id: 'e$i',
        minLen: 1,
        width: size.width,
        height: size.height,
        labelPos: dagre.LabelPosition.center));
  }
  final result = dagre.layout(g,
      dagre.DagreConfig(rankDir: dagre.RankDir.ttb, nodeSep: 50, rankSep: 50));

  final nodes = <SceneNode>[];
  final centers = <String, Point>{};
  boxes.forEach((id, b) {
    centers[id] = result.graph.nodeMap[id]!.position!.center;
  });
  final originalCenters = Map<String, Point>.from(centers);

  // Dagre's stable tie-break can retain a same-rank source order that creates
  // a crossing even when each source has a clear target column. Reorder only
  // those same-rank siblings by the average x position of their downstream
  // targets, then reroute their incident edges from the corrected centers.
  final movedNodes = <String>{};
  final byY = centers.keys.toList()
    ..sort((a, b) => centers[a]!.y.compareTo(centers[b]!.y));
  final rankGroups = <List<String>>[];
  for (final id in byY) {
    if (rankGroups.isEmpty ||
        (centers[id]!.y - centers[rankGroups.last.first]!.y).abs() > 25) {
      rankGroups.add([id]);
    } else {
      rankGroups.last.add(id);
    }
  }
  for (final rank in rankGroups.where((group) => group.length > 1)) {
    double targetX(String id) {
      final targets = diagram.relations
          .where((relation) => relation.from == id)
          .map((relation) => centers[relation.to])
          .whereType<Point>()
          .where((target) => target.y > centers[id]!.y)
          .toList();
      if (targets.isEmpty) return centers[id]!.x;
      return targets.fold(0.0, (sum, target) => sum + target.x) /
          targets.length;
    }

    final ordered = [...rank]
      ..sort((a, b) {
        final byTarget = targetX(a).compareTo(targetX(b));
        return byTarget != 0
            ? byTarget
            : centers[a]!.x.compareTo(centers[b]!.x);
      });
    final current = [...rank]
      ..sort((a, b) => centers[a]!.x.compareTo(centers[b]!.x));
    if (List.generate(
      ordered.length,
      (i) => ordered[i] == current[i],
    ).every((same) => same)) {
      continue;
    }

    int incomingFromAbove(String id) => diagram.relations
        .where((relation) => relation.to == id)
        .where((relation) => centers[relation.from]!.y < centers[id]!.y)
        .length;
    var anchor = 0;
    for (var i = 1; i < ordered.length; i++) {
      if (incomingFromAbove(ordered[i]) > incomingFromAbove(ordered[anchor])) {
        anchor = i;
      }
    }
    final assigned = <String, double>{
      ordered[anchor]: centers[ordered[anchor]]!.x,
    };
    for (var i = anchor - 1; i >= 0; i--) {
      final next = ordered[i + 1];
      assigned[ordered[i]] =
          assigned[next]! -
          boxes[next]!.$1.width / 2 -
          50 -
          boxes[ordered[i]]!.$1.width / 2;
    }
    for (var i = anchor + 1; i < ordered.length; i++) {
      final previous = ordered[i - 1];
      assigned[ordered[i]] =
          assigned[previous]! +
          boxes[previous]!.$1.width / 2 +
          50 +
          boxes[ordered[i]]!.$1.width / 2;
    }
    for (final id in ordered) {
      final center = centers[id]!;
      final x = assigned[id]!;
      if ((center.x - x).abs() > 0.001) movedNodes.add(id);
      centers[id] = Point(x, center.y);
    }
  }
  for (final sourceId in movedNodes.toList()) {
    ReqRelation? relation;
    for (final candidate in diagram.relations) {
      if (candidate.from == sourceId) {
        relation = candidate;
        break;
      }
    }
    if (relation == null) continue;
    final targetId = relation.to;
    final target = centers[targetId]!;
    final peers =
        centers.keys
            .where((id) => id != targetId)
            .where((id) => (centers[id]!.y - target.y).abs() <= 25)
            .toList()
          ..sort((a, b) => centers[a]!.x.compareTo(centers[b]!.x));
    var x = centers[sourceId]!.x;
    for (final peerId in peers) {
      final peer = centers[peerId]!;
      if (peer.x < target.x) {
        x = math.max(
          x,
          peer.x +
              boxes[peerId]!.$1.width / 2 +
              50 +
              boxes[targetId]!.$1.width / 2,
        );
      } else {
        x = math.min(
          x,
          peer.x -
              boxes[peerId]!.$1.width / 2 -
              50 -
              boxes[targetId]!.$1.width / 2,
        );
      }
    }
    if ((target.x - x).abs() > 0.001) {
      centers[targetId] = Point(x, target.y);
      movedNodes.add(targetId);
    }
  }

  for (var i = 0; i < diagram.relations.length; i++) {
    final r = diagram.relations[i];
    final dagreEdge = result.graph.findEdgeById('e$i')!;
    var pts = List<Point>.from(dagreEdge.points);
    if (movedNodes.contains(r.from) || movedNodes.contains(r.to)) {
      pts = _translateRoute(
        pts,
        centers[r.from]! - originalCenters[r.from]!,
        centers[r.to]! - originalCenters[r.to]!,
      );
    }
    if (pts.length < 2) pts = [centers[r.from]!, centers[r.to]!];
    final fromRect =
        Rect.fromCenter(centers[r.from]!, boxes[r.from]!.$1.width, boxes[r.from]!.$1.height);
    final toRect =
        Rect.fromCenter(centers[r.to]!, boxes[r.to]!.$1.width, boxes[r.to]!.$1.height);
    pts[0] = _intersectRect(fromRect, pts[1]);
    pts[pts.length - 1] = _intersectRect(toRect, pts[pts.length - 2]);
    final isContains = r.label == 'contains';

    // Upstream: `contains` is solid (`pattern: normal`), other relations are
    // dashed with `stroke-dasharray: 10,7` (`requirementDb.ts:327`).
    final dash = isContains ? null : const <double>[10, 7];

    final children = <SceneNode>[];
    if (isContains) {
      // `contains` uses a start marker (circle r=9 + crosshair) at the `from`
      // end, no end arrow (`markers.js:requirement_contains`, refX 0).
      final border = pts.first;
      const markerRadius = 9.0;
      final start = _outsideMarkerCenter(fromRect, border, markerRadius);
      pts[0] = start;
      final sdir = _dir(pts[1], start); // points from line toward the source
      // Marker center sits at the start point; the crosshair lines span the
      // circle. Reproduce circle (r=9) + two crossing lines.
      final perp = Point(-sdir.y, sdir.x);
      children.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(pts.first),
          for (final p in pts.skip(1)) LineTo(p),
        ]),
        stroke: Stroke(color: theme.relationColor, width: 1.3, dash: dash),
      ));
      children.add(SceneShape(
        geometry: CircleGeometry(start, markerRadius),
        stroke: Stroke(color: theme.relationColor, width: 1),
      ));
      // Crosshair: one line along the edge direction, one perpendicular.
      children.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(start - sdir * markerRadius),
          LineTo(start + sdir * markerRadius),
        ]),
        stroke: Stroke(color: theme.relationColor, width: 1),
      ));
      children.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(start - perp * markerRadius),
          LineTo(start + perp * markerRadius),
        ]),
        stroke: Stroke(color: theme.relationColor, width: 1),
      ));
    } else {
      // Non-contains: dashed line ending in an open `>` arrow (two strokes,
      // unfilled) — `markers.js:requirement_arrow`, `edgeMarker.ts` fill:false.
      final tip = pts.last;
      final dir = _dir(pts[pts.length - 2], tip);
      pts[pts.length - 1] = tip - dir * 10;
      final perp = Point(-dir.y, dir.x);
      children.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(pts.first),
          for (final p in pts.skip(1)) LineTo(p),
        ]),
        stroke: Stroke(color: theme.relationColor, width: 1.3, dash: dash),
      ));
      children.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(tip - dir * 11 + perp * 5),
          LineTo(tip),
          LineTo(tip - dir * 11 - perp * 5),
        ]),
        stroke: Stroke(color: theme.relationColor, width: 1.3),
      ));
    }
    nodes.add(SceneGroup(
      id: 'rel_$i',
      role: SceneGroupRole.edge,
      semanticLabel: r.label,
      children: children,
    ));
    final size = labelSizes[i]!;
    final mid = _pathMidpoint(pts);
    // Upstream label: `relationLabelColor` (=actorTextColor) on
    // `relationLabelBackground` (=labelBackground='rgba(232,232,232,0.8)').
    nodes.add(SceneGroup(
      id: 'rellabel_$i',
      role: SceneGroupRole.edgeLabel,
      children: [
      SceneShape(
        geometry: RectGeometry(
            Rect.fromCenter(mid, size.width + 4, size.height + 2)),
        fill: Fill(theme.relationLabelBackground),
      ),
      SceneText(
        text: '«${r.label}»',
        bounds: Rect.fromCenter(mid, size.width, size.height),
        style: baseStyle,
        color: theme.relationLabelColor,
      ),
      ],
    ));
  }

  diagram.nodes.forEach((id, n) {
    final (size, lines) = boxes[id]!;
    final rect = Rect.fromCenter(centers[id]!, size.width, size.height);
    // Upstream draws square corners (no rx/ry), `requirementBackground`
    // (=primaryColor) for both requirements and elements, and a border in
    // `requirementBorderColor` width `requirementBorderSize` (1).
    final children = <SceneNode>[
      SceneShape(
        geometry: RectGeometry(rect),
        fill: Fill(theme.requirementBackground),
        stroke: Stroke(color: theme.requirementBorderColor, width: 1),
      ),
    ];
    var y = rect.top + boxPadding / 2;
    // The name row (index 1) is centered like the type row; body rows below
    // the gap are left-aligned (matching the non-elk `center` default would
    // also be valid, but mermaid left-aligns the prefixed body rows visually).
    for (var li = 0; li < lines.length; li++) {
      final (text, style, s, gapAfter) = lines[li];
      children.add(SceneText(
        text: text,
        bounds: li < 2
            ? Rect.fromLTWH(rect.center.x - s.width / 2, y, s.width, s.height)
            : Rect.fromLTWH(rect.left + boxPadding / 2, y, s.width, s.height),
        style: style,
        color: theme.requirementTextColor,
        align: li < 2 ? TextAlignH.center : TextAlignH.left,
      ));
      y += s.height + 4;
      if (gapAfter) {
        // Divider line sits at the top of the gap when body rows follow.
        if (lines.length > 2) {
          children.add(SceneShape(
            geometry: PathGeometry([
              MoveTo(Point(rect.left, y - 2)),
              LineTo(Point(rect.right, y - 2)),
            ]),
            stroke: Stroke(color: theme.requirementBorderColor, width: 1),
          ));
        }
        y += gap;
      }
    }
    nodes.add(SceneGroup(id: id, semanticLabel: n.id, children: children));
  });

  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  final title = diagram.title;
  if (title != null && title.isNotEmpty) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily,
        fontSize: theme.fontSize * 1.15,
        fontWeight: 700);
    final size = measurer.measure(title, style);
    final node = SceneText(
      text: title,
      bounds: Rect.fromLTWH(bounds.center.x - size.width / 2,
          bounds.top - size.height - 25, size.width, size.height),
      style: style,
      color: theme.titleColor,
    );
    nodes.add(node);
    bounds = bounds.union(node.bounds);
  }
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

Point _intersectRect(Rect rect, Point outside) {
  final c = rect.center;
  final dx = outside.x - c.x;
  final dy = outside.y - c.y;
  if (dx == 0 && dy == 0) return c;
  final w = rect.width / 2;
  final h = rect.height / 2;
  double sx, sy;
  if (dy.abs() * w > dx.abs() * h) {
    sy = dy < 0 ? -h : h;
    sx = dx * sy / dy;
  } else {
    sx = dx < 0 ? -w : w;
    sy = dy * sx / dx;
  }
  return Point(c.x + sx, c.y + sy);
}

Point _outsideMarkerCenter(Rect rect, Point border, double radius) {
  final distances = <(double, Point)>[
    ((border.x - rect.left).abs(), Point(rect.left - radius, border.y)),
    ((border.x - rect.right).abs(), Point(rect.right + radius, border.y)),
    ((border.y - rect.top).abs(), Point(border.x, rect.top - radius)),
    ((border.y - rect.bottom).abs(), Point(border.x, rect.bottom + radius)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return distances.first.$2;
}

/// Moves both ends of a routed polyline while retaining Dagre's bends.
/// Displacement is interpolated by arc-length position, so moved nodes do not
/// replace obstacle-aware routes with direct segments.
List<Point> _translateRoute(
  List<Point> points,
  Point sourceDelta,
  Point targetDelta,
) {
  if (points.length < 2) return points;
  var total = 0.0;
  final distances = <double>[0];
  for (var i = 1; i < points.length; i++) {
    total += points[i].distanceTo(points[i - 1]);
    distances.add(total);
  }
  return [
    for (var i = 0; i < points.length; i++)
      Point(
        points[i].x +
            sourceDelta.x * (1 - (total == 0 ? 0 : distances[i] / total)) +
            targetDelta.x * (total == 0 ? 0 : distances[i] / total),
        points[i].y +
            sourceDelta.y * (1 - (total == 0 ? 0 : distances[i] / total)) +
            targetDelta.y * (total == 0 ? 0 : distances[i] / total),
      ),
  ];
}

Point _pathMidpoint(List<Point> points) {
  if (points.isEmpty) return Point.zero;
  if (points.length == 1) return points.first;
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += points[i].distanceTo(points[i - 1]);
  }
  var remaining = total / 2;
  for (var i = 1; i < points.length; i++) {
    final length = points[i].distanceTo(points[i - 1]);
    if (length >= remaining) {
      final fraction = length == 0 ? 0.0 : remaining / length;
      return Point(
        points[i - 1].x + (points[i].x - points[i - 1].x) * fraction,
        points[i - 1].y + (points[i].y - points[i - 1].y) * fraction,
      );
    }
    remaining -= length;
  }
  return points.last;
}

Point _dir(Point from, Point to) {
  final d = to - from;
  final len = (d.x * d.x + d.y * d.y);
  if (len == 0) return const Point(0, 1);
  final l = math.sqrt(len);
  return Point(d.x / l, d.y / l);
}

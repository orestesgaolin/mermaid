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
        open.$3.add((key, m.group(2)!.trim()));
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
  const pad = 12.0;
  final baseStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.85);
  final titleStyle = baseStyle.copyWith(fontWeight: 700);

  // Measure boxes: «kind» line, bold id, divider, field lines.
  final boxes = <String, (Size, List<(String, TextStyleSpec, Size)>)>{};
  for (final n in diagram.nodes.values) {
    final lines = <(String, TextStyleSpec, Size)>[];
    void add(String text, TextStyleSpec style) {
      lines.add((text, style, measurer.measure(text, style, maxWidth: 240)));
    }

    add('«${n.kind}»', baseStyle.copyWith(italic: true));
    add(n.id, titleStyle);
    for (final (k, v) in n.fields) {
      add('$k: $v', baseStyle);
    }
    var w = 0.0, h = 10.0;
    for (final (_, _, s) in lines) {
      w = w > s.width ? w : s.width;
      h += s.height + 4;
    }
    boxes[n.id] = (Size(w + 24, h + 6), lines);
  }

  final g = dagre.DagreGraph();
  boxes.forEach((id, b) {
    g.addNode(dagre.DagreNode(id, width: b.$1.width, height: b.$1.height));
  });
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
      dagre.DagreConfig(rankDir: dagre.RankDir.ttb, nodeSep: 60, rankSep: 70));

  final nodes = <SceneNode>[];
  final centers = <String, Point>{};
  boxes.forEach((id, b) {
    centers[id] = result.graph.nodeMap[id]!.position!.center;
  });

  for (var i = 0; i < diagram.relations.length; i++) {
    final r = diagram.relations[i];
    final dagreEdge = result.graph.findEdgeById('e$i')!;
    var pts = List<Point>.from(dagreEdge.points);
    if (pts.length < 2) pts = [centers[r.from]!, centers[r.to]!];
    final fromRect =
        Rect.fromCenter(centers[r.from]!, boxes[r.from]!.$1.width, boxes[r.from]!.$1.height);
    final toRect =
        Rect.fromCenter(centers[r.to]!, boxes[r.to]!.$1.width, boxes[r.to]!.$1.height);
    pts[0] = _intersectRect(fromRect, pts[1]);
    pts[pts.length - 1] = _intersectRect(toRect, pts[pts.length - 2]);
    final tip = pts.last;
    final dir = _dir(pts[pts.length - 2], tip);
    pts[pts.length - 1] = tip - dir * 10;
    final perp = Point(-dir.y, dir.x);
    nodes.add(SceneGroup(id: 'rel_$i', semanticLabel: r.label, children: [
      SceneShape(
        geometry: PathGeometry([
          MoveTo(pts.first),
          for (final p in pts.skip(1)) LineTo(p),
        ]),
        stroke: Stroke(color: theme.lineColor, width: 1.3, dash: const [4, 4]),
      ),
      SceneShape(
        geometry: PolygonGeometry([tip, tip - dir * 11 + perp * 5, tip - dir * 11 - perp * 5]),
        fill: Fill(theme.lineColor),
      ),
    ]));
    final size = labelSizes[i]!;
    final mid = pts[pts.length ~/ 2];
    nodes.add(SceneGroup(id: 'rellabel_$i', children: [
      SceneShape(
        geometry: RectGeometry(
            Rect.fromCenter(mid, size.width + 4, size.height + 2)),
        fill: Fill(theme.background),
      ),
      SceneText(
        text: '«${r.label}»',
        bounds: Rect.fromCenter(mid, size.width, size.height),
        style: baseStyle,
        color: theme.textColor,
      ),
    ]));
  }

  diagram.nodes.forEach((id, n) {
    final (size, lines) = boxes[id]!;
    final rect = Rect.fromCenter(centers[id]!, size.width, size.height);
    final children = <SceneNode>[
      SceneShape(
        geometry: RectGeometry(rect, rx: 4, ry: 4),
        fill: Fill(n.kind == 'element' ? theme.secondaryColor : theme.mainBkg),
        stroke: Stroke(color: theme.nodeBorder),
      ),
    ];
    var y = rect.top + 8;
    for (var li = 0; li < lines.length; li++) {
      final (text, style, s) = lines[li];
      children.add(SceneText(
        text: text,
        bounds: li < 2
            ? Rect.fromLTWH(rect.center.x - s.width / 2, y, s.width, s.height)
            : Rect.fromLTWH(rect.left + 12, y, s.width, s.height),
        style: style,
        color: theme.textColor,
        align: li < 2 ? TextAlignH.center : TextAlignH.left,
      ));
      y += s.height + 4;
      if (li == 1 && lines.length > 2) {
        children.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(rect.left, y - 2)),
            LineTo(Point(rect.right, y - 2)),
          ]),
          stroke: Stroke(color: theme.nodeBorder, width: 0.8),
        ));
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
          bounds.top - size.height - 10, size.width, size.height),
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

Point _dir(Point from, Point to) {
  final d = to - from;
  final len = (d.x * d.x + d.y * d.y);
  if (len == 0) return const Point(0, 1);
  final l = math.sqrt(len);
  return Point(d.x / l, d.y / l);
}

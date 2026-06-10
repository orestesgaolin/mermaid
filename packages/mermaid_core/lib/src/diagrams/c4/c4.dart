/// C4 diagrams (C4Context / C4Container / C4Component / C4Dynamic):
/// model, parser and layout — one file.
///
/// Reference: upstream c4 jison grammar + c4Renderer. Upstream uses a
/// bespoke row layout; this port places boundaries as dagre clusters, which
/// reads equivalently for typical context diagrams.
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
import '../../vendor/dagre/dart_dagre.dart' as dagre;

class C4Diagram {
  const C4Diagram({
    required this.nodes,
    required this.boundaries,
    required this.rels,
    this.title,
  });

  final Map<String, C4Node> nodes;
  final List<C4Boundary> boundaries;
  final List<C4Rel> rels;
  final String? title;
}

enum C4Kind { person, personExt, system, systemExt, container, component, db, queue }

class C4Node {
  const C4Node({
    required this.id,
    required this.kind,
    required this.label,
    this.description = '',
    this.technology = '',
    this.boundary,
  });

  final String id;
  final C4Kind kind;
  final String label;
  final String description;
  final String technology;
  final String? boundary;
}

class C4Boundary {
  const C4Boundary({required this.id, required this.label, this.parent});

  final String id;
  final String label;
  final String? parent;
}

class C4Rel {
  const C4Rel({
    required this.from,
    required this.to,
    required this.label,
    this.technology = '',
    this.bidirectional = false,
  });

  final String from;
  final String to;
  final String label;
  final String technology;
  final bool bidirectional;
}

C4Diagram parseC4Diagram(String source) {
  final frontTitle = frontmatterTitle(source);
  final text = stripMetadata(source);
  final nodes = <String, C4Node>{};
  final boundaries = <C4Boundary>[];
  final rels = <C4Rel>[];
  String? title = frontTitle;
  var seenHeader = false;
  final boundaryStack = <String>[];

  List<String> args(String s) {
    // Split on commas outside quotes; unquote each.
    final out = <String>[];
    final buf = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') inQuote = !inQuote;
      if (c == ',' && !inQuote) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return [
      for (var a in out)
        () {
          a = a.trim();
          if (a.length >= 2 && a.startsWith('"') && a.endsWith('"')) {
            a = a.substring(1, a.length - 1);
          }
          return a.replaceAll('<br/>', '\n').replaceAll('<br>', '\n');
        }(),
    ];
  }

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^C4(Context|Container|Component|Dynamic|Deployment)\b')
          .hasMatch(line)) {
        throw MermaidParseException('expected a C4 header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    Match? m;
    m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      continue;
    }
    if (line == '}') {
      if (boundaryStack.isEmpty) {
        throw MermaidParseException('"}" without open boundary', line: i + 1);
      }
      boundaryStack.removeLast();
      continue;
    }
    // Boundary(id, "label" [, "type"]) {
    m = RegExp(
            r'^(Enterprise_Boundary|System_Boundary|Container_Boundary|Boundary|Deployment_Node|Node|Node_L|Node_R)\s*\((.*)\)\s*\{$')
        .firstMatch(line);
    if (m != null) {
      final a = args(m.group(2)!);
      final id = a[0];
      boundaries.add(C4Boundary(
        id: id,
        label: a.length > 1 ? a[1] : id,
        parent: boundaryStack.isEmpty ? null : boundaryStack.last,
      ));
      boundaryStack.add(id);
      continue;
    }
    // Element: Kind(id, "label" [, "description"/"technology" ...])
    m = RegExp(r'^(\w+)\s*\((.*)\)\s*$').firstMatch(line);
    if (m != null) {
      final fn = m.group(1)!;
      final a = args(m.group(2)!);
      C4Kind? kind = switch (fn) {
        'Person' => C4Kind.person,
        'Person_Ext' => C4Kind.personExt,
        'System' || 'SystemDb' || 'SystemQueue' =>
          fn == 'System' ? C4Kind.system : (fn == 'SystemDb' ? C4Kind.db : C4Kind.queue),
        'System_Ext' || 'SystemDb_Ext' || 'SystemQueue_Ext' => C4Kind.systemExt,
        'Container' || 'ContainerDb' || 'ContainerQueue' ||
        'Container_Ext' || 'ContainerDb_Ext' || 'ContainerQueue_Ext' =>
          C4Kind.container,
        'Component' || 'ComponentDb' || 'ComponentQueue' ||
        'Component_Ext' || 'ComponentDb_Ext' || 'ComponentQueue_Ext' =>
          C4Kind.component,
        _ => null,
      };
      if (kind != null) {
        if (a.isEmpty) {
          throw MermaidParseException('$fn needs arguments', line: i + 1);
        }
        nodes[a[0]] = C4Node(
          id: a[0],
          kind: kind,
          label: a.length > 1 ? a[1] : a[0],
          technology: (fn.startsWith('Container') || fn.startsWith('Component')) &&
                  a.length > 2
              ? a[2]
              : '',
          description: a.length >
                  ((fn.startsWith('Container') || fn.startsWith('Component'))
                      ? 3
                      : 2)
              ? a.last
              : (a.length > 2 &&
                      !(fn.startsWith('Container') || fn.startsWith('Component'))
                  ? a[2]
                  : ''),
          boundary: boundaryStack.isEmpty ? null : boundaryStack.last,
        );
        continue;
      }
      // Rel(from, to, "label" [, "technology"]) and directional variants.
      if (RegExp(r'^(Bi)?Rel(_[UDLR]|_Up|_Down|_Left|_Right|_Back)?$')
          .hasMatch(fn)) {
        if (a.length < 2) {
          throw MermaidParseException('$fn needs two endpoints', line: i + 1);
        }
        rels.add(C4Rel(
          from: a[0],
          to: a[1],
          label: a.length > 2 ? a[2] : '',
          technology: a.length > 3 ? a[3] : '',
          bidirectional: fn.startsWith('BiRel'),
        ));
        continue;
      }
      // UpdateRelStyle / UpdateElementStyle / LAYOUT hints: ignored.
      if (fn.startsWith('Update') || fn.toUpperCase().startsWith('LAYOUT')) {
        continue;
      }
    }
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(line)) continue;
    throw MermaidParseException('unrecognized statement "$line"', line: i + 1);
  }
  if (!seenHeader) {
    throw const MermaidParseException('empty C4 source');
  }
  return C4Diagram(
      nodes: nodes, boundaries: boundaries, rels: rels, title: title);
}

// Upstream C4 default colors.
const _personFill = Color(0xff08427b);
const _systemFill = Color(0xff1168bd);
const _containerFill = Color(0xff438dd5);
const _componentFill = Color(0xff85bbf0);
const _extFill = Color(0xff999999);

RenderScene layoutC4Diagram(
  C4Diagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const pad = 12.0;
  final labelStyle = TextStyleSpec(
      fontFamily: theme.fontFamily,
      fontSize: theme.fontSize * 0.95,
      fontWeight: 700);
  final descStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.78);

  final boxes = <String, (Size, Size, Size)>{}; // total, label, desc
  for (final n in diagram.nodes.values) {
    final label = measurer.measure(n.label, labelStyle, maxWidth: 170);
    final descText = [
      if (n.technology.isNotEmpty) '[${n.technology}]',
      if (n.description.isNotEmpty) n.description,
    ].join('\n');
    final desc = descText.isEmpty
        ? Size.zero
        : measurer.measure(descText, descStyle, maxWidth: 180);
    final w = math.max(120.0, math.max(label.width, desc.width) + 28);
    final headRoom = n.kind == C4Kind.person || n.kind == C4Kind.personExt
        ? 28.0
        : 0.0;
    final h = label.height + desc.height + 26 + headRoom;
    boxes[n.id] = (Size(w, h), label, desc);
  }

  final g = dagre.DagreGraph();
  for (final b in diagram.boundaries) {
    g.addNode(dagre.DagreNode('__b_${b.id}',
        parent: b.parent != null ? '__b_${b.parent}' : null));
  }
  diagram.nodes.forEach((id, n) {
    g.addNode(dagre.DagreNode(id,
        width: boxes[id]!.$1.width,
        height: boxes[id]!.$1.height,
        parent: n.boundary != null ? '__b_${n.boundary}' : null));
  });
  final labelSizes = <int, Size>{};
  for (var i = 0; i < diagram.rels.length; i++) {
    final r = diagram.rels[i];
    if (!diagram.nodes.containsKey(r.from) ||
        !diagram.nodes.containsKey(r.to)) {
      continue;
    }
    final size = r.label.isEmpty
        ? Size.zero
        : measurer.measure(r.label, descStyle, maxWidth: 150);
    labelSizes[i] = size;
    g.addEdge(dagre.DagreEdge(r.from, r.to,
        id: 'e$i',
        minLen: 1,
        width: size.width,
        height: size.height,
        labelPos: dagre.LabelPosition.center));
  }
  final result = dagre.layout(g,
      dagre.DagreConfig(rankDir: dagre.RankDir.ttb, nodeSep: 50, rankSep: 70));

  final clusterNodes = <SceneNode>[];
  final edgeNodes = <SceneNode>[];
  final labelNodes = <SceneNode>[];
  final elementNodes = <SceneNode>[];
  final centers = <String, Point>{};
  diagram.nodes.forEach((id, _) {
    centers[id] = result.graph.nodeMap[id]!.position!.center;
  });

  // Boundary rects from member bounds.
  Rect? boundaryRect(String id) {
    Rect? acc;
    void include(Rect r) => acc = acc == null ? r : acc!.union(r);
    diagram.nodes.forEach((nid, n) {
      if (n.boundary == id) {
        include(Rect.fromCenter(
            centers[nid]!, boxes[nid]!.$1.width, boxes[nid]!.$1.height));
      }
    });
    for (final b in diagram.boundaries) {
      if (b.parent == id) {
        final r = boundaryRect(b.id);
        if (r != null) include(r.inflate(10));
      }
    }
    return acc;
  }

  for (final b in diagram.boundaries.reversed) {
    final inner = boundaryRect(b.id);
    if (inner == null) continue;
    final size = measurer.measure(b.label, labelStyle);
    final rect = Rect.fromLTRB(inner.left - 14, inner.top - 14,
        inner.right + 14, inner.bottom + 18 + size.height);
    clusterNodes.add(SceneGroup(id: 'boundary_${b.id}', children: [
      SceneShape(
        geometry: RectGeometry(rect),
        stroke: Stroke(color: const Color(0xff444444), dash: const [4, 4]),
      ),
      SceneText(
        text: b.label,
        bounds: Rect.fromLTWH(rect.left + 8, rect.bottom - size.height - 4,
            size.width, size.height),
        style: labelStyle,
        color: const Color(0xff444444),
        align: TextAlignH.left,
      ),
    ]));
  }

  for (var i = 0; i < diagram.rels.length; i++) {
    final r = diagram.rels[i];
    final edge = result.graph.findEdgeById('e$i');
    if (edge == null) continue;
    var pts = List<Point>.from(edge.points);
    if (pts.length < 2) pts = [centers[r.from]!, centers[r.to]!];
    final fromRect = Rect.fromCenter(
        centers[r.from]!, boxes[r.from]!.$1.width, boxes[r.from]!.$1.height);
    final toRect = Rect.fromCenter(
        centers[r.to]!, boxes[r.to]!.$1.width, boxes[r.to]!.$1.height);
    pts[0] = _intersectRect(fromRect, pts[1]);
    pts[pts.length - 1] = _intersectRect(toRect, pts[pts.length - 2]);
    final tip = pts.last;
    final dir = _dir(pts[pts.length - 2], tip);
    pts[pts.length - 1] = tip - dir * 9;
    final perp = Point(-dir.y, dir.x);
    final children = <SceneNode>[
      SceneShape(
        geometry: PathGeometry(
            [MoveTo(pts.first), for (final p in pts.skip(1)) LineTo(p)]),
        stroke: const Stroke(color: Color(0xff666666), width: 1.4, dash: [5, 3]),
      ),
      SceneShape(
        geometry: PolygonGeometry(
            [tip, tip - dir * 10 + perp * 4.5, tip - dir * 10 - perp * 4.5]),
        fill: const Fill(Color(0xff666666)),
      ),
    ];
    if (r.bidirectional) {
      final start = pts.first;
      final sdir = _dir(pts[1], start);
      children.add(SceneShape(
        geometry: PolygonGeometry([
          start,
          start - sdir * 10 + Point(-sdir.y, sdir.x) * 4.5,
          start - sdir * 10 - Point(-sdir.y, sdir.x) * 4.5,
        ]),
        fill: const Fill(Color(0xff666666)),
      ));
    }
    edgeNodes.add(SceneGroup(
        id: 'rel_${r.from}_${r.to}_$i', semanticLabel: r.label, children: children));
    final size = labelSizes[i] ?? Size.zero;
    if (size.width > 0) {
      final mid = pts[pts.length ~/ 2];
      labelNodes.add(SceneGroup(id: 'rellabel_$i', children: [
        SceneShape(
          geometry: RectGeometry(
              Rect.fromCenter(mid, size.width + 4, size.height + 2)),
          fill: Fill(theme.background),
        ),
        SceneText(
          text: r.label,
          bounds: Rect.fromCenter(mid, size.width, size.height),
          style: descStyle,
          color: const Color(0xff444444),
        ),
      ]));
    }
  }

  diagram.nodes.forEach((id, n) {
    final (size, labelSize, descSize) = boxes[id]!;
    final rect = Rect.fromCenter(centers[id]!, size.width, size.height);
    final fill = switch (n.kind) {
      C4Kind.person => _personFill,
      C4Kind.personExt || C4Kind.systemExt => _extFill,
      C4Kind.system || C4Kind.db || C4Kind.queue => _systemFill,
      C4Kind.container => _containerFill,
      C4Kind.component => _componentFill,
    };
    final isPerson = n.kind == C4Kind.person || n.kind == C4Kind.personExt;
    final bodyTop = rect.top + (isPerson ? 22.0 : 0.0);
    final children = <SceneNode>[
      SceneShape(
        geometry: RectGeometry(
            Rect.fromLTRB(rect.left, bodyTop, rect.right, rect.bottom),
            rx: 8,
            ry: 8),
        fill: Fill(fill),
        stroke: Stroke(color: fill, width: 1),
      ),
      if (isPerson)
        SceneShape(
          geometry: CircleGeometry(Point(rect.center.x, rect.top + 14), 14),
          fill: Fill(fill),
          stroke: Stroke(color: theme.background, width: 2),
        ),
      SceneText(
        text: n.label,
        bounds: Rect.fromLTWH(rect.center.x - labelSize.width / 2,
            bodyTop + 8, labelSize.width, labelSize.height),
        style: labelStyle,
        color: _white,
      ),
      if (descSize.height > 0)
        SceneText(
          text: [
            if (n.technology.isNotEmpty) '[${n.technology}]',
            if (n.description.isNotEmpty) n.description,
          ].join('\n'),
          bounds: Rect.fromLTWH(rect.center.x - descSize.width / 2,
              bodyTop + labelSize.height + 12, descSize.width, descSize.height),
          style: descStyle,
          color: const Color(0xffe8eef5),
        ),
    ];
    elementNodes.add(
        SceneGroup(id: id, semanticLabel: n.label, children: children));
  });

  var nodes = <SceneNode>[
    ...clusterNodes,
    ...edgeNodes,
    ...labelNodes,
    ...elementNodes,
  ];
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
          bounds.top - size.height - 12, size.width, size.height),
      style: style,
      color: theme.titleColor,
    );
    nodes = [...nodes, node];
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

// White used on filled C4 boxes.
const _white = Color(0xffffffff);

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
  final len = math.sqrt(d.x * d.x + d.y * d.y);
  return len == 0 ? const Point(0, 1) : Point(d.x / len, d.y / len);
}

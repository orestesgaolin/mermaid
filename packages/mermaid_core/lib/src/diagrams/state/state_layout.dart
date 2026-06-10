/// State diagram layout: dagre-positioned states with start/end/choice/
/// fork/join pseudo-state shapes and composite clusters, ported (simplified)
/// from upstream stateRenderer-v3-unified.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';
import '../../vendor/dagre/dart_dagre.dart' as dagre;
import '../flowchart/flow_model.dart' show FlowDirection;
import 'state_model.dart';

const double _padding = 12;
const double _diagramPadding = 8;
const double _nodeSpacing = 50;
const double _rankSpacing = 50;
const double _clusterPadding = 10;

const _noteBkg = Color(0xfffff5ad);
const _noteBorder = Color(0xffaaaa33);

RenderScene layoutStateDiagram(
  StateDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  return _StateLayout(diagram, measurer, theme).run();
}

class _Placed {
  _Placed(this.node, this.width, this.height, this.labelSize);

  final StateNode node;
  final double width;
  final double height;
  final Size labelSize;
  Point center = Point.zero;

  Rect get rect => Rect.fromCenter(center, width, height);
}

class _StateLayout {
  _StateLayout(this.diagram, this.measurer, this.theme)
      : baseStyle = TextStyleSpec(
          fontFamily: theme.fontFamily,
          fontSize: theme.fontSize,
        );

  final StateDiagram diagram;
  final TextMeasurer measurer;
  final MermaidTheme theme;
  final TextStyleSpec baseStyle;

  final placed = <String, _Placed>{};
  final clusterRects = <String, Rect>{};

  bool get horizontal =>
      diagram.direction == FlowDirection.lr ||
      diagram.direction == FlowDirection.rl;

  RenderScene run() {
    for (final s in diagram.states.values) {
      if (s.kind == StateKind.composite) continue;
      placed[s.id] = _measure(s);
    }
    final noteBoxes = <int, _Placed>{};
    for (var i = 0; i < diagram.notes.length; i++) {
      final n = diagram.notes[i];
      final size = measurer.measure(n.text, baseStyle, maxWidth: 200);
      noteBoxes[i] = _Placed(
        StateNode(id: '__note$i', label: n.text),
        size.width + 2 * _padding,
        size.height + 2 * _padding,
        size,
      );
    }

    // --- dagre ----------------------------------------------------------------
    final g = dagre.DagreGraph();
    for (final s in diagram.states.values) {
      if (s.kind == StateKind.composite) {
        g.addNode(dagre.DagreNode(s.id, parent: s.parent));
      }
    }
    for (final p in placed.values) {
      g.addNode(dagre.DagreNode(p.node.id,
          width: p.width, height: p.height, parent: p.node.parent));
    }
    noteBoxes.forEach((i, b) {
      g.addNode(dagre.DagreNode(b.node.id, width: b.width, height: b.height));
    });

    String? representativeOf(String compositeId) {
      final children = diagram.states[compositeId]?.children ?? const [];
      for (final c in children) {
        if (placed.containsKey(c)) return c;
        final nested = representativeOf(c);
        if (nested != null) return nested;
      }
      return null;
    }

    (String, String?) endpoint(String id) {
      if (placed.containsKey(id)) return (id, null);
      final rep = representativeOf(id);
      return rep != null ? (rep, id) : (id, null);
    }

    final labelSizes = <int, Size>{};
    for (var i = 0; i < diagram.transitions.length; i++) {
      final t = diagram.transitions[i];
      Size? size;
      if (t.label != null && t.label!.isNotEmpty) {
        size = measurer.measure(t.label!, baseStyle, maxWidth: 200);
        labelSizes[i] = size;
      }
      final (from, _) = endpoint(t.from);
      final (to, _) = endpoint(t.to);
      // Self-transitions (including composite-to-itself) are routed manually
      // after layout, like flowchart self-loops.
      if (from == to) continue;
      g.addEdge(dagre.DagreEdge(
        from,
        to,
        id: 'e$i',
        minLen: 1,
        width: size?.width ?? 0,
        height: size?.height ?? 0,
        labelPos: dagre.LabelPosition.center,
      ));
    }
    for (var i = 0; i < diagram.notes.length; i++) {
      final target = diagram.notes[i].target;
      if (placed.containsKey(target)) {
        g.addEdge(dagre.DagreEdge('__note$i', target, id: 'n$i', minLen: 1));
      }
    }

    final result = dagre.layout(
      g,
      dagre.DagreConfig(
        rankDir: switch (diagram.direction) {
          FlowDirection.tb => dagre.RankDir.ttb,
          FlowDirection.bt => dagre.RankDir.btt,
          FlowDirection.lr => dagre.RankDir.ltr,
          FlowDirection.rl => dagre.RankDir.rtl,
        },
        nodeSep: _nodeSpacing,
        rankSep: _rankSpacing,
      ),
    );
    for (final p in [...placed.values, ...noteBoxes.values]) {
      p.center = result.graph.nodeMap[p.node.id]!.position!.center;
    }

    // --- scene ------------------------------------------------------------------
    final clusterNodes = <SceneNode>[];
    final edgeNodes = <SceneNode>[];
    final labelNodes = <SceneNode>[];
    final stateNodes = <SceneNode>[];

    // Composite clusters, outermost-first (parents precede children in the
    // map since composites register before their members).
    for (final s in diagram.states.values) {
      if (s.kind != StateKind.composite) continue;
      final pos = result.graph.nodeMap[s.id]?.position;
      if (pos == null) continue;
      final titleSize = measurer.measure(s.label, baseStyle);
      final rect = Rect.fromLTRB(
        pos.left - _clusterPadding,
        pos.top - _clusterPadding - titleSize.height - 6,
        pos.right + _clusterPadding,
        pos.bottom + _clusterPadding,
      );
      clusterRects[s.id] = rect;
      final titleY = rect.top + 4;
      clusterNodes.add(SceneGroup(id: s.id, semanticLabel: s.label, children: [
        SceneShape(
          geometry: RectGeometry(rect, rx: 8, ry: 8),
          fill: Fill(theme.background),
          stroke: Stroke(color: theme.nodeBorder),
        ),
        // Title band.
        SceneText(
          text: s.label,
          bounds: Rect.fromLTWH(rect.center.x - titleSize.width / 2, titleY,
              titleSize.width, titleSize.height),
          style: baseStyle.copyWith(fontWeight: 700),
          color: theme.textColor,
        ),
        SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(rect.left, titleY + titleSize.height + 4)),
            LineTo(Point(rect.right, titleY + titleSize.height + 4)),
          ]),
          stroke: Stroke(color: theme.nodeBorder),
        ),
      ]));
    }

    final selfLoopCount = <String, int>{};
    for (var i = 0; i < diagram.transitions.length; i++) {
      final t = diagram.transitions[i];
      final (fromId, clusterFrom) = endpoint(t.from);
      final (toId, clusterTo) = endpoint(t.to);

      if (fromId == toId) {
        final anchor = clusterFrom != null
            ? clusterRects[clusterFrom]!
            : placed[fromId]!.rect;
        final idx = selfLoopCount[fromId] ?? 0;
        selfLoopCount[fromId] = idx + 1;
        final labelSize = labelSizes[i];
        final ext = 36.0 + idx * 16;
        final start = Point(anchor.right, anchor.center.y - anchor.height / 4);
        final end = Point(anchor.right, anchor.center.y + anchor.height / 4);
        final c1 = Point(start.x + ext, start.y - ext * 0.3);
        final c2 = Point(end.x + ext, end.y + ext * 0.3);
        final endDir = _dir(c2, end);
        final children = <SceneNode>[
          SceneShape(
            geometry: PathGeometry(
                [MoveTo(start), CubicTo(c1, c2, end - endDir * 8)]),
            stroke: Stroke(color: theme.lineColor, width: 1.5),
          ),
          SceneShape(
            geometry: PolygonGeometry([
              end,
              end - endDir * 10 + Point(-endDir.y, endDir.x) * 5,
              end - endDir * 10 - Point(-endDir.y, endDir.x) * 5,
            ]),
            fill: Fill(theme.arrowheadColor),
          ),
          if (labelSize != null)
            SceneText(
              text: t.label!,
              bounds: Rect.fromLTWH(
                  anchor.right + ext * 0.78 + 6,
                  anchor.center.y - labelSize.height / 2,
                  labelSize.width,
                  labelSize.height),
              style: baseStyle,
              color: theme.textColor,
              align: TextAlignH.left,
            ),
        ];
        edgeNodes.add(SceneGroup(
            id: 'trans_${t.from}_${t.to}_$i',
            semanticLabel: t.label,
            children: children));
        continue;
      }

      final dagreEdge = result.graph.findEdgeById('e$i')!;

      var points = List<Point>.from(dagreEdge.points);
      if (points.length < 2) {
        points = [placed[fromId]!.center, placed[toId]!.center];
      }
      if (clusterTo != null) {
        points = _dropInsideRect(points, clusterRects[clusterTo]!, fromEnd: true);
      }
      if (clusterFrom != null) {
        points =
            _dropInsideRect(points, clusterRects[clusterFrom]!, fromEnd: false);
      }
      final sourceRect =
          clusterFrom != null ? clusterRects[clusterFrom]! : placed[fromId]!.rect;
      final targetRect =
          clusterTo != null ? clusterRects[clusterTo]! : placed[toId]!.rect;
      points[0] = _intersectRect(sourceRect, points[1]);
      points[points.length - 1] =
          _intersectRect(targetRect, points[points.length - 2]);

      final endTip = points.last;
      final endDir = _dir(points[points.length - 2], endTip);
      points[points.length - 1] = endTip - endDir * 8;

      edgeNodes.add(SceneGroup(
        id: 'trans_${t.from}_${t.to}_$i',
        semanticLabel: t.label,
        children: [
          SceneShape(
            geometry: PathGeometry(_curveBasis(points)),
            stroke: Stroke(color: theme.lineColor, width: 1.5),
          ),
          SceneShape(
            geometry: PolygonGeometry([
              endTip,
              endTip - endDir * 10 + Point(-endDir.y, endDir.x) * 5,
              endTip - endDir * 10 - Point(-endDir.y, endDir.x) * 5,
            ]),
            fill: Fill(theme.arrowheadColor),
          ),
        ],
      ));

      final labelSize = labelSizes[i];
      if (labelSize != null) {
        final c = (dagreEdge.labelX != null && dagreEdge.labelY != null)
            ? Point(dagreEdge.labelX!, dagreEdge.labelY!)
            : points[points.length ~/ 2];
        labelNodes.add(SceneGroup(id: 'translabel_$i', children: [
          SceneShape(
            geometry: RectGeometry(
                Rect.fromCenter(c, labelSize.width + 4, labelSize.height + 4),
                rx: 2,
                ry: 2),
            fill: Fill(theme.edgeLabelBackground),
          ),
          SceneText(
            text: t.label!,
            bounds: Rect.fromCenter(c, labelSize.width, labelSize.height),
            style: baseStyle,
            color: theme.textColor,
          ),
        ]));
      }
    }

    // Notes + dashed connectors.
    for (var i = 0; i < diagram.notes.length; i++) {
      final b = noteBoxes[i]!;
      final target = placed[diagram.notes[i].target];
      if (target != null) {
        edgeNodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(_intersectRect(b.rect, target.center)),
            LineTo(_intersectRect(target.rect, b.center)),
          ]),
          stroke: Stroke(color: theme.lineColor, width: 1, dash: const [2, 2]),
        ));
      }
      stateNodes.add(SceneGroup(id: '__note$i', children: [
        SceneShape(
          geometry: RectGeometry(b.rect),
          fill: const Fill(_noteBkg),
          stroke: const Stroke(color: _noteBorder),
        ),
        SceneText(
          text: diagram.notes[i].text,
          bounds: b.rect.inflate(-_padding),
          style: baseStyle,
          color: Color.black,
        ),
      ]));
    }

    for (final p in placed.values) {
      stateNodes.add(_buildState(p));
    }

    var nodes = <SceneNode>[
      ...clusterNodes,
      ...edgeNodes,
      ...labelNodes,
      ...stateNodes,
    ];
    var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 100);

    final title = diagram.title;
    if (title != null && title.isNotEmpty) {
      final style = baseStyle.copyWith(fontWeight: 700);
      final size = measurer.measure(title, style);
      final node = SceneText(
        text: title,
        bounds: Rect.fromLTWH(bounds.center.x - size.width / 2,
            bounds.top - size.height - 8, size.width, size.height),
        style: style,
        color: theme.titleColor,
      );
      nodes = [...nodes, node];
      bounds = bounds.union(node.bounds);
    }

    final dx = _diagramPadding - bounds.left;
    final dy = _diagramPadding - bounds.top;
    return RenderScene(
      size: Size(bounds.width + 2 * _diagramPadding,
          bounds.height + 2 * _diagramPadding),
      background: theme.background,
      nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
    );
  }

  _Placed _measure(StateNode s) {
    switch (s.kind) {
      case StateKind.start:
        return _Placed(s, 14, 14, Size.zero);
      case StateKind.end:
        return _Placed(s, 18, 18, Size.zero);
      case StateKind.choice:
        return _Placed(s, 32, 32, Size.zero);
      case StateKind.fork || StateKind.join:
        return horizontal
            ? _Placed(s, 8, 60, Size.zero)
            : _Placed(s, 60, 8, Size.zero);
      case StateKind.normal || StateKind.composite:
        final size = measurer.measure(s.label, baseStyle, maxWidth: 200);
        return _Placed(
            s, size.width + 2 * _padding, size.height + 2 * _padding, size);
    }
  }

  SceneGroup _buildState(_Placed p) {
    final s = p.node;
    var fill = theme.mainBkg;
    var stroke = theme.nodeBorder;
    void apply(Map<String, String>? styles) {
      if (styles == null) return;
      fill = Color.tryParse(styles['fill'] ?? '') ?? fill;
      stroke = Color.tryParse(styles['stroke'] ?? '') ?? stroke;
    }

    apply(diagram.classDefs['default']);
    for (final c in s.cssClasses) {
      apply(diagram.classDefs[c]);
    }
    apply(s.styles);

    final children = <SceneNode>[];
    switch (s.kind) {
      case StateKind.start:
        children.add(SceneShape(
          geometry: CircleGeometry(p.center, 7),
          fill: Fill(theme.lineColor),
        ));
      case StateKind.end:
        children.addAll([
          SceneShape(
            geometry: CircleGeometry(p.center, 9),
            fill: Fill(theme.background),
            stroke: Stroke(color: theme.lineColor, width: 1.5),
          ),
          SceneShape(
            geometry: CircleGeometry(p.center, 5),
            fill: Fill(theme.lineColor),
          ),
        ]);
      case StateKind.choice:
        children.add(SceneShape(
          geometry: PolygonGeometry([
            p.center + const Point(0, -16),
            p.center + const Point(16, 0),
            p.center + const Point(0, 16),
            p.center + const Point(-16, 0),
          ]),
          fill: Fill(fill),
          stroke: Stroke(color: stroke),
        ));
      case StateKind.fork || StateKind.join:
        children.add(SceneShape(
          geometry: RectGeometry(p.rect, rx: 3, ry: 3),
          fill: Fill(theme.lineColor),
        ));
      case StateKind.normal || StateKind.composite:
        children.addAll([
          SceneShape(
            geometry: RectGeometry(p.rect, rx: 8, ry: 8),
            fill: Fill(fill),
            stroke: Stroke(color: stroke),
          ),
          SceneText(
            text: s.label,
            bounds: Rect.fromCenter(
                p.center, p.labelSize.width, p.labelSize.height),
            style: baseStyle,
            color: theme.textColor,
          ),
        ]);
    }
    return SceneGroup(
        id: s.id,
        semanticLabel: s.label.isEmpty ? null : s.label,
        children: children);
  }

  Point _dir(Point from, Point to) {
    final d = to - from;
    final len = math.sqrt(d.x * d.x + d.y * d.y);
    return len == 0 ? const Point(0, 1) : Point(d.x / len, d.y / len);
  }
}

// --- helpers (private ports, same shapes as class_layout) --------------------

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

List<Point> _dropInsideRect(List<Point> pts, Rect rect,
    {required bool fromEnd}) {
  final list = List<Point>.from(pts);
  if (fromEnd) {
    while (list.length > 2 && rect.contains(list[list.length - 2])) {
      list.removeLast();
    }
  } else {
    while (list.length > 2 && rect.contains(list[1])) {
      list.removeAt(0);
    }
  }
  return list;
}

List<PathCommand> _curveBasis(List<Point> pts) {
  if (pts.isEmpty) return const [];
  if (pts.length == 1) return [MoveTo(pts.first)];
  if (pts.length == 2) return [MoveTo(pts[0]), LineTo(pts[1])];
  final cmds = <PathCommand>[MoveTo(pts[0])];
  cmds.add(LineTo(Point(
    (5 * pts[0].x + pts[1].x) / 6,
    (5 * pts[0].y + pts[1].y) / 6,
  )));
  for (var i = 2; i < pts.length; i++) {
    cmds.add(_basisSegment(pts[i - 2], pts[i - 1], pts[i]));
  }
  final n = pts.length;
  cmds.add(_basisSegment(pts[n - 2], pts[n - 1], pts[n - 1]));
  cmds.add(LineTo(pts[n - 1]));
  return cmds;
}

CubicTo _basisSegment(Point p0, Point p1, Point p) => CubicTo(
      Point((2 * p0.x + p1.x) / 3, (2 * p0.y + p1.y) / 3),
      Point((p0.x + 2 * p1.x) / 3, (p0.y + 2 * p1.y) / 3),
      Point((p0.x + 4 * p1.x + p.x) / 6, (p0.y + 4 * p1.y + p.y) / 6),
    );

/// ER diagram layout: dagre-positioned entity tables with crow's foot
/// relationship markers, ported (simplified) from upstream erRenderer.
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
import 'er_model.dart';

const double _cellPadX = 10;
const double _cellPadY = 6;
const double _diagramPadding = 8;
const double _markerLen = 18;

const _rowAltFill = Color(0xfff1eefb);

RenderScene layoutErDiagram(
  ErDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  return _ErLayout(diagram, measurer, theme).run();
}

class _EntityBox {
  _EntityBox(this.entity, this.width, this.height, this.colWidths,
      this.rowHeights, this.headerHeight);

  final ErEntity entity;
  final double width;
  final double height;

  /// type / name / keys / comment column widths (zero-width columns absent).
  final List<double> colWidths;
  final List<double> rowHeights;
  final double headerHeight;
  Point center = Point.zero;

  Rect get rect => Rect.fromCenter(center, width, height);
}

class _ErLayout {
  _ErLayout(this.diagram, this.measurer, this.theme)
      : baseStyle = TextStyleSpec(
          fontFamily: theme.fontFamily,
          fontSize: theme.fontSize * 0.85,
        ),
        headerStyle = TextStyleSpec(
          fontFamily: theme.fontFamily,
          fontSize: theme.fontSize,
          fontWeight: 700,
        );

  final ErDiagram diagram;
  final TextMeasurer measurer;
  final MermaidTheme theme;
  final TextStyleSpec baseStyle;
  final TextStyleSpec headerStyle;

  final boxes = <String, _EntityBox>{};

  RenderScene run() {
    for (final e in diagram.entities.values) {
      boxes[e.id] = _measureEntity(e);
    }

    final g = dagre.DagreGraph();
    for (final b in boxes.values) {
      g.addNode(
          dagre.DagreNode(b.entity.id, width: b.width, height: b.height));
    }
    final labelSizes = <int, Size>{};
    for (var i = 0; i < diagram.relationships.length; i++) {
      final r = diagram.relationships[i];
      Size? size;
      if (r.label.isNotEmpty) {
        size = measurer.measure(r.label, baseStyle, maxWidth: 150);
        labelSizes[i] = size;
      }
      if (r.from == r.to) continue;
      g.addEdge(dagre.DagreEdge(
        r.from,
        r.to,
        id: 'e$i',
        minLen: 1,
        width: size?.width ?? 0,
        height: size?.height ?? 0,
        labelPos: dagre.LabelPosition.center,
      ));
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
        nodeSep: 60,
        rankSep: 70,
      ),
    );
    for (final b in boxes.values) {
      b.center = result.graph.nodeMap[b.entity.id]!.position!.center;
    }

    final edgeNodes = <SceneNode>[];
    final labelNodes = <SceneNode>[];
    final entityNodes = <SceneNode>[];

    final selfLoops = <String, int>{};
    for (var i = 0; i < diagram.relationships.length; i++) {
      final r = diagram.relationships[i];
      final from = boxes[r.from]!;
      final to = boxes[r.to]!;

      List<Point> points;
      if (r.from == r.to) {
        final idx = selfLoops[r.from] ?? 0;
        selfLoops[r.from] = idx + 1;
        final rect = from.rect;
        final ext = 50.0 + idx * 18;
        points = [
          Point(rect.right, rect.center.y - rect.height / 4),
          Point(rect.right + ext, rect.center.y - rect.height / 4),
          Point(rect.right + ext, rect.center.y + rect.height / 4),
          Point(rect.right, rect.center.y + rect.height / 4),
        ];
      } else {
        final dagreEdge = result.graph.findEdgeById('e$i')!;
        points = List<Point>.from(dagreEdge.points);
        if (points.length < 2) points = [from.center, to.center];
        points[0] = _intersectRect(from.rect, points[1]);
        points[points.length - 1] =
            _intersectRect(to.rect, points[points.length - 2]);
      }

      final startTip = points.first;
      final startDir = _dir(points[1], startTip);
      final endTip = points.last;
      final endDir = _dir(points[points.length - 2], endTip);
      // Crow's foot markers sit between line end and entity; shorten line.
      points[0] = startTip - startDir * _markerLen;
      points[points.length - 1] = endTip - endDir * _markerLen;

      edgeNodes.add(SceneGroup(
        id: 'rel_${r.from}_${r.to}_$i',
        semanticLabel: r.label.isEmpty ? null : r.label,
        children: [
          SceneShape(
            geometry: PathGeometry(points.length == 2
                ? [MoveTo(points[0]), LineTo(points[1])]
                : _curveBasis(points)),
            stroke: Stroke(
              color: theme.lineColor,
              width: 1.5,
              dash: r.identifying ? null : const [4, 4],
            ),
          ),
          ..._crowsFoot(r.cardFrom, startTip, startDir),
          ..._crowsFoot(r.cardTo, endTip, endDir),
        ],
      ));

      final labelSize = labelSizes[i];
      if (labelSize != null) {
        final c = r.from == r.to
            ? Point(points[1].x + 8 + labelSize.width / 2,
                (points[1].y + points[2].y) / 2)
            : _midpoint(points);
        labelNodes.add(SceneGroup(id: 'rellabel_$i', children: [
          SceneShape(
            geometry: RectGeometry(
                Rect.fromCenter(c, labelSize.width + 4, labelSize.height + 2)),
            fill: Fill(theme.background),
          ),
          SceneText(
            text: r.label,
            bounds: Rect.fromCenter(c, labelSize.width, labelSize.height),
            style: baseStyle,
            color: theme.textColor,
          ),
        ]));
      }
    }

    for (final b in boxes.values) {
      entityNodes.add(_buildEntity(b));
    }

    var nodes = <SceneNode>[...edgeNodes, ...labelNodes, ...entityNodes];
    var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 100);

    final title = diagram.title;
    if (title != null && title.isNotEmpty) {
      final size = measurer.measure(title, headerStyle);
      final node = SceneText(
        text: title,
        bounds: Rect.fromLTWH(bounds.center.x - size.width / 2,
            bounds.top - size.height - 10, size.width, size.height),
        style: headerStyle,
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

  // --- entity table -----------------------------------------------------------

  List<List<String>> _attributeCells(ErEntity e) => [
        for (final a in e.attributes)
          [
            a.type,
            a.name,
            if (e.attributes.any((x) => x.keys.isNotEmpty)) a.keys.join(','),
            if (e.attributes.any((x) => x.comment != null)) a.comment ?? '',
          ],
      ];

  _EntityBox _measureEntity(ErEntity e) {
    final headerSize = measurer.measure(e.label, headerStyle);
    final cells = _attributeCells(e);
    final colCount = cells.isEmpty ? 0 : cells.first.length;
    final colWidths = List<double>.filled(colCount, 0);
    final rowHeights = <double>[];
    for (final row in cells) {
      var rowH = 0.0;
      for (var c = 0; c < row.length; c++) {
        final size = measurer.measure(row[c], baseStyle);
        colWidths[c] = math.max(colWidths[c], size.width + 2 * _cellPadX);
        rowH = math.max(rowH, size.height + 2 * _cellPadY);
      }
      rowHeights.add(rowH);
    }
    final headerHeight = headerSize.height + 2 * _cellPadY;
    var width = math.max(headerSize.width + 2 * _cellPadX,
        colWidths.fold(0.0, (a, b) => a + b));
    width = math.max(width, 80);
    // Stretch the last column to fill the box.
    if (colCount > 0) {
      final total = colWidths.fold(0.0, (a, b) => a + b);
      if (total < width) colWidths[colCount - 1] += width - total;
    }
    final height =
        headerHeight + rowHeights.fold(0.0, (a, b) => a + b);
    return _EntityBox(e, width, height, colWidths, rowHeights, headerHeight);
  }

  SceneGroup _buildEntity(_EntityBox b) {
    final rect = b.rect;
    final cells = _attributeCells(b.entity);
    final children = <SceneNode>[
      SceneShape(
        geometry: RectGeometry(rect),
        fill: Fill(theme.mainBkg),
        stroke: Stroke(color: theme.nodeBorder),
      ),
      SceneText(
        text: b.entity.label,
        bounds: Rect.fromLTWH(
            rect.left, rect.top + _cellPadY, rect.width, b.headerHeight),
        style: headerStyle,
        color: theme.textColor,
      ),
    ];
    var y = rect.top + b.headerHeight;
    for (var rIdx = 0; rIdx < cells.length; rIdx++) {
      final rowH = b.rowHeights[rIdx];
      if (rIdx.isOdd) {
        children.add(SceneShape(
          geometry:
              RectGeometry(Rect.fromLTWH(rect.left, y, rect.width, rowH)),
          fill: const Fill(_rowAltFill),
        ));
      }
      children.add(SceneShape(
        geometry: PathGeometry(
            [MoveTo(Point(rect.left, y)), LineTo(Point(rect.right, y))]),
        stroke: Stroke(color: theme.nodeBorder, width: 0.7),
      ));
      var x = rect.left;
      for (var c = 0; c < cells[rIdx].length; c++) {
        final text = cells[rIdx][c];
        if (text.isNotEmpty) {
          final size = measurer.measure(text, baseStyle);
          children.add(SceneText(
            text: text,
            bounds: Rect.fromLTWH(x + _cellPadX, y + (rowH - size.height) / 2,
                size.width, size.height),
            style: baseStyle,
            color: theme.textColor,
            align: TextAlignH.left,
          ));
        }
        x += b.colWidths[c];
      }
      y += rowH;
    }
    // Column separators.
    var x = rect.left;
    for (var c = 0; c < b.colWidths.length - 1; c++) {
      x += b.colWidths[c];
      children.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(x, rect.top + b.headerHeight)),
          LineTo(Point(x, rect.bottom)),
        ]),
        stroke: Stroke(color: theme.nodeBorder, width: 0.7),
      ));
    }
    return SceneGroup(
        id: b.entity.id, semanticLabel: b.entity.label, children: children);
  }

  // --- crow's foot markers ------------------------------------------------------

  /// Draws the marker for [card] with [tip] at the entity border, pointing
  /// inward along -[dir].
  List<SceneNode> _crowsFoot(ErCardinality card, Point tip, Point dir) {
    final perp = Point(-dir.y, dir.x);
    final stroke = Stroke(color: theme.lineColor, width: 1.5);
    SceneNode bar(double at) => SceneShape(
          geometry: PathGeometry([
            MoveTo(tip - dir * at + perp * 6),
            LineTo(tip - dir * at - perp * 6),
          ]),
          stroke: stroke,
        );
    SceneNode circle(double at) => SceneShape(
          geometry: CircleGeometry(tip - dir * at, 5),
          fill: Fill(theme.background),
          stroke: stroke,
        );
    SceneNode foot() => SceneShape(
          geometry: PathGeometry([
            MoveTo(tip + perp * 7),
            LineTo(tip - dir * 12),
            MoveTo(tip),
            LineTo(tip - dir * 12),
            MoveTo(tip - perp * 7),
            LineTo(tip - dir * 12),
          ]),
          stroke: stroke,
        );

    switch (card) {
      case ErCardinality.onlyOne:
        return [bar(8), bar(13)];
      case ErCardinality.zeroOrOne:
        return [circle(16), bar(8)];
      case ErCardinality.oneOrMore:
        return [foot(), bar(15)];
      case ErCardinality.zeroOrMore:
        return [foot(), circle(17)];
    }
  }

  Point _midpoint(List<Point> pts) {
    if (pts.length.isOdd) return pts[pts.length ~/ 2];
    final a = pts[pts.length ~/ 2 - 1];
    final b = pts[pts.length ~/ 2];
    return Point((a.x + b.x) / 2, (a.y + b.y) / 2);
  }

  Point _dir(Point from, Point to) {
    final d = to - from;
    final len = math.sqrt(d.x * d.x + d.y * d.y);
    return len == 0 ? const Point(0, 1) : Point(d.x / len, d.y / len);
  }
}

// --- helpers (same private ports as class/state layouts) ---------------------

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

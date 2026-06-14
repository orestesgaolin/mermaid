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

// Upstream erBox falls back to PADDING = er.diagramPadding ?? 10 (horizontal,
// once per column) and TEXT_PADDING = er.entityPadding ?? 6 (vertical, once per
// row) for the htmlLabels default. The richer config-schema defaults
// (diagramPadding 20 / entityPadding 15) are not present on the resolved config
// the unified renderer feeds erBox, so the 10/6 fallbacks win.
const double _cellPadX = 10;
const double _cellPadY = 6;
const double _diagramPadding = 8;
const double _markerLen = 18;

// Upstream config.er defaults (config.schema.yaml).
const double _minEntityWidth = 100;
const double _minEntityHeight = 75;

// Content-row banding from the default theme: rowOdd = lighten(primary,75) ≈
// #ffffff, rowEven = lighten(primary,1) ≈ #f1f1ff (a near-invisible band).
const _rowOddFill = Color(0xffffffff);
const _rowEvenFill = Color(0xfff1f1ff);

// tertiaryColor for the default theme = adjust(primary,{h:-160}) ≈ #f9ffec.
const _tertiaryColor = Color(0xfff9ffec);

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

class _EntityStyle {
  const _EntityStyle({this.fill, this.stroke, this.color});
  final Color? fill;
  final Color? stroke;
  final Color? color;
}

class _ErLayout {
  _ErLayout(this.diagram, this.measurer, this.theme)
      : baseStyle = TextStyleSpec(
          fontFamily: theme.fontFamily,
          fontSize: theme.fontSize,
        ),
        headerStyle = TextStyleSpec(
          fontFamily: theme.fontFamily,
          fontSize: theme.fontSize,
        ),
        labelStyle = const TextStyleSpec(
          fontFamily: '"trebuchet ms", verdana, arial, sans-serif',
          fontSize: 14,
        );

  final ErDiagram diagram;
  final TextMeasurer measurer;
  final MermaidTheme theme;

  /// Attribute-cell text style (full `fontSize`, normal weight — matches
  /// unified `erBox`, which draws all cells at `config.fontSize`).
  final TextStyleSpec baseStyle;

  /// Entity-name header style (full `fontSize`, normal weight).
  final TextStyleSpec headerStyle;

  /// Relationship-edge label style (`styles.ts` `.edgeLabel .label` = 14px).
  final TextStyleSpec labelStyle;

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
        size = measurer.measure(r.label, labelStyle, maxWidth: 150);
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
        nodeSep: 140,
        rankSep: 80,
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
              width: 1,
              // Upstream non-identifying lines use stroke-dasharray 8,8.
              dash: r.identifying ? null : const [8, 8],
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
            // `.relationshipLabelBox` = tertiaryColor @ opacity 0.7.
            fill: Fill(_tertiaryColor.withOpacity(0.7)),
          ),
          SceneText(
            text: r.label,
            bounds: Rect.fromCenter(c, labelSize.width, labelSize.height),
            style: labelStyle,
            // `.edgeLabel .label` fill = nodeBorder.
            color: theme.nodeBorder,
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
        // Upstream titleTopMargin default = 25.
        bounds: Rect.fromLTWH(bounds.center.x - size.width / 2,
            bounds.top - size.height - 25, size.width, size.height),
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
    // erBox: nameBBox.height += TEXT_PADDING.
    final headerHeight = headerSize.height + _cellPadY;
    final cells = _attributeCells(e);

    if (cells.isEmpty) {
      // Attribute-less entity: drawRect with labelPaddingX = PADDING,
      // labelPaddingY = PADDING * 1.5, then clamp width to minEntityWidth.
      var width = headerSize.width + _cellPadX * 2;
      if (width < _minEntityWidth) width = _minEntityWidth;
      final height =
          math.max(headerSize.height + _cellPadX * 1.5 * 2, _minEntityHeight);
      return _EntityBox(e, width, height, const [], const [], headerHeight);
    }

    final colCount = cells.first.length;
    final colWidths = List<double>.filled(colCount, 0);
    final rowHeights = <double>[];
    for (final row in cells) {
      var rowH = 0.0;
      for (var c = 0; c < row.length; c++) {
        final size = measurer.measure(row[c], baseStyle);
        // erBox adds PADDING once per column, TEXT_PADDING once per row.
        colWidths[c] = math.max(colWidths[c], size.width + _cellPadX);
        rowH = math.max(rowH, size.height);
      }
      rowHeights.add(rowH + _cellPadY);
    }
    // w = max(headerBBox.width + PADDING*2, node.width, sum(colWidths)).
    var width = math.max(headerSize.width + _cellPadX * 2,
        colWidths.fold(0.0, (a, b) => a + b));
    width = math.max(width, _minEntityWidth);
    // Stretch the last column to fill the box.
    final total = colWidths.fold(0.0, (a, b) => a + b);
    if (total < width) colWidths[colCount - 1] += width - total;
    // h = sum(rowHeights) + nameBBox.height, floored at minEntityHeight.
    var height = headerHeight + rowHeights.fold(0.0, (a, b) => a + b);
    height = math.max(height, _minEntityHeight);
    return _EntityBox(e, width, height, colWidths, rowHeights, headerHeight);
  }

  SceneGroup _buildEntity(_EntityBox b) {
    final rect = b.rect;
    final cells = _attributeCells(b.entity);
    final style = _resolveStyle(b.entity);
    final children = <SceneNode>[
      SceneShape(
        geometry: RectGeometry(rect),
        fill: Fill(style.fill ?? theme.mainBkg),
        stroke: Stroke(color: style.stroke ?? theme.nodeBorder, width: 1),
      ),
      SceneText(
        text: b.entity.label,
        bounds: Rect.fromLTWH(
            rect.left, rect.top + _cellPadY, rect.width, b.headerHeight),
        style: headerStyle,
        color: style.color ?? theme.textColor,
      ),
    ];
    var y = rect.top + b.headerHeight;
    for (var rIdx = 0; rIdx < cells.length; rIdx++) {
      final rowH = b.rowHeights[rIdx];
      // Upstream parity: contentRowIndex is 1-based, isEven = (index % 2 == 0).
      // First content row (index 1) is odd → rowOdd.
      final isEven = (rIdx + 1).isEven;
      children.add(SceneShape(
        geometry: RectGeometry(Rect.fromLTWH(rect.left, y, rect.width, rowH)),
        fill: Fill(isEven ? _rowEvenFill : _rowOddFill),
      ));
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
            color: style.color ?? theme.textColor,
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

  /// Draws the crow's-foot marker for [card] with [tip] at the entity border.
  ///
  /// Geometry mirrors the upstream END markers in `erMarkers.js`: each marker
  /// is authored in a local frame where `lx` grows toward the entity (the
  /// marker's `refX` lands on the border) and `ly` is the perpendicular axis
  /// about `refY`. `_p(refX, refY, lx, ly)` maps that local frame to world:
  /// along the line via `dir` (which points inward toward the entity) and
  /// across it via `perp`. Stroke width 1, circle fill white (`.marker`).
  List<SceneNode> _crowsFoot(ErCardinality card, Point tip, Point dir) {
    final perp = Point(-dir.y, dir.x);
    final stroke = Stroke(color: theme.lineColor, width: 1);

    Point p(double refX, double refY, double lx, double ly) =>
        tip - dir * (refX - lx) + perp * (ly - refY);

    SceneNode bars(double refX, double refY, List<double> xs) => SceneShape(
          geometry: PathGeometry([
            for (final lx in xs) ...[
              MoveTo(p(refX, refY, lx, refY - 9)),
              LineTo(p(refX, refY, lx, refY + 9)),
            ],
          ]),
          stroke: stroke,
        );
    SceneNode circle(double refX, double refY, double cx, double cy) =>
        SceneShape(
          geometry: CircleGeometry(p(refX, refY, cx, cy), 6),
          fill: const Fill(Color(0xffffffff)),
          stroke: stroke,
        );
    // Crow's foot: a leaf-shaped pair of quadratic arcs.
    // `M lx0,refY Q cx,(refY-18) wx,refY Q cx,(refY+18) lx0,refY`.
    SceneNode foot(double refX, double refY, double lx0, double cx, double wx) =>
        SceneShape(
          geometry: PathGeometry([
            MoveTo(p(refX, refY, lx0, refY)),
            QuadTo(p(refX, refY, cx, refY - 18), p(refX, refY, wx, refY)),
            QuadTo(p(refX, refY, cx, refY + 18), p(refX, refY, lx0, refY)),
          ]),
          stroke: stroke,
        );

    switch (card) {
      case ErCardinality.onlyOne:
        // ONLY_ONE_END refX 18 refY 9: bars at 3 and 9.
        return [bars(18, 9, const [3, 9])];
      case ErCardinality.zeroOrOne:
        // ZERO_OR_ONE_END refX 30 refY 9: circle (9,9) + bar at 21.
        return [circle(30, 9, 9, 9), bars(30, 9, const [21])];
      case ErCardinality.oneOrMore:
        // ONE_OR_MORE_END refX 27 refY 18: bar at 3 + foot 9..45.
        return [bars(27, 18, const [3]), foot(27, 18, 9, 27, 45)];
      case ErCardinality.zeroOrMore:
        // ZERO_OR_MORE_END refX 39 refY 18: circle (9,18) + foot 21..57.
        return [circle(39, 18, 9, 18), foot(39, 18, 21, 39, 57)];
    }
  }

  /// Resolves the effective fill/stroke/text color for [e] from its attached
  /// classes (`classDef`) and inline `style` declarations (inline wins).
  _EntityStyle _resolveStyle(ErEntity e) {
    Color? fill;
    Color? stroke;
    Color? color;
    void apply(List<String> decls) {
      for (final decl in decls) {
        final i = decl.indexOf(':');
        if (i < 0) continue;
        final key = decl.substring(0, i).trim().toLowerCase();
        final value = decl.substring(i + 1).trim();
        final parsed = Color.tryParse(value);
        if (parsed == null) continue;
        switch (key) {
          case 'fill':
            fill = parsed;
          case 'stroke':
            stroke = parsed;
          case 'color':
            color = parsed;
        }
      }
    }

    for (final cls in e.cssClasses) {
      final def = diagram.classDefs[cls];
      if (def != null) apply(def);
    }
    apply(e.cssStyles);
    return _EntityStyle(fill: fill, stroke: stroke, color: color);
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

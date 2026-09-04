/// Pie chart layout: slices (bezier-approximated arcs), in-slice percentage
/// labels, and a legend, following upstream pieRenderer.
library;

import 'dart:math' as math;

import '../../config_values.dart';
import '../../directives.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';
import 'pie_model.dart';

// Matches upstream pieRenderer: min(pieWidth=450, height=450)/2 − MARGIN(40).
const double _radius = 185;
const double _diagramPadding = 12;

// Upstream theme-default pieOuterStrokeWidth.
const double _outerStrokeWidth = 2;

// Upstream LEGEND_RECT_SIZE / LEGEND_SPACING.
const double _legendRectSize = 18;
const double _legendSpacing = 4;

// Upstream pieOpacity (theme-default).
const double _pieOpacity = 0.7;

// Upstream pie fixed font sizes (theme-default, in px, independent of base).
const double _sectionTextSize = 17;
const double _legendTextSize = 17;
const double _titleTextSize = 25;

/// Typed layout values from `config.pie`.
class PieConfig {
  const PieConfig({
    this.textPosition = 0.75,
    this.donutHole = 0,
    this.legendPosition = 'right',
  });

  /// Radial label position, from the center (`0`) to the outer edge (`1`).
  final double textPosition;

  /// Inner radius as a fraction of the pie radius (`0` to `0.9`).
  final double donutHole;

  /// One of `top`, `bottom`, `left`, `right`, or `center`.
  final String legendPosition;

  factory PieConfig.fromSource(String source) {
    final values = resolveDiagramConfig(source, 'pie');
    return PieConfig(
      textPosition: clampedDouble(values, 'textPosition', 0.75, min: 0, max: 1),
      donutHole: clampedDouble(values, 'donutHole', 0, min: 0, max: 0.9),
      legendPosition: enumValue(values, 'legendPosition', const {
        'top',
        'bottom',
        'left',
        'right',
        'center',
      }, 'right'),
    );
  }
}

RenderScene layoutPieChart(
  PieChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
  PieConfig config = const PieConfig(),
}) {
  // Upstream pieStrokeColor / pieOuterStrokeColor (theme-default: black).
  final strokeColor = theme.pieStrokeColor;
  final outerStrokeColor = theme.pieOuterStrokeColor;
  // Upstream pieSectionTextColor / pieLegendTextColor / pieTitleTextColor.
  final sectionTextColor = theme.pieSectionTextColor;
  final legendTextColor = theme.pieLegendTextColor;
  final titleTextColor = theme.pieTitleTextColor;
  // Upstream pie1..pie12 ordinal scale (theme-derived; default theme equals the
  // precomputed default-theme hex). 1-indexed list of 12.
  final palette = theme.pie;
  final sectionStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: _sectionTextSize);
  final legendStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: _legendTextSize);
  final nodes = <SceneNode>[];
  final center = const Point(_radius + 20, _radius + 20);
  final total = chart.slices.fold(0.0, (a, s) => a + s.value);
  final legendStyleSizes = <Size>[];
  for (final slice in chart.slices) {
    final text = chart.showData
        ? '${slice.label} [${_fmt(slice.value)}]'
        : slice.label;
    legendStyleSizes.add(measurer.measure(text, legendStyle));
  }
  final longestLegendWidth = legendStyleSizes.fold(
    0.0,
    (width, size) => math.max(width, size.width),
  );
  final legendHeight = _legendRectSize + _legendSpacing;
  final totalLegendHeight = legendHeight * chart.slices.length;
  final Point pieOffset = switch (config.legendPosition) {
    'top' => Point(0, totalLegendHeight + legendHeight),
    'left' => Point(longestLegendWidth + _legendRectSize + _legendSpacing, 0),
    _ => const Point(0, 0),
  };
  final pieCenter = Point(center.x + pieOffset.x, center.y + pieOffset.y);

  // Mirror upstream createPieArcs / draw filtering:
  //  - createPieArcs drops sections where (value/sum)*100 < 1.
  //  - draw further drops arcs whose rounded percent == 0.
  // The legend, by contrast, lists ALL sections. Slice colors are keyed by
  // the original section index (d3 scaleOrdinal over all section labels), so
  // we keep the original index alongside each drawn slice.
  final drawn = <int>[];
  for (var i = 0; i < chart.slices.length; i++) {
    if (total == 0) continue;
    final pct = chart.slices[i].value / total * 100;
    if (pct < 1) continue;
    if (pct.round() == 0) continue;
    drawn.add(i);
  }

  // Outer ring (pieOuterCircle): radius + outerStrokeWidth/2, black 2px, no fill.
  nodes.add(
    SceneShape(
      geometry: CircleGeometry(pieCenter, _radius + _outerStrokeWidth / 2),
      stroke: Stroke(color: outerStrokeColor, width: _outerStrokeWidth),
    ),
  );

  // Slices, clockwise from 12 o'clock (upstream d3.pie default, sort=null).
  var angle = -math.pi / 2;
  for (final i in drawn) {
    final slice = chart.slices[i];
    final sweep = slice.value / total * 2 * math.pi;
    final color = palette[i % palette.length];
    final end = angle + sweep;
    final pct = '${(slice.value / total * 100).round()}%';
    final size = measurer.measure(pct, sectionStyle);
    final pos = _polar(
      pieCenter,
      _radius * config.textPosition,
      angle + sweep / 2,
    );
    final geometry = config.donutHole == 0
        ? PathGeometry([
            MoveTo(pieCenter),
            LineTo(_polar(pieCenter, _radius, angle)),
            ..._arc(pieCenter, _radius, angle, end),
            const ClosePath(),
          ])
        : PathGeometry([
            MoveTo(_polar(pieCenter, _radius, angle)),
            ..._arc(pieCenter, _radius, angle, end),
            LineTo(_polar(pieCenter, _radius * config.donutHole, end)),
            ..._arc(pieCenter, _radius * config.donutHole, end, angle),
            const ClosePath(),
          ]);
    nodes.add(
      SceneGroup(
        id: 'slice_$i',
        semanticLabel: slice.label,
        children: [
          SceneShape(
            geometry: geometry,
            fill: Fill(color.withOpacity(_pieOpacity)),
            stroke: Stroke(color: strokeColor, width: 2),
          ),
          SceneText(
            text: pct,
            bounds: Rect.fromCenter(pos, size.width, size.height),
            style: sectionStyle,
            color: sectionTextColor,
          ),
        ],
      ),
    );
    angle = end;
  }

  // Legend placement mirrors upstream pieRenderer. `top` and `left` also
  // translate the pie itself to make space; the title remains at its original
  // center like upstream.
  final legendOffset = totalLegendHeight / 2;
  final legendX = switch (config.legendPosition) {
    'center' || 'top' || 'bottom' =>
      center.x - longestLegendWidth / 2 - (_legendRectSize + _legendSpacing),
    'left' => center.x - _radius - (_legendRectSize + _legendSpacing),
    _ => center.x + 12 * _legendRectSize,
  };
  for (var i = 0; i < chart.slices.length; i++) {
    final slice = chart.slices[i];
    final text = chart.showData
        ? '${slice.label} [${_fmt(slice.value)}]'
        : slice.label;
    final size = legendStyleSizes[i];
    final legendY = switch (config.legendPosition) {
      'top' => center.y + i * legendHeight - _radius,
      'bottom' => center.y + i * legendHeight + _radius + legendHeight,
      _ => center.y + i * legendHeight - legendOffset,
    };
    final color = palette[i % palette.length];
    nodes.add(SceneGroup(id: 'legend_$i', role: SceneGroupRole.internal, children: [
      SceneShape(
        geometry: RectGeometry(
            Rect.fromLTWH(legendX, legendY, _legendRectSize, _legendRectSize)),
        // Upstream legend rect: fill AND stroke = slice color.
        fill: Fill(color),
        stroke: Stroke(color: color, width: 1),
      ),
      SceneText(
        text: text,
        bounds: Rect.fromLTWH(
            legendX + _legendRectSize + _legendSpacing,
            legendY + (_legendRectSize - _legendSpacing) - size.height,
            size.width,
            size.height),
        style: legendStyle,
        color: legendTextColor,
        align: TextAlignH.left,
      ),
    ]));
  }

  // Title centered above the pie group, at y = -(height-50)/2 = -200 (upstream).
  final title = chart.title;
  var top = 0.0;
  if (title != null && title.isNotEmpty) {
    final style =
        TextStyleSpec(fontFamily: theme.fontFamily, fontSize: _titleTextSize);
    final size = measurer.measure(title, style);
    final titleY = center.y - 200;
    nodes.add(SceneText(
      text: title,
      bounds: Rect.fromLTWH(
          center.x - size.width / 2, titleY - size.height / 2, size.width,
          size.height),
      style: style,
      color: titleTextColor,
    ));
    top = titleY - size.height / 2;
  }

  // Keep the established default bounds calculation unchanged. Other legend
  // positions use actual scene bounds because `top` and `left` move the pie.
  if (config.legendPosition != 'right') {
    final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 120, 80);
    final dx = _diagramPadding - bounds.left;
    final dy = _diagramPadding - bounds.top;
    return RenderScene(
      size: Size(
        bounds.width + 2 * _diagramPadding,
        bounds.height + 2 * _diagramPadding,
      ),
      background: theme.background,
      nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
    );
  }

  // Bounding box: pie + ring, legend, and title.
  var minLeft = center.x - _radius;
  var maxRight = center.x + _radius;
  var maxBottom = center.y + _radius;
  var minTop = math.min(center.y - _radius, top);
  for (var i = 0; i < chart.slices.length; i++) {
    final slice = chart.slices[i];
    final text =
        chart.showData ? '${slice.label} [${_fmt(slice.value)}]' : slice.label;
    final w = measurer.measure(text, legendStyle).width;
    maxRight = math.max(
        maxRight, legendX + _legendRectSize + _legendSpacing + w);
    final legendY = center.y + i * legendHeight - legendOffset;
    maxBottom = math.max(maxBottom, legendY + _legendRectSize);
  }
  if (title != null && title.isNotEmpty) {
    final w = measurer.measure(title, TextStyleSpec(
        fontFamily: theme.fontFamily, fontSize: _titleTextSize)).width;
    minLeft = math.min(minLeft, center.x - w / 2);
    maxRight = math.max(maxRight, center.x + w / 2);
  }

  final dx = _diagramPadding - minLeft;
  final dy = _diagramPadding - minTop;
  return RenderScene(
    size: Size(maxRight - minLeft + 2 * _diagramPadding,
        maxBottom - minTop + 2 * _diagramPadding),
    background: theme.background,
    nodes: [
      for (final n in nodes) translateSceneNode(n, dx, dy),
    ],
  );
}

// Upstream legend renders raw JS `d.value`; integers print without a decimal,
// fractions keep their digits. Mirror that here.
String _fmt(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : v.toString();

Point _polar(Point c, double r, double a) =>
    Point(c.x + r * math.cos(a), c.y + r * math.sin(a));

/// Circular arc as cubic segments (<= 90° each).
List<PathCommand> _arc(Point c, double r, double a0, double a1) {
  final cmds = <PathCommand>[];
  var start = a0;
  final direction = a1 >= a0 ? 1.0 : -1.0;
  bool hasMore() => direction > 0 ? start < a1 - 1e-9 : start > a1 + 1e-9;
  while (hasMore()) {
    final end = direction > 0
        ? math.min(start + math.pi / 2, a1)
        : math.max(start - math.pi / 2, a1);
    final sweep = end - start;
    final k = 4 / 3 * math.tan(sweep / 4) * r;
    final p0 = _polar(c, r, start);
    final p1 = _polar(c, r, end);
    final c1 = Point(p0.x - k * math.sin(start), p0.y + k * math.cos(start));
    final c2 = Point(p1.x + k * math.sin(end), p1.y - k * math.cos(end));
    cmds.add(CubicTo(c1, c2, p1));
    start = end;
  }
  return cmds;
}

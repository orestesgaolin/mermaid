/// Pie chart layout: slices (bezier-approximated arcs), in-slice percentage
/// labels, and a legend, following upstream pieRenderer.
library;

import 'dart:math' as math;

import '../../color.dart';
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

// Upstream default textPosition (pieRenderer: labelArc inner=outer=radius*0.75).
const double _textPosition = 0.75;

// Upstream pieOpacity (theme-default).
const double _pieOpacity = 0.7;

// Upstream pie fixed font sizes (theme-default, in px, independent of base).
const double _sectionTextSize = 17;
const double _legendTextSize = 17;
const double _titleTextSize = 25;

// Upstream pieStrokeColor / pieOuterStrokeColor (theme-default: black).
const Color _strokeColor = Color(0xff000000);

// Upstream pieSectionTextColor = textColor (theme-default '#333').
const Color _sectionTextColor = Color(0xff333333);

// Upstream pieLegendTextColor / pieTitleTextColor = taskTextDarkColor
// (theme-default 'black').
const Color _legendTextColor = Color(0xff000000);
const Color _titleTextColor = Color(0xff000000);

// Upstream theme-default pie1..pie12 (default theme: primary #ECECFF,
// secondary #ffffde, tertiary = adjust(primary, h:-160); remaining derived
// via HSL adjust). Values precomputed to the default-theme hex constants.
const _palette = <Color>[
  Color(0xffececff), // pie1  = primaryColor
  Color(0xffffffde), // pie2  = secondaryColor
  Color(0xffb9ff20), // pie3  = adjust(tertiary, l:-40)
  Color(0xffb9b9ff), // pie4  = adjust(primary,  l:-10)
  Color(0xffffff45), // pie5  = adjust(secondary,l:-30)
  Color(0xffd9ff86), // pie6  = adjust(tertiary, l:-20)
  Color(0xffff86ff), // pie7  = adjust(primary, h:+60,l:-20)
  Color(0xff20ffff), // pie8  = adjust(primary, h:-60,l:-40)
  Color(0xffff2020), // pie9  = adjust(primary, h:120,l:-40)
  Color(0xffff20ff), // pie10 = adjust(primary, h:+60,l:-40)
  Color(0xff20ff90), // pie11 = adjust(primary, h:-90,l:-40)
  Color(0xffff5353), // pie12 = adjust(primary, h:120,l:-30)
];

RenderScene layoutPieChart(
  PieChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final sectionStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: _sectionTextSize);
  final legendStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: _legendTextSize);
  final nodes = <SceneNode>[];
  final center = const Point(_radius + 20, _radius + 20);
  final total = chart.slices.fold(0.0, (a, s) => a + s.value);

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
  nodes.add(SceneShape(
    geometry: CircleGeometry(center, _radius + _outerStrokeWidth / 2),
    stroke: const Stroke(color: _strokeColor, width: _outerStrokeWidth),
  ));

  // Slices, clockwise from 12 o'clock (upstream d3.pie default, sort=null).
  var angle = -math.pi / 2;
  for (final i in drawn) {
    final slice = chart.slices[i];
    final sweep = slice.value / total * 2 * math.pi;
    final color = _palette[i % _palette.length];
    final end = angle + sweep;
    final pct = '${(slice.value / total * 100).round()}%';
    final size = measurer.measure(pct, sectionStyle);
    final pos = _polar(center, _radius * _textPosition, angle + sweep / 2);
    nodes.add(SceneGroup(
      id: 'slice_$i',
      semanticLabel: slice.label,
      children: [
        SceneShape(
          geometry: PathGeometry([
            MoveTo(center),
            LineTo(_polar(center, _radius, angle)),
            ..._arc(center, _radius, angle, end),
            const ClosePath(),
          ]),
          fill: Fill(color.withOpacity(_pieOpacity)),
          stroke: const Stroke(color: _strokeColor, width: 2),
        ),
        SceneText(
          text: pct,
          bounds: Rect.fromCenter(pos, size.width, size.height),
          style: sectionStyle,
          color: _sectionTextColor,
        ),
      ],
    ));
    angle = end;
  }

  // Legend, to the right of the pie (upstream legendPosition 'right').
  // Horizontal offset from center is 12 * LEGEND_RECT_SIZE; vertical is
  // index*legendHeight − (legendHeight*n)/2, legendHeight = rect + spacing.
  final legendHeight = _legendRectSize + _legendSpacing;
  final legendX = center.x + 12 * _legendRectSize;
  final legendOffset = legendHeight * chart.slices.length / 2;
  for (var i = 0; i < chart.slices.length; i++) {
    final slice = chart.slices[i];
    final text = chart.showData
        ? '${slice.label} [${_fmt(slice.value)}]'
        : slice.label;
    final size = measurer.measure(text, legendStyle);
    final legendY = center.y + i * legendHeight - legendOffset;
    final color = _palette[i % _palette.length];
    nodes.add(SceneGroup(id: 'legend_$i', children: [
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
        color: _legendTextColor,
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
      color: _titleTextColor,
    ));
    top = titleY - size.height / 2;
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
  while (start < a1 - 1e-9) {
    final end = math.min(start + math.pi / 2, a1);
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

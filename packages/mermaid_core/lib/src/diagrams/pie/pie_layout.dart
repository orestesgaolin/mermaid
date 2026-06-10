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

const double _radius = 130;
const double _diagramPadding = 12;

/// Approximation of upstream theme-default pie1..pie12.
const _palette = <Color>[
  Color(0xffececff),
  Color(0xffffffde),
  Color(0xffd5c9e5),
  Color(0xffc9e5d2),
  Color(0xffe5d2c9),
  Color(0xffc9d6e5),
  Color(0xffe5c9dd),
  Color(0xffdee5c9),
  Color(0xffc9e5e2),
  Color(0xffe5dfc9),
  Color(0xffd2c9e5),
  Color(0xffe5c9c9),
];

RenderScene layoutPieChart(
  PieChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final legendStyle = baseStyle.copyWith(fontSize: theme.fontSize * 0.85);
  final nodes = <SceneNode>[];
  final center = const Point(_radius + 20, _radius + 20);
  final total = chart.slices.fold(0.0, (a, s) => a + s.value);

  // Slices, clockwise from 12 o'clock (upstream d3.pie default).
  var angle = -math.pi / 2;
  for (var i = 0; i < chart.slices.length; i++) {
    final slice = chart.slices[i];
    final sweep = total == 0 ? 0.0 : slice.value / total * 2 * math.pi;
    final color = _palette[i % _palette.length];
    final end = angle + sweep;
    if (sweep > 0) {
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
            fill: Fill(color),
            stroke: Stroke(color: theme.background, width: 2),
          ),
          if (sweep > 0.15)
            () {
              final pct = '${(slice.value / total * 100).round()}%';
              final size = measurer.measure(pct, legendStyle);
              final pos = _polar(center, _radius * 0.62, angle + sweep / 2);
              return SceneText(
                text: pct,
                bounds: Rect.fromCenter(pos, size.width, size.height),
                style: legendStyle,
                color: Color.black,
              );
            }(),
        ],
      ));
    }
    angle = end;
  }

  // Legend, to the right of the pie.
  final legendX = center.x + _radius + 30;
  var legendY = center.y - chart.slices.length * 11.0;
  for (var i = 0; i < chart.slices.length; i++) {
    final slice = chart.slices[i];
    final text = chart.showData
        ? '${slice.label} [${_fmt(slice.value)}]'
        : slice.label;
    final size = measurer.measure(text, legendStyle);
    nodes.add(SceneGroup(id: 'legend_$i', children: [
      SceneShape(
        geometry:
            RectGeometry(Rect.fromLTWH(legendX, legendY, 14, 14)),
        fill: Fill(_palette[i % _palette.length]),
        stroke: Stroke(color: theme.nodeBorder, width: 0.7),
      ),
      SceneText(
        text: text,
        bounds: Rect.fromLTWH(legendX + 20, legendY + 7 - size.height / 2,
            size.width, size.height),
        style: legendStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ),
    ]));
    legendY += 22;
  }

  // Title centered above.
  final title = chart.title;
  var top = 0.0;
  if (title != null && title.isNotEmpty) {
    final style = baseStyle.copyWith(fontWeight: 700);
    final size = measurer.measure(title, style);
    nodes.add(SceneText(
      text: title,
      bounds: Rect.fromLTWH(
          center.x - size.width / 2, -10 - size.height, size.width, size.height),
      style: style,
      color: theme.titleColor,
    ));
    top = -10.0 - size.height;
  }

  var maxRight = center.x + _radius;
  var maxBottom = center.y + _radius;
  for (var i = 0; i < chart.slices.length; i++) {
    final slice = chart.slices[i];
    final text =
        chart.showData ? '${slice.label} [${_fmt(slice.value)}]' : slice.label;
    maxRight = math.max(maxRight,
        legendX + 20 + measurer.measure(text, legendStyle).width);
  }
  maxBottom = math.max(maxBottom, legendY);

  final dx = _diagramPadding - 0;
  final dy = _diagramPadding - top;
  return RenderScene(
    size: Size(maxRight + 2 * _diagramPadding,
        maxBottom - top + 2 * _diagramPadding),
    background: theme.background,
    nodes: [
      for (final n in nodes) translateSceneNode(n, dx, dy),
    ],
  );
}

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

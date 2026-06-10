/// Gantt chart layout: time-scaled bars grouped by section with a date axis,
/// following upstream ganttRenderer.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';
import 'gantt_dates.dart';
import 'gantt_model.dart';

const double _barHeight = 22;
const double _rowGap = 10;
const double _chartWidth = 640;
const double _diagramPadding = 12;

// theme-default gantt colors.
const _taskFill = Color(0xff8a90dd);
const _taskBorder = Color(0xff534fbc);
const _activeFill = Color(0xffbfc7ff);
const _doneFill = Color(0xffd3d3d3);
const _doneBorder = Color(0xff808080);
const _critFill = Color(0xffff8888);
const _critBorder = Color(0xffff0000);
// Soft per-section band tints (upstream alternates section fills).
const _sectionBands = <Color>[
  Color(0x33ececff),
  Color(0x33ffffde),
  Color(0x33d5e5cf),
  Color(0x33e5d0cf),
];
const _gridColor = Color(0xffd3d3d3);

RenderScene layoutGanttChart(
  GanttChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.85);
  final tasks = chart.tasks.toList();
  if (tasks.isEmpty) {
    return RenderScene(
        size: const Size(200, 60),
        background: theme.background,
        nodes: const []);
  }

  var minDate = tasks.first.start;
  var maxDate = tasks.first.end;
  for (final t in tasks) {
    if (t.start.isBefore(minDate)) minDate = t.start;
    if (t.end.isAfter(maxDate)) maxDate = t.end;
  }
  if (!maxDate.isAfter(minDate)) {
    maxDate = minDate.add(const Duration(days: 1));
  }
  final spanMs = maxDate.difference(minDate).inMilliseconds;

  // Left gutter for section names (measured in the bold style they are
  // drawn with, or they soft-wrap).
  final sectionStyle = baseStyle.copyWith(fontWeight: 700);
  var gutter = 10.0;
  for (final s in chart.sections) {
    if (s.name.isEmpty) continue;
    gutter = math.max(
        gutter, measurer.measure(s.name, sectionStyle).width + 16);
  }

  double xOf(DateTime d) =>
      gutter + d.difference(minDate).inMilliseconds / spanMs * _chartWidth;

  final nodes = <SceneNode>[];
  final rowStride = _barHeight + _rowGap;
  final chartTop = 8.0;
  var y = chartTop;

  // Section bands + bars.
  var sectionIndex = 0;
  for (final section in chart.sections) {
    final bandHeight = section.tasks.length * rowStride;
    nodes.add(SceneShape(
      geometry: RectGeometry(
          Rect.fromLTWH(0, y - _rowGap / 2, gutter + _chartWidth + 20,
              bandHeight.toDouble())),
      fill: Fill(_sectionBands[sectionIndex % _sectionBands.length]),
    ));
    if (section.name.isNotEmpty) {
      final size = measurer.measure(section.name, sectionStyle);
      nodes.add(SceneText(
        text: section.name,
        bounds: Rect.fromLTWH(4, y + bandHeight / 2 - _rowGap / 2 - size.height / 2,
            size.width, size.height),
        style: sectionStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ));
    }
    for (final t in section.tasks) {
      final x1 = xOf(t.start);
      final x2 = xOf(t.end);
      var fill = _taskFill;
      var border = _taskBorder;
      if (t.done) {
        fill = _doneFill;
        border = _doneBorder;
      } else if (t.active) {
        fill = _activeFill;
      }
      if (t.crit) {
        fill = t.done ? _doneFill : _critFill;
        border = _critBorder;
      }
      final children = <SceneNode>[];
      if (t.milestone) {
        final cx = x1;
        final cy = y + _barHeight / 2;
        const r = 11.0;
        children.add(SceneShape(
          geometry: PolygonGeometry([
            Point(cx, cy - r),
            Point(cx + r, cy),
            Point(cx, cy + r),
            Point(cx - r, cy),
          ]),
          fill: Fill(fill),
          stroke: Stroke(color: border, width: 1.5),
        ));
      } else {
        children.add(SceneShape(
          geometry: RectGeometry(
              Rect.fromLTWH(x1, y, math.max(x2 - x1, 2), _barHeight),
              rx: 3,
              ry: 3),
          fill: Fill(fill),
          stroke: Stroke(color: border),
        ));
      }
      final size = measurer.measure(t.name, baseStyle);
      final fitsInside = !t.milestone && size.width < (x2 - x1) - 8;
      children.add(SceneText(
        text: t.name,
        bounds: fitsInside
            ? Rect.fromLTWH((x1 + x2) / 2 - size.width / 2,
                y + _barHeight / 2 - size.height / 2, size.width, size.height)
            : Rect.fromLTWH(
                (t.milestone ? x1 + 14 : x2) + 6,
                y + _barHeight / 2 - size.height / 2,
                size.width,
                size.height),
        style: baseStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ));
      nodes.add(SceneGroup(id: t.id, semanticLabel: t.name, children: children));
      y += rowStride;
    }
    sectionIndex++;
  }
  final chartBottom = y;

  // Axis ticks + grid. Every tick draws a grid line; labels thin out when
  // they would collide.
  final ticks = _ticks(minDate, maxDate);
  final fmt = chart.axisFormat ?? _defaultAxisFormat(minDate, maxDate);
  var labelEvery = 1;
  if (ticks.length > 1) {
    final spacing = xOf(ticks[1]) - xOf(ticks[0]);
    final labelW =
        measurer.measure(formatGanttDate(ticks.first, fmt), baseStyle).width;
    labelEvery = math.max(1, ((labelW + 12) / spacing).ceil());
  }
  for (var i = 0; i < ticks.length; i++) {
    final tick = ticks[i];
    final x = xOf(tick);
    nodes.add(SceneShape(
      geometry: PathGeometry(
          [MoveTo(Point(x, chartTop - 10)), LineTo(Point(x, chartBottom + 4))]),
      stroke: const Stroke(color: _gridColor, width: 1),
    ));
    if (i % labelEvery != 0) continue;
    final label = formatGanttDate(tick, fmt);
    final size = measurer.measure(label, baseStyle);
    nodes.add(SceneText(
      text: label,
      bounds: Rect.fromLTWH(
          x - size.width / 2, chartBottom + 6, size.width, size.height),
      style: baseStyle,
      color: theme.textColor,
    ));
  }

  // Title.
  final title = chart.title;
  if (title != null && title.isNotEmpty) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily,
        fontSize: theme.fontSize * 1.2,
        fontWeight: 700);
    final size = measurer.measure(title, style);
    nodes.add(SceneText(
      text: title,
      bounds: Rect.fromLTWH(gutter + _chartWidth / 2 - size.width / 2,
          chartTop - size.height - 14, size.width, size.height),
      style: style,
      color: theme.titleColor,
    ));
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  final dx = _diagramPadding - bounds.left;
  final dy = _diagramPadding - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * _diagramPadding,
        bounds.height + 2 * _diagramPadding),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

/// Ticks at natural boundaries; density tracks mermaid's d3 auto ticks
/// (roughly one tick per 45-90px of chart).
List<DateTime> _ticks(DateTime min, DateTime max) {
  final span = max.difference(min);
  Duration step;
  if (span <= const Duration(hours: 12)) {
    step = const Duration(hours: 1);
  } else if (span <= const Duration(days: 2)) {
    step = const Duration(hours: 6);
  } else if (span <= const Duration(days: 16)) {
    step = const Duration(days: 1);
  } else if (span <= const Duration(days: 40)) {
    step = const Duration(days: 2);
  } else if (span <= const Duration(days: 110)) {
    step = const Duration(days: 7);
  } else if (span <= const Duration(days: 365)) {
    step = const Duration(days: 30);
  } else {
    step = const Duration(days: 90);
  }
  // Align the first tick to a step boundary after min.
  var tick = DateTime(min.year, min.month, min.day);
  if (step.inHours < 24) {
    tick = DateTime(min.year, min.month, min.day, min.hour);
  }
  final out = <DateTime>[];
  while (!tick.isAfter(max)) {
    if (!tick.isBefore(min)) out.add(tick);
    tick = tick.add(step);
  }
  return out;
}

String _defaultAxisFormat(DateTime min, DateTime max) {
  final span = max.difference(min);
  if (span <= const Duration(days: 2)) return '%H:%M';
  // Upstream default axisFormat (config.schema.yaml).
  return '%Y-%m-%d';
}

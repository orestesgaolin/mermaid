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

// Upstream config defaults (config.schema.yaml GanttDiagramConfig).
const double _barHeight = 20;
const double _barGap = 4;
const double _leftPadding = 75;
const double _chartWidth = 1050; // 1200 - leftPadding(75) - rightPadding(75)
const double _diagramPadding = 12;

// theme-default gantt colors.
const _taskFill = Color(0xff8a90dd);
const _taskBorder = Color(0xff534fbc);
const _activeFill = Color(0xffbfc7ff);
const _doneFill = Color(0xffd3d3d3);
const _doneBorder = Color(0xff808080);
// critBkgColor=red(#ff0000), critBorderColor=#ff8888 (theme-default).
const _critFill = Color(0xffff0000);
const _critBorder = Color(0xffff8888);
// Outside / dark task text = taskTextDarkColor = black.
const _taskTextDark = Color(0xff000000);
// Inside task text for normal tasks = taskTextColor = taskTextLightColor = white.
const _taskTextLight = Color(0xffffffff);
// excludeBkgColor (theme-default).
const _excludeBkgColor = Color(0xffeeeeee);
// Section band fills (theme-default), with `.section` opacity 0.2 baked in.
// section0=sectionBkgColor=rgba(102,102,255,0.49)*0.2 -> alpha ~0.098;
// section1/3=altSectionBkgColor=white@0.2; section2=sectionBkgColor2=#fff400@0.2.
const _sectionBands = <Color>[
  Color(0x196666ff),
  Color(0x33ffffff),
  Color(0x33fff400),
  Color(0x33ffffff),
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

  // Bars start at a fixed left padding (upstream leftPadding=75); section
  // names are placed within that gutter.
  final sectionStyle = baseStyle.copyWith(fontWeight: 700);
  const gutter = _leftPadding;

  double xOf(DateTime d) =>
      gutter + d.difference(minDate).inMilliseconds / spanMs * _chartWidth;

  // Plot right edge (upstream `w - rightPadding`), used for label overflow.
  final plotRight = gutter + _chartWidth;

  final nodes = <SceneNode>[];
  final rowStride = _barHeight + _barGap;
  final chartTop = 8.0;
  var y = chartTop;

  // `vert` markers don't occupy rows; collect them and draw full-height bars
  // once the chart bottom is known (upstream vertLabels).
  final vertTasks = <GanttTask>[];

  // Section bands + bars.
  var sectionIndex = 0;
  for (final section in chart.sections) {
    final rowTasks = section.tasks.where((t) => !t.vert).toList();
    // Section band: spans the full width, `y = rowTop - 2`, one stride per row
    // (upstream drawRects band geometry). Vert markers don't occupy rows.
    final bandHeight = rowTasks.length * rowStride;
    nodes.add(SceneShape(
      geometry: RectGeometry(
          Rect.fromLTWH(0, y - 2, gutter + _chartWidth + 20,
              bandHeight.toDouble())),
      fill: Fill(_sectionBands[sectionIndex % _sectionBands.length]),
    ));
    if (section.name.isNotEmpty) {
      final size = measurer.measure(section.name, sectionStyle);
      nodes.add(SceneText(
        text: section.name,
        bounds: Rect.fromLTWH(4, y + bandHeight / 2 - size.height / 2,
            size.width, size.height),
        style: sectionStyle,
        color: theme.titleColor,
        align: TextAlignH.left,
      ));
    }
    for (final t in section.tasks) {
      if (t.vert) {
        vertTasks.add(t);
        continue;
      }
      final x1 = xOf(t.start);
      // Bar is drawn to renderEnd (original duration); excluded days extend
      // `end` for sequencing/axis only, matching upstream's renderEndTime.
      final x2 = xOf(t.renderEnd);
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
        // Upstream `.milestone`: a barHeight square rotated 45° scaled 0.8.
        // Half-diagonal = barHeight * 0.8 / sqrt(2) (~0.566 * barHeight).
        final cx = (x1 + x2) / 2;
        final cy = y + _barHeight / 2;
        final r = _barHeight * 0.8 / math.sqrt2;
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
      // Inside text: normal tasks use taskTextColor (white); active/done/crit
      // use taskTextDarkColor (black). Outside text always taskTextOutsideColor
      // (black).
      final styled = t.active || t.done || t.crit;
      final insideColor = styled ? _taskTextDark : _taskTextLight;
      final Rect labelBounds;
      final TextAlignH labelAlign;
      final Color labelColor;
      if (fitsInside) {
        labelBounds = Rect.fromLTWH((x1 + x2) / 2 - size.width / 2,
            y + _barHeight / 2 - size.height / 2, size.width, size.height);
        labelAlign = TextAlignH.left;
        labelColor = insideColor;
      } else {
        // Place outside-right unless it would overflow the plot, then
        // outside-left (upstream drawRects label placement).
        final rightX = (t.milestone ? x2 : x2) + 6;
        final overflowsRight = rightX + size.width > plotRight;
        if (overflowsRight) {
          labelBounds = Rect.fromLTWH(x1 - 6 - size.width,
              y + _barHeight / 2 - size.height / 2, size.width, size.height);
          labelAlign = TextAlignH.right;
        } else {
          labelBounds = Rect.fromLTWH(rightX,
              y + _barHeight / 2 - size.height / 2, size.width, size.height);
          labelAlign = TextAlignH.left;
        }
        labelColor = _taskTextDark;
      }
      children.add(SceneText(
        text: t.name,
        bounds: labelBounds,
        style: baseStyle,
        color: labelColor,
        align: labelAlign,
      ));
      nodes.add(SceneGroup(id: t.id, semanticLabel: t.name, children: children));
      y += rowStride;
    }
    sectionIndex++;
  }
  final chartBottom = y;

  // `vert` markers: thin full-height vertical bars at the start date with a
  // bottom-anchored label (upstream vertical markers + vertLabels).
  for (final t in vertTasks) {
    final x = xOf(t.start);
    final width = math.max(0.08 * _barHeight, 1.0);
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
    final children = <SceneNode>[
      SceneShape(
        geometry: RectGeometry(
            Rect.fromLTWH(x - width / 2, chartTop, width, chartBottom - chartTop)),
        fill: Fill(fill),
        stroke: Stroke(color: border),
      ),
    ];
    if (t.name.isNotEmpty) {
      final size = measurer.measure(t.name, baseStyle);
      children.add(SceneText(
        text: t.name,
        bounds: Rect.fromLTWH(
            x - size.width / 2, chartBottom + 2, size.width, size.height),
        style: baseStyle,
        color: _taskTextDark,
        align: TextAlignH.center,
      ));
    }
    nodes.add(SceneGroup(id: t.id, semanticLabel: t.name, children: children));
  }

  // Excluded-day shading (weekends / specific dates), behind the translucent
  // section bands. The today marker is a vertical line at the current date.
  final overlays = <SceneNode>[];
  if (chart.excludeWeekdays.isNotEmpty || chart.excludeDates.isNotEmpty) {
    // Coalesce contiguous excluded days into a single range rect filled with
    // excludeBkgColor (upstream drawExcludeDays).
    var day = DateTime(minDate.year, minDate.month, minDate.day);
    DateTime? rangeStart;
    void flush(DateTime endExclusive) {
      if (rangeStart == null) return;
      final x1 = xOf(rangeStart!);
      final x2 = xOf(endExclusive);
      overlays.add(SceneShape(
        geometry: RectGeometry(
            Rect.fromLTWH(x1, chartTop - 2, x2 - x1, chartBottom - chartTop)),
        fill: const Fill(_excludeBkgColor),
      ));
      rangeStart = null;
    }

    while (!day.isAfter(maxDate)) {
      final excluded = chart.excludeWeekdays.contains(day.weekday) ||
          chart.excludeDates.contains(day);
      if (excluded) {
        rangeStart ??= day;
      } else {
        flush(day);
      }
      day = day.add(const Duration(days: 1));
    }
    flush(day);
  }
  if (overlays.isNotEmpty) nodes.insertAll(0, overlays);
  if (!chart.todayMarkerOff) {
    final now = DateTime.now();
    if (!now.isBefore(minDate) && !now.isAfter(maxDate)) {
      final x = xOf(now);
      nodes.add(SceneShape(
        geometry: PathGeometry(
            [MoveTo(Point(x, chartTop - 2)), LineTo(Point(x, chartBottom))]),
        // todayLineColor = red (theme-default).
        stroke: const Stroke(color: Color(0xffff0000), width: 2),
      ));
    }
  }

  // Axis ticks + grid. Every tick draws a grid line; labels thin out when
  // they would collide.
  final ticks = _ticks(minDate, maxDate);
  final fmt = chart.axisFormat ??
      _defaultAxisFormat(minDate, maxDate, chart.dateFormat);
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

  // Title: fixed font-size 18, centered on the full chart width (upstream
  // titleText at (w/2, titleTopMargin)).
  final title = chart.title;
  if (title != null && title.isNotEmpty) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily, fontSize: 18, fontWeight: 700);
    final size = measurer.measure(title, style);
    // Full chart width includes the right padding (mirrors leftPadding).
    final fullWidth = gutter + _chartWidth + _leftPadding;
    nodes.add(SceneText(
      text: title,
      bounds: Rect.fromLTWH(fullWidth / 2 - size.width / 2,
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

String _defaultAxisFormat(DateTime min, DateTime max, String? dateFormat) {
  // Upstream makeGrid uses %d when dateFormat === 'D'.
  if (dateFormat == 'D') return '%d';
  final span = max.difference(min);
  if (span <= const Duration(days: 2)) return '%H:%M';
  // Upstream default axisFormat (config.schema.yaml).
  return '%Y-%m-%d';
}

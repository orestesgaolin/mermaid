/// XY chart (xychart-beta): model, parser and layout — one file.
///
/// Reference: upstream xychart jison grammar + xychartBuilder.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

class XyChart {
  const XyChart({
    this.title,
    this.xAxisTitle,
    this.yAxisTitle,
    this.categories = const [],
    this.xRange,
    this.yRange,
    this.series = const [],
    this.horizontal = false,
    this.showDataLabel = false,
    this.showDataLabelOutsideBar = false,
  });

  final String? title;
  final String? xAxisTitle;
  final String? yAxisTitle;

  /// Categorical x-axis labels; empty when [xRange] is used.
  final List<String> categories;
  final (double, double)? xRange;
  final (double, double)? yRange;
  final List<XySeries> series;
  final bool horizontal;

  /// Render each bar's value as text in/over the bar (`XYChartConfig`).
  final bool showDataLabel;

  /// When [showDataLabel], place the label outside (above/right of) the bar.
  final bool showDataLabelOutsideBar;
}

enum XySeriesKind { bar, line }

class XySeries {
  const XySeries({
    required this.kind,
    required this.values,
    this.label,
    this.pointLabels,
  });

  final XySeriesKind kind;
  final List<double> values;
  final String? label;

  /// Optional per-point quoted labels (line plots only); same length as
  /// [values]. Null when no point carried a label.
  final List<String>? pointLabels;
}

XyChart parseXyChart(String source) {
  final frontTitle = frontmatterTitle(source);
  final text = stripMetadata(source);
  String? title = frontTitle;
  String? xTitle, yTitle;
  var categories = <String>[];
  (double, double)? xRange, yRange;
  final series = <XySeries>[];
  var horizontal = false;
  var seenHeader = false;

  // Read `xyChart.showDataLabel(/OutsideBar)` from YAML frontmatter config,
  // mirroring upstream `XYChartConfig` (set via `%%{init}%%`/frontmatter, not
  // the diagram grammar).
  var showDataLabel = false;
  var showDataLabelOutsideBar = false;
  final fm = RegExp(r'^\s*---[ \t]*\n([\s\S]*?)\n[ \t]*---[ \t]*\n')
      .firstMatch(source.replaceAll('\r\n', '\n'));
  if (fm != null) {
    final block = fm.group(1)!;
    bool flag(String key) =>
        RegExp('$key:\\s*true', caseSensitive: false).hasMatch(block);
    showDataLabel = flag('showDataLabel');
    showDataLabelOutsideBar = flag('showDataLabelOutsideBar');
  }

  String unquote(String s) {
    final t = s.trim();
    return t.length >= 2 && t.startsWith('"') && t.endsWith('"')
        ? t.substring(1, t.length - 1)
        : t;
  }

  // Parse a `[ datum, datum, ... ]` list where each datum is
  // `NUMBER ["label"]` (upstream `plotData`/`dataPoint`). Returns the numeric
  // values plus optional per-point labels (null when no point had a label).
  (List<double>, List<String>?) dataPoints(String list, int line) {
    final values = <double>[];
    final labels = <String>[];
    var hasLabel = false;
    for (final raw in list.split(',')) {
      final p = raw.trim();
      if (p.isEmpty) continue;
      final lm = RegExp(r'"([^"]*)"').firstMatch(p);
      if (lm != null) {
        labels.add(lm.group(1)!);
        hasLabel = true;
      } else {
        labels.add('');
      }
      final numText = p.replaceAll(RegExp(r'"[^"]*"'), '').trim();
      values.add(double.tryParse(numText) ??
          (throw MermaidParseException('invalid number "$p"', line: line)));
    }
    return (values, hasLabel ? labels : null);
  }

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      final m = RegExp(r'^xychart(-beta)?(\s+horizontal)?\s*$').firstMatch(line);
      if (m == null) {
        throw MermaidParseException('expected "xychart-beta" header',
            line: i + 1);
      }
      horizontal = m.group(2) != null;
      seenHeader = true;
      continue;
    }
    Match? m;
    m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      title = unquote(m.group(1)!);
      continue;
    }
    // x-axis ["title"] [cat, cat, ...]  |  x-axis ["title"] a --> b
    m = RegExp(r'^x-axis\s+(?:("([^"]*)"|[^\[\d][^\[]*?)\s+)?\[(.*)\]\s*$')
        .firstMatch(line);
    if (m != null) {
      if (m.group(1) != null) xTitle = unquote(m.group(1)!);
      categories =
          m.group(3)!.split(',').map((c) => unquote(c)).toList();
      continue;
    }
    m = RegExp(
            r'^x-axis\s+(?:("([^"]*)"|\S+)\s+)?([\d.+-]+)\s*-->\s*([\d.+-]+)\s*$')
        .firstMatch(line);
    if (m != null) {
      if (m.group(1) != null) xTitle = unquote(m.group(1)!);
      xRange = (double.parse(m.group(3)!), double.parse(m.group(4)!));
      continue;
    }
    m = RegExp(
            r'^y-axis\s+(?:("([^"]*)"|\S+(?:\s+\S+)*?)\s+)?([\d.+-]+)\s*-->\s*([\d.+-]+)\s*$')
        .firstMatch(line);
    if (m != null) {
      if (m.group(1) != null) yTitle = unquote(m.group(1)!);
      yRange = (double.parse(m.group(3)!), double.parse(m.group(4)!));
      continue;
    }
    m = RegExp(r'^y-axis\s+(.+)$').firstMatch(line);
    if (m != null) {
      yTitle = unquote(m.group(1)!);
      continue;
    }
    m = RegExp(r'^(bar|line)\s+(?:("([^"]*)")\s+)?\[(.*)\]\s*$')
        .firstMatch(line);
    if (m != null) {
      final kind = m.group(1) == 'bar' ? XySeriesKind.bar : XySeriesKind.line;
      final (values, pointLabels) = dataPoints(m.group(4)!, i + 1);
      series.add(XySeries(
        kind: kind,
        label: m.group(3),
        values: values,
        // Per-point labels are a line-plot feature upstream (`linePlot.ts`).
        pointLabels: kind == XySeriesKind.line ? pointLabels : null,
      ));
      continue;
    }
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(line)) continue;
    throw MermaidParseException('unrecognized statement "$line"', line: i + 1);
  }
  if (!seenHeader) {
    throw const MermaidParseException('empty xychart source');
  }
  return XyChart(
    title: title,
    xAxisTitle: xTitle,
    yAxisTitle: yTitle,
    categories: categories,
    xRange: xRange,
    yRange: yRange,
    series: series,
    horizontal: horizontal,
    showDataLabel: showDataLabel,
    showDataLabelOutsideBar: showDataLabelOutsideBar,
  );
}

/// Plot color, indexed by plot declaration order, from the theme's
/// `xyChartPlotColorPalette` (default-theme values match upstream
/// theme-default.js `plotColorPalette`; dark/forest/neutral adapt).
Color _plotColor(List<Color> palette, int plotIndex) =>
    palette[plotIndex == 0 ? 0 : plotIndex % palette.length];

// --- XYChartConfig defaults (config.schema.yaml) ---
const _canvasW = 700.0;
const _canvasH = 500.0;
const _plotReservedSpacePercent = 50.0;
const _chartTitleFontSize = 20.0;
const _chartTitlePadding = 10.0;
// XYChartAxisConfig defaults.
const _labelFontSize = 14.0;
const _labelPadding = 5.0;
const _titleFontSize = 16.0;
const _titlePadding = 5.0;
const _tickLength = 5.0;
const _tickWidth = 2.0;
const _axisLineWidth = 2.0;
const _maxOuterPaddingPercentForLabel = 0.2;
const _barWidthToTickWidthRatio = 0.7;

/// d3 `scaleLinear().ticks()` (`d3-array` ticks): ~`count` nice round values
/// spanning [start, stop].
List<double> _d3Ticks(double start, double stop, int count) {
  if (start == stop) return [start];
  final step = _tickIncrement(start, stop, count);
  if (step == 0 || !step.isFinite) return [];
  final List<double> ticks;
  if (step > 0) {
    var lo = (start / step).ceil();
    var hi = (stop / step).floor();
    if ((lo * step) < start) lo++;
    if ((hi * step) > stop) hi--;
    final n = (hi - lo + 1);
    if (n <= 0) return [];
    ticks = [for (var i = 0; i < n; i++) (lo + i) * step];
  } else {
    final invStep = -step;
    var lo = (start * invStep).floor();
    var hi = (stop * invStep).ceil();
    if ((lo / invStep) < start) lo++;
    if ((hi / invStep) > stop) hi--;
    final n = (hi - lo + 1);
    if (n <= 0) return [];
    ticks = [for (var i = 0; i < n; i++) (lo + i) / invStep];
  }
  return ticks;
}

/// d3 `tickIncrement`: the nice step (positive) or inverse step (negative).
double _tickIncrement(double start, double stop, int count) {
  const e10 = 7.0710678118654755; // sqrt(50)
  const e5 = 3.1622776601683795; // sqrt(10)
  const e2 = 1.4142135623730951; // sqrt(2)
  final step = (stop - start) / math.max(0, count);
  final power = (math.log(step) / math.ln10).floor();
  final error = step / math.pow(10, power);
  final factor = error >= e10
      ? 10
      : error >= e5
          ? 5
          : error >= e2
              ? 2
              : 1;
  if (power >= 0) {
    return (factor * math.pow(10, power)).toDouble();
  }
  return -(math.pow(10, -power) / factor).toDouble();
}

/// d3 number formatting for tick labels: integers print without a decimal.
String _formatTick(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return '${v.round()}';
  // Trim trailing zeros from a fixed representation.
  var s = v.toStringAsFixed(6);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

/// One chart axis: either a `band` (categorical) or `linear` (value) scale,
/// modelled on upstream `BaseAxis`/`BandAxis`/`LinearAxis`.
class _Axis {
  _Axis.band(this.categories, this.title)
      : isBand = true,
        domainMin = 0,
        domainMax = 0;
  _Axis.linear(this.domainMin, this.domainMax, this.title)
      : isBand = false,
        categories = const [];

  final bool isBand;
  final List<String> categories;
  final double domainMin;
  final double domainMax;
  final String title;

  // Layout state, mirroring BaseAxis.
  double rangeStart = 0;
  double rangeEnd = 10;
  // 'left' | 'bottom' | 'top'
  String position = 'left';
  double outerPadding = 0;
  bool showAxisLine = false;
  bool showLabel = false;
  bool showTick = false;
  bool showTitle = false;
  double titleTextHeight = 0;

  List<String> tickLabels() =>
      isBand ? categories : [for (final t in _ticks()) _formatTick(t)];

  List<double> _ticks() => _d3Ticks(domainMin, domainMax, 10);

  int get tickCount => isBand ? categories.length : _ticks().length;

  // getRange(): inner range after subtracting outer padding.
  double get innerStart => rangeStart + outerPadding;
  double get innerEnd => rangeEnd - outerPadding;

  double get tickDistance =>
      (innerStart - innerEnd).abs() / math.max(1, tickCount);

  /// Pixel position for a category index (band) — `scaleBand` with
  /// paddingInner=1, paddingOuter=0, align=0.5 ⇒ evenly spaced, bandwidth 0.
  double bandScale(int i) {
    final n = categories.length;
    if (n == 0) return innerStart;
    final step = (innerEnd - innerStart) / math.max(1, n - 1);
    return innerStart + step * i;
  }

  /// Pixel position for a value (linear). Left axis reverses the domain so the
  /// value grows upward.
  double linearScale(double v) {
    final reverse = position == 'left';
    final d0 = reverse ? domainMax : domainMin;
    final d1 = reverse ? domainMin : domainMax;
    if (d1 == d0) return innerStart;
    final t = (v - d0) / (d1 - d0);
    return innerStart + t * (innerEnd - innerStart);
  }

  bool get vertical => position == 'left' || position == 'right';

  /// Reserve space for this axis given an available box, returning the space
  /// consumed. `boundingW`/`boundingH` capture the axis band thickness.
  double boundingW = 0;
  double boundingH = 0;
  double boundingX = 0;
  double boundingY = 0;

  Size calculateSpace(Size avail, TextMeasurer measurer, String fontFamily) {
    if (vertical) {
      _calcVertical(avail, measurer, fontFamily);
    } else {
      _calcHorizontal(avail, measurer, fontFamily);
    }
    return Size(boundingW, boundingH);
  }

  Size _maxDim(List<String> texts, double fontSize, TextMeasurer m, String ff) {
    var w = 0.0, h = 0.0;
    final style = TextStyleSpec(fontFamily: ff, fontSize: fontSize);
    for (final t in texts) {
      final s = m.measure(t, style);
      w = math.max(w, s.width);
      h = math.max(h, s.height);
    }
    return Size(w, h);
  }

  void _calcHorizontal(Size avail, TextMeasurer m, String ff) {
    var availableHeight = avail.height;
    if (availableHeight > _axisLineWidth) {
      availableHeight -= _axisLineWidth;
      showAxisLine = true;
    }
    final labelDim = _maxDim(tickLabels(), _labelFontSize, m, ff);
    final maxPadding = _maxOuterPaddingPercentForLabel * avail.width;
    outerPadding = math.min(labelDim.width / 2, maxPadding);
    final heightRequired = labelDim.height + _labelPadding * 2;
    if (heightRequired <= availableHeight) {
      availableHeight -= heightRequired;
      showLabel = true;
    }
    if (availableHeight >= _tickLength) {
      showTick = true;
      availableHeight -= _tickLength;
    }
    if (title.isNotEmpty) {
      final td = _maxDim([title], _titleFontSize, m, ff);
      final req = td.height + _titlePadding * 2;
      titleTextHeight = td.height;
      if (req <= availableHeight) {
        availableHeight -= req;
        showTitle = true;
      }
    }
    boundingW = avail.width;
    boundingH = avail.height - availableHeight;
  }

  void _calcVertical(Size avail, TextMeasurer m, String ff) {
    var availableWidth = avail.width;
    if (availableWidth > _axisLineWidth) {
      availableWidth -= _axisLineWidth;
      showAxisLine = true;
    }
    final labelDim = _maxDim(tickLabels(), _labelFontSize, m, ff);
    final maxPadding = _maxOuterPaddingPercentForLabel * avail.height;
    outerPadding = math.min(labelDim.height / 2, maxPadding);
    final widthRequired = labelDim.width + _labelPadding * 2;
    if (widthRequired <= availableWidth) {
      availableWidth -= widthRequired;
      showLabel = true;
    }
    if (availableWidth >= _tickLength) {
      showTick = true;
      availableWidth -= _tickLength;
    }
    if (title.isNotEmpty) {
      final td = _maxDim([title], _titleFontSize, m, ff);
      final req = td.height + _titlePadding * 2;
      titleTextHeight = td.height;
      if (req <= availableWidth) {
        availableWidth -= req;
        showTitle = true;
      }
    }
    boundingW = avail.width - availableWidth;
    boundingH = avail.height;
  }

  void recalculateOuterPaddingToDrawBar() {
    if (_barWidthToTickWidthRatio * tickDistance > outerPadding * 2) {
      outerPadding = (_barWidthToTickWidthRatio * tickDistance / 2).floorToDouble();
    }
  }
}

RenderScene layoutXyChart(
  XyChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final ff = theme.fontFamily;
  // Upstream sources all axis/title/label/data-label colors from
  // `primaryTextColor` and the background from `background` (#f4f4f4 default).
  final textColor = theme.primaryTextColor;
  final nodes = <SceneNode>[];

  final horizontal = chart.horizontal;

  final pointCount = chart.categories.isNotEmpty
      ? chart.categories.length
      : chart.series.fold(0, (a, s) => math.max(a, s.values.length));
  if (pointCount == 0 || chart.series.isEmpty) {
    return RenderScene(
      size: const Size(_canvasW, _canvasH),
      background: theme.background,
      nodes: const [],
    );
  }

  // Value range across all series (or explicit yRange) — no forced-zero
  // baseline (`setYAxisRangeFromPlotData`).
  var minV = chart.yRange?.$1 ?? double.infinity;
  var maxV = chart.yRange?.$2 ?? double.negativeInfinity;
  if (chart.yRange == null) {
    for (final s in chart.series) {
      for (var i = 0; i < s.values.length && i < pointCount; i++) {
        minV = math.min(minV, s.values[i]);
        maxV = math.max(maxV, s.values[i]);
      }
    }
    if (!minV.isFinite) {
      minV = 0;
      maxV = 1;
    }
  }
  if (maxV < minV) {
    final t = minV;
    minV = maxV;
    maxV = t;
  }

  // Category labels: categories, or numeric x-range endpoints.
  final catLabels = chart.categories.isNotEmpty
      ? chart.categories
      : [
          for (var i = 0; i < pointCount; i++)
            _formatTick((chart.xRange?.$1 ?? 1) +
                i *
                    ((chart.xRange == null || pointCount <= 1)
                        ? 1
                        : (chart.xRange!.$2 - chart.xRange!.$1) /
                            (pointCount - 1))),
        ];

  // Build the two axes. Vertical (default): x = band, y = linear. Horizontal
  // swaps which axis is band vs linear, but the band axis is always 'xAxis'.
  final xAxis = chart.categories.isNotEmpty || chart.xRange == null
      ? _Axis.band(catLabels, chart.xAxisTitle ?? '')
      : _Axis.linear(chart.xRange!.$1, chart.xRange!.$2, chart.xAxisTitle ?? '');
  final yAxis = _Axis.linear(minV, maxV, chart.yAxisTitle ?? '');

  final hasBar = chart.series.any((s) => s.kind == XySeriesKind.bar);

  // --- Orchestrator space reservation. ---
  var availW = _canvasW;
  var availH = _canvasH;
  var plotX = 0.0;
  var plotY = 0.0;
  var titleYEnd = 0.0;
  var chartW = (_canvasW * _plotReservedSpacePercent / 100).floorToDouble();
  var chartH = (_canvasH * _plotReservedSpacePercent / 100).floorToDouble();
  // plot.calculateSpace reserves chartW/chartH.
  availW -= chartW;
  availH -= chartH;

  // Title space.
  var titleH = 0.0;
  final hasTitle = chart.title != null && chart.title!.isNotEmpty;
  if (hasTitle) {
    final td = measurer.measure(chart.title!,
        TextStyleSpec(fontFamily: ff, fontSize: _chartTitleFontSize));
    titleH = td.height + 2 * _chartTitlePadding;
  }

  if (!horizontal) {
    plotY = titleH;
    availH -= titleH;
    xAxis.position = 'bottom';
    final xs = xAxis.calculateSpace(Size(availW, availH), measurer, ff);
    availH -= xs.height;
    yAxis.position = 'left';
    final ys = yAxis.calculateSpace(Size(availW, availH), measurer, ff);
    plotX = ys.width;
    availW -= ys.width;
    if (availW > 0) {
      chartW += availW;
      availW = 0;
    }
    if (availH > 0) {
      chartH += availH;
      availH = 0;
    }
    xAxis.rangeStart = plotX;
    xAxis.rangeEnd = plotX + chartW;
    xAxis.boundingX = plotX;
    xAxis.boundingY = plotY + chartH;
    yAxis.rangeStart = plotY;
    yAxis.rangeEnd = plotY + chartH;
    yAxis.boundingX = 0;
    yAxis.boundingY = plotY;
  } else {
    titleYEnd = titleH;
    availH -= titleH;
    // In horizontal mode the band (x) axis sits on the left, value (y) on top.
    xAxis.position = 'left';
    final xs = xAxis.calculateSpace(Size(availW, availH), measurer, ff);
    availW -= xs.width;
    plotX = xs.width;
    yAxis.position = 'top';
    final ys = yAxis.calculateSpace(Size(availW, availH), measurer, ff);
    availH -= ys.height;
    plotY = titleYEnd + ys.height;
    if (availW > 0) {
      chartW += availW;
      availW = 0;
    }
    if (availH > 0) {
      chartH += availH;
      availH = 0;
    }
    yAxis.rangeStart = plotX;
    yAxis.rangeEnd = plotX + chartW;
    yAxis.boundingX = plotX;
    yAxis.boundingY = titleYEnd;
    xAxis.rangeStart = plotY;
    xAxis.rangeEnd = plotY + chartH;
    xAxis.boundingX = 0;
    xAxis.boundingY = plotY;
  }

  final plot = Rect.fromLTWH(plotX, plotY, chartW, chartH);

  if (hasBar) xAxis.recalculateOuterPaddingToDrawBar();

  // --- Plot scale helpers. ---
  // In vertical mode x=band, y=linear. In horizontal mode x(band)=vertical,
  // y(linear)=horizontal. When an explicit x-range is given the x-axis is
  // linear, so point i maps to its evenly-stepped x value.
  double catScale(int i) {
    if (xAxis.isBand) return xAxis.bandScale(i);
    final step = pointCount <= 1
        ? 0.0
        : (xAxis.domainMax - xAxis.domainMin) / (pointCount - 1);
    return xAxis.linearScale(xAxis.domainMin + i * step);
  }

  double valScale(double v) => yAxis.linearScale(v);

  // --- Plots (drawn in declaration order; bars then their labels). ---
  for (var pi = 0; pi < chart.series.length; pi++) {
    final s = chart.series[pi];
    final color = _plotColor(theme.xyChartPlotColorPalette, pi);
    if (s.kind == XySeriesKind.bar) {
      final barWidth =
          math.min(xAxis.outerPadding * 2, xAxis.tickDistance) * 0.95;
      final half = barWidth / 2;
      for (var i = 0; i < s.values.length && i < pointCount; i++) {
        final cp = catScale(i);
        final vp = valScale(s.values[i]);
        final Rect rect;
        if (horizontal) {
          // value runs along x from plot.left; category along y.
          rect = Rect.fromLTWH(plot.left, cp - half, vp - plot.left, barWidth);
        } else {
          // value runs along y; bar from value down to plot bottom.
          rect = Rect.fromLTWH(
              cp - half, vp, barWidth, plot.bottom - vp);
        }
        nodes.add(SceneShape(geometry: RectGeometry(rect), fill: Fill(color)));
      }
      if (chart.showDataLabel) {
        _addDataLabels(nodes, s, pointCount, catScale, valScale, plot,
            horizontal, barWidth, chart.showDataLabelOutsideBar, textColor, ff);
      }
    } else {
      final pts = [
        for (var i = 0; i < s.values.length && i < pointCount; i++)
          horizontal
              ? Point(valScale(s.values[i]), catScale(i))
              : Point(catScale(i), valScale(s.values[i])),
      ];
      if (pts.length >= 2) {
        nodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(pts.first),
            for (final p in pts.skip(1)) LineTo(p),
          ]),
          stroke: Stroke(color: color, width: 2),
        ));
      }
      // Per-point labels (`linePlot.ts` pointLabels), offset 10, fontSize 12.
      final labels = s.pointLabels;
      if (labels != null) {
        const labelOffset = 10.0;
        final style = TextStyleSpec(fontFamily: ff, fontSize: 12);
        for (var i = 0; i < pts.length && i < labels.length; i++) {
          final label = labels[i];
          if (label.isEmpty) continue;
          final size = measurer.measure(label, style);
          final Rect b;
          if (horizontal) {
            b = Rect.fromLTWH(pts[i].x + labelOffset,
                pts[i].y - size.height / 2, size.width, size.height);
          } else {
            b = Rect.fromLTWH(pts[i].x - size.width / 2,
                pts[i].y - labelOffset - size.height / 2, size.width,
                size.height);
          }
          nodes.add(SceneText(
            text: label,
            bounds: b,
            style: style,
            color: color,
            align: horizontal ? TextAlignH.left : TextAlignH.center,
          ));
        }
      }
    }
  }

  // --- Axis drawing (baseAxis.ts). ---
  _drawAxis(nodes, xAxis, measurer, ff, textColor);
  _drawAxis(nodes, yAxis, measurer, ff, textColor);

  // --- Chart title. ---
  if (hasTitle) {
    final style = TextStyleSpec(
        fontFamily: ff, fontSize: _chartTitleFontSize, fontWeight: 700);
    final size = measurer.measure(chart.title!, style);
    nodes.add(SceneText(
      text: chart.title!,
      bounds: Rect.fromLTWH(_canvasW / 2 - size.width / 2,
          titleH / 2 - size.height / 2, size.width, size.height),
      style: style,
      color: theme.titleColor,
    ));
  }

  // Upstream draws an explicit background rect filling the 700x500 canvas
  // (`xychartRenderer.ts`); our IR carries that fill on `RenderScene.background`,
  // which backends paint behind the scene — so no separate rect node is needed.
  return RenderScene(
    size: const Size(_canvasW, _canvasH),
    background: theme.background,
    nodes: nodes,
  );
}

/// Draw an axis line, ticks, labels and title for [axis] (`baseAxis.ts`).
void _drawAxis(List<SceneNode> nodes, _Axis axis, TextMeasurer measurer,
    String ff, Color color) {
  final labelStyle = TextStyleSpec(fontFamily: ff, fontSize: _labelFontSize);
  final titleStyle = TextStyleSpec(fontFamily: ff, fontSize: _titleFontSize);

  double scaleAt(int i) =>
      axis.isBand ? axis.bandScale(i) : axis.linearScale(axis._ticks()[i]);
  final tickTexts = axis.tickLabels();
  final tickN = tickTexts.length;

  if (axis.position == 'left') {
    // Vertical value/band axis on the left of the plot.
    if (axis.showAxisLine) {
      final x = axis.boundingX + axis.boundingW - _axisLineWidth / 2;
      // Span the plot extent (the scale range, which the ticks use), not the
      // axis band thickness — `boundingH` is the pre-reservation available
      // height, not the final plot height.
      nodes.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(x, axis.rangeStart)),
          LineTo(Point(x, axis.rangeEnd)),
        ]),
        stroke: Stroke(color: color, width: _axisLineWidth),
      ));
    }
    if (axis.showLabel) {
      final lx = axis.boundingX +
          axis.boundingW -
          (axis.showLabel ? _labelPadding : 0) -
          (axis.showTick ? _tickLength : 0) -
          (axis.showAxisLine ? _axisLineWidth : 0);
      for (var i = 0; i < tickN; i++) {
        final t = tickTexts[i];
        final size = measurer.measure(t, labelStyle);
        final y = scaleAt(i);
        nodes.add(SceneText(
          text: t,
          bounds: Rect.fromLTWH(
              lx - size.width, y - size.height / 2, size.width, size.height),
          style: labelStyle,
          color: color,
          align: TextAlignH.right,
        ));
      }
    }
    if (axis.showTick) {
      final x =
          axis.boundingX + axis.boundingW - (axis.showAxisLine ? _axisLineWidth : 0);
      for (var i = 0; i < tickN; i++) {
        final y = scaleAt(i);
        nodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(x, y)),
            LineTo(Point(x - _tickLength, y)),
          ]),
          stroke: Stroke(color: color, width: _tickWidth),
        ));
      }
    }
    if (axis.showTitle && axis.title.isNotEmpty) {
      final size = measurer.measure(axis.title, titleStyle);
      nodes.add(SceneText(
        text: axis.title,
        bounds: Rect.fromCenter(
            Point(axis.boundingX + _titlePadding + size.height / 2,
                axis.boundingY + axis.boundingH / 2),
            size.width,
            size.height),
        style: titleStyle,
        color: color,
        rotation: 270,
      ));
    }
  } else if (axis.position == 'bottom') {
    if (axis.showAxisLine) {
      final y = axis.boundingY + _axisLineWidth / 2;
      nodes.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(axis.rangeStart, y)),
          LineTo(Point(axis.rangeEnd, y)),
        ]),
        stroke: Stroke(color: color, width: _axisLineWidth),
      ));
    }
    if (axis.showLabel) {
      final y = axis.boundingY +
          _labelPadding +
          (axis.showTick ? _tickLength : 0) +
          (axis.showAxisLine ? _axisLineWidth : 0);
      for (var i = 0; i < tickN; i++) {
        final t = tickTexts[i];
        final size = measurer.measure(t, labelStyle);
        final x = scaleAt(i);
        nodes.add(SceneText(
          text: t,
          bounds: Rect.fromLTWH(x - size.width / 2, y, size.width, size.height),
          style: labelStyle,
          color: color,
          align: TextAlignH.center,
        ));
      }
    }
    if (axis.showTick) {
      final y = axis.boundingY + (axis.showAxisLine ? _axisLineWidth : 0);
      for (var i = 0; i < tickN; i++) {
        final x = scaleAt(i);
        nodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(x, y)),
            LineTo(Point(x, y + _tickLength)),
          ]),
          stroke: Stroke(color: color, width: _tickWidth),
        ));
      }
    }
    if (axis.showTitle && axis.title.isNotEmpty) {
      final size = measurer.measure(axis.title, titleStyle);
      final cx = axis.rangeStart + (axis.rangeEnd - axis.rangeStart) / 2;
      final ty = axis.boundingY +
          axis.boundingH -
          _titlePadding -
          axis.titleTextHeight;
      nodes.add(SceneText(
        text: axis.title,
        bounds: Rect.fromLTWH(cx - size.width / 2, ty, size.width, size.height),
        style: titleStyle,
        color: color,
        align: TextAlignH.center,
      ));
    }
  } else if (axis.position == 'top') {
    if (axis.showAxisLine) {
      final y = axis.boundingY + axis.boundingH - _axisLineWidth / 2;
      nodes.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(axis.rangeStart, y)),
          LineTo(Point(axis.rangeEnd, y)),
        ]),
        stroke: Stroke(color: color, width: _axisLineWidth),
      ));
    }
    if (axis.showLabel) {
      final y = axis.boundingY +
          (axis.showTitle ? axis.titleTextHeight + _titlePadding * 2 : 0) +
          _labelPadding;
      for (var i = 0; i < tickN; i++) {
        final t = tickTexts[i];
        final size = measurer.measure(t, labelStyle);
        final x = scaleAt(i);
        nodes.add(SceneText(
          text: t,
          bounds: Rect.fromLTWH(x - size.width / 2, y, size.width, size.height),
          style: labelStyle,
          color: color,
          align: TextAlignH.center,
        ));
      }
    }
    if (axis.showTick) {
      for (var i = 0; i < tickN; i++) {
        final x = scaleAt(i);
        final y1 = axis.boundingY +
            axis.boundingH -
            (axis.showAxisLine ? _axisLineWidth : 0);
        final y2 = axis.boundingY +
            axis.boundingH -
            _tickLength -
            (axis.showAxisLine ? _axisLineWidth : 0);
        nodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(x, y1)),
            LineTo(Point(x, y2)),
          ]),
          stroke: Stroke(color: color, width: _tickWidth),
        ));
      }
    }
    if (axis.showTitle && axis.title.isNotEmpty) {
      final size = measurer.measure(axis.title, titleStyle);
      nodes.add(SceneText(
        text: axis.title,
        bounds: Rect.fromLTWH(axis.boundingX + axis.boundingW / 2 - size.width / 2,
            axis.boundingY + _titlePadding, size.width, size.height),
        style: titleStyle,
        color: color,
        align: TextAlignH.center,
      ));
    }
  }
}

/// Emit value labels in/over bars with adaptive font sizing
/// (`xychartRenderer.ts`).
void _addDataLabels(
  List<SceneNode> nodes,
  XySeries s,
  int pointCount,
  double Function(int) catScale,
  double Function(double) valScale,
  Rect plot,
  bool horizontal,
  double barWidth,
  bool outside,
  Color color,
  String ff,
) {
  const charWidthFactor = 0.7;
  // Collect valid bars (non-zero width & height).
  final items = <(Rect, String)>[];
  final half = barWidth / 2;
  for (var i = 0; i < s.values.length && i < pointCount; i++) {
    final cp = catScale(i);
    final vp = valScale(s.values[i]);
    final Rect rect;
    if (horizontal) {
      rect = Rect.fromLTWH(plot.left, cp - half, vp - plot.left, barWidth);
    } else {
      rect = Rect.fromLTWH(cp - half, vp, barWidth, plot.bottom - vp);
    }
    if (rect.width > 0 && rect.height > 0) {
      final label = s.values[i] == s.values[i].roundToDouble()
          ? '${s.values[i].round()}'
          : '${s.values[i]}';
      items.add((rect, label));
    }
  }
  if (items.isEmpty) return;

  double uniformFontSize;
  if (horizontal) {
    const rightMargin = 10.0;
    final sizes = items.map((it) {
      var fs = it.$1.height * 0.7;
      while (fs > 0 &&
          fs * it.$2.length * charWidthFactor > it.$1.width - rightMargin) {
        fs -= 1;
      }
      return fs;
    });
    uniformFontSize = sizes.reduce(math.min).floorToDouble();
    if (uniformFontSize <= 0) return;
    final style = TextStyleSpec(fontFamily: ff, fontSize: uniformFontSize);
    for (final it in items) {
      final r = it.$1;
      final tw = uniformFontSize * it.$2.length * charWidthFactor;
      final x = outside ? r.right + rightMargin : r.right - rightMargin - tw;
      nodes.add(SceneText(
        text: it.$2,
        bounds: Rect.fromLTWH(
            x, r.top + r.height / 2 - uniformFontSize / 2, tw, uniformFontSize),
        style: style,
        color: color,
        align: outside ? TextAlignH.left : TextAlignH.right,
      ));
    }
  } else {
    const yOffset = 10.0;
    final sizes = items.map((it) {
      final r = it.$1;
      var fs = r.width / (it.$2.length * 0.7);
      bool fits(double f) {
        final tw = f * it.$2.length * charWidthFactor;
        final cx = r.left + r.width / 2;
        final h = cx - tw / 2 >= r.left && cx + tw / 2 <= r.right;
        final v = r.top + yOffset + f <= r.bottom;
        return h && v;
      }

      while (fs > 0 && !fits(fs)) {
        fs -= 1;
      }
      return fs;
    });
    uniformFontSize = sizes.reduce(math.min).floorToDouble();
    if (uniformFontSize <= 0) return;
    final style = TextStyleSpec(fontFamily: ff, fontSize: uniformFontSize);
    for (final it in items) {
      final r = it.$1;
      final y = outside ? r.top - yOffset - uniformFontSize : r.top + yOffset;
      nodes.add(SceneText(
        text: it.$2,
        bounds: Rect.fromLTWH(
            r.left, y, r.width, uniformFontSize),
        style: style,
        color: color,
        align: TextAlignH.center,
      ));
    }
  }
}

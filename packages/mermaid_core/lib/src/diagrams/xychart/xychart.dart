/// XY chart (xychart-beta): model, parser and layout — one file.
///
/// Reference: upstream xychart jison grammar + xychartBuilder.
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
}

enum XySeriesKind { bar, line }

class XySeries {
  const XySeries({required this.kind, required this.values, this.label});

  final XySeriesKind kind;
  final List<double> values;
  final String? label;
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

  String unquote(String s) {
    final t = s.trim();
    return t.length >= 2 && t.startsWith('"') && t.endsWith('"')
        ? t.substring(1, t.length - 1)
        : t;
  }

  List<double> numbers(String list, int line) => [
        for (final p in list.split(','))
          double.tryParse(
                  p.replaceAll(RegExp(r'"[^"]*"'), '').trim()) ??
              (throw MermaidParseException('invalid number "$p"', line: line)),
      ];

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
      series.add(XySeries(
        kind: m.group(1) == 'bar' ? XySeriesKind.bar : XySeriesKind.line,
        label: m.group(3),
        values: numbers(m.group(4)!, i + 1),
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
  );
}

/// Upstream xychart default plot palette (theme-default derives the first
/// entries from the pie palette; the rendered look is pale lavender bars
/// with a grey second series).
const _plotPalette = <Color>[
  Color(0xffececff),
  Color(0xff848484),
  Color(0xffffffde),
  Color(0xff2ca02c),
  Color(0xffd62728),
  Color(0xff9467bd),
];

RenderScene layoutXyChart(
  XyChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const plotW = 560.0;
  const plotH = 320.0;
  final baseStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.8);
  final nodes = <SceneNode>[];

  // Value range across all series (or explicit yRange).
  var minV = chart.yRange?.$1 ?? double.infinity;
  var maxV = chart.yRange?.$2 ?? double.negativeInfinity;
  if (chart.yRange == null) {
    for (final s in chart.series) {
      for (final v in s.values) {
        minV = math.min(minV, v);
        maxV = math.max(maxV, v);
      }
    }
    if (!minV.isFinite) {
      minV = 0;
      maxV = 1;
    }
    if (minV > 0) minV = 0;
  }
  if (maxV <= minV) maxV = minV + 1;

  final pointCount = chart.categories.isNotEmpty
      ? chart.categories.length
      : chart.series.fold(0, (a, s) => math.max(a, s.values.length));
  if (pointCount == 0) {
    return RenderScene(
        size: const Size(200, 60), background: theme.background, nodes: const []);
  }

  final horizontal = chart.horizontal;
  final plot = Rect.fromLTWH(0, 0, plotW, plotH);

  // Value axis runs along x (horizontal charts) or y (vertical, default).
  double valPix(double v) {
    final t = (v - minV) / (maxV - minV);
    return horizontal ? plot.left + t * plotW : plot.bottom - t * plotH;
  }

  // Category axis runs along y (horizontal) or x (vertical).
  final catExtent = horizontal ? plotH : plotW;
  final band = catExtent / pointCount;
  double catPix(int i) =>
      (horizontal ? plot.top : plot.left) + band * (i + 0.5);

  final baseVal = valPix(math.max(0, minV));

  // Value grid + labels at "nice" steps (1/2/5 x 10^n).
  final rawStep = (maxV - minV) / 5;
  final mag = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final norm = rawStep / mag;
  final step = (norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10))) * mag;
  for (var v = (minV / step).ceil() * step; v <= maxV + 1e-9; v += step) {
    final p = valPix(v);
    nodes.add(SceneShape(
      geometry: PathGeometry(horizontal
          ? [MoveTo(Point(p, plot.top)), LineTo(Point(p, plot.bottom))]
          : [MoveTo(Point(plot.left, p)), LineTo(Point(plot.right, p))]),
      stroke: const Stroke(color: Color(0xffdddddd), width: 1),
    ));
    final label =
        v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    final size = measurer.measure(label, baseStyle);
    nodes.add(SceneText(
      text: label,
      bounds: horizontal
          ? Rect.fromLTWH(
              p - size.width / 2, plot.bottom + 6, size.width, size.height)
          : Rect.fromLTWH(plot.left - size.width - 8, p - size.height / 2,
              size.width, size.height),
      style: baseStyle,
      color: theme.textColor,
      align: horizontal ? TextAlignH.center : TextAlignH.right,
    ));
  }

  // Bars first (lines draw on top), grouped side by side along the cat axis.
  final barSeries =
      chart.series.where((s) => s.kind == XySeriesKind.bar).toList();
  for (var b = 0; b < barSeries.length; b++) {
    final s = barSeries[b];
    final color = _plotPalette[chart.series.indexOf(s) % _plotPalette.length];
    final groupW = band * 0.7;
    final barW = groupW / barSeries.length;
    for (var i = 0; i < s.values.length && i < pointCount; i++) {
      final c = catPix(i) - groupW / 2 + b * barW + barW / 2;
      final p = valPix(s.values[i]);
      final lo = c - (barW - 2) / 2, hi = c + (barW - 2) / 2;
      nodes.add(SceneShape(
        geometry: RectGeometry(horizontal
            ? Rect.fromLTRB(math.min(baseVal, p), lo, math.max(baseVal, p), hi)
            : Rect.fromLTRB(lo, math.min(baseVal, p), hi, math.max(baseVal, p))),
        fill: Fill(color),
      ));
    }
  }
  for (final s in chart.series) {
    if (s.kind != XySeriesKind.line) continue;
    final color = _plotPalette[chart.series.indexOf(s) % _plotPalette.length];
    final pts = [
      for (var i = 0; i < s.values.length && i < pointCount; i++)
        horizontal
            ? Point(valPix(s.values[i]), catPix(i))
            : Point(catPix(i), valPix(s.values[i])),
    ];
    if (pts.length < 2) continue;
    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(pts.first),
        for (final p in pts.skip(1)) LineTo(p),
      ]),
      stroke: Stroke(color: color, width: 2),
    ));
  }

  // Axes: an L from the shared origin at bottom-left.
  nodes.add(SceneShape(
    geometry: PathGeometry([
      MoveTo(Point(plot.left, plot.top)),
      LineTo(Point(plot.left, plot.bottom)),
      LineTo(Point(plot.right, plot.bottom)),
    ]),
    stroke: Stroke(color: theme.lineColor, width: 1.2),
  ));

  // Category labels: categories or numeric range endpoints.
  final catLabels = chart.categories.isNotEmpty
      ? chart.categories
      : [
          for (var i = 0; i < pointCount; i++)
            '${(chart.xRange?.$1 ?? 1) + i * ((chart.xRange == null || pointCount <= 1) ? 1 : (chart.xRange!.$2 - chart.xRange!.$1) / (pointCount - 1))}',
        ];
  // Thin labels if they would collide.
  var labelEvery = 1;
  if (catLabels.isNotEmpty) {
    final widest = catLabels
        .map((l) => measurer.measure(l, baseStyle).width)
        .reduce(math.max);
    labelEvery = math.max(1, ((widest + 10) / band).ceil());
  }
  for (var i = 0; i < pointCount && i < catLabels.length; i++) {
    if (i % labelEvery != 0) continue;
    final size = measurer.measure(catLabels[i], baseStyle);
    nodes.add(SceneText(
      text: catLabels[i],
      bounds: horizontal
          ? Rect.fromLTWH(plot.left - size.width - 8,
              catPix(i) - size.height / 2, size.width, size.height)
          : Rect.fromLTWH(catPix(i) - size.width / 2, plot.bottom + 6,
              size.width, size.height),
      style: baseStyle,
      color: theme.textColor,
      align: horizontal ? TextAlignH.right : TextAlignH.center,
    ));
  }

  void axisTitle(String? text, Point center) {
    if (text == null || text.isEmpty) return;
    final size = measurer.measure(text, baseStyle);
    nodes.add(SceneText(
      text: text,
      bounds: Rect.fromCenter(center, size.width, size.height),
      style: baseStyle.copyWith(fontWeight: 700),
      color: theme.textColor,
    ));
  }

  // x-axis title labels the category axis; y-axis title the value axis.
  if (horizontal) {
    axisTitle(chart.xAxisTitle, Point(plot.left, plot.top - 16));
    axisTitle(chart.yAxisTitle, Point(plot.center.x, plot.bottom + 34));
  } else {
    axisTitle(chart.xAxisTitle, Point(plot.center.x, plot.bottom + 34));
    axisTitle(chart.yAxisTitle, Point(plot.left, plot.top - 16));
  }

  var bounds = sceneBounds(nodes)!;
  if (chart.title != null && chart.title!.isNotEmpty) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily,
        fontSize: theme.fontSize * 1.15,
        fontWeight: 700);
    final size = measurer.measure(chart.title!, style);
    final node = SceneText(
      text: chart.title!,
      bounds: Rect.fromLTWH(plot.center.x - size.width / 2,
          bounds.top - size.height - 12, size.width, size.height),
      style: style,
      color: theme.titleColor,
    );
    nodes.add(node);
    bounds = bounds.union(node.bounds);
  }

  const pad = 12.0;
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

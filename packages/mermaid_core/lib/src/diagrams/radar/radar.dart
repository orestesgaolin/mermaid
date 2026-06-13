/// Radar / spider chart (`radar-beta`): value axes radiating from a center,
/// with one closed polygon per curve. Reference: upstream radar.
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

class RadarCurve {
  RadarCurve(this.label, this.values);
  final String label;
  final List<double> values;
}

class RadarChart {
  const RadarChart(this.axes, this.curves, this.min, this.max, this.title);
  final List<String> axes;
  final List<RadarCurve> curves;
  final double min;
  final double max;
  final String? title;
}

String _unlabel(String s) {
  final m = RegExp(r'\[(.*?)\]').firstMatch(s);
  var label = m != null ? m.group(1)! : s.trim();
  if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
    label = label.substring(1, label.length - 1);
  }
  return label;
}

RadarChart parseRadar(String source) {
  final title = frontmatterTitle(source);
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final axes = <String>[];
  final curves = <RadarCurve>[];
  double? min, max;
  var seenHeader = false;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^radar(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "radar" header', line: i + 1);
      }
      seenHeader = true;
      final rest = line.replaceFirst(RegExp(r'^radar(-beta)?\s*'), '');
      if (rest.trim().isEmpty) continue;
      line = rest.trim();
    }
    var m = RegExp(r'^axis\s+(.+)$').firstMatch(line);
    if (m != null) {
      for (final part in m.group(1)!.split(',')) {
        if (part.trim().isNotEmpty) axes.add(_unlabel(part));
      }
      continue;
    }
    m = RegExp(r'^curve\s+(.+?)\{(.*)\}\s*$').firstMatch(line);
    if (m != null) {
      final label = _unlabel(m.group(1)!);
      final values = [
        for (final v in m.group(2)!.split(','))
          if (v.trim().isNotEmpty) double.tryParse(v.trim()) ?? 0.0
      ];
      curves.add(RadarCurve(label, values));
      continue;
    }
    m = RegExp(r'^max\s+([\d.]+)$').firstMatch(line);
    if (m != null) {
      max = double.parse(m.group(1)!);
      continue;
    }
    m = RegExp(r'^min\s+([\d.]+)$').firstMatch(line);
    if (m != null) {
      min = double.parse(m.group(1)!);
      continue;
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty radar source');
  // Default range from data.
  if (min == null || max == null) {
    var lo = 0.0, hi = 0.0;
    for (final cu in curves) {
      for (final v in cu.values) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    min ??= lo;
    max ??= hi == lo ? lo + 1 : hi;
  }
  return RadarChart(axes, curves, min, max, title);
}

const _palette = <Color>[
  Color(0xff5b8ff9),
  Color(0xfff6bd16),
  Color(0xff61ddaa),
  Color(0xfff08bb4),
  Color(0xff7262fd),
];

RenderScene layoutRadar(
  RadarChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.85);
  final nodes = <SceneNode>[];
  const r = 170.0;
  final center = const Point(0, 0);
  final n = chart.axes.length;
  if (n < 3) {
    return RenderScene(
        size: const Size(200, 80), background: theme.background, nodes: const []);
  }
  // Axis angle: start at top, clockwise.
  double angle(int i) => -math.pi / 2 + 2 * math.pi * i / n;
  Point at(int i, double frac) =>
      Point(center.x + r * frac * math.cos(angle(i)),
          center.y + r * frac * math.sin(angle(i)));

  // Concentric grid rings (4 levels).
  for (var ring = 1; ring <= 4; ring++) {
    final frac = ring / 4;
    nodes.add(SceneShape(
      geometry: PolygonGeometry([for (var i = 0; i < n; i++) at(i, frac)]),
      stroke: const Stroke(color: Color(0xffdddddd), width: 1),
    ));
  }
  // Axis spokes + labels.
  for (var i = 0; i < n; i++) {
    final tip = at(i, 1);
    nodes.add(SceneShape(
      geometry: PathGeometry([MoveTo(center), LineTo(tip)]),
      stroke: const Stroke(color: Color(0xffcccccc), width: 1),
    ));
    final lp = at(i, 1.12);
    final ts = measurer.measure(chart.axes[i], baseStyle);
    nodes.add(SceneText(
      text: chart.axes[i],
      bounds: Rect.fromCenter(lp, ts.width, ts.height),
      style: baseStyle,
      color: theme.textColor,
    ));
  }

  // Curves.
  final span = chart.max - chart.min == 0 ? 1 : chart.max - chart.min;
  for (var ci = 0; ci < chart.curves.length; ci++) {
    final cu = chart.curves[ci];
    final color = _palette[ci % _palette.length];
    final pts = [
      for (var i = 0; i < n; i++)
        at(i, ((i < cu.values.length ? cu.values[i] : chart.min) - chart.min) / span),
    ];
    nodes.add(SceneShape(
      geometry: PolygonGeometry(pts),
      fill: Fill(color.withOpacity(0.25)),
      stroke: Stroke(color: color, width: 2),
    ));
  }

  // Legend.
  var ly = -r - 30.0;
  final lx = r + 30.0;
  for (var ci = 0; ci < chart.curves.length; ci++) {
    final color = _palette[ci % _palette.length];
    nodes.add(SceneShape(
      geometry: RectGeometry(Rect.fromLTWH(lx, ly, 12, 12), rx: 2, ry: 2),
      fill: Fill(color),
    ));
    final ts = measurer.measure(chart.curves[ci].label, baseStyle);
    nodes.add(SceneText(
      text: chart.curves[ci].label,
      bounds: Rect.fromLTWH(lx + 18, ly, ts.width, ts.height),
      style: baseStyle,
      color: theme.textColor,
      align: TextAlignH.left,
    ));
    ly += 20;
  }

  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(-r, -r, 2 * r, 2 * r);
  if (chart.title != null && chart.title!.isNotEmpty) {
    final style = baseStyle.copyWith(fontWeight: 700, fontSize: theme.fontSize * 1.1);
    final ts = measurer.measure(chart.title!, style);
    final node = SceneText(
      text: chart.title!,
      bounds: Rect.fromLTWH(
          center.x - ts.width / 2, bounds.top - ts.height - 8, ts.width, ts.height),
      style: style,
      color: theme.titleColor,
    );
    nodes.add(node);
    bounds = bounds.union(node.bounds);
  }
  const m = 16.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final nd in nodes) translateSceneNode(nd, m - bounds.left, m - bounds.top)
    ],
  );
}

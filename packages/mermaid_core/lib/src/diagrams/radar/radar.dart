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
  const RadarChart(
    this.axes,
    this.curves,
    this.min,
    this.max,
    this.title, {
    this.ticks = 5,
    this.showLegend = true,
    this.graticule = 'circle',
  });
  final List<String> axes;
  final List<RadarCurve> curves;
  final double min;
  final double max;
  final String? title;

  /// Number of concentric graticule rings (upstream default 5).
  final int ticks;

  /// Whether to render the legend (upstream default true).
  final bool showLegend;

  /// `circle` (default, concentric circles + smooth curves) or `polygon`
  /// (nested polygon rings + straight-line curves).
  final String graticule;
}

String _unlabel(String s) {
  final m = RegExp(r'\[(.*?)\]').firstMatch(s);
  var label = m != null ? m.group(1)! : s.trim();
  if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
    label = label.substring(1, label.length - 1);
  }
  return label;
}

/// Bare axis name (without any `[label]`), used to match axis-keyed curve
/// entries (`curve c{ax1: 5, ax2: 6}`) back to their axis order.
String _axisName(String s) {
  final br = s.indexOf('[');
  return (br >= 0 ? s.substring(0, br) : s).trim();
}

/// Parse a curve body into a value list ordered to match [axisNames].
///
/// Mirrors upstream `db.ts:computeCurveEntries`: bare numbers are taken in
/// order; axis-keyed entries (`name: value`) are reordered against the axes
/// and a missing axis entry throws.
List<double> _parseCurveEntries(
  String body,
  List<String> axisNames,
  int lineNo,
) {
  final parts = [
    for (final p in body.split(',')) if (p.trim().isNotEmpty) p.trim()
  ];
  if (parts.isEmpty) return const [];
  final keyed = parts.first.contains(':');
  if (!keyed) {
    return [for (final p in parts) double.tryParse(p) ?? 0.0];
  }
  // Axis-keyed: build name -> value map, then reorder by axis order.
  final byAxis = <String, double>{};
  for (final p in parts) {
    final idx = p.indexOf(':');
    if (idx < 0) continue;
    final name = _axisName(p.substring(0, idx));
    final value = double.tryParse(p.substring(idx + 1).trim()) ?? 0.0;
    byAxis[name] = value;
  }
  if (axisNames.isEmpty) {
    throw MermaidParseException(
        'Axes must be populated before curves for reference entries',
        line: lineNo);
  }
  return [
    for (final name in axisNames)
      if (byAxis.containsKey(name))
        byAxis[name]!
      else
        throw MermaidParseException('Missing entry for axis $name',
            line: lineNo),
  ];
}

RadarChart parseRadar(String source) {
  final title = frontmatterTitle(source);
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final axes = <String>[]; // display labels
  final axisNames = <String>[]; // bare names for keyed-entry matching
  final curves = <RadarCurve>[];
  double? min, max;
  var ticks = 5;
  var showLegend = true;
  var graticule = 'circle';
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
        if (part.trim().isNotEmpty) {
          axes.add(_unlabel(part));
          axisNames.add(_axisName(part));
        }
      }
      continue;
    }
    m = RegExp(r'^curve\s+(.+?)\{(.*)\}\s*$').firstMatch(line);
    if (m != null) {
      final label = _unlabel(m.group(1)!);
      final values = _parseCurveEntries(m.group(2)!, axisNames, i + 1);
      curves.add(RadarCurve(label, values));
      continue;
    }
    m = RegExp(r'^ticks\s+(\d+)$').firstMatch(line);
    if (m != null) {
      ticks = int.parse(m.group(1)!);
      continue;
    }
    m = RegExp(r'^showLegend\s+(true|false)$').firstMatch(line);
    if (m != null) {
      showLegend = m.group(1) == 'true';
      continue;
    }
    m = RegExp(r'^graticule\s+(circle|polygon)$').firstMatch(line);
    if (m != null) {
      graticule = m.group(1)!;
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
  // Defaults mirror upstream options: min defaults to 0, max defaults to the
  // maximum curve entry.
  min ??= 0.0;
  if (max == null) {
    var hi = double.negativeInfinity;
    for (final cu in curves) {
      for (final v in cu.values) {
        hi = math.max(hi, v);
      }
    }
    max = hi.isFinite ? hi : min + 1;
  }
  return RadarChart(
    axes,
    curves,
    min,
    max,
    title,
    ticks: ticks,
    showLegend: showLegend,
    graticule: graticule,
  );
}

/// Curve / legend colors = default theme `cScale0..11`
/// (`darken(primary/secondary/tertiary or hue-rotated primary, 10)`).
const _cScale = <Color>[
  Color(0xffb9b9ff), // cScale0  darken(primaryColor #ECECFF)
  Color(0xffffffab), // cScale1  darken(secondaryColor #ffffde)
  Color(0xffe9ffb9), // cScale2  darken(tertiaryColor)
  Color(0xffdeb9ff), // cScale3  adjust h+30
  Color(0xffffb9ff), // cScale4  adjust h+60
  Color(0xffffb9de), // cScale5  adjust h+90
  Color(0xffffb9b9), // cScale6  adjust h+120
  Color(0xffffdeb9), // cScale7  adjust h+150
  Color(0xffdeffb9), // cScale8  adjust h+210
  Color(0xffb9ffde), // cScale9  adjust h+270
  Color(0xffb9ffff), // cScale10 adjust h+300
  Color(0xffb9deff), // cScale11 adjust h+330
];

/// Catmull-Rom spline tension (upstream `curveTension` default).
const _curveTension = 0.17;

RenderScene layoutRadar(
  RadarChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  // Axis/legend labels are a fixed 12px upstream.
  final labelStyle = TextStyleSpec(fontFamily: theme.fontFamily, fontSize: 12);
  final nodes = <SceneNode>[];
  // Upstream config defaults: 600x600 canvas, radius = min(w,h)/2 = 300.
  const r = 300.0;
  final center = const Point(0, 0);
  final n = chart.axes.length;
  if (n < 3) {
    return RenderScene(
        size: const Size(200, 80), background: theme.background, nodes: const []);
  }
  final isPolygon = chart.graticule == 'polygon';
  // Axis angle: start at top, clockwise.
  double angle(int i) => -math.pi / 2 + 2 * math.pi * i / n;
  Point at(int i, double frac) =>
      Point(center.x + r * frac * math.cos(angle(i)),
          center.y + r * frac * math.sin(angle(i)));

  const graticuleColor = Color(0xffdedede);
  final ticks = chart.ticks < 1 ? 1 : chart.ticks;

  // Graticule rings: concentric circles (circle) or nested polygons (polygon).
  for (var ring = 1; ring <= ticks; ring++) {
    final rr = r * ring / ticks;
    if (isPolygon) {
      nodes.add(SceneShape(
        geometry: PolygonGeometry([
          for (var i = 0; i < n; i++)
            Point(center.x + rr * math.cos(angle(i)),
                center.y + rr * math.sin(angle(i))),
        ]),
        fill: Fill(graticuleColor.withOpacity(0.3)),
        stroke: const Stroke(color: graticuleColor, width: 1),
      ));
    } else {
      nodes.add(SceneShape(
        geometry: CircleGeometry(center, rr),
        fill: Fill(graticuleColor.withOpacity(0.3)),
        stroke: const Stroke(color: graticuleColor, width: 1),
      ));
    }
  }

  // Axis spokes + labels.
  for (var i = 0; i < n; i++) {
    final tip = at(i, 1);
    nodes.add(SceneShape(
      geometry: PathGeometry([MoveTo(center), LineTo(tip)]),
      stroke: Stroke(color: theme.lineColor, width: 2),
    ));
    // Label anchor at factor 1.05 plus a 4px outward pad, with per-quadrant
    // horizontal/vertical anchoring (mirrors upstream text-anchor +
    // dominant-baseline derived from cos/sin sign).
    final cosA = math.cos(angle(i));
    final sinA = math.sin(angle(i));
    const labelPad = 4.0;
    final ax = r * 1.05 * cosA + labelPad * cosA;
    final ay = r * 1.05 * sinA + labelPad * sinA;
    final ts = measurer.measure(chart.axes[i], labelStyle);

    // Horizontal anchor: start (left), end (right), or middle.
    final double left;
    final TextAlignH align;
    if (cosA > 0.01) {
      left = ax; // text-anchor start
      align = TextAlignH.left;
    } else if (cosA < -0.01) {
      left = ax - ts.width; // text-anchor end
      align = TextAlignH.right;
    } else {
      left = ax - ts.width / 2; // middle
      align = TextAlignH.center;
    }
    // Vertical baseline: hanging (top at anchor), auto (bottom at anchor),
    // central (centered on anchor).
    final double top;
    if (sinA > 0.01) {
      top = ay; // hanging
    } else if (sinA < -0.01) {
      top = ay - ts.height; // auto (baseline)
    } else {
      top = ay - ts.height / 2; // central
    }
    nodes.add(SceneText(
      text: chart.axes[i],
      bounds: Rect.fromLTWH(left, top, ts.width, ts.height),
      style: labelStyle,
      color: theme.textColor,
      align: align,
    ));
  }

  // Curves. Skip any whose entry count != axis count (upstream behavior).
  final span = chart.max - chart.min == 0 ? 1 : chart.max - chart.min;
  for (var ci = 0; ci < chart.curves.length; ci++) {
    final cu = chart.curves[ci];
    if (cu.values.length != n) continue;
    final color = _cScale[ci % _cScale.length];
    final pts = [
      for (var i = 0; i < n; i++)
        at(i, (cu.values[i].clamp(chart.min, chart.max) - chart.min) / span),
    ];
    if (isPolygon) {
      nodes.add(SceneShape(
        geometry: PolygonGeometry(pts),
        fill: Fill(color.withOpacity(0.5)),
        stroke: Stroke(color: color, width: 2),
      ));
    } else {
      nodes.add(SceneShape(
        geometry: PathGeometry(_closedCurve(pts)),
        fill: Fill(color.withOpacity(0.5)),
        stroke: Stroke(color: color, width: 2),
      ));
    }
  }

  // Legend (only when enabled). Upstream positions it top-right at
  // ((width/2 + marginRight) * 3/4, -(height/2 + marginTop) * 3/4).
  if (chart.showLegend) {
    const legendX = (300.0 + 50.0) * 3 / 4; // 262.5
    var ly = -(300.0 + 50.0) * 3 / 4; // -262.5
    for (var ci = 0; ci < chart.curves.length; ci++) {
      final color = _cScale[ci % _cScale.length];
      nodes.add(SceneShape(
        geometry: RectGeometry(Rect.fromLTWH(legendX, ly, 12, 12)),
        fill: Fill(color),
      ));
      final ts = measurer.measure(chart.curves[ci].label, labelStyle);
      nodes.add(SceneText(
        text: chart.curves[ci].label,
        bounds: Rect.fromLTWH(legendX + 16, ly, ts.width, ts.height),
        style: labelStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ));
      ly += 20;
    }
  }

  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(-r, -r, 2 * r, 2 * r);
  if (chart.title != null && chart.title!.isNotEmpty) {
    // Title uses theme fontSize, non-bold, anchored middle/hanging at the top.
    final style = labelStyle.copyWith(fontSize: theme.fontSize);
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

/// A closed smooth (Catmull-Rom) curve through [pts], for radar area fills.
List<PathCommand> _closedCurve(List<Point> pts) {
  final n = pts.length;
  if (n < 3) {
    return [MoveTo(pts.first), for (var i = 1; i < n; i++) LineTo(pts[i])];
  }
  final cmds = <PathCommand>[MoveTo(pts[0])];
  for (var i = 0; i < n; i++) {
    final p0 = pts[(i - 1 + n) % n];
    final p1 = pts[i];
    final p2 = pts[(i + 1) % n];
    final p3 = pts[(i + 2) % n];
    cmds.add(CubicTo(
      Point(p1.x + (p2.x - p0.x) * _curveTension,
          p1.y + (p2.y - p0.y) * _curveTension),
      Point(p2.x - (p3.x - p1.x) * _curveTension,
          p2.y - (p3.y - p1.y) * _curveTension),
      p2,
    ));
  }
  cmds.add(const ClosePath());
  return cmds;
}

/// Radar / spider chart (`radar-beta`): value axes radiating from a center,
/// with one closed polygon per curve. Reference: upstream radar.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../config_values.dart';
import '../../detect.dart';
import '../../directives.dart';
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

/// Typed layout values from `config.radar`.
class RadarConfig {
  const RadarConfig({
    this.width = 600,
    this.height = 600,
    this.marginTop = 50,
    this.marginRight = 50,
    this.marginBottom = 50,
    this.marginLeft = 50,
    this.axisScaleFactor = 1,
    this.axisLabelFactor = 1.05,
    this.curveTension = 0.17,
  });

  final double width;
  final double height;
  final double marginTop;
  final double marginRight;
  final double marginBottom;
  final double marginLeft;
  final double axisScaleFactor;
  final double axisLabelFactor;
  final double curveTension;

  factory RadarConfig.fromSource(String source) {
    final values = resolveDiagramConfig(source, 'radar');
    return RadarConfig(
      width: positiveDouble(values, 'width', 600),
      height: positiveDouble(values, 'height', 600),
      marginTop: nonNegativeDouble(values, 'marginTop', 50),
      marginRight: nonNegativeDouble(values, 'marginRight', 50),
      marginBottom: nonNegativeDouble(values, 'marginBottom', 50),
      marginLeft: nonNegativeDouble(values, 'marginLeft', 50),
      axisScaleFactor: nonNegativeDouble(values, 'axisScaleFactor', 1),
      axisLabelFactor: nonNegativeDouble(values, 'axisLabelFactor', 1.05),
      curveTension: clampedDouble(values, 'curveTension', 0.17, min: 0, max: 1),
    );
  }
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
    for (final p in body.split(','))
      if (p.trim().isNotEmpty) p.trim(),
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
      line: lineNo,
    );
  }
  return [
    for (final name in axisNames)
      if (byAxis.containsKey(name))
        byAxis[name]!
      else
        throw MermaidParseException(
          'Missing entry for axis $name',
          line: lineNo,
        ),
  ];
}

RadarChart parseRadar(String source) {
  var title = frontmatterTitle(source);
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
    var m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      // A body `title` wins over the frontmatter one, as in every other
      // diagram (upstream's `setDiagramTitle` simply overwrites).
      title = m.group(1)!.trim();
      continue;
    }
    m = RegExp(r'^axis\s+(.+)$').firstMatch(line);
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

RenderScene layoutRadar(
  RadarChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
  RadarConfig config = const RadarConfig(),
}) {
  // Axis/legend labels are a fixed 12px upstream.
  final labelStyle = TextStyleSpec(fontFamily: theme.fontFamily, fontSize: 12);
  final nodes = <SceneNode>[];
  final r = math.min(config.width, config.height) / 2;
  final center = const Point(0, 0);
  final n = chart.axes.length;
  if (n < 3) {
    return RenderScene(
      size: const Size(200, 80),
      background: theme.background,
      nodes: const [],
    );
  }
  final isPolygon = chart.graticule == 'polygon';
  // Axis angle: start at top, clockwise.
  double angle(int i) => -math.pi / 2 + 2 * math.pi * i / n;
  Point at(int i, double frac) => Point(
    center.x + r * frac * math.cos(angle(i)),
    center.y + r * frac * math.sin(angle(i)),
  );

  const graticuleColor = Color(0xffdedede);
  final ticks = chart.ticks < 1 ? 1 : chart.ticks;

  // Graticule rings: concentric circles (circle) or nested polygons (polygon).
  for (var ring = 1; ring <= ticks; ring++) {
    final rr = r * ring / ticks;
    if (isPolygon) {
      nodes.add(
        SceneShape(
          geometry: PolygonGeometry([
            for (var i = 0; i < n; i++)
              Point(
                center.x + rr * math.cos(angle(i)),
                center.y + rr * math.sin(angle(i)),
              ),
          ]),
          fill: Fill(graticuleColor.withOpacity(0.3)),
          stroke: const Stroke(color: graticuleColor, width: 1),
        ),
      );
    } else {
      nodes.add(
        SceneShape(
          geometry: CircleGeometry(center, rr),
          fill: Fill(graticuleColor.withOpacity(0.3)),
          stroke: const Stroke(color: graticuleColor, width: 1),
        ),
      );
    }
  }

  // Axis spokes + labels.
  for (var i = 0; i < n; i++) {
    final tip = at(i, config.axisScaleFactor);
    nodes.add(
      SceneShape(
        geometry: PathGeometry([MoveTo(center), LineTo(tip)]),
        stroke: Stroke(color: theme.lineColor, width: 2),
      ),
    );
    // Label anchor at factor 1.05 plus a 4px outward pad, with per-quadrant
    // horizontal/vertical anchoring (mirrors upstream text-anchor +
    // dominant-baseline derived from cos/sin sign).
    final cosA = math.cos(angle(i));
    final sinA = math.sin(angle(i));
    const labelPad = 4.0;
    final ax = r * config.axisLabelFactor * cosA + labelPad * cosA;
    final ay = r * config.axisLabelFactor * sinA + labelPad * sinA;
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
    nodes.add(
      SceneText(
        text: chart.axes[i],
        bounds: Rect.fromLTWH(left, top, ts.width, ts.height),
        style: labelStyle,
        color: theme.textColor,
        align: align,
      ),
    );
  }

  // Curve / legend colors = theme ordinal scale (`cScale0..11`).
  final cScale = theme.cScale;

  // Curves. Skip any whose entry count != axis count (upstream behavior).
  final span = chart.max - chart.min == 0 ? 1 : chart.max - chart.min;
  for (var ci = 0; ci < chart.curves.length; ci++) {
    final cu = chart.curves[ci];
    if (cu.values.length != n) continue;
    final color = cScale[ci % cScale.length];
    final pts = [
      for (var i = 0; i < n; i++)
        at(i, (cu.values[i].clamp(chart.min, chart.max) - chart.min) / span),
    ];
    if (isPolygon) {
      nodes.add(
        SceneShape(
          geometry: PolygonGeometry(pts),
          fill: Fill(color.withOpacity(0.5)),
          stroke: Stroke(color: color, width: 2),
        ),
      );
    } else {
      nodes.add(
        SceneShape(
          geometry: PathGeometry(_closedCurve(pts, config.curveTension)),
          fill: Fill(color.withOpacity(0.5)),
          stroke: Stroke(color: color, width: 2),
        ),
      );
    }
  }

  // Legend (only when enabled). Upstream positions it top-right at
  // ((width/2 + marginRight) * 3/4, -(height/2 + marginTop) * 3/4).
  if (chart.showLegend) {
    final legendX = ((config.width / 2 + config.marginRight) * 3) / 4;
    var ly = (-(config.height / 2 + config.marginTop) * 3) / 4;
    for (var ci = 0; ci < chart.curves.length; ci++) {
      final color = cScale[ci % cScale.length];
      nodes.add(
        SceneShape(
          geometry: RectGeometry(Rect.fromLTWH(legendX, ly, 12, 12)),
          fill: Fill(color),
        ),
      );
      final ts = measurer.measure(chart.curves[ci].label, labelStyle);
      nodes.add(
        SceneText(
          text: chart.curves[ci].label,
          bounds: Rect.fromLTWH(legendX + 16, ly, ts.width, ts.height),
          style: labelStyle,
          color: theme.textColor,
          align: TextAlignH.left,
        ),
      );
      ly += 20;
    }
  }

  if (chart.title != null && chart.title!.isNotEmpty) {
    // Title uses theme fontSize, non-bold, anchored middle/hanging at the top.
    final style = labelStyle.copyWith(fontSize: theme.fontSize);
    final ts = measurer.measure(chart.title!, style);
    final node = SceneText(
      text: chart.title!,
      bounds: Rect.fromLTWH(
        center.x - ts.width / 2,
        -config.height / 2 - config.marginTop,
        ts.width,
        ts.height,
      ),
      style: style,
      color: theme.titleColor,
    );
    nodes.add(node);
  }
  // Upstream drawFrame uses the configured canvas plus all four margins.
  return RenderScene(
    size: Size(
      config.width + config.marginLeft + config.marginRight,
      config.height + config.marginTop + config.marginBottom,
    ),
    background: theme.background,
    nodes: [
      for (final nd in nodes)
        translateSceneNode(
          nd,
          config.width / 2 + config.marginLeft,
          config.height / 2 + config.marginTop,
        ),
    ],
  );
}

/// A closed smooth (Catmull-Rom) curve through [pts], for radar area fills.
List<PathCommand> _closedCurve(List<Point> pts, double tension) {
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
    cmds.add(
      CubicTo(
        Point(p1.x + (p2.x - p0.x) * tension, p1.y + (p2.y - p0.y) * tension),
        Point(p2.x - (p3.x - p1.x) * tension, p2.y - (p3.y - p1.y) * tension),
        p2,
      ),
    );
  }
  cmds.add(const ClosePath());
  return cmds;
}

/// Quadrant chart: model, parser and layout (compact diagram — one file).
///
/// Reference: upstream quadrant-chart jison grammar + quadrantBuilder.ts.
library;

import '../../color.dart';
import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

class QuadrantChart {
  const QuadrantChart({
    this.title,
    this.xAxisLeft,
    this.xAxisRight,
    this.yAxisBottom,
    this.yAxisTop,
    this.quadrantLabels = const [null, null, null, null],
    this.points = const [],
  });

  final String? title;
  final String? xAxisLeft;
  final String? xAxisRight;
  final String? yAxisBottom;
  final String? yAxisTop;

  /// quadrant-1 (top right) .. quadrant-4 (bottom right), upstream order.
  final List<String?> quadrantLabels;
  final List<QuadrantPoint> points;
}

class QuadrantPoint {
  const QuadrantPoint({required this.label, required this.x, required this.y});

  final String label;

  /// 0..1 in chart space (y up).
  final double x;
  final double y;
}

QuadrantChart parseQuadrantChart(String source) {
  final frontTitle = frontmatterTitle(source);
  final text = stripMetadata(source);
  String? title = frontTitle;
  String? xl, xr, yb, yt;
  final quadrantLabels = List<String?>.filled(4, null);
  final points = <QuadrantPoint>[];
  var seenHeader = false;

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^quadrantChart\b').hasMatch(line)) {
        throw MermaidParseException('expected "quadrantChart" header',
            line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    Match? m;
    m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      continue;
    }
    m = RegExp(r'^x-axis\s+(.+?)(?:\s*-->\s*(.+))?$').firstMatch(line);
    if (m != null) {
      xl = m.group(1)!.trim();
      xr = m.group(2)?.trim();
      continue;
    }
    m = RegExp(r'^y-axis\s+(.+?)(?:\s*-->\s*(.+))?$').firstMatch(line);
    if (m != null) {
      yb = m.group(1)!.trim();
      yt = m.group(2)?.trim();
      continue;
    }
    m = RegExp(r'^quadrant-([1-4])\s+(.+)$').firstMatch(line);
    if (m != null) {
      quadrantLabels[int.parse(m.group(1)!) - 1] = m.group(2)!.trim();
      continue;
    }
    m = RegExp(r'^(.+?):\s*\[\s*([\d.]+)\s*,\s*([\d.]+)\s*\]$')
        .firstMatch(line);
    if (m != null) {
      points.add(QuadrantPoint(
        label: m.group(1)!.trim(),
        x: double.parse(m.group(2)!).clamp(0, 1),
        y: double.parse(m.group(3)!).clamp(0, 1),
      ));
      continue;
    }
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(line)) continue;
    throw MermaidParseException('unrecognized statement "$line"', line: i + 1);
  }
  if (!seenHeader) {
    throw const MermaidParseException('empty quadrant chart source');
  }
  return QuadrantChart(
    title: title,
    xAxisLeft: xl,
    xAxisRight: xr,
    yAxisBottom: yb,
    yAxisTop: yt,
    quadrantLabels: quadrantLabels,
    points: points,
  );
}

const _quadrantFills = [
  Color(0xffe5e5fb), // q1 top right
  Color(0xffd6d6f5), // q2 top left
  Color(0xffe5e5fb), // q3 bottom left
  Color(0xfff0f0ff), // q4 bottom right
];

RenderScene layoutQuadrantChart(
  QuadrantChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const plot = 320.0;
  final baseStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.85);
  final nodes = <SceneNode>[];
  const left = 10.0, top = 10.0;
  final rect = Rect.fromLTWH(left, top, plot, plot);

  // Quadrant regions: q1 top-right, q2 top-left, q3 bottom-left,
  // q4 bottom-right (upstream numbering).
  final regions = [
    Rect.fromLTWH(rect.center.x, rect.top, plot / 2, plot / 2),
    Rect.fromLTWH(rect.left, rect.top, plot / 2, plot / 2),
    Rect.fromLTWH(rect.left, rect.center.y, plot / 2, plot / 2),
    Rect.fromLTWH(rect.center.x, rect.center.y, plot / 2, plot / 2),
  ];
  for (var q = 0; q < 4; q++) {
    nodes.add(SceneShape(
      geometry: RectGeometry(regions[q]),
      fill: Fill(_quadrantFills[q]),
    ));
    final label = chart.quadrantLabels[q];
    if (label != null) {
      final size = measurer.measure(label, baseStyle, maxWidth: plot / 2 - 16);
      nodes.add(SceneText(
        text: label,
        bounds: Rect.fromCenter(regions[q].center, size.width, size.height),
        style: baseStyle,
        color: theme.textColor,
      ));
    }
  }
  nodes.add(SceneShape(
    geometry: RectGeometry(rect),
    stroke: Stroke(color: theme.nodeBorder),
  ));

  // Points with labels above.
  for (final p in chart.points) {
    final pos = Point(
        rect.left + p.x * plot, rect.bottom - p.y * plot);
    final size = measurer.measure(p.label, baseStyle);
    nodes.add(SceneGroup(id: 'point_${p.label}', children: [
      SceneShape(
        geometry: CircleGeometry(pos, 5),
        fill: Fill(theme.nodeBorder),
      ),
      SceneText(
        text: p.label,
        bounds: Rect.fromLTWH(pos.x - size.width / 2, pos.y - size.height - 7,
            size.width, size.height),
        style: baseStyle,
        color: theme.textColor,
      ),
    ]));
  }

  // Axis labels.
  void axisLabel(String? text, Point center) {
    if (text == null || text.isEmpty) return;
    final size = measurer.measure(text, baseStyle);
    nodes.add(SceneText(
      text: text,
      bounds: Rect.fromCenter(center, size.width, size.height),
      style: baseStyle.copyWith(fontWeight: 700),
      color: theme.textColor,
    ));
  }

  axisLabel(chart.xAxisLeft, Point(rect.left + plot / 4, rect.bottom + 16));
  axisLabel(chart.xAxisRight, Point(rect.right - plot / 4, rect.bottom + 16));
  // The IR has no text rotation; y-axis labels sit left of the plot, low
  // label beside the bottom half and high label beside the top half.
  double yLabelX(String text) =>
      rect.left - 12 - measurer.measure(text, baseStyle).width / 2;
  if (chart.yAxisBottom != null) {
    axisLabel(chart.yAxisBottom,
        Point(yLabelX(chart.yAxisBottom!), rect.bottom - plot / 4));
  }
  if (chart.yAxisTop != null) {
    axisLabel(
        chart.yAxisTop, Point(yLabelX(chart.yAxisTop!), rect.top + plot / 4));
  }

  var bounds = sceneBounds(nodes)!;
  final title = chart.title;
  if (title != null && title.isNotEmpty) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily,
        fontSize: theme.fontSize * 1.15,
        fontWeight: 700);
    final size = measurer.measure(title, style);
    final node = SceneText(
      text: title,
      bounds: Rect.fromLTWH(rect.center.x - size.width / 2,
          bounds.top - size.height - 12, size.width, size.height),
      style: style,
      color: theme.titleColor,
    );
    nodes.add(node);
    bounds = bounds.union(node.bounds);
  }

  const pad = 10.0;
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

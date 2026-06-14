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
    this.classes = const {},
  });

  final String? title;
  final String? xAxisLeft;
  final String? xAxisRight;
  final String? yAxisBottom;
  final String? yAxisTop;

  /// quadrant-1 (top right) .. quadrant-4 (bottom right), upstream order.
  final List<String?> quadrantLabels;
  final List<QuadrantPoint> points;

  /// classDef name -> styles, applied to points referencing it via `:::name`.
  final Map<String, QuadrantPointStyle> classes;
}

/// Inline / classDef style for a point (upstream `StylesObject`).
class QuadrantPointStyle {
  const QuadrantPointStyle({
    this.radius,
    this.color,
    this.strokeColor,
    this.strokeWidth,
  });

  final double? radius;
  final Color? color;
  final Color? strokeColor;

  /// Stroke width in px (upstream stores e.g. `"2px"`).
  final double? strokeWidth;

  QuadrantPointStyle merge(QuadrantPointStyle other) => QuadrantPointStyle(
        radius: other.radius ?? radius,
        color: other.color ?? color,
        strokeColor: other.strokeColor ?? strokeColor,
        strokeWidth: other.strokeWidth ?? strokeWidth,
      );
}

class QuadrantPoint {
  const QuadrantPoint({
    required this.label,
    required this.x,
    required this.y,
    this.className,
    this.style = const QuadrantPointStyle(),
  });

  final String label;

  /// 0..1 in chart space (y up).
  final double x;
  final double y;

  /// Optional `:::className` reference.
  final String? className;

  /// Inline style overrides (`radius`, `color`, `stroke-color`, `stroke-width`).
  final QuadrantPointStyle style;
}

/// Parses one `key:value` inline style fragment, validating like upstream
/// `utils.ts`. Throws [MermaidParseException] on invalid values.
QuadrantPointStyle _parseStyles(Iterable<String> styles, int lineNo) {
  var result = const QuadrantPointStyle();
  for (final raw in styles) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    final idx = s.indexOf(':');
    if (idx < 0) {
      throw MermaidParseException('invalid style "$s"', line: lineNo);
    }
    final key = s.substring(0, idx).trim();
    final value = s.substring(idx + 1).trim();
    switch (key) {
      case 'radius':
        if (!RegExp(r'^\d+$').hasMatch(value)) {
          throw MermaidParseException(
              'value for radius $value is invalid, please use a valid number',
              line: lineNo);
        }
        result = result.merge(QuadrantPointStyle(radius: double.parse(value)));
      case 'color':
        final c = _parseHex(value);
        if (c == null) {
          throw MermaidParseException(
              'value for color $value is invalid, please use a valid hex code',
              line: lineNo);
        }
        result = result.merge(QuadrantPointStyle(color: c));
      case 'stroke-color':
        final c = _parseHex(value);
        if (c == null) {
          throw MermaidParseException(
              'value for stroke-color $value is invalid, please use a valid '
              'hex code',
              line: lineNo);
        }
        result = result.merge(QuadrantPointStyle(strokeColor: c));
      case 'stroke-width':
        final m = RegExp(r'^(\d+)px$').firstMatch(value);
        if (m == null) {
          throw MermaidParseException(
              'value for stroke-width $value is invalid, please use a valid '
              'number of pixels (eg. 10px)',
              line: lineNo);
        }
        result = result
            .merge(QuadrantPointStyle(strokeWidth: double.parse(m.group(1)!)));
      default:
        throw MermaidParseException('style named $key is not supported.',
            line: lineNo);
    }
  }
  return result;
}

/// Accepts `#rgb`/`#rrggbb` (with or without leading `#`), matching upstream
/// `validateHexCode`.
Color? _parseHex(String value) {
  if (!RegExp(r'^#?([\dA-Fa-f]{6}|[\dA-Fa-f]{3})$').hasMatch(value)) {
    return null;
  }
  return Color.tryParse(value.startsWith('#') ? value : '#$value');
}

/// Splits a comma-separated style list, respecting nothing fancier (upstream
/// `stylesOpt` is plain comma-split).
List<String> _splitStyles(String s) =>
    s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

QuadrantChart parseQuadrantChart(String source) {
  final frontTitle = frontmatterTitle(source);
  final text = stripMetadata(source);
  String? title = frontTitle;
  String? xl, xr, yb, yt;
  final quadrantLabels = List<String?>.filled(4, null);
  final points = <QuadrantPoint>[];
  final classes = <String, QuadrantPointStyle>{};
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
    // classDef <name> <styles>
    m = RegExp(r'^classDef\s+(\w+)\s+(.+)$').firstMatch(line);
    if (m != null) {
      classes[m.group(1)!] = _parseStyles(_splitStyles(m.group(2)!), i + 1);
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
    // Point: `label[:::class] : [x, y][ radius: N, color: #hex, ...]`
    m = RegExp(r'^(.+?)(?::::(\w+))?\s*:\s*\[\s*([\d.]+)\s*,\s*([\d.]+)\s*\]'
            r'(?:\s+(.+))?$')
        .firstMatch(line);
    if (m != null) {
      final inline =
          m.group(5) != null ? _parseStyles(_splitStyles(m.group(5)!), i + 1) : const QuadrantPointStyle();
      points.add(QuadrantPoint(
        label: m.group(1)!.trim(),
        className: m.group(2),
        x: double.parse(m.group(3)!).clamp(0, 1),
        y: double.parse(m.group(4)!).clamp(0, 1),
        style: inline,
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
    classes: classes,
  );
}

// Upstream default theme constants (theme-default.js). primaryColor=#ECECFF;
// quadrant fills lighten +5/+10/+15 per channel; text fills = invert(primary)
// with −5/−10/−15 nudges; point fill = darken(primary).
const _quadrant1Fill = Color(0xffececff);
const _quadrant2Fill = Color(0xfff1f1ff);
const _quadrant3Fill = Color(0xfff6f6ff);
const _quadrant4Fill = Color(0xfffbfbff);
const _quadrant1TextFill = Color(0xff131300);
const _quadrant2TextFill = Color(0xff0e0e00);
const _quadrant3TextFill = Color(0xff090900);
const _quadrant4TextFill = Color(0xff040400);
const _quadrantPointFill = Color(0xffb9b9ff); // darken(#ECECFF)

// Upstream QuadrantBuilder default config (quadrantBuilder.ts).
const _chartWidth = 500.0;
const _chartHeight = 500.0;
const _quadrantPadding = 5.0;
const _titlePadding = 10.0;
const _titleFontSize = 20.0;
const _xAxisLabelPadding = 5.0;
const _yAxisLabelPadding = 5.0;
const _xAxisLabelFontSize = 16.0;
const _yAxisLabelFontSize = 16.0;
const _quadrantLabelFontSize = 16.0;
const _quadrantTextTopPadding = 5.0;
const _pointTextPadding = 5.0;
const _pointLabelFontSize = 12.0;
const _pointRadius = 5.0;
const _internalBorderStrokeWidth = 1.0;
const _externalBorderStrokeWidth = 2.0;

/// Text anchored at [x],[y] mirroring upstream's `text-anchor`/
/// `dominant-baseline`: [left] => start anchor (left-aligned at x), else
/// center; [top] => hanging baseline (top at y), else vertically centered.
SceneText _anchoredText({
  required String text,
  required double x,
  required double y,
  required Size size,
  required TextStyleSpec style,
  required Color color,
  required bool left,
  required bool top,
  double rotation = 0,
}) {
  final bx = left ? x : x - size.width / 2;
  final by = top ? y : y - size.height / 2;
  return SceneText(
    text: text,
    bounds: Rect.fromLTWH(bx, by, size.width, size.height),
    style: style,
    color: color,
    align: left ? TextAlignH.left : TextAlignH.center,
    rotation: rotation,
  );
}

RenderScene layoutQuadrantChart(
  QuadrantChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final nodes = <SceneNode>[];

  final hasPoints = chart.points.isNotEmpty;
  final showXAxis = (chart.xAxisLeft != null && chart.xAxisLeft!.isNotEmpty) ||
      (chart.xAxisRight != null && chart.xAxisRight!.isNotEmpty);
  final showYAxis =
      (chart.yAxisTop != null && chart.yAxisTop!.isNotEmpty) ||
          (chart.yAxisBottom != null && chart.yAxisBottom!.isNotEmpty);
  final showTitle = chart.title != null && chart.title!.isNotEmpty;

  // Upstream forces x-axis to the bottom once there are points.
  final xAxisTop = !hasPoints;

  // calculateSpace().
  final xAxisSpaceCalc = _xAxisLabelPadding * 2 + _xAxisLabelFontSize;
  final xAxisTopSpace = xAxisTop && showXAxis ? xAxisSpaceCalc : 0.0;
  final xAxisBottomSpace = !xAxisTop && showXAxis ? xAxisSpaceCalc : 0.0;
  final yAxisLeftSpace =
      showYAxis ? _yAxisLabelPadding * 2 + _yAxisLabelFontSize : 0.0;
  final titleTopSpace = showTitle ? _titleFontSize + _titlePadding * 2 : 0.0;

  final quadrantLeft = _quadrantPadding + yAxisLeftSpace;
  final quadrantTop = _quadrantPadding + xAxisTopSpace + titleTopSpace;
  final quadrantWidth =
      _chartWidth - _quadrantPadding * 2 - yAxisLeftSpace;
  final quadrantHeight = _chartHeight -
      _quadrantPadding * 2 -
      xAxisTopSpace -
      xAxisBottomSpace -
      titleTopSpace;
  final quadrantHalfWidth = quadrantWidth / 2;
  final quadrantHalfHeight = quadrantHeight / 2;

  // Quadrant regions: q1 top-right, q2 top-left, q3 bottom-left,
  // q4 bottom-right (upstream numbering).
  final regions = [
    Rect.fromLTWH(quadrantLeft + quadrantHalfWidth, quadrantTop,
        quadrantHalfWidth, quadrantHalfHeight),
    Rect.fromLTWH(
        quadrantLeft, quadrantTop, quadrantHalfWidth, quadrantHalfHeight),
    Rect.fromLTWH(quadrantLeft, quadrantTop + quadrantHalfHeight,
        quadrantHalfWidth, quadrantHalfHeight),
    Rect.fromLTWH(quadrantLeft + quadrantHalfWidth,
        quadrantTop + quadrantHalfHeight, quadrantHalfWidth, quadrantHalfHeight),
  ];
  const quadrantFills = [
    _quadrant1Fill,
    _quadrant2Fill,
    _quadrant3Fill,
    _quadrant4Fill
  ];
  const quadrantTextFills = [
    _quadrant1TextFill,
    _quadrant2TextFill,
    _quadrant3TextFill,
    _quadrant4TextFill
  ];
  final quadrantStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: _quadrantLabelFontSize);

  for (var q = 0; q < 4; q++) {
    nodes.add(SceneShape(
      geometry: RectGeometry(regions[q]),
      fill: Fill(quadrantFills[q]),
    ));
    final label = chart.quadrantLabels[q];
    if (label != null && label.isNotEmpty) {
      final size =
          measurer.measure(label, quadrantStyle, maxWidth: quadrantHalfWidth);
      final cx = regions[q].left + regions[q].width / 2;
      // No points => centered in region; points => anchored at region top.
      final top = hasPoints;
      final ty = hasPoints
          ? regions[q].top + _quadrantTextTopPadding
          : regions[q].center.y;
      nodes.add(_anchoredText(
        text: label,
        x: cx,
        y: ty,
        size: size,
        style: quadrantStyle,
        color: quadrantTextFills[q],
        left: false,
        top: top,
      ));
    }
  }

  // Borders: 4 external (width 2) + 2 internal divider lines (width 1).
  const halfExt = _externalBorderStrokeWidth / 2;
  final extStroke = Stroke(
      color: theme.primaryBorderColor, width: _externalBorderStrokeWidth);
  final intStroke = Stroke(
      color: theme.primaryBorderColor, width: _internalBorderStrokeWidth);
  void line(double x1, double y1, double x2, double y2, Stroke stroke) {
    nodes.add(SceneShape(
      geometry: PolygonGeometry([Point(x1, y1), Point(x2, y2)]),
      stroke: stroke,
    ));
  }

  final right = quadrantLeft + quadrantWidth;
  final bottom = quadrantTop + quadrantHeight;
  // top
  line(quadrantLeft - halfExt, quadrantTop, right + halfExt, quadrantTop,
      extStroke);
  // right
  line(right, quadrantTop + halfExt, right, bottom - halfExt, extStroke);
  // bottom
  line(quadrantLeft - halfExt, bottom, right + halfExt, bottom, extStroke);
  // left
  line(quadrantLeft, quadrantTop + halfExt, quadrantLeft, bottom - halfExt,
      extStroke);
  // vertical inner
  line(quadrantLeft + quadrantHalfWidth, quadrantTop + halfExt,
      quadrantLeft + quadrantHalfWidth, bottom - halfExt, intStroke);
  // horizontal inner
  line(quadrantLeft + halfExt, quadrantTop + quadrantHalfHeight,
      right - halfExt, quadrantTop + quadrantHalfHeight, intStroke);

  // Points: scaleLinear x∈[0,1]→[left,left+width], y∈[0,1]→[top+height,top].
  final pointStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: _pointLabelFontSize);
  for (final p in chart.points) {
    var style = chart.classes[p.className] ?? const QuadrantPointStyle();
    // Inline styles override class styles (upstream `{...class, ...point}`).
    style = style.merge(p.style);
    final px = quadrantLeft + p.x * quadrantWidth;
    final py = quadrantTop + quadrantHeight - p.y * quadrantHeight;
    final radius = style.radius ?? _pointRadius;
    final fill = style.color ?? _quadrantPointFill;
    final strokeColor = style.strokeColor ?? _quadrantPointFill;
    final strokeWidth = style.strokeWidth ?? 0;
    final size = measurer.measure(p.label, pointStyle);
    nodes.add(SceneGroup(id: 'point_${p.label}', children: [
      SceneShape(
        geometry: CircleGeometry(Point(px, py), radius),
        fill: Fill(fill),
        stroke:
            strokeWidth > 0 ? Stroke(color: strokeColor, width: strokeWidth) : null,
      ),
      // Label centered below the dot (anchor center, hanging baseline).
      _anchoredText(
        text: p.label,
        x: px,
        y: py + _pointTextPadding,
        size: size,
        style: pointStyle,
        color: theme.primaryTextColor,
        left: false,
        top: true,
      ),
    ]));
  }

  // Axis labels.
  final axisStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: _xAxisLabelFontSize);
  final yAxisStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: _yAxisLabelFontSize);
  final drawXMiddle = chart.xAxisRight != null && chart.xAxisRight!.isNotEmpty;
  final drawYMiddle = chart.yAxisTop != null && chart.yAxisTop!.isNotEmpty;

  final xAxisY = xAxisTop
      ? _xAxisLabelPadding + titleTopSpace
      : _xAxisLabelPadding + quadrantTop + quadrantHeight + _quadrantPadding;

  void xLabel(String? text, double baseX) {
    if (text == null || text.isEmpty || !showXAxis) return;
    final size = measurer.measure(text, axisStyle);
    final x = baseX + (drawXMiddle ? quadrantHalfWidth / 2 : 0);
    nodes.add(_anchoredText(
      text: text,
      x: x,
      y: xAxisY,
      size: size,
      style: axisStyle,
      color: theme.primaryTextColor,
      left: !drawXMiddle,
      top: true,
    ));
  }

  xLabel(chart.xAxisLeft, quadrantLeft);
  xLabel(chart.xAxisRight, quadrantLeft + quadrantHalfWidth);

  // Y-axis labels rotated −90° at the left edge.
  void yLabel(String? text, double anchorY) {
    if (text == null || text.isEmpty || !showYAxis) return;
    final size = measurer.measure(text, yAxisStyle);
    nodes.add(_anchoredText(
      text: text,
      x: _yAxisLabelPadding,
      y: anchorY,
      size: size,
      style: yAxisStyle,
      color: theme.primaryTextColor,
      left: !drawYMiddle,
      top: true,
      rotation: -90,
    ));
  }

  yLabel(
      chart.yAxisBottom,
      quadrantTop +
          quadrantHeight -
          (drawYMiddle ? quadrantHalfHeight / 2 : 0));
  yLabel(chart.yAxisTop,
      quadrantTop + quadrantHalfHeight - (drawYMiddle ? quadrantHalfHeight / 2 : 0));

  // Title: centered at chartWidth/2, anchored (top baseline) at titlePadding.
  if (showTitle) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily,
        fontSize: _titleFontSize,
        fontWeight: 700);
    final size = measurer.measure(chart.title!, style);
    nodes.add(_anchoredText(
      text: chart.title!,
      x: _chartWidth / 2,
      y: _titlePadding,
      size: size,
      style: style,
      color: theme.primaryTextColor,
      left: false,
      top: true,
    ));
  }

  final bounds = sceneBounds(nodes)!;
  const pad = 5.0;
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

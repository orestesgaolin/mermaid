/// Quadrant chart: model, parser and layout (compact diagram — one file).
///
/// Reference: upstream quadrant-chart jison grammar + quadrantBuilder.ts.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../config_values.dart';
import '../../detect.dart';
import '../../directives.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
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

/// Layout dimensions resolved from `config.quadrantChart`.
class QuadrantConfig {
  const QuadrantConfig({
    this.chartWidth = 500,
    this.chartHeight = 500,
    this.quadrantPadding = 5,
    this.titlePadding = 10,
    this.titleFontSize = 20,
    this.xAxisLabelPadding = 5,
    this.yAxisLabelPadding = 5,
    this.xAxisLabelFontSize = 16,
    this.yAxisLabelFontSize = 16,
    this.quadrantLabelFontSize = 16,
    this.quadrantTextTopPadding = 5,
    this.pointTextPadding = 5,
    this.pointLabelFontSize = 12,
    this.pointRadius = 5,
    this.quadrantInternalBorderStrokeWidth = 1,
    this.quadrantExternalBorderStrokeWidth = 2,
    this.xAxisPosition = 'top',
    this.yAxisPosition = 'left',
  });

  /// Fixed scene and chart width in logical pixels.
  final double chartWidth;

  /// Fixed scene and chart height in logical pixels.
  final double chartHeight;

  /// Inset between the scene edge and reserved axis/title space.
  final double quadrantPadding;

  final double titlePadding;
  final double titleFontSize;
  final double xAxisLabelPadding;
  final double yAxisLabelPadding;
  final double xAxisLabelFontSize;
  final double yAxisLabelFontSize;
  final double quadrantLabelFontSize;
  final double quadrantTextTopPadding;
  final double pointTextPadding;
  final double pointLabelFontSize;
  final double pointRadius;
  final double quadrantInternalBorderStrokeWidth;
  final double quadrantExternalBorderStrokeWidth;
  final String xAxisPosition, yAxisPosition;

  /// Resolves frontmatter first, then applies every init directive in order.
  factory QuadrantConfig.fromSource(String source) {
    final values = resolveDiagramConfig(source, 'quadrantChart');
    return QuadrantConfig(
      chartWidth: positiveDouble(values, 'chartWidth', 500),
      chartHeight: positiveDouble(values, 'chartHeight', 500),
      quadrantPadding: nonNegativeDouble(values, 'quadrantPadding', 5),
      titlePadding: nonNegativeDouble(values, 'titlePadding', 10),
      titleFontSize: nonNegativeDouble(values, 'titleFontSize', 20),
      xAxisLabelPadding: nonNegativeDouble(values, 'xAxisLabelPadding', 5),
      yAxisLabelPadding: nonNegativeDouble(values, 'yAxisLabelPadding', 5),
      xAxisLabelFontSize: nonNegativeDouble(values, 'xAxisLabelFontSize', 16),
      yAxisLabelFontSize: nonNegativeDouble(values, 'yAxisLabelFontSize', 16),
      quadrantLabelFontSize: nonNegativeDouble(
        values,
        'quadrantLabelFontSize',
        16,
      ),
      quadrantTextTopPadding: nonNegativeDouble(
        values,
        'quadrantTextTopPadding',
        5,
      ),
      pointTextPadding: nonNegativeDouble(values, 'pointTextPadding', 5),
      pointLabelFontSize: nonNegativeDouble(values, 'pointLabelFontSize', 12),
      pointRadius: nonNegativeDouble(values, 'pointRadius', 5),
      quadrantInternalBorderStrokeWidth: nonNegativeDouble(
        values,
        'quadrantInternalBorderStrokeWidth',
        1,
      ),
      quadrantExternalBorderStrokeWidth: nonNegativeDouble(
        values,
        'quadrantExternalBorderStrokeWidth',
        2,
      ),
      xAxisPosition: enumValue(values, 'xAxisPosition', const {
        'top',
        'bottom',
      }, 'top'),
      yAxisPosition: enumValue(values, 'yAxisPosition', const {
        'left',
        'right',
      }, 'left'),
    );
  }
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
            line: lineNo,
          );
        }
        result = result.merge(QuadrantPointStyle(radius: double.parse(value)));
      case 'color':
        final c = _parseHex(value);
        if (c == null) {
          throw MermaidParseException(
            'value for color $value is invalid, please use a valid hex code',
            line: lineNo,
          );
        }
        result = result.merge(QuadrantPointStyle(color: c));
      case 'stroke-color':
        final c = _parseHex(value);
        if (c == null) {
          throw MermaidParseException(
            'value for stroke-color $value is invalid, please use a valid '
            'hex code',
            line: lineNo,
          );
        }
        result = result.merge(QuadrantPointStyle(strokeColor: c));
      case 'stroke-width':
        final m = RegExp(r'^(\d+)px$').firstMatch(value);
        if (m == null) {
          throw MermaidParseException(
            'value for stroke-width $value is invalid, please use a valid '
            'number of pixels (eg. 10px)',
            line: lineNo,
          );
        }
        result = result.merge(
          QuadrantPointStyle(strokeWidth: double.parse(m.group(1)!)),
        );
      default:
        throw MermaidParseException(
          'style named $key is not supported.',
          line: lineNo,
        );
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
        throw MermaidParseException(
          'expected "quadrantChart" header',
          line: i + 1,
        );
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
    m = RegExp(r'^x-axis\s+(.+)$').firstMatch(line);
    if (m != null) {
      final axis = _parseAxisText(m.group(1)!, i + 1);
      xl = axis.$1;
      xr = axis.$2;
      continue;
    }
    m = RegExp(r'^y-axis\s+(.+)$').firstMatch(line);
    if (m != null) {
      final axis = _parseAxisText(m.group(1)!, i + 1);
      yb = axis.$1;
      yt = axis.$2;
      continue;
    }
    m = RegExp(r'^quadrant-([1-4])\s+(.+)$').firstMatch(line);
    if (m != null) {
      quadrantLabels[int.parse(m.group(1)!) - 1] = m.group(2)!.trim();
      continue;
    }
    // Point: `label[:::class] : [x, y][ radius: N, color: #hex, ...]`
    m = RegExp(
      r'^(.+?)(?::::(\w+))?\s*:\s*\[\s*([\d.]+)\s*,\s*([\d.]+)\s*\]'
      r'(?:\s+(.+))?$',
    ).firstMatch(line);
    if (m != null) {
      final inline = m.group(5) != null
          ? _parseStyles(_splitStyles(m.group(5)!), i + 1)
          : const QuadrantPointStyle();
      points.add(
        QuadrantPoint(
          label: m.group(1)!.trim(),
          className: m.group(2),
          x: double.parse(m.group(3)!).clamp(0, 1),
          y: double.parse(m.group(4)!).clamp(0, 1),
          style: inline,
        ),
      );
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

(String, String?) _parseAxisText(String raw, int lineNo) {
  final delimiter = _axisDelimiter(raw);
  if (delimiter == null) return (_unquote(raw.trim()), null);
  final left = _unquote(raw.substring(0, delimiter.$1).trim());
  if (left.isEmpty) {
    throw MermaidParseException(
      'axis delimiter requires a label before it',
      line: lineNo,
    );
  }
  final right = _unquote(raw.substring(delimiter.$2).trim());
  // Upstream appends `" \u27F6 "` (long right arrow, both spaces kept) to the
  // left label when the delimiter has nothing after it (quadrant.jison).
  return right.isEmpty ? ('$left \u27F6 ', null) : (left, right);
}

(int, int)? _axisDelimiter(String text) {
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x22) {
      quoted = !quoted;
      continue;
    }
    if (quoted || text.codeUnitAt(i) != 0x2d) continue;
    var end = i;
    while (end < text.length && text.codeUnitAt(end) == 0x2d) {
      end++;
    }
    if (end - i >= 2 && end < text.length && text.codeUnitAt(end) == 0x3e) {
      return (i, end + 1);
    }
  }
  return null;
}

String _unquote(String text) {
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    return text.substring(1, text.length - 1);
  }
  return text;
}

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
}) {
  final bx = left ? x : x - size.width / 2;
  final by = top ? y : y - size.height / 2;
  return SceneText(
    text: text,
    bounds: Rect.fromLTWH(bx, by, size.width, size.height),
    style: style,
    color: color,
    align: left ? TextAlignH.left : TextAlignH.center,
  );
}

RenderScene layoutQuadrantChart(
  QuadrantChart chart, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
  QuadrantConfig config = const QuadrantConfig(),
}) {
  final nodes = <SceneNode>[];

  final hasPoints = chart.points.isNotEmpty;
  final showXAxis =
      (chart.xAxisLeft != null && chart.xAxisLeft!.isNotEmpty) ||
      (chart.xAxisRight != null && chart.xAxisRight!.isNotEmpty);
  final showYAxis =
      (chart.yAxisTop != null && chart.yAxisTop!.isNotEmpty) ||
      (chart.yAxisBottom != null && chart.yAxisBottom!.isNotEmpty);
  final showTitle = chart.title != null && chart.title!.isNotEmpty;

  // Upstream forces x-axis to the bottom once there are points.
  final xAxisTop = !hasPoints && config.xAxisPosition == 'top';
  final yAxisLeft = config.yAxisPosition == 'left';

  // calculateSpace().
  final xAxisSpaceCalc =
      config.xAxisLabelPadding * 2 + config.xAxisLabelFontSize;
  final xAxisTopSpace = xAxisTop && showXAxis ? xAxisSpaceCalc : 0.0;
  final xAxisBottomSpace = !xAxisTop && showXAxis ? xAxisSpaceCalc : 0.0;
  final yAxisSpace = showYAxis
      ? config.yAxisLabelPadding * 2 + config.yAxisLabelFontSize
      : 0.0;
  final yAxisLeftSpace = yAxisLeft ? yAxisSpace : 0.0;
  final titleTopSpace = showTitle
      ? config.titleFontSize + config.titlePadding * 2
      : 0.0;

  final quadrantLeft = config.quadrantPadding + yAxisLeftSpace;
  final quadrantTop = config.quadrantPadding + xAxisTopSpace + titleTopSpace;
  // A `chartWidth`/`chartHeight` smaller than the padding plus the reserved
  // title/axis bands leaves a negative plot region. Upstream just draws the
  // degenerate (invisible) region; clamp to zero so `render()` keeps to its
  // documented contract — a finite scene, or MermaidParseException /
  // UnsupportedError — instead of throwing ArgumentError.
  final quadrantWidth = math.max(
    0.0,
    config.chartWidth - config.quadrantPadding * 2 - yAxisSpace,
  );
  final quadrantHeight = math.max(
    0.0,
    config.chartHeight -
        config.quadrantPadding * 2 -
        xAxisTopSpace -
        xAxisBottomSpace -
        titleTopSpace,
  );
  final quadrantHalfWidth = quadrantWidth / 2;
  final quadrantHalfHeight = quadrantHeight / 2;

  // Quadrant regions: q1 top-right, q2 top-left, q3 bottom-left,
  // q4 bottom-right (upstream numbering).
  final regions = [
    Rect.fromLTWH(
      quadrantLeft + quadrantHalfWidth,
      quadrantTop,
      quadrantHalfWidth,
      quadrantHalfHeight,
    ),
    Rect.fromLTWH(
      quadrantLeft,
      quadrantTop,
      quadrantHalfWidth,
      quadrantHalfHeight,
    ),
    Rect.fromLTWH(
      quadrantLeft,
      quadrantTop + quadrantHalfHeight,
      quadrantHalfWidth,
      quadrantHalfHeight,
    ),
    Rect.fromLTWH(
      quadrantLeft + quadrantHalfWidth,
      quadrantTop + quadrantHalfHeight,
      quadrantHalfWidth,
      quadrantHalfHeight,
    ),
  ];
  final quadrantFills = [
    theme.quadrant1Fill,
    theme.quadrant2Fill,
    theme.quadrant3Fill,
    theme.quadrant4Fill,
  ];
  final quadrantTextFills = [
    theme.quadrant1TextFill,
    theme.quadrant2TextFill,
    theme.quadrant3TextFill,
    theme.quadrant4TextFill,
  ];
  final quadrantStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: config.quadrantLabelFontSize,
  );

  for (var q = 0; q < 4; q++) {
    nodes.add(
      SceneShape(
        geometry: RectGeometry(regions[q]),
        fill: Fill(quadrantFills[q]),
      ),
    );
    final label = chart.quadrantLabels[q];
    if (label != null && label.isNotEmpty) {
      final size = measurer.measure(
        label,
        quadrantStyle,
        maxWidth: math.max(1.0, quadrantHalfWidth),
      );
      final cx = regions[q].left + regions[q].width / 2;
      // No points => centered in region; points => anchored at region top.
      final top = hasPoints;
      final ty = hasPoints
          ? regions[q].top + config.quadrantTextTopPadding
          : regions[q].center.y;
      nodes.add(
        _anchoredText(
          text: label,
          x: cx,
          y: ty,
          size: size,
          style: quadrantStyle,
          color: quadrantTextFills[q],
          left: false,
          top: top,
        ),
      );
    }
  }

  // Borders: 4 external (width 2) + 2 internal divider lines (width 1).
  final halfExt = config.quadrantExternalBorderStrokeWidth / 2;
  final extStroke = Stroke(
    color: theme.quadrantExternalBorderStrokeFill,
    width: config.quadrantExternalBorderStrokeWidth,
  );
  final intStroke = Stroke(
    color: theme.quadrantInternalBorderStrokeFill,
    width: config.quadrantInternalBorderStrokeWidth,
  );
  void line(double x1, double y1, double x2, double y2, Stroke stroke) {
    nodes.add(
      SceneShape(
        geometry: PolygonGeometry([Point(x1, y1), Point(x2, y2)]),
        stroke: stroke,
      ),
    );
  }

  final right = quadrantLeft + quadrantWidth;
  final bottom = quadrantTop + quadrantHeight;
  // top
  line(
    quadrantLeft - halfExt,
    quadrantTop,
    right + halfExt,
    quadrantTop,
    extStroke,
  );
  // right
  line(right, quadrantTop + halfExt, right, bottom - halfExt, extStroke);
  // bottom
  line(quadrantLeft - halfExt, bottom, right + halfExt, bottom, extStroke);
  // left
  line(
    quadrantLeft,
    quadrantTop + halfExt,
    quadrantLeft,
    bottom - halfExt,
    extStroke,
  );
  // vertical inner
  line(
    quadrantLeft + quadrantHalfWidth,
    quadrantTop + halfExt,
    quadrantLeft + quadrantHalfWidth,
    bottom - halfExt,
    intStroke,
  );
  // horizontal inner
  line(
    quadrantLeft + halfExt,
    quadrantTop + quadrantHalfHeight,
    right - halfExt,
    quadrantTop + quadrantHalfHeight,
    intStroke,
  );

  // Points: scaleLinear x∈[0,1]→[left,left+width], y∈[0,1]→[top+height,top].
  final pointStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: config.pointLabelFontSize,
  );
  for (final p in chart.points) {
    var style = chart.classes[p.className] ?? const QuadrantPointStyle();
    // Inline styles override class styles (upstream `{...class, ...point}`).
    style = style.merge(p.style);
    final px = quadrantLeft + p.x * quadrantWidth;
    final py = quadrantTop + quadrantHeight - p.y * quadrantHeight;
    final radius = style.radius ?? config.pointRadius;
    final fill = style.color ?? theme.quadrantPointFill;
    final strokeColor = style.strokeColor ?? theme.quadrantPointFill;
    final strokeWidth = style.strokeWidth ?? 0;
    final size = measurer.measure(p.label, pointStyle);
    nodes.add(
      SceneGroup(
        id: 'point_${p.label}',
        children: [
          SceneShape(
            geometry: CircleGeometry(Point(px, py), radius),
            fill: Fill(fill),
            stroke: strokeWidth > 0
                ? Stroke(color: strokeColor, width: strokeWidth)
                : null,
          ),
          // Label centered below the dot (anchor center, hanging baseline).
          _anchoredText(
            text: p.label,
            x: px,
            y: py + config.pointTextPadding,
            size: size,
            style: pointStyle,
            color: theme.quadrantPointTextFill,
            left: false,
            top: true,
          ),
        ],
      ),
    );
  }

  // Axis labels.
  final axisStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: config.xAxisLabelFontSize,
  );
  final yAxisStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: config.yAxisLabelFontSize,
  );
  final drawXMiddle = chart.xAxisRight != null && chart.xAxisRight!.isNotEmpty;
  final drawYMiddle = chart.yAxisTop != null && chart.yAxisTop!.isNotEmpty;

  final xAxisY = xAxisTop
      ? config.xAxisLabelPadding + titleTopSpace
      : config.xAxisLabelPadding +
            quadrantTop +
            quadrantHeight +
            config.quadrantPadding;

  void xLabel(String? text, double baseX) {
    if (text == null || text.isEmpty || !showXAxis) return;
    final size = measurer.measure(text, axisStyle);
    final x = baseX + (drawXMiddle ? quadrantHalfWidth / 2 : 0);
    nodes.add(
      _anchoredText(
        text: text,
        x: x,
        y: xAxisY,
        size: size,
        style: axisStyle,
        color: theme.quadrantXAxisTextFill,
        left: !drawXMiddle,
        top: true,
      ),
    );
  }

  xLabel(chart.xAxisLeft, quadrantLeft);
  xLabel(chart.xAxisRight, quadrantLeft + quadrantHalfWidth);

  // Y-axis labels rotated −90° at the left edge.
  void yLabel(String? text, double anchorY) {
    if (text == null || text.isEmpty || !showYAxis) return;
    final size = measurer.measure(text, yAxisStyle);
    final center = Point(
      yAxisLeft
          ? config.yAxisLabelPadding + size.height / 2
          : config.chartWidth - config.yAxisLabelPadding - size.height / 2,
      drawYMiddle ? anchorY : anchorY - size.width / 2,
    );
    nodes.add(
      SceneText(
        text: text,
        bounds: Rect.fromCenter(center, size.width, size.height),
        style: yAxisStyle,
        color: theme.quadrantYAxisTextFill,
        align: TextAlignH.left,
        rotation: -90,
      ),
    );
  }

  yLabel(
    chart.yAxisBottom,
    quadrantTop + quadrantHeight - (drawYMiddle ? quadrantHalfHeight / 2 : 0),
  );
  yLabel(
    chart.yAxisTop,
    quadrantTop +
        quadrantHalfHeight -
        (drawYMiddle ? quadrantHalfHeight / 2 : 0),
  );

  // Title: centered at chartWidth/2, anchored (top baseline) at titlePadding.
  if (showTitle) {
    final style = TextStyleSpec(
      fontFamily: theme.fontFamily,
      fontSize: config.titleFontSize,
      fontWeight: 700,
    );
    final size = measurer.measure(chart.title!, style);
    nodes.add(
      _anchoredText(
        text: chart.title!,
        x: config.chartWidth / 2,
        y: config.titlePadding,
        size: size,
        style: style,
        color: theme.quadrantTitleFill,
        left: false,
        top: true,
      ),
    );
  }

  return RenderScene(
    size: Size(config.chartWidth, config.chartHeight),
    background: theme.background,
    nodes: nodes,
  );
}

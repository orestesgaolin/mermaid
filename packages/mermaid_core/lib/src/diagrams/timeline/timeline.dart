/// Timeline diagram: model, parser and layout (compact — one file).
///
/// Reference: upstream timeline jison grammar + timelineRenderer.ts.
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

/// Layout direction parsed from the `timeline [LR|TD]` header. Upstream's
/// renderer is columnar regardless of direction, so this is carried for
/// fidelity but does not change the topology.
enum TimelineDirection { td, lr }

class TimelineDiagram {
  const TimelineDiagram({
    required this.sections,
    this.title,
    this.direction = TimelineDirection.td,
  });

  /// Periods outside any `section` land in a section with an empty name.
  final List<TimelineSection> sections;
  final String? title;
  final TimelineDirection direction;
}

class TimelineSection {
  const TimelineSection({required this.name, required this.periods});

  final String name;
  final List<TimelinePeriod> periods;
}

class TimelinePeriod {
  const TimelinePeriod({required this.label, required this.events});

  final String label;
  final List<String> events;
}

TimelineDiagram parseTimeline(String source) {
  final frontTitle = frontmatterTitle(source);
  final text = stripMetadata(source);
  String? title = frontTitle;
  final sections = <(String, List<TimelinePeriod>)>[];
  List<String>? lastEvents;
  var seenHeader = false;
  var direction = TimelineDirection.td;

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      final header = RegExp(r'^timeline\b(.*)$').firstMatch(line);
      if (header == null) {
        throw MermaidParseException('expected "timeline" header', line: i + 1);
      }
      final dir = header.group(1)!.trim().toUpperCase();
      if (dir == 'LR') {
        direction = TimelineDirection.lr;
      } else if (dir == 'TD' || dir == 'TB') {
        direction = TimelineDirection.td;
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
    m = RegExp(r'^section\s+(.+)$').firstMatch(line);
    if (m != null) {
      sections.add((m.group(1)!.trim(), []));
      lastEvents = null;
      continue;
    }
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(line)) continue;

    // Continuation: `: another event` appends to the previous period.
    if (line.startsWith(':')) {
      if (lastEvents == null) {
        throw MermaidParseException('event without a period', line: i + 1);
      }
      lastEvents.add(_normalize(line.substring(1)));
      continue;
    }

    // Period line: `2004 : Facebook : Google` (events optional).
    final parts = line.split(':').map((p) => p.trim()).toList();
    final label = _normalize(parts.first);
    if (label.isEmpty) {
      throw MermaidParseException('unrecognized statement "$line"',
          line: i + 1);
    }
    final events = [
      for (final e in parts.skip(1))
        if (e.isNotEmpty) _normalize(e),
    ];
    if (sections.isEmpty) sections.add(('', []));
    sections.last.$2.add(TimelinePeriod(label: label, events: events));
    lastEvents = sections.last.$2.last.events;
    continue;
  }
  if (!seenHeader) {
    throw const MermaidParseException('empty timeline source');
  }
  return TimelineDiagram(
    sections: [
      for (final (name, periods) in sections)
        if (periods.isNotEmpty) TimelineSection(name: name, periods: periods),
    ],
    title: title,
    direction: direction,
  );
}

String _normalize(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .trim();

// Section/task/event fills are upstream's `cScale<i>` and the per-node bottom
// underline uses `cScaleInv<i>` (`.section-<i> {rect,path,circle} fill:
// cScale<i>` and `.section-<i> line { stroke: cScaleInv<i> }`). Both come from
// the shared theme palette (default theme: darken(primary/secondary/..., 10)),
// so they adapt to dark/forest/neutral. THEME_COLOR_LIMIT = 12; index `% 12`.
const _themeColorLimit = 12;

/// CSS `filter: brightness(120%)` — multiply each RGB channel by 1.2, clamped.
/// Upstream applies this to `.eventWrapper` to lighten the section fill.
Color _brightness(Color c, double factor) => Color.fromARGB(
      c.alpha,
      (c.red * factor).round().clamp(0, 255),
      (c.green * factor).round().clamp(0, 255),
      (c.blue * factor).round().clamp(0, 255),
    );

// Upstream timelineRenderer constants (default `conf.timeline.leftMargin`).
const _leftMargin = 50.0;
const _nodeBaseWidth = 150.0;
const _nodePadding = 20.0;
const _nodeWidth = _nodeBaseWidth + 2 * _nodePadding; // 190
const _nodeRadius = 5.0;
const _columnAdvance = 200.0;
const _eventMaxHeight = 50.0;

RenderScene layoutTimeline(
  TimelineDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  // Upstream node text uses the diagram fontSize (default 16px) directly, not
  // a scaled-down variant; section/task labels are bold via `.section-<i>`.
  final fontSize = theme.fontSize;
  final labelStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: fontSize);
  final nodes = <SceneNode>[];

  // Virtual node height (svgDraw.getVirtualNodeHeight): text wrapped to the
  // base width, `bbox.height + fontSize*1.1*0.5 + padding`.
  double virtualHeight(String text) {
    final size = measurer.measure(text, labelStyle, maxWidth: _nodeBaseWidth);
    return size.height + fontSize * 1.1 * 0.5 + _nodePadding;
  }

  final hasSections = diagram.sections.any((s) => s.name.isNotEmpty);

  // Pass 1: measure max section/task heights and the longest event column.
  var maxSectionHeight = 0.0;
  if (hasSections) {
    for (final section in diagram.sections) {
      if (section.name.isEmpty) continue;
      maxSectionHeight =
          math.max(maxSectionHeight, virtualHeight(section.name) + 20);
    }
  }
  var maxTaskHeight = 0.0;
  var maxEventLineLength = 0.0;
  for (final section in diagram.sections) {
    for (final period in section.periods) {
      maxTaskHeight = math.max(maxTaskHeight, virtualHeight(period.label) + 20);
      var col = 0.0;
      for (final event in period.events) {
        // Event nodes clamp to maxHeight 50.
        col += math.max(virtualHeight(event), _eventMaxHeight);
      }
      if (period.events.isNotEmpty) col += (period.events.length - 1) * 10;
      maxEventLineLength = math.max(maxEventLineLength, col);
    }
  }
  if (maxTaskHeight == 0) maxTaskHeight = _eventMaxHeight;

  /// Draws one timeline-node (rounded rect with corner radius 5, a bottom
  /// underline, and centered wrapped text) at [x],[y]. [colorIndex] selects
  /// the cScale fill; [event] applies the brightness-120% lightening.
  SceneNode drawNode({
    required double x,
    required double y,
    required double width,
    required double height,
    required String text,
    required int colorIndex,
    required String idPrefix,
    bool event = false,
  }) {
    final ci = colorIndex % _themeColorLimit;
    var fill = theme.cScale[ci];
    if (event) fill = _brightness(fill, 1.2);
    final size = measurer.measure(text, labelStyle, maxWidth: width);
    return SceneGroup(id: '${idPrefix}_${x.round()}_${y.round()}', children: [
      SceneShape(
        geometry: RectGeometry(Rect.fromLTWH(x, y, width, height),
            rx: _nodeRadius, ry: _nodeRadius),
        fill: Fill(fill),
        stroke: Stroke(color: theme.nodeBorder, width: 0.7),
      ),
      // Per-node bottom underline (`defaultBkg` <line>, cScaleInv, width 3).
      SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(x, y + height)),
          LineTo(Point(x + width, y + height)),
        ]),
        stroke: Stroke(color: theme.cScaleInv[ci], width: 3),
      ),
      SceneText(
        text: text,
        bounds: Rect.fromLTWH(
            x + width / 2 - size.width / 2,
            y + height / 2 - size.height / 2,
            size.width,
            size.height),
        style: event ? labelStyle : labelStyle.copyWith(fontWeight: 700),
        color: theme.textColor,
      ),
    ]);
  }

  const sectionBeginY = 50.0;
  var masterX = 50.0 + _leftMargin; // 100
  var sectionNumber = 0;

  void drawTasks(List<TimelinePeriod> tasks, int sectionColor, double startX) {
    final taskY = sectionBeginY + (hasSections ? maxSectionHeight + 50 : 0);
    var x = startX;
    var color = sectionColor;
    for (final period in tasks) {
      // Task node.
      nodes.add(drawNode(
        x: x,
        y: taskY,
        width: _nodeWidth,
        height: maxTaskHeight,
        text: period.label,
        colorIndex: color,
        idPrefix: 'period',
      ));

      if (period.events.isNotEmpty) {
        // Vertical dashed connector from the task bottom down past the events.
        final lineX = x + _nodeWidth / 2;
        final lineEnd =
            taskY + maxTaskHeight + 100 + maxEventLineLength + 100;
        nodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(lineX, taskY + maxTaskHeight)),
            LineTo(Point(lineX, lineEnd)),
          ]),
          stroke: Stroke(color: Color.black, width: 2, dash: const [5, 5]),
        ));

        // Events stacked vertically below the task (+200 from task top).
        var ey = taskY + 200;
        for (final event in period.events) {
          final h = math.max(virtualHeight(event), _eventMaxHeight);
          nodes.add(drawNode(
            x: x,
            y: ey,
            width: _nodeWidth,
            height: h,
            text: event,
            colorIndex: color,
            idPrefix: 'event',
            event: true,
          ));
          ey += 10 + h;
        }
      }

      x += _columnAdvance;
      // Without sections, cycle the color per task (multicolor).
      if (!hasSections) color++;
    }
  }

  if (hasSections) {
    for (final section in diagram.sections) {
      final tasks = section.periods;
      final sectionWidth =
          _columnAdvance * math.max(tasks.length, 1) - 50;
      nodes.add(drawNode(
        x: masterX,
        y: sectionBeginY,
        width: sectionWidth,
        height: maxSectionHeight,
        text: section.name,
        colorIndex: sectionNumber,
        idPrefix: 'tl_section',
      ));
      if (tasks.isNotEmpty) {
        drawTasks(tasks, sectionNumber, masterX);
      }
      masterX += _columnAdvance * math.max(tasks.length, 1);
      sectionNumber++;
    }
  } else {
    final tasks = [
      for (final section in diagram.sections) ...section.periods,
    ];
    drawTasks(tasks, sectionNumber, masterX);
  }

  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);

  // Bottom horizontal "activity line": black, width 4, with an arrowhead.
  final depthY = hasSections
      ? maxSectionHeight + maxTaskHeight + 150
      : maxTaskHeight + 100;
  final axisX2 = bounds.width + 3 * _leftMargin;
  nodes.add(SceneShape(
    geometry: PathGeometry([
      MoveTo(Point(_leftMargin, depthY)),
      LineTo(Point(axisX2, depthY)),
      // Arrowhead (marker `M0,0 V4 L6,2 Z`, scaled to the line).
      MoveTo(Point(axisX2 - 6, depthY - 3)),
      LineTo(Point(axisX2 + 2, depthY)),
      LineTo(Point(axisX2 - 6, depthY + 3)),
    ]),
    stroke: Stroke(color: Color.black, width: 4),
  ));
  bounds = sceneBounds(nodes) ?? bounds;

  // Title: large bold, near the top-left (`font-size:4ex`, y=20).
  final title = diagram.title;
  if (title != null && title.isNotEmpty) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily,
        fontSize: fontSize * 2,
        fontWeight: 700);
    final size = measurer.measure(title, style);
    final node = SceneText(
      text: title,
      bounds: Rect.fromLTWH(
          bounds.width / 2 - _leftMargin, 20 - size.height / 2,
          size.width, size.height),
      style: style,
      color: theme.titleColor,
      align: TextAlignH.left,
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

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

class TimelineDiagram {
  const TimelineDiagram({required this.sections, this.title});

  /// Periods outside any `section` land in a section with an empty name.
  final List<TimelineSection> sections;
  final String? title;
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

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^timeline\b').hasMatch(line)) {
        throw MermaidParseException('expected "timeline" header', line: i + 1);
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
  );
}

String _normalize(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .trim();

const _sectionFills = [
  Color(0xffececff),
  Color(0xffffffde),
  Color(0xffd5e5cf),
  Color(0xffe5d0cf),
  Color(0xffcfd6e5),
  Color(0xffe5cfe0),
];

RenderScene layoutTimeline(
  TimelineDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const colWidth = 140.0;
  const colGap = 10.0;
  const eventH0 = 24.0;
  final baseStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.85);
  final nodes = <SceneNode>[];

  const sectionTop = 0.0;
  const sectionH = 26.0;
  const periodTop = sectionTop + sectionH + 10;
  const periodH = 30.0;
  const axisY = periodTop + periodH + 16.0;
  const eventsTop = axisY + 16.0;

  var x = 0.0;
  var sectionIndex = 0;
  for (final section in diagram.sections) {
    final width = section.periods.length * (colWidth + colGap) - colGap;
    final fill = _sectionFills[sectionIndex % _sectionFills.length];
    if (section.name.isNotEmpty) {
      final size = measurer.measure(section.name, baseStyle);
      nodes.add(SceneGroup(id: 'tl_section_$sectionIndex', children: [
        SceneShape(
          geometry: RectGeometry(
              Rect.fromLTWH(x, sectionTop, width, sectionH), rx: 3, ry: 3),
          fill: Fill(fill),
          stroke: Stroke(color: theme.nodeBorder, width: 0.7),
        ),
        SceneText(
          text: section.name,
          bounds: Rect.fromLTWH(x + width / 2 - size.width / 2,
              sectionTop + sectionH / 2 - size.height / 2, size.width,
              size.height),
          style: baseStyle.copyWith(fontWeight: 700),
          color: theme.textColor,
        ),
      ]));
    }
    for (final period in section.periods) {
      final cx = x + colWidth / 2;
      final labelSize =
          measurer.measure(period.label, baseStyle, maxWidth: colWidth - 12);
      final children = <SceneNode>[
        SceneShape(
          geometry: RectGeometry(
              Rect.fromLTWH(x, periodTop, colWidth,
                  math.max(periodH, labelSize.height + 10)),
              rx: 4,
              ry: 4),
          fill: Fill(fill),
          stroke: Stroke(color: theme.nodeBorder),
        ),
        SceneText(
          text: period.label,
          bounds: Rect.fromLTWH(cx - labelSize.width / 2, periodTop + 7,
              labelSize.width, labelSize.height),
          style: baseStyle.copyWith(fontWeight: 700),
          color: theme.textColor,
        ),
      ];
      // Dashed drop from the period box through the axis to the events.
      children.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(cx, periodTop + periodH)),
          LineTo(Point(cx, eventsTop)),
        ]),
        stroke:
            Stroke(color: theme.lineColor, width: 0.8, dash: const [3, 3]),
      ));
      var y = eventsTop;
      for (final event in period.events) {
        final size =
            measurer.measure(event, baseStyle, maxWidth: colWidth - 16);
        final h = math.max(eventH0, size.height + 10);
        children.addAll([
          SceneShape(
            geometry: PathGeometry([
              MoveTo(Point(cx, y - 8)),
              LineTo(Point(cx, y)),
            ]),
            stroke: Stroke(
                color: theme.lineColor, width: 0.8, dash: const [3, 3]),
          ),
          SceneShape(
            geometry: RectGeometry(Rect.fromLTWH(x + 4, y, colWidth - 8, h),
                rx: 3, ry: 3),
            fill: Fill(fill.withOpacity(0.55)),
            stroke: Stroke(color: theme.nodeBorder, width: 0.7),
          ),
          SceneText(
            text: event,
            bounds: Rect.fromLTWH(cx - size.width / 2, y + 5, size.width,
                size.height),
            style: baseStyle,
            color: theme.textColor,
          ),
        ]);
        y += h + 8;
      }
      nodes.add(SceneGroup(
          id: 'period_${period.label}',
          semanticLabel: period.label,
          children: children));
      x += colWidth + colGap;
    }
    sectionIndex++;
  }

  // Horizontal arrow axis between the period row and the events.
  if (x > 0) {
    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(const Point(0, axisY)),
        LineTo(Point(x + 8, axisY)),
        MoveTo(Point(x - 1, axisY - 5)),
        LineTo(Point(x + 8, axisY)),
        LineTo(Point(x - 1, axisY + 5)),
      ]),
      stroke: Stroke(color: theme.lineColor, width: 1.5),
    ));
  }

  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  final title = diagram.title;
  if (title != null && title.isNotEmpty) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily,
        fontSize: theme.fontSize * 1.2,
        fontWeight: 700);
    final size = measurer.measure(title, style);
    final node = SceneText(
      text: title,
      bounds: Rect.fromLTWH(bounds.center.x - size.width / 2,
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

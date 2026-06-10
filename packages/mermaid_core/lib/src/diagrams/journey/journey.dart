/// User journey diagram: model, parser and layout (compact — one file).
///
/// Reference: upstream journey jison grammar + journeyRenderer.ts.
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

class JourneyDiagram {
  const JourneyDiagram({required this.sections, this.title});

  final List<JourneySection> sections;
  final String? title;
}

class JourneySection {
  const JourneySection({required this.name, required this.tasks});

  final String name;
  final List<JourneyTask> tasks;
}

class JourneyTask {
  const JourneyTask({
    required this.name,
    required this.score,
    this.actors = const [],
  });

  final String name;

  /// 1 (bad) .. 5 (great).
  final int score;
  final List<String> actors;
}

JourneyDiagram parseJourney(String source) {
  final frontTitle = frontmatterTitle(source);
  final text = stripMetadata(source);
  String? title = frontTitle;
  final sections = <(String, List<JourneyTask>)>[];
  var seenHeader = false;

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^journey\b').hasMatch(line)) {
        throw MermaidParseException('expected "journey" header', line: i + 1);
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
      continue;
    }
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(line)) continue;

    // Task: `name : score : actor1, actor2` (actors optional).
    final colon1 = line.indexOf(':');
    if (colon1 > 0) {
      final name = line.substring(0, colon1).trim();
      final rest = line.substring(colon1 + 1).trim();
      final colon2 = rest.indexOf(':');
      final scoreText = (colon2 < 0 ? rest : rest.substring(0, colon2)).trim();
      final score = int.tryParse(scoreText);
      if (score == null) {
        throw MermaidParseException('invalid score "$scoreText"', line: i + 1);
      }
      final actors = colon2 < 0
          ? const <String>[]
          : rest
              .substring(colon2 + 1)
              .split(',')
              .map((a) => a.trim())
              .where((a) => a.isNotEmpty)
              .toList();
      if (sections.isEmpty) sections.add(('', []));
      sections.last.$2.add(JourneyTask(
          name: name, score: score.clamp(1, 5), actors: actors));
      continue;
    }
    throw MermaidParseException('unrecognized statement "$line"', line: i + 1);
  }
  if (!seenHeader) {
    throw const MermaidParseException('empty journey source');
  }
  return JourneyDiagram(
    sections: [
      for (final (name, tasks) in sections)
        if (tasks.isNotEmpty) JourneySection(name: name, tasks: tasks),
    ],
    title: title,
  );
}

const _sectionFills = [
  Color(0xffececff),
  Color(0xffffffde),
  Color(0xffd5e5cf),
  Color(0xffe5d0cf),
  Color(0xffcfd6e5),
  Color(0xffe5cfe0),
];
const _actorFills = [
  Color(0xff8a90dd),
  Color(0xffe8a33d),
  Color(0xff5fb6a9),
  Color(0xffbf6790),
  Color(0xff7fbf67),
  Color(0xff6788bf),
];

RenderScene layoutJourney(
  JourneyDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const taskWidth = 130.0;
  const taskGap = 12.0;
  final baseStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.85);
  final nodes = <SceneNode>[];

  // Actor color assignment in first-appearance order.
  final actorColor = <String, Color>{};
  for (final s in diagram.sections) {
    for (final t in s.tasks) {
      for (final a in t.actors) {
        actorColor.putIfAbsent(
            a, () => _actorFills[actorColor.length % _actorFills.length]);
      }
    }
  }

  // Legend.
  var legendY = 0.0;
  actorColor.forEach((actor, color) {
    final size = measurer.measure(actor, baseStyle);
    nodes.add(SceneGroup(id: 'actor_$actor', children: [
      SceneShape(
          geometry: CircleGeometry(Point(8, legendY + 8), 7),
          fill: Fill(color)),
      SceneText(
        text: actor,
        bounds: Rect.fromLTWH(
            22, legendY + 8 - size.height / 2, size.width, size.height),
        style: baseStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ),
    ]));
    legendY += 22;
  });

  final sectionTop = legendY + 16;
  const sectionH = 28.0;
  final taskLabelTop = sectionTop + sectionH + 8;

  // Task label block height: tallest wrapped name.
  var labelBlockH = 0.0;
  for (final s in diagram.sections) {
    for (final t in s.tasks) {
      labelBlockH = math.max(labelBlockH,
          measurer.measure(t.name, baseStyle, maxWidth: taskWidth - 10).height);
    }
  }
  final faceCenterY = taskLabelTop + labelBlockH + 36;

  var x = 0.0;
  var sectionIndex = 0;
  for (final section in diagram.sections) {
    final sectionWidth =
        section.tasks.length * (taskWidth + taskGap) - taskGap;
    final fill = _sectionFills[sectionIndex % _sectionFills.length];
    if (section.name.isNotEmpty) {
      final size = measurer.measure(section.name, baseStyle);
      nodes.add(SceneGroup(id: 'section_$sectionIndex', children: [
        SceneShape(
          geometry: RectGeometry(
              Rect.fromLTWH(x, sectionTop, sectionWidth, sectionH),
              rx: 3,
              ry: 3),
          fill: Fill(fill),
          stroke: Stroke(color: theme.nodeBorder, width: 0.7),
        ),
        SceneText(
          text: section.name,
          bounds: Rect.fromLTWH(x + sectionWidth / 2 - size.width / 2,
              sectionTop + sectionH / 2 - size.height / 2, size.width,
              size.height),
          style: baseStyle.copyWith(fontWeight: 700),
          color: theme.textColor,
        ),
      ]));
    }
    for (final t in section.tasks) {
      final cx = x + taskWidth / 2;
      final nameSize =
          measurer.measure(t.name, baseStyle, maxWidth: taskWidth - 10);
      final children = <SceneNode>[
        SceneShape(
          geometry: RectGeometry(
              Rect.fromLTWH(x, taskLabelTop, taskWidth, labelBlockH + 12),
              rx: 3,
              ry: 3),
          fill: Fill(fill),
          stroke: Stroke(color: theme.nodeBorder, width: 0.7),
        ),
        SceneText(
          text: t.name,
          bounds: Rect.fromLTWH(cx - nameSize.width / 2,
              taskLabelTop + 6, nameSize.width, nameSize.height),
          style: baseStyle,
          color: theme.textColor,
        ),
        ..._face(Point(cx, faceCenterY), t.score, theme),
      ];
      // Actor dots above the face.
      var dotX = cx - (t.actors.length - 1) * 9.0;
      for (final a in t.actors) {
        children.add(SceneShape(
          geometry: CircleGeometry(Point(dotX, faceCenterY - 32), 6),
          fill: Fill(actorColor[a]!),
        ));
        dotX += 18;
      }
      nodes.add(SceneGroup(id: 'task_${t.name}', semanticLabel: t.name,
          children: children));
      x += taskWidth + taskGap;
    }
    sectionIndex++;
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

/// Smiley face colored by score: red (<=2), yellow (3), green (>=4); mouth
/// follows the mood.
List<SceneNode> _face(Point c, int score, MermaidTheme theme) {
  final color = score <= 2
      ? const Color(0xffe57373)
      : score == 3
          ? const Color(0xffffe082)
          : const Color(0xff81c784);
  const r = 15.0;
  final mouth = switch (score) {
    <= 2 => PathGeometry([
        MoveTo(Point(c.x - 6, c.y + 8)),
        QuadTo(Point(c.x, c.y + 2), Point(c.x + 6, c.y + 8)),
      ]),
    3 => PathGeometry([
        MoveTo(Point(c.x - 6, c.y + 6)),
        LineTo(Point(c.x + 6, c.y + 6)),
      ]),
    _ => PathGeometry([
        MoveTo(Point(c.x - 6, c.y + 4)),
        QuadTo(Point(c.x, c.y + 10), Point(c.x + 6, c.y + 4)),
      ]),
  };
  return [
    SceneShape(
      geometry: CircleGeometry(c, r),
      fill: Fill(color),
      stroke: Stroke(color: theme.lineColor),
    ),
    SceneShape(
        geometry: CircleGeometry(Point(c.x - 5, c.y - 4), 1.8),
        fill: Fill(theme.lineColor)),
    SceneShape(
        geometry: CircleGeometry(Point(c.x + 5, c.y - 4), 1.8),
        fill: Fill(theme.lineColor)),
    SceneShape(
        geometry: mouth,
        stroke: Stroke(color: theme.lineColor, width: 1.5)),
  ];
}

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
    // Multi-line accDescr block: `accDescr { ... }` — skip until closing `}`.
    if (RegExp(r'^accDescr\s*\{').hasMatch(line)) {
      if (!line.contains('}')) {
        while (i + 1 < lines.length && !lines[i + 1].contains('}')) {
          i++;
        }
        if (i + 1 < lines.length) i++; // consume the closing `}` line
      }
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

// Upstream journey defaults (config.schema.yaml).
//
// Note on fills: journeyRenderer sets each section/task rect's inline fill to
// `sectionFills[n]` (dark navy/purple palette) AND gives it class
// `section-type-n` / `task-type-n`. styles.js emits `.section-type-n { fill:
// fillType<n> }` whenever `fillType0` is set — which it always is in every
// theme. A CSS class fill beats an SVG presentation attribute, so the dark
// `sectionFills` are dead: the actually-rendered fill is `theme.fillType[n]`
// (the light pastels in the default theme). The section/task TEXT element
// carries the same class, so its `fill="#fff"` presentation attribute is
// likewise overridden — the rendered text colour is also `theme.fillType[n]`.
// We therefore drive both rect fill and text colour from `theme.fillType`,
// indexed by `n = sectionIndex % 7` (sectionFills.length).
const _sectionFillCount = 7;
const _actorFills = [
  Color(0xff8FBC8F),
  Color(0xff7CFC00),
  Color(0xff00FFFF),
  Color(0xff20B2AA),
  Color(0xffB0E0E6),
  Color(0xffFFFFE0),
];

// Upstream journey layout constants (config.schema.yaml journey defaults).
const _diagramMarginX = 50.0;
const _diagramMarginY = 10.0;
const _leftMargin = 150.0;
const _boxWidth = 150.0;
const _boxHeight = 65.0;
const _taskMargin = 50.0;
const _taskFontSize = 14.0;
const _maxLabelWidth = 360.0;

RenderScene layoutJourney(
  JourneyDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  // Upstream uses a fixed pixel layout sourced from getConfig().journey.
  // taskFontFamily is '"Open Sans", sans-serif'; we keep the theme family
  // for measurement consistency but pin the size to the upstream default.
  final baseStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: _taskFontSize);
  final nodes = <SceneNode>[];

  // Actor colour assignment follows the alphabetically sorted actor set
  // (journeyDb.getActors → updateActors sorts the unique people).
  final actorSet = <String>{};
  for (final s in diagram.sections) {
    for (final t in s.tasks) {
      actorSet.addAll(t.actors);
    }
  }
  final actorNames = actorSet.toList()..sort();
  final actorColor = <String, Color>{};
  for (var p = 0; p < actorNames.length; p++) {
    actorColor[actorNames[p]] = _actorFills[p % _actorFills.length];
  }

  // Actor legend on the LEFT column. Circle cx:20, label x:40.
  // yPos starts at 60 and steps by max(20, lineCount*20). leftMargin grows
  // with the widest wrapped legend label. Upstream stores labelData.fill =
  // '#666' but svgDrawCommon.drawText never applies it; the legend <text>
  // only ever carries class "legend", so the CSS `.legend { fill: textColor }`
  // rule is the sole fill source — the rendered colour is theme.textColor.
  final legendLabelColor = theme.textColor;
  var maxLegendWidth = 0.0;
  var yPos = 60.0;
  for (final actor in actorNames) {
    final lines = _wrapLegendLabel(actor, baseStyle, measurer, _maxLabelWidth);
    nodes.add(SceneShape(
      geometry: CircleGeometry(Point(20, yPos), 7),
      fill: Fill(actorColor[actor]!),
      stroke: Stroke(color: const Color(0xff000000), width: 1),
    ));
    for (var li = 0; li < lines.length; li++) {
      final size = measurer.measure(lines[li], baseStyle);
      final ly = yPos + 7 + li * 20;
      nodes.add(SceneText(
        text: lines[li],
        bounds: Rect.fromLTWH(40, ly - size.height, size.width, size.height),
        style: baseStyle,
        color: legendLabelColor,
        align: TextAlignH.left,
      ));
      // Upstream: expand maxWidth when a line is wider than the running max.
      if (size.width > maxLegendWidth &&
          size.width > _leftMargin - size.width) {
        maxLegendWidth = size.width;
      }
    }
    yPos += math.max(20, lines.length * 20);
  }
  final leftMargin = _leftMargin + maxLegendWidth;

  // Faces hang at cy = 300 + (5-score)*30 (range 300..420); drop lines run
  // from the task box top (y=140) down to maxHeight = 300 + 5*30 = 450.
  const sectionY = 50.0;
  final taskY = _boxHeight * 2 + _diagramMarginY; // 140
  const faceBaseY = 300.0;
  const maxHeight = 300.0 + 5 * 30.0; // 450

  // Flatten tasks into a single continuous row (global index i), tracking
  // section spans. x = i*taskMargin + i*width + leftMargin.
  var globalIndex = 0;
  var lastX = leftMargin;
  var sectionIndex = 0;
  for (final section in diagram.sections) {
    final count = section.tasks.length;
    // n = sectionNumber % sectionFills.length; the CSS `.section-type-n` /
    // `.task-type-n` rule paints both rect and text with theme.fillType[n].
    final n = sectionIndex % _sectionFillCount;
    final fill = theme.fillType[n];
    final textColor = fill;
    final sectionX = globalIndex * _taskMargin + globalIndex * _boxWidth +
        leftMargin;
    if (section.name.isNotEmpty) {
      final sectionWidth =
          _boxWidth * count + _diagramMarginX * (count - 1);
      final size = measurer.measure(section.name, baseStyle);
      nodes.add(SceneGroup(id: 'section_$sectionIndex', children: [
        SceneShape(
          geometry: RectGeometry(
              Rect.fromLTWH(sectionX, sectionY, sectionWidth, _boxHeight),
              rx: 3,
              ry: 3),
          fill: Fill(fill),
        ),
        SceneText(
          text: section.name,
          bounds: Rect.fromLTWH(
              sectionX + sectionWidth / 2 - size.width / 2,
              sectionY + _boxHeight / 2 - size.height / 2,
              size.width,
              size.height),
          style: baseStyle,
          color: textColor,
        ),
      ]));
    }
    for (final t in section.tasks) {
      final taskX = globalIndex * _taskMargin + globalIndex * _boxWidth +
          leftMargin;
      final cx = taskX + _boxWidth / 2;
      final faceY = faceBaseY + (5 - t.score) * 30.0;
      final nameSize =
          measurer.measure(t.name, baseStyle, maxWidth: _boxWidth);
      final children = <SceneNode>[
        // Drop line from task box top edge down to the descender baseline.
        // Upstream draws this as a <line> with stroke "#666", but the CSS
        // `line { stroke: textColor }` rule overrides the presentation
        // attribute, so the rendered colour is theme.textColor.
        SceneShape(
          geometry: PathGeometry(
              [MoveTo(Point(cx, taskY)), LineTo(Point(cx, maxHeight))]),
          stroke: Stroke(color: theme.textColor, width: 1, dash: const [4, 2]),
        ),
        ..._face(Point(cx, faceY), t.score),
        SceneShape(
          geometry: RectGeometry(
              Rect.fromLTWH(taskX, taskY, _boxWidth, _boxHeight),
              rx: 3,
              ry: 3),
          fill: Fill(fill),
        ),
        SceneText(
          text: t.name,
          bounds: Rect.fromLTWH(cx - nameSize.width / 2,
              taskY + _boxHeight / 2 - nameSize.height / 2, nameSize.width,
              nameSize.height),
          style: baseStyle,
          color: textColor,
        ),
      ];
      // Actor dots on the task box top edge: cx start task.x+14, step 10,
      // r7, stroke black.
      var dotX = taskX + 14.0;
      for (final a in t.actors) {
        children.add(SceneShape(
          geometry: CircleGeometry(Point(dotX, taskY), 7),
          fill: Fill(actorColor[a]!),
          stroke: Stroke(color: const Color(0xff000000), width: 1),
        ));
        dotX += 10;
      }
      nodes.add(SceneGroup(
          id: 'task_${t.name}', semanticLabel: t.name, children: children));
      lastX = taskX + _boxWidth + _taskMargin;
      globalIndex++;
    }
    sectionIndex++;
  }

  // Activity line at y = height*4 = 260, from leftMargin to the right edge,
  // stroke-width 4, with a small triangular arrowhead. Upstream sets the
  // <line> stroke to "black", but the CSS `line { stroke: textColor }` rule
  // overrides it, so the rendered colour is theme.textColor. The arrowhead
  // marker path (`M 0,0 V 4 L6,2 Z`) carries no fill/class, so it renders
  // with the SVG default fill of black.
  if (globalIndex > 0) {
    const activityY = _boxHeight * 4; // 260
    final lineEnd = lastX - _taskMargin + _diagramMarginX; // ~ stopx
    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(leftMargin, activityY)),
        LineTo(Point(lineEnd, activityY)),
      ]),
      stroke: Stroke(color: theme.textColor, width: 4),
    ));
    // Arrowhead: marker path 'M 0,0 V 4 L6,2 Z' anchored at the line tip.
    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(lineEnd, activityY - 4)),
        LineTo(Point(lineEnd, activityY + 4)),
        LineTo(Point(lineEnd + 8, activityY)),
        ClosePath(),
      ]),
      fill: Fill(const Color(0xff000000)),
    ));
  }

  // Title: top-left at x = leftMargin, y = 25, bold, titleFontSize '4ex'.
  // 4ex ≈ 4 * (fontSize/2) → ~2*taskFontSize for a large heading.
  final title = diagram.title;
  if (title != null && title.isNotEmpty) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily,
        fontSize: _taskFontSize * 2,
        fontWeight: 700);
    final size = measurer.measure(title, style);
    nodes.add(SceneText(
      text: title,
      bounds: Rect.fromLTWH(leftMargin, 25 - size.height, size.width,
          size.height),
      style: style,
      color: theme.titleColor,
      align: TextAlignH.left,
    ));
  }

  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  // Upstream viewBox starts at y = -25 to leave room for the title row.
  bounds = bounds.union(const Rect.fromLTWH(0, -25, 1, 1));

  const pad = _diagramMarginY;
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

/// Knuth-plass-ish legend label wrapping at [maxWidth] with hyphenation of
/// over-long words (matches drawActorLegend).
List<String> _wrapLegendLabel(
    String text, TextStyleSpec style, TextMeasurer measurer, double maxWidth) {
  if (measurer.measure(text, style).width <= maxWidth) return [text];
  final lines = <String>[];
  var current = '';
  for (final word in text.split(' ')) {
    final test = current.isEmpty ? word : '$current $word';
    if (measurer.measure(test, style).width > maxWidth) {
      if (current.isNotEmpty) lines.add(current);
      current = word;
      // Break an over-long word with a trailing hyphen.
      if (measurer.measure(word, style).width > maxWidth) {
        var broken = '';
        for (final char in word.split('')) {
          broken += char;
          if (measurer.measure('$broken-', style).width > maxWidth) {
            lines.add('${broken.substring(0, broken.length - 1)}-');
            broken = char;
          }
        }
        current = broken;
      }
    } else {
      current = test;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.isEmpty ? [text] : lines;
}

/// Journey smiley face. Fill is a uniform cornsilk (`.face` CSS = #FFF8DC,
/// stroke #999) for every score; the mood is conveyed by the mouth only.
List<SceneNode> _face(Point c, int score) {
  const r = 15.0;
  const eyeColor = Color(0xff666666);
  // Mouth: crescent arc approximated with cubic curves. smile (>3),
  // sad (<3), flat line (==3) — upstream uses a d3 ring-arc.
  final SceneShape mouth;
  if (score > 3) {
    // Smile: downward crescent below centre (translate +2).
    mouth = SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(c.x - r / 2, c.y + 2)),
        CubicTo(Point(c.x - r / 4, c.y + 2 + r / 2),
            Point(c.x + r / 4, c.y + 2 + r / 2), Point(c.x + r / 2, c.y + 2)),
      ]),
      stroke: Stroke(color: eyeColor, width: r / 2 - r / 2.2),
    );
  } else if (score < 3) {
    // Sad: upward crescent below centre (translate +7).
    mouth = SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(c.x - r / 2, c.y + 7)),
        CubicTo(Point(c.x - r / 4, c.y + 7 - r / 2),
            Point(c.x + r / 4, c.y + 7 - r / 2), Point(c.x + r / 2, c.y + 7)),
      ]),
      stroke: Stroke(color: eyeColor, width: r / 2 - r / 2.2),
    );
  } else {
    // Ambivalent: flat line.
    mouth = SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(c.x - 5, c.y + 7)),
        LineTo(Point(c.x + 5, c.y + 7)),
      ]),
      stroke: Stroke(color: eyeColor, width: 1),
    );
  }
  return [
    SceneShape(
      geometry: CircleGeometry(c, r),
      fill: Fill(const Color(0xffFFF8DC)),
      stroke: Stroke(color: const Color(0xff999999), width: 2),
    ),
    SceneShape(
        geometry: CircleGeometry(Point(c.x - r / 3, c.y - r / 3), 1.5),
        fill: Fill(eyeColor)),
    SceneShape(
        geometry: CircleGeometry(Point(c.x + r / 3, c.y - r / 3), 1.5),
        fill: Fill(eyeColor)),
    mouth,
  ];
}

/// Ishikawa / fishbone diagram (`ishikawa-beta`): a problem head on the right
/// with category "bones" angled off a horizontal spine, each listing causes.
library;

import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

class IshikawaCategory {
  IshikawaCategory(this.name);
  final String name;
  final causes = <String>[];
}

class IshikawaDiagram {
  const IshikawaDiagram(this.problem, this.categories);
  final String problem;
  final List<IshikawaCategory> categories;
}

IshikawaDiagram parseIshikawa(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  var seenHeader = false;
  String problem = '';
  final categories = <IshikawaCategory>[];
  int? headIndent;
  int? catIndent;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c);
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*ishikawa(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "ishikawa" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    final indent = line.length - line.trimLeft().length;
    final t = line.trim();
    if (headIndent == null) {
      headIndent = indent;
      problem = t;
      continue;
    }
    catIndent ??= indent;
    if (indent <= catIndent) {
      categories.add(IshikawaCategory(t));
    } else if (categories.isNotEmpty) {
      categories.last.causes.add(t);
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty ishikawa source');
  return IshikawaDiagram(problem, categories);
}

RenderScene layoutIshikawa(
  IshikawaDiagram d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.85);
  final catStyle = baseStyle.copyWith(fontWeight: 700);
  final nodes = <SceneNode>[];

  final boneSpacing = 200.0;
  final spineY = 0.0;
  final n = d.categories.length;
  final spineLen = (n / 2).ceil() * boneSpacing + 120;
  final headX = spineLen + 20;

  // Spine.
  nodes.add(SceneShape(
    geometry: PathGeometry(
        [MoveTo(Point(0, spineY)), LineTo(Point(spineLen, spineY))]),
    stroke: Stroke(color: theme.lineColor, width: 2),
  ));
  // Head box (the problem).
  final ps = measurer.measure(d.problem, catStyle, maxWidth: 160);
  final headRect = Rect.fromLTWH(headX, spineY - ps.height / 2 - 10,
      ps.width + 24, ps.height + 20);
  nodes.add(SceneShape(
    geometry: RectGeometry(headRect, rx: 6, ry: 6),
    fill: Fill(theme.mainBkg),
    stroke: Stroke(color: theme.nodeBorder),
  ));
  nodes.add(SceneText(
    text: d.problem,
    bounds: Rect.fromCenter(headRect.center, ps.width, ps.height),
    style: catStyle,
    color: theme.textColor,
  ));

  // Bones: alternate above/below, angled toward the head.
  for (var i = 0; i < n; i++) {
    final cat = d.categories[i];
    final above = i.isEven;
    final baseX = spineLen - (i ~/ 2) * boneSpacing - 80;
    final tipX = baseX - 70;
    final tipY = spineY + (above ? -110.0 : 110.0);
    nodes.add(SceneShape(
      geometry: PathGeometry(
          [MoveTo(Point(baseX, spineY)), LineTo(Point(tipX, tipY))]),
      stroke: Stroke(color: theme.lineColor, width: 1.5),
    ));
    final cs = measurer.measure(cat.name, catStyle);
    nodes.add(SceneText(
      text: cat.name,
      bounds: Rect.fromCenter(
          Point(tipX, tipY + (above ? -10 : 10)), cs.width, cs.height),
      style: catStyle,
      color: theme.titleColor,
    ));
    // Causes listed along the bone.
    final dirY = above ? 1.0 : -1.0;
    var place = tipY + dirY * 16;
    for (final cause in cat.causes) {
      final cz = measurer.measure(cause, baseStyle, maxWidth: 150);
      final px = (baseX + tipX) / 2 + 10;
      nodes.add(SceneText(
        text: cause,
        bounds: Rect.fromLTWH(px, place - cz.height / 2, cz.width, cz.height),
        style: baseStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ));
      place += dirY * (cz.height + 6);
    }
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 200, 200);
  const m = 16.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final nd in nodes)
        translateSceneNode(nd, m - bounds.left, m - bounds.top)
    ],
  );
}

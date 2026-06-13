/// Venn diagram (`venn-beta`): named sets drawn as overlapping translucent
/// circles, with optional union labels.
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

class VennDiagram {
  const VennDiagram(this.sets, this.unions, this.title);
  final List<String> sets;

  /// Member-set list → label for `union A,B["label"]`.
  final Map<String, String> unions;
  final String? title;
}

VennDiagram parseVenn(String source) {
  final title0 = frontmatterTitle(source);
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final sets = <String>[];
  final unions = <String, String>{};
  String? title = title0;
  var seenHeader = false;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^venn(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "venn" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    var m = RegExp(r'^title\s+"?([^"]+)"?\s*$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      continue;
    }
    m = RegExp(r'^set\s+(\S+)\s*$').firstMatch(line);
    if (m != null) {
      sets.add(m.group(1)!);
      continue;
    }
    m = RegExp(r'^union\s+([\w,]+)\s*(?:\["([^"]*)"\])?\s*$').firstMatch(line);
    if (m != null) {
      unions[m.group(1)!] = m.group(2) ?? '';
      continue;
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty venn source');
  return VennDiagram(sets, unions, title);
}

const _palette = <Color>[
  Color(0xff5b8ff9),
  Color(0xfff6bd16),
  Color(0xff61ddaa),
];

RenderScene layoutVenn(
  VennDiagram d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final nodes = <SceneNode>[];
  const r = 110.0;
  final n = d.sets.length;
  // Arrange circle centers so adjacent sets overlap.
  final centers = <Point>[];
  if (n == 1) {
    centers.add(const Point(0, 0));
  } else if (n == 2) {
    centers..add(Point(-r * 0.55, 0))..add(Point(r * 0.55, 0));
  } else {
    // n>=3: place around a small circle.
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / n;
      centers.add(Point(r * 0.6 * math.cos(a), r * 0.6 * math.sin(a)));
    }
  }
  for (var i = 0; i < n; i++) {
    final color = _palette[i % _palette.length];
    nodes.add(SceneShape(
      geometry: CircleGeometry(centers[i], r),
      fill: Fill(color.withOpacity(0.35)),
      stroke: Stroke(color: color, width: 1.5),
    ));
    // Set label near the outer edge (along the center→outward direction).
    final cx = centers[i].x, cy = centers[i].y;
    final len = math.sqrt(cx * cx + cy * cy);
    final dir = len == 0 ? const Point(0, -1) : Point(cx / len, cy / len);
    final lp = Point(cx + dir.x * r * 0.6, cy + dir.y * r * 0.6);
    final ls = measurer.measure(d.sets[i], baseStyle);
    nodes.add(SceneText(
      text: d.sets[i],
      bounds: Rect.fromCenter(lp, ls.width, ls.height),
      style: baseStyle.copyWith(fontWeight: 700),
      color: theme.textColor,
    ));
  }
  // Union labels in the center.
  var uy = 0.0;
  d.unions.forEach((members, label) {
    if (label.isEmpty) return;
    final ls = measurer.measure(label, baseStyle);
    nodes.add(SceneText(
      text: label,
      bounds: Rect.fromCenter(Point(0, uy), ls.width, ls.height),
      style: baseStyle,
      color: theme.textColor,
    ));
    uy += ls.height + 4;
  });

  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(-r, -r, 2 * r, 2 * r);
  final children = [...nodes];
  if (d.title != null && d.title!.isNotEmpty) {
    final style = baseStyle.copyWith(fontWeight: 700, fontSize: theme.fontSize * 1.1);
    final ts = measurer.measure(d.title!, style);
    final node = SceneText(
      text: d.title!,
      bounds: Rect.fromLTWH(-ts.width / 2, bounds.top - ts.height - 8, ts.width, ts.height),
      style: style,
      color: theme.titleColor,
    );
    children.add(node);
    bounds = bounds.union(node.bounds);
  }
  const m = 16.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final nd in children) translateSceneNode(nd, m - bounds.left, m - bounds.top)
    ],
  );
}

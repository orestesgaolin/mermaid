/// Wardley map (`wardley-beta`): components plotted on value (y) vs evolution
/// (x) axes, linked into a value chain, with optional `evolve` shifts.
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

class WardleyComponent {
  WardleyComponent(this.name, this.x, this.y, this.anchor);
  final String name;
  final double x; // evolution 0..1
  final double y; // value 0..1
  final bool anchor;
  double? evolveTo;
}

class WardleyMap {
  const WardleyMap(this.components, this.edges, this.title);
  final List<WardleyComponent> components;
  final List<(String, String)> edges;
  final String? title;
}

WardleyMap parseWardley(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final comps = <String, WardleyComponent>{};
  final order = <WardleyComponent>[];
  final edges = <(String, String)>[];
  String? title;
  var seenHeader = false;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^wardley(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "wardley" header', line: i + 1);
      }
      seenHeader = true;
      final rest = line.replaceFirst(RegExp(r'^wardley(-beta)?\s*'), '');
      if (rest.trim().isEmpty) continue;
      line = rest.trim();
    }
    var m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      continue;
    }
    m = RegExp(r'^(anchor|component)\s+(.+?)\s*\[\s*([\d.]+)\s*,\s*([\d.]+)\s*\]$')
        .firstMatch(line);
    if (m != null) {
      final comp = WardleyComponent(m.group(2)!.trim(), double.parse(m.group(4)!),
          double.parse(m.group(3)!), m.group(1) == 'anchor');
      comps[comp.name] = comp;
      order.add(comp);
      continue;
    }
    m = RegExp(r'^(.+?)\s*->\s*(.+)$').firstMatch(line);
    if (m != null && !line.startsWith('note')) {
      edges.add((m.group(1)!.trim(), m.group(2)!.trim()));
      continue;
    }
    m = RegExp(r'^evolve\s+(.+?)\s+([\d.]+)$').firstMatch(line);
    if (m != null) {
      comps[m.group(1)!.trim()]?.evolveTo = double.parse(m.group(2)!);
      continue;
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty wardley source');
  return WardleyMap(order, edges, title);
}

RenderScene layoutWardley(
  WardleyMap map, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.8);
  final nodes = <SceneNode>[];
  const w = 540.0, h = 380.0;
  // Note: value (y) increases upward → invert.
  Point at(double ex, double vy) => Point(ex * w, (1 - vy) * h);
  final centers = {for (final c in map.components) c.name: at(c.x, c.y)};

  // Axes box.
  nodes.add(SceneShape(
    geometry: RectGeometry(const Rect.fromLTWH(0, 0, w, h)),
    stroke: Stroke(color: theme.lineColor, width: 1),
  ));
  // Evolution axis labels.
  const stages = ['Genesis', 'Custom', 'Product', 'Commodity'];
  for (var i = 0; i < 4; i++) {
    final x = w * (i + 0.5) / 4;
    final s = measurer.measure(stages[i], baseStyle);
    nodes.add(SceneText(
      text: stages[i],
      bounds: Rect.fromLTWH(x - s.width / 2, h + 6, s.width, s.height),
      style: baseStyle,
      color: theme.textColor,
    ));
  }
  // Value axis label (left).
  final vs = measurer.measure('Value', baseStyle.copyWith(fontWeight: 700));
  nodes.add(SceneText(
    text: 'Value',
    bounds: Rect.fromLTWH(-vs.width - 8, h / 2, vs.width, vs.height),
    style: baseStyle.copyWith(fontWeight: 700),
    color: theme.textColor,
  ));

  // Edges.
  for (final (from, to) in map.edges) {
    final a = centers[from], b = centers[to];
    if (a == null || b == null) continue;
    nodes.add(SceneShape(
      geometry: PathGeometry([MoveTo(a), LineTo(b)]),
      stroke: Stroke(color: theme.lineColor, width: 1),
    ));
  }

  // Components (dots + labels), and evolve arrows.
  for (final comp in map.components) {
    final c = centers[comp.name]!;
    if (comp.evolveTo != null) {
      final e = at(comp.evolveTo!, comp.y);
      nodes.add(SceneShape(
        geometry: PathGeometry([MoveTo(c), LineTo(e)]),
        stroke: const Stroke(color: Color(0xffcc3333), width: 1.5, dash: [4, 3]),
      ));
      nodes.add(SceneShape(
        geometry: CircleGeometry(e, 5),
        fill: const Fill(Color(0xffffffff)),
        stroke: const Stroke(color: Color(0xffcc3333), width: 1.5),
      ));
    }
    nodes.add(SceneShape(
      geometry: CircleGeometry(c, 6),
      fill: Fill(comp.anchor ? theme.mainBkg : const Color(0xffffffff)),
      stroke: Stroke(color: theme.nodeBorder, width: 1.5),
    ));
    final ls = measurer.measure(comp.name, baseStyle);
    nodes.add(SceneText(
      text: comp.name,
      bounds: Rect.fromLTWH(c.x + 9, c.y - ls.height / 2, ls.width, ls.height),
      style: baseStyle,
      color: theme.textColor,
      align: TextAlignH.left,
    ));
  }

  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, w, h);
  final children = [...nodes];
  if (map.title != null && map.title!.isNotEmpty) {
    final style = baseStyle.copyWith(fontWeight: 700, fontSize: theme.fontSize * 1.1);
    final ts = measurer.measure(map.title!, style);
    final node = SceneText(
      text: map.title!,
      bounds: Rect.fromLTWH(w / 2 - ts.width / 2, bounds.top - ts.height - 8,
          ts.width, ts.height),
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
      for (final n in children) translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

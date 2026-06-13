/// Cynefin framework (`cynefin-beta`): five domains (clear, complicated,
/// complex, chaotic, plus a central confusion/disorder) each listing items.
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

class CynefinDiagram {
  const CynefinDiagram(this.domains, this.title);
  final Map<String, List<String>> domains;
  final String? title;
}

CynefinDiagram parseCynefin(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final domains = <String, List<String>>{};
  String? title;
  var seenHeader = false;
  String? current;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c);
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*cynefin(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "cynefin" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    final t = line.trim();
    final tm = RegExp(r'^title\s+(.+)$').firstMatch(t);
    if (tm != null) {
      title = tm.group(1)!.trim();
      continue;
    }
    final dm = RegExp(r'^(clear|complicated|complex|chaotic|confusion|disorder)$')
        .firstMatch(t);
    if (dm != null) {
      current = dm.group(1) == 'disorder' ? 'confusion' : dm.group(1);
      domains.putIfAbsent(current!, () => []);
      continue;
    }
    // Quoted item under the current domain.
    var item = t;
    if (item.length >= 2 && item.startsWith('"') && item.endsWith('"')) {
      item = item.substring(1, item.length - 1);
    }
    if (current != null) domains[current]!.add(item);
  }
  if (!seenHeader) throw const MermaidParseException('empty cynefin source');
  return CynefinDiagram(domains, title);
}

const _w = 300.0, _h = 230.0;
const _domainFills = {
  'complex': Color(0xffe3f2fd),
  'complicated': Color(0xffe8f5e9),
  'clear': Color(0xfffff8e1),
  'chaotic': Color(0xfffce4ec),
};

RenderScene layoutCynefin(
  CynefinDiagram d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.8);
  final titleStyle = baseStyle.copyWith(fontWeight: 700);
  final nodes = <SceneNode>[];
  // Quadrant positions: complex=TL, complicated=TR, chaotic=BL, clear=BR.
  final rects = {
    'complex': const Rect.fromLTWH(0, 0, _w, _h),
    'complicated': const Rect.fromLTWH(_w, 0, _w, _h),
    'chaotic': const Rect.fromLTWH(0, _h, _w, _h),
    'clear': const Rect.fromLTWH(_w, _h, _w, _h),
  };
  rects.forEach((name, rect) {
    nodes.add(SceneShape(
      geometry: RectGeometry(rect),
      fill: Fill(_domainFills[name]!),
      stroke: Stroke(color: theme.nodeBorder),
    ));
    final ns = measurer.measure(name, titleStyle);
    nodes.add(SceneText(
      text: name[0].toUpperCase() + name.substring(1),
      bounds: Rect.fromLTWH(rect.left + 8, rect.top + 6, ns.width + 4, ns.height),
      style: titleStyle,
      color: theme.titleColor,
      align: TextAlignH.left,
    ));
    var y = rect.top + 28.0;
    for (final item in d.domains[name] ?? const []) {
      final s = measurer.measure(item, baseStyle, maxWidth: _w - 20);
      nodes.add(SceneText(
        text: item,
        bounds: Rect.fromLTWH(rect.left + 12, y, _w - 24, s.height),
        style: baseStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ));
      y += s.height + 6;
    }
  });
  // Central confusion disc.
  final confusion = d.domains['confusion'];
  if (confusion != null) {
    nodes.add(SceneShape(
      geometry: CircleGeometry(const Point(_w, _h), 46),
      fill: const Fill(Color(0xfff5f5f5)),
      stroke: Stroke(color: theme.nodeBorder),
    ));
    final cs = measurer.measure('Confusion', baseStyle);
    nodes.add(SceneText(
      text: 'Confusion',
      bounds: Rect.fromCenter(const Point(_w, _h), cs.width, cs.height),
      style: baseStyle.copyWith(fontWeight: 700),
      color: theme.textColor,
    ));
  }
  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 2 * _w, 2 * _h);
  final children = [...nodes];
  if (d.title != null && d.title!.isNotEmpty) {
    final ts = measurer.measure(d.title!, titleStyle.copyWith(fontSize: theme.fontSize * 1.1));
    final node = SceneText(
      text: d.title!,
      bounds: Rect.fromLTWH(_w - ts.width / 2, -ts.height - 10, ts.width, ts.height),
      style: titleStyle.copyWith(fontSize: theme.fontSize * 1.1),
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

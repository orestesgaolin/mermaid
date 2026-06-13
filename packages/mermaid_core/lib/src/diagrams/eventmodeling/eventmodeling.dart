/// Event modeling (`eventmodeling`): timeframe columns of typed blocks
/// (ui / cmd / evt / view…), laid out in swimlanes by block type.
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

class EmBlock {
  EmBlock(this.timeframe, this.type, this.name);
  final int timeframe;
  final String type;
  final String name;
}

class EventModeling {
  const EventModeling(this.blocks);
  final List<EmBlock> blocks;
}

EventModeling parseEventModeling(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final blocks = <EmBlock>[];
  var seenHeader = false;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^eventmodeling\b').hasMatch(line)) {
        throw MermaidParseException('expected "eventmodeling" header',
            line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    // tf NN type Name [{ ... }]
    final m = RegExp(r'^tf\s+(\d+)\s+(\w+)\s+([^\{]+?)\s*(\{.*\})?\s*$')
        .firstMatch(line);
    if (m != null) {
      blocks.add(EmBlock(
          int.parse(m.group(1)!), m.group(2)!, m.group(3)!.trim()));
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty eventmodeling source');
  return EventModeling(blocks);
}

// Lane order (top→bottom) and colors, mirroring event-modeling conventions.
const _lanes = ['ui', 'cmd', 'evt', 'view', 'rmo', 'proc'];
const _laneLabels = {
  'ui': 'UI',
  'cmd': 'Command',
  'evt': 'Event',
  'view': 'Read Model',
  'rmo': 'Read Model',
  'proc': 'Processor',
};
const _laneFills = {
  'ui': Color(0xffe0e0e0),
  'cmd': Color(0xff90caf9),
  'evt': Color(0xffffcc80),
  'view': Color(0xffa5d6a7),
  'rmo': Color(0xffa5d6a7),
  'proc': Color(0xffce93d8),
};

RenderScene layoutEventModeling(
  EventModeling d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize * 0.8);
  final nodes = <SceneNode>[];
  const colW = 150.0, laneH = 70.0, gap = 12.0, gutter = 90.0;

  // Which lanes are present, in canonical order.
  final present = _lanes.where((l) => d.blocks.any((b) => b.type == l)).toList();
  final laneY = {for (var i = 0; i < present.length; i++) present[i]: i * laneH};
  final maxTf = d.blocks.fold(0, (a, b) => b.timeframe > a ? b.timeframe : a);

  // Lane bands + labels.
  for (final l in present) {
    final y = laneY[l]!.toDouble();
    nodes.add(SceneShape(
      geometry:
          RectGeometry(Rect.fromLTWH(gutter, y, maxTf * (colW + gap), laneH)),
      fill: const Fill(Color(0x11000000)),
      stroke: const Stroke(color: Color(0xffdddddd)),
    ));
    final ls = measurer.measure(_laneLabels[l] ?? l, baseStyle.copyWith(fontWeight: 700));
    nodes.add(SceneText(
      text: _laneLabels[l] ?? l,
      bounds: Rect.fromLTWH(4, y + laneH / 2 - ls.height / 2, gutter - 8, ls.height),
      style: baseStyle.copyWith(fontWeight: 700),
      color: theme.textColor,
      align: TextAlignH.left,
    ));
  }

  for (final b in d.blocks) {
    final y = (laneY[b.type] ?? 0).toDouble();
    final x = gutter + (b.timeframe - 1) * (colW + gap) + gap / 2;
    final rect = Rect.fromLTWH(x, y + 10, colW - gap, laneH - 20);
    nodes.add(SceneShape(
      geometry: RectGeometry(rect, rx: 4, ry: 4),
      fill: Fill(_laneFills[b.type] ?? const Color(0xffeeeeee)),
      stroke: Stroke(color: theme.nodeBorder),
    ));
    final ts = measurer.measure(b.name, baseStyle, maxWidth: colW - gap - 8);
    nodes.add(SceneText(
      text: b.name,
      bounds: Rect.fromCenter(rect.center, ts.width, ts.height),
      style: baseStyle,
      color: const Color(0xff222222),
    ));
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 200, 100);
  const m = 16.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final n in nodes) translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

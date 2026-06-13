/// Kanban board (`kanban`): columns of stacked task cards. Indentation nests
/// tasks under the preceding column. Reference: upstream kanban db/renderer.
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

class KanbanColumn {
  KanbanColumn(this.title);
  final String title;
  final tasks = <String>[];
}

class KanbanBoard {
  const KanbanBoard(this.columns);
  final List<KanbanColumn> columns;
}

String _label(String s) {
  final m = RegExp(r'^[^\s\[]*\s*\[(.*)\]\s*$').firstMatch(s.trim());
  var label = m != null ? m.group(1)! : s.trim();
  if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
    label = label.substring(1, label.length - 1);
  }
  return label.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
}

KanbanBoard parseKanban(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final columns = <KanbanColumn>[];
  var seenHeader = false;
  int? columnIndent;
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    var line = raw;
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c);
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*kanban\b').hasMatch(line)) {
        throw MermaidParseException('expected "kanban" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    final indent = line.length - line.trimLeft().length;
    columnIndent ??= indent;
    if (indent <= columnIndent) {
      columns.add(KanbanColumn(_label(line)));
    } else if (columns.isNotEmpty) {
      columns.last.tasks.add(_label(line));
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty kanban source');
  return KanbanBoard(columns);
}

const _colGap = 16.0;
const _cardGap = 8.0;
const _pad = 10.0;
const _colWidth = 200.0;

const _cardFills = <Color>[
  Color(0xffeef0ff),
  Color(0xfffff3e0),
  Color(0xffe8f5e9),
  Color(0xfffce4ec),
  Color(0xffe0f7fa),
];

RenderScene layoutKanban(
  KanbanBoard board, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final titleStyle = baseStyle.copyWith(fontWeight: 700);
  final nodes = <SceneNode>[];
  const cardW = _colWidth - 2 * _pad;
  var x = 0.0;
  var maxBottom = 0.0;

  for (var ci = 0; ci < board.columns.length; ci++) {
    final col = board.columns[ci];
    final fill = _cardFills[ci % _cardFills.length];
    // Measure cards.
    final cardSizes = [
      for (final t in col.tasks) measurer.measure(t, baseStyle, maxWidth: cardW)
    ];
    final titleSize = measurer.measure(col.title, titleStyle, maxWidth: cardW);
    var h = _pad + titleSize.height + _cardGap;
    for (final s in cardSizes) {
      h += s.height + 2 * _pad + _cardGap;
    }
    h += _pad;

    // Column background.
    nodes.add(SceneShape(
      geometry: RectGeometry(Rect.fromLTWH(x, 0, _colWidth, h), rx: 6, ry: 6),
      fill: Fill(theme.clusterBkg),
      stroke: Stroke(color: theme.clusterBorder),
    ));
    // Column title.
    nodes.add(SceneText(
      text: col.title,
      bounds: Rect.fromLTWH(
          x + _pad, _pad, cardW, titleSize.height),
      style: titleStyle,
      color: theme.titleColor,
      align: TextAlignH.left,
    ));
    // Cards.
    var cy = _pad + titleSize.height + _cardGap;
    for (var ti = 0; ti < col.tasks.length; ti++) {
      final s = cardSizes[ti];
      final ch = s.height + 2 * _pad;
      nodes.add(SceneShape(
        geometry: RectGeometry(Rect.fromLTWH(x + _pad, cy, cardW, ch),
            rx: 5, ry: 5),
        fill: Fill(fill),
        stroke: Stroke(color: theme.nodeBorder),
      ));
      nodes.add(SceneText(
        text: col.tasks[ti],
        bounds: Rect.fromLTWH(x + 2 * _pad, cy + _pad, cardW - 2 * _pad, s.height),
        style: baseStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ));
      cy += ch + _cardGap;
    }
    maxBottom = math.max(maxBottom, h);
    x += _colWidth + _colGap;
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  const m = 16.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final n in nodes) translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

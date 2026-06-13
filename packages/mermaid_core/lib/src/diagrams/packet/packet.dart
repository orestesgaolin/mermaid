/// Packet diagram: model, parser and layout — one file.
///
/// Reference: upstream packet db/renderer. Fields are bit ranges
/// (`start-end: "Label"`, `start: "Label"`, or `+count: "Label"` continuing
/// from the previous field). Rendered as a 32-bit-per-row grid of labelled
/// blocks with bit-index markers, mirroring upstream's defaults
/// (bitsPerRow 32, bitWidth 32, rowHeight 32).
library;

import 'dart:math' as math;

import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

class PacketField {
  const PacketField(this.start, this.end, this.label);
  final int start;
  final int end;
  final String label;
  int get bits => end - start + 1;
}

class Packet {
  const Packet({required this.fields, this.title});
  final List<PacketField> fields;
  final String? title;
}

Packet parsePacket(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final fields = <PacketField>[];
  var seenHeader = false;
  var prevEnd = -1;
  String? bodyTitle;

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment);
    line = line.trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^packet(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "packet" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    // In-body `title ...` statement, and accessibility lines, are tolerated.
    final titleM = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (titleM != null) {
      bodyTitle = titleM.group(1)!.trim();
      continue;
    }
    if (RegExp(r'^(accTitle|accDescr)\b').hasMatch(line)) continue;
    final m = RegExp(r'^(\+?\d+)(?:\s*-\s*(\d+))?\s*:\s*"(.*)"\s*$')
        .firstMatch(line);
    if (m == null) {
      throw MermaidParseException('invalid packet field "$line"', line: i + 1);
    }
    final g1 = m.group(1)!;
    int start, end;
    if (g1.startsWith('+')) {
      final count = int.parse(g1.substring(1));
      start = prevEnd + 1;
      end = start + count - 1;
    } else {
      start = int.parse(g1);
      end = m.group(2) != null ? int.parse(m.group(2)!) : start;
    }
    if (end < start) {
      throw MermaidParseException('packet field end < start', line: i + 1);
    }
    fields.add(PacketField(start, end, m.group(3)!));
    prevEnd = end;
  }
  if (!seenHeader) throw const MermaidParseException('empty packet source');
  if (fields.isEmpty) {
    throw const MermaidParseException('packet has no fields');
  }
  return Packet(
      fields: fields, title: frontmatterTitle(source) ?? bodyTitle);
}

RenderScene layoutPacket(
  Packet diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const bitsPerRow = 32;
  const bitWidth = 30.0;
  const rowHeight = 34.0;
  const rowGap = 8.0;
  const bitLabelH = 14.0; // space above each row for bit numbers
  final labelStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize - 3);
  final bitStyle = labelStyle.copyWith(fontSize: 10);
  final nodes = <SceneNode>[];

  double rowTop(int row) => bitLabelH + row * (rowHeight + rowGap + bitLabelH);

  // Split each field at row boundaries and emit a block per segment.
  for (final f in diagram.fields) {
    var bit = f.start;
    while (bit <= f.end) {
      final row = bit ~/ bitsPerRow;
      final rowEndBit = (row + 1) * bitsPerRow - 1;
      final segEnd = math.min(f.end, rowEndBit);
      final colStart = bit % bitsPerRow;
      final x = colStart * bitWidth;
      final y = rowTop(row);
      final w = (segEnd - bit + 1) * bitWidth;
      final rect = Rect.fromLTWH(x, y, w, rowHeight);

      final children = <SceneNode>[
        SceneShape(
          geometry: RectGeometry(rect),
          fill: Fill(theme.mainBkg),
          stroke: Stroke(color: theme.nodeBorder, width: 1),
        ),
        SceneText(
          text: f.label,
          bounds: rect,
          style: labelStyle,
          color: theme.textColor,
        ),
        // Start bit number at the segment's top-left.
        SceneText(
          text: '$bit',
          bounds: Rect.fromLTWH(x, y - bitLabelH, 24, bitLabelH),
          style: bitStyle,
          color: theme.textColor,
          align: TextAlignH.left,
        ),
      ];
      // End bit number at the top-right, if the segment is more than one bit.
      if (segEnd != bit) {
        children.add(SceneText(
          text: '$segEnd',
          bounds: Rect.fromLTWH(x + w - 24, y - bitLabelH, 24, bitLabelH),
          style: bitStyle,
          color: theme.textColor,
          align: TextAlignH.right,
        ));
      }
      nodes.add(SceneGroup(
          id: 'packet_${f.start}_$bit', semanticLabel: f.label, children: children));
      bit = segEnd + 1;
    }
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  const pad = 12.0;
  final out = <SceneNode>[];

  // Optional title above the grid.
  if (diagram.title != null && diagram.title!.isNotEmpty) {
    final titleStyle =
        labelStyle.copyWith(fontWeight: 700, fontSize: theme.fontSize);
    final size = measurer.measure(diagram.title!, titleStyle, maxWidth: 100000);
    out.add(SceneText(
      text: diagram.title!,
      bounds: Rect.fromLTWH(bounds.left, bounds.top - pad - size.height,
          bounds.width, size.height),
      style: titleStyle,
      color: theme.titleColor,
    ));
  }
  out.addAll(nodes);

  final full = sceneBounds(out) ?? bounds;
  final dx = pad - full.left;
  final dy = pad - full.top;
  return RenderScene(
    size: Size(full.width + 2 * pad, full.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in out) translateSceneNode(n, dx, dy)],
  );
}

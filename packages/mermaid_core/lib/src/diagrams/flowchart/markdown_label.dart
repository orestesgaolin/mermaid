import '../../color.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';

/// A measured single-line Mermaid Markdown label.
class MarkdownLabelLayout {
  const MarkdownLabelLayout({
    required this.plainText,
    required this.runs,
    required this.size,
  });

  final String plainText;
  final List<MarkdownLabelRun> runs;
  final Size size;

  List<SceneNode> render(Point center, Color color) {
    var x = center.x - size.width / 2;
    final nodes = <SceneNode>[];
    for (final run in runs) {
      nodes.add(
        SceneText(
          text: run.text,
          bounds: Rect.fromLTWH(
            x,
            center.y - run.size.height / 2,
            run.size.width,
            run.size.height,
          ),
          style: run.style,
          color: color,
        ),
      );
      x += run.size.width;
    }
    return nodes;
  }
}

class MarkdownLabelRun {
  const MarkdownLabelRun(this.text, this.style, this.size);

  final String text;
  final TextStyleSpec style;
  final Size size;
}

/// Parses and measures `**bold**` spans in Mermaid Markdown-string labels.
///
/// Mermaid also supports richer Markdown constructs. This deliberately starts
/// with strong emphasis, which is the inline styling used by flowchart labels
/// in the Flutter website integration.
MarkdownLabelLayout layoutMarkdownLabel(
  String label,
  TextStyleSpec baseStyle,
  TextMeasurer measurer,
) {
  final parts = <(String, bool)>[];
  var offset = 0;
  while (offset < label.length) {
    final open = label.indexOf('**', offset);
    if (open < 0) {
      parts.add((label.substring(offset), false));
      break;
    }
    if (open > offset) parts.add((label.substring(offset, open), false));
    final close = label.indexOf('**', open + 2);
    if (close < 0) {
      parts.add((label.substring(open), false));
      break;
    }
    if (close > open + 2) {
      parts.add((label.substring(open + 2, close), true));
    }
    offset = close + 2;
  }
  if (parts.isEmpty) parts.add((label, false));

  final runs = <MarkdownLabelRun>[];
  var width = 0.0;
  var height = 0.0;
  for (final (text, bold) in parts) {
    if (text.isEmpty) continue;
    final style = bold ? baseStyle.copyWith(fontWeight: 700) : baseStyle;
    final size = measurer.measure(text, style);
    runs.add(MarkdownLabelRun(text, style, size));
    width += size.width;
    if (size.height > height) height = size.height;
  }
  return MarkdownLabelLayout(
    plainText: parts.map((part) => part.$1).join(),
    runs: runs,
    size: Size(width, height),
  );
}

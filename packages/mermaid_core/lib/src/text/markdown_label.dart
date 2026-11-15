import '../color.dart';
import '../geometry.dart';
import '../ir/scene.dart';
import 'label_text.dart';

export 'label_text.dart';
import 'text_measurer.dart';
import 'text_style.dart';

/// A measured label made of styled inline runs.
///
/// Produced for Mermaid Markdown-string labels (`**bold**`) and for labels
/// that use the HTML emphasis tags `<b>`/`<strong>` and `<i>`/`<em>`, from
/// the spans of their [LabelText].
class MarkdownLabelLayout {
  const MarkdownLabelLayout({
    required this.plainText,
    required this.lines,
    required this.size,
  });

  /// The label text without markup, with its hard line breaks as `\n`.
  /// Soft wraps are not included, so it reads as the source label does.
  final String plainText;

  /// Painted lines, top to bottom, after hard breaks and wrapping.
  final List<MarkdownLabelLine> lines;
  final Size size;

  /// All runs of all lines, in reading order.
  List<MarkdownLabelRun> get runs => [for (final line in lines) ...line.runs];

  /// Scene text nodes for the label block centered on [center]. Each line
  /// is centered horizontally, as mermaid.js centers HTML labels, or starts
  /// at the block's left edge or ends at its right edge for [align]
  /// [TextAlignH.left] or [TextAlignH.right].
  List<SceneNode> render(
    Point center,
    Color color, {
    TextAlignH align = TextAlignH.center,
  }) {
    final nodes = <SceneNode>[];
    var y = center.y - size.height / 2;
    for (final line in lines) {
      final lineLeft = switch (align) {
        TextAlignH.left => center.x - size.width / 2,
        TextAlignH.center => center.x - line.size.width / 2,
        TextAlignH.right => center.x + size.width / 2 - line.size.width,
      };
      // Painted runs with their start and their text including spaces. A
      // run of only spaces is not painted; its text joins the run before it
      // (or the first painted run, at the line start).
      final painted = <(MarkdownLabelRun, double, StringBuffer)>[];
      var leading = '';
      var x = lineLeft;
      for (final run in line.runs) {
        if (run.paintText.isNotEmpty) {
          painted.add((run, x, StringBuffer(leading)..write(run.text)));
          leading = '';
        } else if (painted.isEmpty) {
          leading += run.text;
        } else {
          painted.last.$3.write(run.text);
        }
        x += run.size.width;
      }
      for (var i = 0; i < painted.length; i++) {
        final (run, runX, text) = painted[i];
        final left = runX + run.paintOffset;
        nodes.add(
          SceneText(
            text: run.paintText,
            bounds: Rect.fromLTWH(
              left,
              y + (line.size.height - run.size.height) / 2,
              run.paintWidth,
              run.size.height,
            ),
            style: run.style,
            color: color,
            run: SceneTextRun(
              index: i,
              count: painted.length,
              text: text.toString(),
              lineLeft: lineLeft - left,
              lineWidth: line.size.width,
              lineAlign: align,
            ),
          ),
        );
      }
      y += line.size.height;
    }
    return nodes;
  }
}

/// One painted line of a [MarkdownLabelLayout].
class MarkdownLabelLine {
  const MarkdownLabelLine(this.runs, this.size);

  final List<MarkdownLabelRun> runs;
  final Size size;
}

class MarkdownLabelRun {
  MarkdownLabelRun(
    this.text,
    this.style,
    this.size, {
    String? paintText,
    this.paintOffset = 0,
    double? paintWidth,
  }) : paintText = paintText ?? text,
       paintWidth = paintWidth ?? size.width;

  /// The run text, including spaces at its ends; [size] measures all of it.
  final String text;
  final TextStyleSpec style;
  final Size size;

  /// [text] without spaces at its ends. SVG `<text>` drops those spaces, so
  /// the run paints only this part, at [paintOffset] from the run start and
  /// [paintWidth] wide, and both backends place the glyphs alike.
  final String paintText;
  final double paintOffset;
  final double paintWidth;
}

MarkdownLabelRun _measureRun(
  String text,
  TextStyleSpec style,
  TextMeasurer measurer,
) {
  final size = measurer.measure(text, style);
  final trimmed = text.trim();
  if (trimmed.length == text.length) {
    return MarkdownLabelRun(text, style, size);
  }
  if (trimmed.isEmpty) {
    return MarkdownLabelRun(text, style, size, paintText: '', paintWidth: 0);
  }
  final leading = text.substring(0, text.indexOf(trimmed));
  return MarkdownLabelRun(
    text,
    style,
    size,
    paintText: trimmed,
    paintOffset: leading.isEmpty ? 0 : measurer.measure(leading, style).width,
    paintWidth: measurer.measure(trimmed, style).width,
  );
}

/// [layoutStyledLabel] for a label with a bold or italic part, or null for
/// a label without one, which keeps its plain text path. [wrappingWidth]
/// has the meaning of `TextMeasurer.measure`'s `maxWidth`.
MarkdownLabelLayout? layoutHtmlLabel(
  LabelText label,
  TextStyleSpec baseStyle,
  TextMeasurer measurer, {
  double? wrappingWidth,
}) => label.isStyled
    ? layoutStyledLabel(
        label,
        baseStyle,
        measurer,
        wrappingWidth: wrappingWidth,
      )
    : null;

/// Measures the spans of [label] as styled runs, one painted line for each
/// line of the label.
///
/// When [wrappingWidth] is set, a line wider than it wraps at whitespace,
/// like the `white-space: break-spaces` HTML label of mermaid.js. A single
/// word wider than the limit stays on its own line.
MarkdownLabelLayout layoutStyledLabel(
  LabelText label,
  TextStyleSpec baseStyle,
  TextMeasurer measurer, {
  double? wrappingWidth,
}) {
  final hardLines = label.lines;
  final bold = baseStyle.copyWith(fontWeight: 700);
  final italic = baseStyle.copyWith(italic: true);
  final boldItalic = bold.copyWith(italic: true);
  TextStyleSpec styleOf(LabelSpan span) => span.bold
      ? (span.italic ? boldItalic : bold)
      : (span.italic ? italic : baseStyle);

  final emptyHeight = measurer.measure('', baseStyle).height;
  final lines = <MarkdownLabelLine>[];
  var width = 0.0;
  var height = 0.0;
  for (final hardLine in hardLines) {
    for (final spans in _wrapSpans(
      hardLine,
      styleOf,
      measurer,
      wrappingWidth,
    )) {
      final runs = <MarkdownLabelRun>[];
      var lineWidth = 0.0;
      var lineHeight = 0.0;
      for (final span in _mergeSpans(spans)) {
        if (span.text.isEmpty) continue;
        final run = _measureRun(span.text, styleOf(span), measurer);
        runs.add(run);
        lineWidth += run.size.width;
        if (run.size.height > lineHeight) lineHeight = run.size.height;
      }
      if (runs.isEmpty) lineHeight = emptyHeight;
      lines.add(MarkdownLabelLine(runs, Size(lineWidth, lineHeight)));
      if (lineWidth > width) width = lineWidth;
      height += lineHeight;
    }
  }
  return MarkdownLabelLayout(
    plainText: label.text,
    lines: lines,
    size: Size(width, height),
  );
}

/// Joins adjacent spans with the same style into one run.
List<LabelSpan> _mergeSpans(List<LabelSpan> spans) {
  final out = <LabelSpan>[];
  for (final span in spans) {
    if (out.isNotEmpty &&
        out.last.bold == span.bold &&
        out.last.italic == span.italic) {
      out.last = LabelSpan(
        out.last.text + span.text,
        bold: span.bold,
        italic: span.italic,
      );
    } else {
      out.add(span);
    }
  }
  return out;
}

final _whitespaceOrWord = RegExp(r'\s+|\S+');

/// Greedy whitespace wrap of one hard line of spans.
List<List<LabelSpan>> _wrapSpans(
  List<LabelSpan> line,
  TextStyleSpec Function(LabelSpan) styleOf,
  TextMeasurer measurer,
  double? wrappingWidth,
) {
  if (wrappingWidth == null || line.isEmpty) return [line];
  double widthOf(List<LabelSpan> spans) {
    var w = 0.0;
    for (final s in spans) {
      if (s.text.isNotEmpty) w += measurer.measure(s.text, styleOf(s)).width;
    }
    return w;
  }

  if (widthOf(line) <= wrappingWidth) return [line];

  // Words may cross style boundaries (`<b>foo</b>bar` is one word); a break
  // is allowed only at whitespace.
  final words = <List<LabelSpan>>[];
  final gaps = <List<LabelSpan>>[]; // Whitespace before each word.
  var pendingGap = <LabelSpan>[];
  List<LabelSpan>? word;
  for (final span in line) {
    for (final m in _whitespaceOrWord.allMatches(span.text)) {
      final piece = LabelSpan(m[0]!, bold: span.bold, italic: span.italic);
      if (piece.text.trim().isEmpty) {
        word = null;
        pendingGap.add(piece);
      } else if (word == null) {
        word = [piece];
        words.add(word);
        gaps.add(pendingGap);
        pendingGap = [];
      } else {
        word.add(piece);
      }
    }
  }

  final out = <List<LabelSpan>>[];
  var current = <LabelSpan>[];
  var currentWidth = 0.0;
  for (var w = 0; w < words.length; w++) {
    final wordWidth = widthOf(words[w]);
    if (current.isEmpty) {
      current.addAll(words[w]);
      currentWidth = wordWidth;
      continue;
    }
    final gapWidth = widthOf(gaps[w]);
    if (currentWidth + gapWidth + wordWidth > wrappingWidth) {
      out.add(current);
      current = [...words[w]];
      currentWidth = wordWidth;
    } else {
      current
        ..addAll(gaps[w])
        ..addAll(words[w]);
      currentWidth += gapWidth + wordWidth;
    }
  }
  if (current.isNotEmpty) out.add(current);
  return out.isEmpty ? [line] : out;
}

/// Measures and paints diagram labels.
///
/// A label without styles keeps the plain path: one [TextMeasurer.measure]
/// call and one [SceneText]. A label with a bold or italic part is laid out
/// once with [layoutStyledLabel] and painted as styled runs, so the measured
/// size is the size of the runs that paint.
class RichLabels {
  RichLabels(this.measurer);

  final TextMeasurer measurer;
  final _cache = <(LabelText, TextStyleSpec, double?), MarkdownLabelLayout>{};

  /// The styled-run layout of [label], or null when it has no styles.
  MarkdownLabelLayout? layout(
    LabelText label,
    TextStyleSpec style, {
    double? maxWidth,
  }) => label.isStyled
      ? _cache.putIfAbsent(
          (label, style, maxWidth),
          () => layoutStyledLabel(
            label,
            style,
            measurer,
            wrappingWidth: maxWidth,
          ),
        )
      : null;

  /// The size [paint] fills for [label].
  Size measure(LabelText label, TextStyleSpec style, {double? maxWidth}) =>
      layout(label, style, maxWidth: maxWidth)?.size ??
      measurer.measure(label.text, style, maxWidth: maxWidth);

  /// Scene nodes for [label] inside [bounds]: the styled runs, aligned in
  /// [bounds] as [align] says, or one [SceneText] for a plain label.
  /// [maxWidth] must be the value [measure] used.
  List<SceneNode> paint(
    LabelText label, {
    required Rect bounds,
    required TextStyleSpec style,
    required Color color,
    double? maxWidth,
    TextAlignH align = TextAlignH.center,
  }) {
    final rich = layout(label, style, maxWidth: maxWidth);
    if (rich == null) {
      return [
        SceneText(
          text: label.text,
          bounds: bounds,
          style: style,
          color: color,
          align: align,
        ),
      ];
    }
    final half = rich.size.width / 2;
    final x = switch (align) {
      TextAlignH.left => bounds.left + half,
      TextAlignH.center => bounds.center.x,
      TextAlignH.right => bounds.right - half,
    };
    return rich.render(Point(x, bounds.center.y), color, align: align);
  }
}

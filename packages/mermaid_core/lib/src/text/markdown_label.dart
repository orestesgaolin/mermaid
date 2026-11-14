import '../color.dart';
import '../geometry.dart';
import '../ir/scene.dart';
import 'label_markup.dart';

export 'label_markup.dart' show hasLabelMarkup, plainLabelText;
import 'text_measurer.dart';
import 'text_style.dart';

/// A measured label made of styled inline runs.
///
/// Produced for Mermaid Markdown-string labels (`**bold**`) and for labels
/// that use the HTML emphasis tags `<b>`/`<strong>` and `<i>`/`<em>`.
/// `normalizeHtmlTags` (`html_tags.dart`) canonicalizes those tags to
/// `<b>`/`</b>` and `<i>`/`</i>` and removes every other tag, so only those
/// four tags reach this layout.
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

/// [layoutMarkdownLabel] for a label that uses the canonical `<b>`/`<i>`
/// emphasis tags, or null for a label without them, which keeps its plain
/// text path. [wrappingWidth] has the meaning of `TextMeasurer.measure`'s
/// `maxWidth`.
MarkdownLabelLayout? layoutHtmlLabel(
  String label,
  TextStyleSpec baseStyle,
  TextMeasurer measurer, {
  double? wrappingWidth,
}) => hasLabelMarkup(label)
    ? layoutMarkdownLabel(
        label,
        baseStyle,
        measurer,
        markdown: false,
        wrappingWidth: wrappingWidth,
      )
    : null;

/// Parses and measures a styled label.
///
/// Recognizes `**bold**` spans when [markdown] is true, and the canonical
/// `<b>`/`<i>` emphasis tags in any label. `\n` starts a new line. When
/// [wrappingWidth] is set, a line wider than it wraps at whitespace, like the
/// `white-space: break-spaces` HTML label of mermaid.js. A single word wider
/// than the limit stays on its own line.
MarkdownLabelLayout layoutMarkdownLabel(
  String label,
  TextStyleSpec baseStyle,
  TextMeasurer measurer, {
  bool markdown = true,
  double? wrappingWidth,
}) {
  final hardLines = _parseSpans(label, markdown);
  final bold = baseStyle.copyWith(fontWeight: 700);
  final italic = baseStyle.copyWith(italic: true);
  final boldItalic = bold.copyWith(italic: true);
  TextStyleSpec styleOf(_Span span) => span.bold
      ? (span.italic ? boldItalic : bold)
      : (span.italic ? italic : baseStyle);

  final emptyHeight = measurer.measure('', baseStyle).height;
  final lines = <MarkdownLabelLine>[];
  final plain = StringBuffer();
  var width = 0.0;
  var height = 0.0;
  for (final hardLine in hardLines) {
    if (!identical(hardLine, hardLines.first)) plain.write('\n');
    for (final span in hardLine) {
      plain.write(span.text);
    }
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
    plainText: plain.toString(),
    lines: lines,
    size: Size(width, height),
  );
}

class _Span {
  const _Span(this.text, this.bold, this.italic);

  final String text;
  final bool bold;
  final bool italic;
}

/// Splits [label] into hard lines of styled spans.
List<List<_Span>> _parseSpans(String label, bool markdown) {
  final lines = <List<_Span>>[[]];
  final buffer = StringBuffer();
  var boldDepth = 0;
  var italicDepth = 0;
  var markdownBold = false;
  void flush() {
    if (buffer.isEmpty) return;
    lines.last.add(
      _Span(buffer.toString(), boldDepth > 0 || markdownBold, italicDepth > 0),
    );
    buffer.clear();
  }

  var i = 0;
  while (i < label.length) {
    final c = label.codeUnitAt(i);
    if (c == 0x0a) {
      flush();
      lines.add([]);
      i++;
      continue;
    }
    if (c == 0x3c) {
      final tag = emphasisTagAt(label, i);
      if (tag != null) {
        flush();
        final (length, isBold, closing) = tag;
        // A stray closing tag is ignored, as an HTML parser ignores it.
        if (isBold) {
          if (!closing) {
            boldDepth++;
          } else if (boldDepth > 0) {
            boldDepth--;
          }
        } else {
          if (!closing) {
            italicDepth++;
          } else if (italicDepth > 0) {
            italicDepth--;
          }
        }
        i += length;
        continue;
      }
      // A `<` marked as text: keep the `<`, drop the mark.
      if (label.startsWith(literalLtMark, i + 1)) {
        buffer.writeCharCode(c);
        i += 1 + literalLtMark.length;
        continue;
      }
    }
    // `**` opens strong emphasis only when a closing `**` follows; an
    // unmatched delimiter stays literal text.
    if (markdown &&
        c == 0x2a &&
        label.startsWith('**', i) &&
        (markdownBold || label.indexOf('**', i + 2) >= 0)) {
      flush();
      markdownBold = !markdownBold;
      i += 2;
      continue;
    }
    buffer.writeCharCode(c);
    i++;
  }
  flush();
  return lines;
}

/// Joins adjacent spans with the same style into one run.
List<_Span> _mergeSpans(List<_Span> spans) {
  final out = <_Span>[];
  for (final span in spans) {
    if (out.isNotEmpty &&
        out.last.bold == span.bold &&
        out.last.italic == span.italic) {
      out.last = _Span(out.last.text + span.text, span.bold, span.italic);
    } else {
      out.add(span);
    }
  }
  return out;
}

final _whitespaceOrWord = RegExp(r'\s+|\S+');

/// Greedy whitespace wrap of one hard line of spans.
List<List<_Span>> _wrapSpans(
  List<_Span> line,
  TextStyleSpec Function(_Span) styleOf,
  TextMeasurer measurer,
  double? wrappingWidth,
) {
  if (wrappingWidth == null || line.isEmpty) return [line];
  double widthOf(List<_Span> spans) {
    var w = 0.0;
    for (final s in spans) {
      if (s.text.isNotEmpty) w += measurer.measure(s.text, styleOf(s)).width;
    }
    return w;
  }

  if (widthOf(line) <= wrappingWidth) return [line];

  // Words may cross style boundaries (`<b>foo</b>bar` is one word); a break
  // is allowed only at whitespace.
  final words = <List<_Span>>[];
  final gaps = <List<_Span>>[]; // Whitespace before each word.
  var pendingGap = <_Span>[];
  List<_Span>? word;
  for (final span in line) {
    for (final m in _whitespaceOrWord.allMatches(span.text)) {
      final piece = _Span(m[0]!, span.bold, span.italic);
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

  final out = <List<_Span>>[];
  var current = <_Span>[];
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

/// Measures and paints diagram labels that may carry the canonical
/// `<b>`/`<i>` emphasis tags from `normalizeHtmlTags`.
///
/// A label without tags keeps the plain path: one [TextMeasurer.measure]
/// call and one [SceneText]. A label with tags is laid out once with
/// [layoutMarkdownLabel] and painted as styled runs, so the measured size is
/// the size of the runs that paint.
class RichLabels {
  RichLabels(this.measurer);

  final TextMeasurer measurer;
  final _cache = <(String, TextStyleSpec, double?), MarkdownLabelLayout?>{};

  /// The styled-run layout of [text], or null when it has no emphasis tags.
  MarkdownLabelLayout? layout(
    String text,
    TextStyleSpec style, {
    double? maxWidth,
  }) => _cache.putIfAbsent((
    text,
    style,
    maxWidth,
  ), () => layoutHtmlLabel(text, style, measurer, wrappingWidth: maxWidth));

  /// The size [paint] fills for [text].
  Size measure(String text, TextStyleSpec style, {double? maxWidth}) =>
      layout(text, style, maxWidth: maxWidth)?.size ??
      measurer.measure(text, style, maxWidth: maxWidth);

  /// Scene nodes for [text] inside [bounds]: the styled runs, aligned in
  /// [bounds] as [align] says, or one [SceneText] for a plain label.
  /// [maxWidth] must be the value [measure] used.
  List<SceneNode> paint(
    String text, {
    required Rect bounds,
    required TextStyleSpec style,
    required Color color,
    double? maxWidth,
    TextAlignH align = TextAlignH.center,
  }) {
    final rich = layout(text, style, maxWidth: maxWidth);
    if (rich == null) {
      return [
        SceneText(
          text: text,
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

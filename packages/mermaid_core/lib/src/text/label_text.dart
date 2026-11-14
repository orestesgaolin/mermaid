/// The text of a diagram label after parsing.
library;

/// A piece of label text with one style.
class LabelSpan {
  const LabelSpan(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;

  @override
  bool operator ==(Object other) =>
      other is LabelSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(text, bold, italic);

  @override
  String toString() =>
      'LabelSpan($text${bold ? ', bold' : ''}${italic ? ', italic' : ''})';
}

/// A diagram label: plain text, or lines of spans when a part of it is bold
/// or italic.
///
/// Parsers make it from the label source: `<br>` is a line break, `<b>` and
/// `<i>` (and `**` in a Markdown string) set the style of a span, and entity
/// codes (`#quot;`, `&lt;`) are the character. [text] has no markup, so a
/// `<` in it is always text.
class LabelText {
  /// A label without bold or italic parts. `\n` in [text] is a line break.
  const LabelText(this.text) : _lines = null;

  LabelText._styled(this.text, List<List<LabelSpan>> lines) : _lines = lines;

  /// A label made of [lines] of spans. Empty spans are dropped and adjacent
  /// spans with the same style are joined.
  factory LabelText.styled(List<List<LabelSpan>> lines) {
    final merged = <List<LabelSpan>>[];
    final text = StringBuffer();
    var styled = false;
    for (final line in lines) {
      if (merged.isNotEmpty) text.write('\n');
      final out = <LabelSpan>[];
      for (final span in line) {
        if (span.text.isEmpty) continue;
        text.write(span.text);
        styled = styled || span.bold || span.italic;
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
      merged.add(List.unmodifiable(out));
    }
    final plain = text.toString();
    return styled
        ? LabelText._styled(plain, List.unmodifiable(merged))
        : LabelText(plain);
  }

  static const empty = LabelText('');

  /// The label without styles; `\n` is a line break. This is the text a
  /// reader hears (semantic labels).
  final String text;

  final List<List<LabelSpan>>? _lines;

  /// Whether a part of the label is bold or italic.
  bool get isStyled => _lines != null;

  bool get isEmpty => text.isEmpty;
  bool get isNotEmpty => text.isNotEmpty;

  /// The lines of the label, each a list of spans. A plain label has one
  /// span for each line that is not empty.
  List<List<LabelSpan>> get lines =>
      _lines ??
      [
        for (final line in text.split('\n'))
          line.isEmpty ? const [] : [LabelSpan(line)],
      ];

  /// This label with the plain text [prefix] before it.
  LabelText withPrefix(String prefix) {
    final lines = _lines;
    if (lines == null) return LabelText('$prefix$text');
    return LabelText.styled([
      [LabelSpan(prefix), ...lines.first],
      ...lines.skip(1),
    ]);
  }

  /// This label with the lines of [more] after its last line.
  LabelText withLines(LabelText more) => isStyled || more.isStyled
      ? LabelText.styled([...lines, ...more.lines])
      : LabelText('$text\n${more.text}');

  @override
  bool operator ==(Object other) {
    if (other is! LabelText || other.text != text) return false;
    final a = _lines, b = other._lines;
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    final lines = _lines;
    return lines == null
        ? text.hashCode
        : Object.hash(text, Object.hashAll(lines.expand((line) => line)));
  }

  @override
  String toString() => isStyled ? 'LabelText($lines)' : 'LabelText($text)';
}

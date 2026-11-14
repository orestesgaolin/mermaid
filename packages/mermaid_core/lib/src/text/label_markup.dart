/// The markup that a normalized diagram label can hold.
///
/// `normalizeHtmlTags` (`html_tags.dart`) reduces label HTML to the canonical
/// emphasis tags `<b>`, `</b>`, `<i>` and `</i>`. `layoutMarkdownLabel`
/// (`markdown_label.dart`) paints them as bold and italic runs.
library;

/// Follows a `<` in a normalized label that is text although the characters
/// after it read as a canonical emphasis tag (`#lt;b#gt;` decodes to the text
/// `<b>`). U+2060 WORD JOINER has no width. `layoutMarkdownLabel` and
/// [plainLabelText] remove it.
const literalLtMark = '⁠';

const _literalLt = '<$literalLtMark';

/// A canonical emphasis tag.
final emphasisTag = RegExp(r'</?[bi]>');

/// A `<` that starts a canonical emphasis tag.
final emphasisTagStart = RegExp(r'<(?=/?[bi]>)');

/// `(length, isBold, closing)` for a canonical emphasis tag at [i] of [s],
/// or null when there is none.
(int, bool, bool)? emphasisTagAt(String s, int i) {
  if (s.startsWith('<b>', i)) return (3, true, false);
  if (s.startsWith('</b>', i)) return (4, true, true);
  if (s.startsWith('<i>', i)) return (3, false, false);
  if (s.startsWith('</i>', i)) return (4, false, true);
  return null;
}

/// The canonical emphasis tag for the HTML element [bold] (`b`/`strong`) or
/// italic (`i`/`em`).
String canonicalEmphasisTag({required bool bold, required bool closing}) =>
    bold ? (closing ? '</b>' : '<b>') : (closing ? '</i>' : '<i>');

/// Marks each `<` of [text] that would read as a canonical emphasis tag as
/// text, with [literalLtMark].
String markLiteralLt(String text) =>
    text.contains('<') ? text.replaceAll(emphasisTagStart, _literalLt) : text;

/// Whether the normalized [label] holds markup that `layoutMarkdownLabel`
/// reads: an emphasis tag, which becomes a styled run, or a `<` marked as
/// text with [literalLtMark].
bool hasLabelMarkup(String label) =>
    label.contains('<') &&
    (emphasisTag.hasMatch(label) || label.contains(_literalLt));

/// The normalized [label] without its markup: the text a reader hears (for
/// semantic labels).
String plainLabelText(String label) => hasLabelMarkup(label)
    ? label.replaceAll(emphasisTag, '').replaceAll(_literalLt, '<')
    : label;

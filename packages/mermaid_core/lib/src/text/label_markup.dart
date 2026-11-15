/// The markup of a label between `normalizeHtmlTags` and `parseLabelMarkup`
/// (`html_tags.dart`): the canonical emphasis tags `<b>`, `</b>`, `<i>` and
/// `</i>`.
library;

/// A canonical emphasis tag.
final emphasisTag = RegExp(r'</?[bi]>');

/// `(length, isBold, closing)` for a canonical emphasis tag at [i] of [s],
/// or null when there is none.
(int, bool, bool)? emphasisTagAt(String s, int i) {
  if (s.startsWith('<b>', i)) return (3, true, false);
  if (s.startsWith('</b>', i)) return (4, true, true);
  if (s.startsWith('<i>', i)) return (3, false, false);
  if (s.startsWith('</i>', i)) return (4, false, true);
  return null;
}

/// The canonical emphasis tag for a bold (`b`/`strong`) or an italic
/// (`i`/`em`) HTML element.
String canonicalEmphasisTag({required bool bold, required bool closing}) =>
    bold ? (closing ? '</b>' : '<b>') : (closing ? '</i>' : '<i>');

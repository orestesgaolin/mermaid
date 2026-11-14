/// Inline HTML in diagram labels, reduced to what the label layout paints.
library;

import 'label_markup.dart';

/// `<br>`, `<br/>` or `<br />`: a line break in a label.
final htmlLineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);

/// An HTML comment or an opening/closing/self-closing HTML tag in a label.
final _htmlMarkup = RegExp(
  r'<!--[\s\S]*?-->|<(/?)([A-Za-z][A-Za-z0-9-]*)(?:\s[^<>]*)?/?>',
);

/// Elements whose content DOMPurify (mermaid.js `sanitizeText`) removes
/// together with the element. Other unknown elements keep their text.
const _droppedContentTags = {
  'script',
  'style',
  'iframe',
  'noscript',
  'noembed',
  'noframes',
  'template',
  'title',
  'xmp',
};

/// Mirrors how mermaid.js shows label HTML (htmlLabels, default
/// `securityLevel: strict`): `sanitizeText` keeps the markup and the browser
/// renders it. The emphasis tags `<b>`/`<strong>` and `<i>`/`<em>` become
/// the canonical `<b>`/`<i>` that `layoutMarkdownLabel` paints as bold and
/// italic runs. Every other tag is removed and its text kept, as the browser
/// shows the text of an element it does not style here; script-like elements
/// lose their text too, as DOMPurify removes it. A `<` that does not start a
/// tag (`a < b`) stays literal text.
///
/// Call it after `<br>` became `\n`: `<br>` is removed here like any other
/// tag.
String normalizeHtmlTags(String s) {
  if (!s.contains('<')) return s;
  final out = StringBuffer();
  var pos = 0;
  while (pos < s.length) {
    final m = _htmlMarkup.allMatches(s, pos).firstOrNull;
    if (m == null) break;
    out.write(s.substring(pos, m.start));
    pos = m.end;
    final name = m.group(2)?.toLowerCase();
    if (name == null) continue; // Comment.
    final closing = m.group(1)!.isNotEmpty;
    switch (name) {
      case 'b' || 'strong':
        out.write(canonicalEmphasisTag(bold: true, closing: closing));
      case 'i' || 'em':
        out.write(canonicalEmphasisTag(bold: false, closing: closing));
      default:
        if (!closing && _droppedContentTags.contains(name)) {
          final end = s.toLowerCase().indexOf('</$name', pos);
          if (end < 0) return out.toString();
          final close = s.indexOf('>', end);
          pos = close < 0 ? s.length : close + 1;
        }
    }
  }
  out.write(s.substring(pos));
  return out.toString();
}

/// [normalizeHtmlTags] after `<br>`, `<br/>` and `<br />` became `\n`, for
/// a label that mermaid.js shows as an HTML label.
String normalizeHtmlMarkup(String s) =>
    s.contains('<') ? normalizeHtmlTags(s.replaceAll(htmlLineBreak, '\n')) : s;

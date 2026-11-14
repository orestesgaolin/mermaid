/// Inline HTML in diagram labels, reduced to what the label layout paints.
library;

import 'label_entities.dart';
import 'label_markup.dart';
import 'label_text.dart';

export 'label_text.dart';

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
/// the canonical `<b>`/`<i>` that [parseLabelMarkup] turns into bold and
/// italic spans. Every other tag is removed and its text kept, as the browser
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

/// The label that mermaid.js shows as an HTML label for the source [s]:
/// [normalizeHtmlMarkup], then [parseLabelMarkup]. With [trim], white space
/// at the ends is removed before entity codes are decoded, so a coded space
/// at an end stays.
LabelText parseHtmlLabel(String s, {bool trim = false}) {
  final markup = normalizeHtmlMarkup(s);
  return parseLabelMarkup(trim ? markup.trim() : markup);
}

/// Parses [markup], label text with canonical emphasis tags (the output of
/// [normalizeHtmlTags]): `\n` starts a line, `<b>` and `<i>` set the style
/// of the spans in them, and the entity codes of the text between the tags
/// are decoded. With [markdown], a `**bold**` pair is bold too; an unmatched
/// `**` stays text.
LabelText parseLabelMarkup(String markup, {bool markdown = false}) {
  final hasTags = markup.contains('<') && emphasisTag.hasMatch(markup);
  if (!hasTags && !(markdown && markup.contains('**'))) {
    return LabelText(decodeLabelEntities(markup));
  }
  final lines = <List<LabelSpan>>[[]];
  final buffer = StringBuffer();
  var boldDepth = 0;
  var italicDepth = 0;
  var markdownBold = false;
  void flush() {
    if (buffer.isEmpty) return;
    lines.last.add(
      LabelSpan(
        decodeLabelEntities(buffer.toString()),
        bold: boldDepth > 0 || markdownBold,
        italic: italicDepth > 0,
      ),
    );
    buffer.clear();
  }

  var i = 0;
  while (i < markup.length) {
    final c = markup.codeUnitAt(i);
    if (c == 0x0a) {
      flush();
      lines.add([]);
      i++;
      continue;
    }
    if (c == 0x3c) {
      final tag = emphasisTagAt(markup, i);
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
    }
    // `**` opens strong emphasis only when a closing `**` follows; an
    // unmatched delimiter stays literal text.
    if (markdown &&
        c == 0x2a &&
        markup.startsWith('**', i) &&
        (markdownBold || markup.indexOf('**', i + 2) >= 0)) {
      flush();
      markdownBold = !markdownBold;
      i += 2;
      continue;
    }
    buffer.writeCharCode(c);
    i++;
  }
  flush();
  return LabelText.styled(lines);
}

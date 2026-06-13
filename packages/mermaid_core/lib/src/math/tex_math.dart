/// A small TeX subset laid out with low-level scene primitives (glyph
/// [SceneText] + rule [SceneShape]), rather than an embedded widget. This
/// keeps math in the same backend-agnostic IR as everything else, so it also
/// renders through the SVG backend.
///
/// Upstream uses KaTeX (`$$...$$`, `common.ts katexRegex`). Full KaTeX parity
/// would need a font-metrics engine (e.g. flutter_math_fork in the Flutter
/// backend); this covers the common constructs — superscripts, subscripts,
/// `\frac`, `\sqrt`, grouping and a symbol table — which handle the canonical
/// mermaid math examples (`x^2`, `\frac{1}{2}`, `\sqrt{x+3}`, `\pi r^2`).
library;

import 'dart:math' as math;

import '../color.dart';
import '../geometry.dart';
import '../ir/scene.dart';
import '../text/text_measurer.dart';
import '../text/text_style.dart';

final _mathRe = RegExp(r'\$\$(.*?)\$\$', dotAll: true);

/// Whether [text] contains a `$$...$$` math span.
bool hasMath(String text) => _mathRe.hasMatch(text);

/// If [label] is wholly a single `$$...$$` span, returns the inner TeX;
/// otherwise null. (Mixed inline math within a label is not handled yet.)
String? wholeMath(String label) {
  final t = label.trim();
  final m = RegExp(r'^\$\$(.*)\$\$$', dotAll: true).firstMatch(t);
  return m?.group(1);
}

/// A laid-out math box: size + a painter that emits scene nodes given the
/// top-left origin. [ascent] is the distance from the top to the baseline.
class MathLayout {
  MathLayout(this.size, this.ascent, this._paint);

  final Size size;
  final double ascent;
  final void Function(Point origin, List<SceneNode> out) _paint;

  List<SceneNode> render(Point topLeft) {
    final out = <SceneNode>[];
    _paint(topLeft, out);
    return out;
  }
}

/// Lays out [tex] at [style]'s size. Coordinates are relative to (0,0).
MathLayout layoutMath(
    String tex, TextStyleSpec style, TextMeasurer measurer, Color color) {
  final box = _row(_Lexer(tex), style, measurer, color, stopOnBrace: false);
  return MathLayout(
    Size(box.width, box.ascent + box.descent),
    box.ascent,
    (origin, out) => box.paint(origin.x, origin.y + box.ascent, out),
  );
}

// ---------------------------------------------------------------------------
// Box model: width + ascent/descent around a baseline, plus a painter that
// draws at (x, baselineY).
// ---------------------------------------------------------------------------

class _Box {
  _Box(this.width, this.ascent, this.descent, this.paint);
  final double width;
  final double ascent;
  final double descent;

  /// Draw with the left edge at [x] and the baseline at [baseline].
  final void Function(double x, double baseline, List<SceneNode> out) paint;
}

_Box _glyph(String text, TextStyleSpec style, TextMeasurer m, Color color,
    {bool italic = false}) {
  if (italic) style = style.copyWith(italic: true);
  final size = m.measure(text, style, maxWidth: 100000);
  // Approximate baseline: ~80% of the line box is ascent.
  final ascent = size.height * 0.8;
  return _Box(size.width, ascent, size.height - ascent, (x, baseline, out) {
    out.add(SceneText(
      text: text,
      bounds: Rect.fromLTWH(x, baseline - ascent, size.width, size.height),
      style: style,
      color: color,
      align: TextAlignH.left,
    ));
  });
}

_Box _hbox(List<_Box> boxes) {
  if (boxes.isEmpty) return _Box(0, 0, 0, (a, b, c) {});
  final width = boxes.fold(0.0, (a, b) => a + b.width);
  final ascent = boxes.fold(0.0, (a, b) => math.max(a, b.ascent));
  final descent = boxes.fold(0.0, (a, b) => math.max(a, b.descent));
  return _Box(width, ascent, descent, (x, baseline, out) {
    var cx = x;
    for (final b in boxes) {
      b.paint(cx, baseline, out);
      cx += b.width;
    }
  });
}

// ---------------------------------------------------------------------------
// Tiny lexer over the TeX string.
// ---------------------------------------------------------------------------

class _Lexer {
  _Lexer(this.s);
  final String s;
  int i = 0;

  bool get atEnd => i >= s.length;
  String peek() => atEnd ? '' : s[i];

  /// Reads one token: a macro `\name`, a single char, or a brace/script marker.
  String next() {
    if (atEnd) return '';
    final c = s[i++];
    if (c == r'\') {
      final start = i;
      while (i < s.length && RegExp(r'[A-Za-z]').hasMatch(s[i])) {
        i++;
      }
      if (i == start && i < s.length) i++; // e.g. \, or \{ — single symbol
      return '\\${s.substring(start, i)}';
    }
    return c;
  }
}

const _symbols = <String, String>{
  r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
  r'\epsilon': 'ε', r'\theta': 'θ', r'\lambda': 'λ', r'\mu': 'μ',
  r'\pi': 'π', r'\rho': 'ρ', r'\sigma': 'σ', r'\tau': 'τ', r'\phi': 'φ',
  r'\omega': 'ω', r'\Delta': 'Δ', r'\Sigma': 'Σ', r'\Omega': 'Ω',
  r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±', r'\mp': '∓',
  r'\le': '≤', r'\leq': '≤', r'\ge': '≥', r'\geq': '≥', r'\ne': '≠',
  r'\neq': '≠', r'\approx': '≈', r'\infty': '∞', r'\sum': '∑',
  r'\int': '∫', r'\partial': '∂', r'\rightarrow': '→', r'\to': '→',
  r'\leftarrow': '←', r'\Rightarrow': '⇒', r'\in': '∈', r'\cup': '∪',
  r'\cap': '∩', r'\sqrt': '√',
};

/// Builds a horizontal row from the lexer until end (or a closing brace when
/// [stopOnBrace] is set — used by group parsing).
_Box _row(_Lexer lx, TextStyleSpec style, TextMeasurer m, Color color,
    {required bool stopOnBrace}) {
  final atoms = <_Box>[];
  while (!lx.atEnd) {
    final c = lx.peek();
    if (stopOnBrace && c == '}') {
      lx.next(); // consume }
      break;
    }
    if (c == ' ') {
      lx.next();
      continue;
    }
    if (c == '^' || c == '_') {
      lx.next();
      final script = _atom(lx, _scriptStyle(style), m, color);
      final base =
          atoms.isNotEmpty ? atoms.removeLast() : _glyph('', style, m, color);
      atoms.add(
          c == '^' ? _superscript(base, script) : _subscript(base, script));
      continue;
    }
    atoms.add(_atom(lx, style, m, color));
  }
  return _hbox(atoms);
}

/// Reads a single atom: a `{group}`, `\frac{}{}`, `\sqrt{}`, a symbol macro,
/// or one character.
_Box _atom(_Lexer lx, TextStyleSpec style, TextMeasurer m, Color color) {
  while (lx.peek() == ' ') {
    lx.next();
  }
  final tok = lx.next();
  if (tok.isEmpty) return _glyph('', style, m, color);
  if (tok == '{') return _row(lx, style, m, color, stopOnBrace: true);
  if (tok == r'\frac') {
    final num = _atom(lx, style, m, color);
    final den = _atom(lx, style, m, color);
    return _frac(num, den, style, color);
  }
  if (tok == r'\sqrt') {
    return _sqrt(_atom(lx, style, m, color), style, m, color);
  }
  if (tok == r'\text' || tok == r'\mathrm' || tok == r'\operatorname') {
    return _glyph(_readRawBrace(lx), style, m, color);
  }
  if (tok == r'\overbrace') {
    return _brace(_atom(lx, style, m, color), style, m, color, over: true);
  }
  if (tok == r'\underbrace') {
    return _brace(_atom(lx, style, m, color), style, m, color, over: false);
  }
  if (tok == r'\vec' || tok == r'\hat' || tok == r'\bar' || tok == r'\overline') {
    return _accent(_atom(lx, style, m, color), tok, style, color);
  }
  if (tok == r'\begin') {
    return _parseEnv(lx, _readRawBrace(lx), style, m, color);
  }
  if (tok == r'\left' || tok == r'\right') {
    // Consume the delimiter char; size-matching delimiters are approximated by
    // their plain glyph (full \left\right auto-sizing is a known gap).
    final d = lx.next();
    if (d == '.') return _glyph('', style, m, color); // \left. = invisible
    return _glyph(d.startsWith(r'\') ? (_symbols[d] ?? d.substring(1)) : d,
        style, m, color);
  }
  final sym = _symbols[tok];
  final text = sym ?? (tok.startsWith(r'\') ? tok.substring(1) : tok);
  // KaTeX italicizes single-letter variables (and lowercase greek); numbers,
  // operators, multi-letter function names and `\text` stay upright.
  final isVar = text.length == 1 &&
      RegExp(r'[A-Za-zα-ω]').hasMatch(text) &&
      !(tok.startsWith(r'\') && sym == null);
  return _glyph(text, style, m, color, italic: isVar);
}

/// Reads a `{...}` group as a literal string (spaces preserved, braces
/// balanced), or a single token if no brace follows. Used by `\text`.
String _readRawBrace(_Lexer lx) {
  while (lx.peek() == ' ') {
    lx.next();
  }
  if (lx.peek() != '{') return lx.next();
  lx.next(); // consume '{'
  final sb = StringBuffer();
  var depth = 1;
  while (!lx.atEnd) {
    final c = lx.s[lx.i++];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) break;
    }
    sb.write(c);
  }
  return sb.toString();
}

TextStyleSpec _scriptStyle(TextStyleSpec s) =>
    s.copyWith(fontSize: s.fontSize * 0.72);

_Box _superscript(_Box base, _Box script) {
  final rise = base.ascent * 0.5;
  final ascent = math.max(base.ascent, rise + script.ascent + script.descent);
  return _Box(base.width + script.width, ascent, base.descent,
      (x, baseline, out) {
    base.paint(x, baseline, out);
    script.paint(x + base.width, baseline - rise, out);
  });
}

_Box _subscript(_Box base, _Box script) {
  final drop = base.descent + script.ascent * 0.3;
  final descent = math.max(base.descent, drop + script.descent);
  return _Box(base.width + script.width, base.ascent, descent,
      (x, baseline, out) {
    base.paint(x, baseline, out);
    script.paint(x + base.width, baseline + drop, out);
  });
}

_Box _frac(_Box num, _Box den, TextStyleSpec style, Color color) {
  final width = math.max(num.width, den.width) + 6;
  const gap = 3.0;
  final ruleY = 0.0; // relative to baseline (rule sits on baseline)
  final ascent = num.ascent + num.descent + gap;
  final descent = den.ascent + den.descent + gap;
  return _Box(width, ascent + 2, descent, (x, baseline, out) {
    // Numerator centered above the rule.
    num.paint(x + (width - num.width) / 2,
        baseline + ruleY - gap - num.descent, out);
    // Rule.
    out.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(x, baseline + ruleY)),
        LineTo(Point(x + width, baseline + ruleY)),
      ]),
      stroke: Stroke(color: color, width: math.max(1, style.fontSize * 0.06)),
    ));
    // Denominator centered below.
    den.paint(x + (width - den.width) / 2,
        baseline + ruleY + gap + den.ascent, out);
  });
}

_Box _sqrt(_Box inner, TextStyleSpec style, TextMeasurer m, Color color) {
  final radical = _glyph('√', style, m, color);
  final w = radical.width + inner.width + 4;
  final ascent = math.max(radical.ascent, inner.ascent) + 2;
  final descent = math.max(radical.descent, inner.descent);
  return _Box(w, ascent, descent, (x, baseline, out) {
    radical.paint(x, baseline, out);
    final ix = x + radical.width + 2;
    // Overline across the radicand.
    out.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(ix - 2, baseline - inner.ascent - 1)),
        LineTo(Point(ix + inner.width + 2, baseline - inner.ascent - 1)),
      ]),
      stroke: Stroke(color: color, width: math.max(1, style.fontSize * 0.06)),
    ));
    inner.paint(ix, baseline, out);
  });
}

// ---------------------------------------------------------------------------
// Environments: \begin{matrix|bmatrix|pmatrix|vmatrix|Bmatrix|cases} ...
// rows separated by `\\`, columns by `&`.
// ---------------------------------------------------------------------------

/// A row within an environment, stopping (without consuming) at `&`, `\\` or
/// `\end`.
_Box _cellRow(_Lexer lx, TextStyleSpec style, TextMeasurer m, Color color) {
  final atoms = <_Box>[];
  while (!lx.atEnd) {
    while (lx.peek() == ' ') {
      lx.next();
    }
    final save = lx.i;
    final tok = lx.next();
    if (tok.isEmpty ||
        tok == '&' ||
        tok == r'\\' ||
        tok == r'\end' ||
        tok == '}') {
      lx.i = save;
      break;
    }
    if (tok == '^' || tok == '_') {
      final script = _atom(lx, _scriptStyle(style), m, color);
      final base =
          atoms.isNotEmpty ? atoms.removeLast() : _glyph('', style, m, color);
      atoms.add(
          tok == '^' ? _superscript(base, script) : _subscript(base, script));
      continue;
    }
    lx.i = save;
    atoms.add(_atom(lx, style, m, color));
  }
  return _hbox(atoms);
}

_Box _parseEnv(
    _Lexer lx, String env, TextStyleSpec style, TextMeasurer m, Color color) {
  final rows = <List<_Box>>[<_Box>[]];
  while (!lx.atEnd) {
    rows.last.add(_cellRow(lx, style, m, color));
    while (lx.peek() == ' ') {
      lx.next();
    }
    final tok = lx.next();
    if (tok == r'\end') {
      _readRawBrace(lx);
      break;
    } else if (tok == r'\\') {
      rows.add(<_Box>[]);
    } else if (tok == '&') {
      continue;
    } else if (tok.isEmpty) {
      break;
    }
  }
  // Drop a trailing empty row (from a final `\\`).
  if (rows.length > 1 && rows.last.length == 1 && rows.last.first.width == 0) {
    rows.removeLast();
  }
  return _matrix(rows, env, style, color);
}

const _delims = <String, (String, String)>{
  'bmatrix': ('[', ']'),
  'pmatrix': ('(', ')'),
  'vmatrix': ('|', '|'),
  'Vmatrix': ('|', '|'),
  'Bmatrix': ('{', '}'),
  'matrix': ('', ''),
  'array': ('', ''),
  'cases': ('{', ''),
};

_Box _matrix(
    List<List<_Box>> rows, String env, TextStyleSpec style, Color color) {
  final (left, right) = _delims[env] ?? ('', '');
  final leftAlign = env == 'cases';
  final ncols = rows.fold(0, (a, r) => math.max(a, r.length));
  final colW = List<double>.filled(ncols, 0);
  for (final r in rows) {
    for (var j = 0; j < r.length; j++) {
      colW[j] = math.max(colW[j], r[j].width);
    }
  }
  final rowAsc = [for (final r in rows) r.fold(0.0, (a, c) => math.max(a, c.ascent))];
  final rowDesc =
      [for (final r in rows) r.fold(0.0, (a, c) => math.max(a, c.descent))];
  const colGap = 10.0;
  const rowGap = 6.0;
  final contentW =
      colW.fold(0.0, (a, b) => a + b) + colGap * (ncols - 1).clamp(0, 1000);
  var contentH = rowGap * (rows.length - 1).clamp(0, 1000);
  for (var i = 0; i < rows.length; i++) {
    contentH += rowAsc[i] + rowDesc[i];
  }
  final delimW = (left.isEmpty ? 0.0 : style.fontSize * 0.32) +
      (right.isEmpty ? 0.0 : style.fontSize * 0.32);
  const pad = 4.0;
  final totalW = contentW + delimW + pad * 2;
  final half = contentH / 2;

  return _Box(totalW, half, half, (x, baseline, out) {
    final top = baseline - half;
    final leftDelimW = left.isEmpty ? 0.0 : style.fontSize * 0.32;
    final contentX = x + leftDelimW + pad;
    if (left.isNotEmpty) {
      _drawDelim(left, x, top, leftDelimW, contentH, true, color, out);
    }
    if (right.isNotEmpty) {
      final rdw = style.fontSize * 0.32;
      _drawDelim(right, x + totalW - rdw, top, rdw, contentH, false, color, out);
    }
    var cy = top;
    for (var i = 0; i < rows.length; i++) {
      var cx = contentX;
      final cellBaseline = cy + rowAsc[i];
      for (var j = 0; j < ncols; j++) {
        if (j < rows[i].length) {
          final cell = rows[i][j];
          final cellX = leftAlign ? cx : cx + (colW[j] - cell.width) / 2;
          cell.paint(cellX, cellBaseline, out);
        }
        cx += colW[j] + colGap;
      }
      cy += rowAsc[i] + rowDesc[i] + rowGap;
    }
  });
}

/// Draws a sized delimiter (bracket/paren/bar/brace) into [out].
void _drawDelim(String kind, double x, double top, double w, double h,
    bool isLeft, Color color, List<SceneNode> out) {
  final sw = 1.3;
  final b = top + h;
  void path(List<PathCommand> cmds) => out.add(SceneShape(
      geometry: PathGeometry(cmds), stroke: Stroke(color: color, width: sw)));
  switch (kind) {
    case '[':
      path([
        MoveTo(Point(x + w, top)),
        LineTo(Point(x + 1, top)),
        LineTo(Point(x + 1, b)),
        LineTo(Point(x + w, b)),
      ]);
    case ']':
      path([
        MoveTo(Point(x, top)),
        LineTo(Point(x + w - 1, top)),
        LineTo(Point(x + w - 1, b)),
        LineTo(Point(x, b)),
      ]);
    case '|':
      final cx = x + w / 2;
      path([MoveTo(Point(cx, top)), LineTo(Point(cx, b))]);
    case '(':
      path([
        MoveTo(Point(x + w, top)),
        CubicTo(Point(x, top + h * 0.25), Point(x, top + h * 0.75),
            Point(x + w, b)),
      ]);
    case ')':
      path([
        MoveTo(Point(x, top)),
        CubicTo(Point(x + w, top + h * 0.25), Point(x + w, top + h * 0.75),
            Point(x, b)),
      ]);
    case '{':
      final mid = top + h / 2;
      final r = x + w;
      path([
        MoveTo(Point(r, top)),
        CubicTo(Point(x + w * 0.5, top + h * 0.1), Point(x + w * 0.5, mid - h * 0.1),
            Point(x, mid)),
        CubicTo(Point(x + w * 0.5, mid + h * 0.1), Point(x + w * 0.5, b - h * 0.1),
            Point(r, b)),
      ]);
    case '}':
      final mid = top + h / 2;
      path([
        MoveTo(Point(x, top)),
        CubicTo(Point(x + w * 0.5, top + h * 0.1), Point(x + w * 0.5, mid - h * 0.1),
            Point(x + w, mid)),
        CubicTo(Point(x + w * 0.5, mid + h * 0.1), Point(x + w * 0.5, b - h * 0.1),
            Point(x, b)),
      ]);
  }
}

/// A horizontal brace over/under [inner], with the body kept on the baseline.
/// `^{label}` / `_{label}` then compose above/below via the row parser.
_Box _brace(_Box inner, TextStyleSpec style, TextMeasurer m, Color color,
    {required bool over}) {
  final braceH = style.fontSize * 0.28;
  const gap = 2.0;
  final ascent = over ? inner.ascent + gap + braceH : inner.ascent;
  final descent = over ? inner.descent : inner.descent + gap + braceH;
  return _Box(inner.width, ascent, descent, (x, baseline, out) {
    inner.paint(x, baseline, out);
    final w = inner.width;
    final mid = x + w / 2;
    final y = over ? baseline - inner.ascent - gap : baseline + inner.descent + gap;
    final tip = over ? y - braceH : y + braceH;
    // Two curves meeting at a center tip — a horizontal curly brace.
    out.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(x, y)),
        CubicTo(Point(x + w * 0.2, y), Point(mid - w * 0.1, tip),
            Point(mid, tip)),
        CubicTo(Point(mid + w * 0.1, tip), Point(x + w * 0.8, y),
            Point(x + w, y)),
      ]),
      stroke: Stroke(color: color, width: math.max(1, style.fontSize * 0.05)),
    ));
  });
}

/// An accent (`\vec`, `\hat`, `\bar`, `\overline`) drawn above [inner].
_Box _accent(_Box inner, String kind, TextStyleSpec style, Color color) {
  const gap = 1.5;
  final h = style.fontSize * 0.18;
  return _Box(inner.width, inner.ascent + gap + h, inner.descent,
      (x, baseline, out) {
    inner.paint(x, baseline, out);
    final y = baseline - inner.ascent - gap;
    final w = inner.width;
    final sw = math.max(1.0, style.fontSize * 0.06);
    switch (kind) {
      case r'\vec':
        out.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(x, y)),
            LineTo(Point(x + w, y)),
            LineTo(Point(x + w - 3, y - 2)),
            MoveTo(Point(x + w, y)),
            LineTo(Point(x + w - 3, y + 2)),
          ]),
          stroke: Stroke(color: color, width: sw),
        ));
      case r'\hat':
        out.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(x + w / 2 - 3, y + 2)),
            LineTo(Point(x + w / 2, y - 2)),
            LineTo(Point(x + w / 2 + 3, y + 2)),
          ]),
          stroke: Stroke(color: color, width: sw),
        ));
      default: // \bar, \overline
        out.add(SceneShape(
          geometry: PathGeometry([MoveTo(Point(x, y)), LineTo(Point(x + w, y))]),
          stroke: Stroke(color: color, width: sw),
        ));
    }
  });
}

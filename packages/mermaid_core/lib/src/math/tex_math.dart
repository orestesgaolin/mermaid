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
import '../ir/scene_utils.dart';
import '../text/text_measurer.dart';
import '../text/text_style.dart';
import 'katex_math.dart';

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

/// Returns a layout for [label] if it contains any `$$…$$` math, else null.
/// Handles both a whole-math label and text with inline math spans.
MathLayout? layoutLabel(
    String label, TextStyleSpec style, TextMeasurer measurer, Color color) {
  if (!hasMath(label)) return null;
  final whole = wholeMath(label);
  final ml = whole != null
      ? layoutMath(whole, style, measurer, color)
      : _layoutInline(label, style, measurer, color);
  // Wrap in a marked group so the hand-drawn pass keeps math crisp (it would
  // otherwise sketch the glyph outlines into illegibility).
  return MathLayout(
    ml.size,
    ml.ascent,
    (origin, out) =>
        out.add(SceneGroup(id: mathSceneGroupId, children: ml.render(origin))),
  );
}

/// Lays out a single line of mixed text and `$$…$$` math, sharing a baseline.
MathLayout _layoutInline(
    String label, TextStyleSpec style, TextMeasurer measurer, Color color) {
  final parts = <({double w, double asc, double desc, void Function(Point, List<SceneNode>) paint})>[];
  var last = 0;
  void addText(String s) {
    if (s.isEmpty) return;
    final size = measurer.measure(s, style, maxWidth: 100000);
    parts.add((
      w: size.width,
      asc: size.height * 0.8,
      desc: size.height * 0.2,
      paint: (o, out) => out.add(SceneText(
            text: s,
            bounds: Rect.fromLTWH(o.x, o.y, size.width, size.height),
            style: style,
            color: color,
            align: TextAlignH.left,
          )),
    ));
  }

  for (final m in _mathRe.allMatches(label)) {
    if (m.start > last) addText(label.substring(last, m.start));
    final ml = layoutMath(m.group(1)!, style, measurer, color);
    parts.add((
      w: ml.size.width,
      asc: ml.ascent,
      desc: ml.size.height - ml.ascent,
      paint: (o, out) => out.addAll(ml.render(o)),
    ));
    last = m.end;
  }
  if (last < label.length) addText(label.substring(last));

  final width = parts.fold(0.0, (a, p) => a + p.w);
  final asc = parts.fold(0.0, (a, p) => math.max(a, p.asc));
  final desc = parts.fold(0.0, (a, p) => math.max(a, p.desc));
  return MathLayout(Size(width, asc + desc), asc, (origin, out) {
    var x = origin.x;
    for (final p in parts) {
      p.paint(Point(x, origin.y + (asc - p.asc)), out);
      x += p.w;
    }
  });
}

/// Lays out [tex] at [style]'s size. Coordinates are relative to (0,0).
MathLayout layoutMath(
    String tex, TextStyleSpec style, TextMeasurer measurer, Color color) {
  // Prefer the faithful KaTeX port (exact metrics, full coverage); fall back
  // to the built-in subset engine if it can't handle the input.
  final kx = buildKatexMath(tex, style.fontSize, color);
  if (kx != null) {
    return MathLayout(
      kx.size,
      kx.ascent,
      (origin, out) => out.addAll([
        for (final n in kx.nodes) translateSceneNode(n, origin.x, origin.y),
      ]),
    );
  }
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
    {bool roman = true}) {
  // Math sets in KaTeX fonts: roman (numbers/operators/text/functions) in
  // KaTeX_Main, variables in the inherently-italic KaTeX_Math.
  final kstyle = style.copyWith(
      fontFamily: roman ? 'KaTeX_Main' : 'KaTeX_Math', italic: false);
  final size = m.measure(text, kstyle, maxWidth: 100000);
  // Approximate baseline: ~80% of the line box is ascent.
  final ascent = size.height * 0.8;
  return _Box(size.width, ascent, size.height - ascent, (x, baseline, out) {
    out.add(SceneText(
      text: text,
      bounds: Rect.fromLTWH(x, baseline - ascent, size.width, size.height),
      style: kstyle,
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
  // Lowercase greek.
  r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
  r'\epsilon': 'ε', r'\varepsilon': 'ε', r'\zeta': 'ζ', r'\eta': 'η',
  r'\theta': 'θ', r'\vartheta': 'ϑ', r'\iota': 'ι', r'\kappa': 'κ',
  r'\lambda': 'λ', r'\mu': 'μ', r'\nu': 'ν', r'\xi': 'ξ', r'\pi': 'π',
  r'\rho': 'ρ', r'\sigma': 'σ', r'\tau': 'τ', r'\upsilon': 'υ',
  r'\phi': 'φ', r'\varphi': 'φ', r'\chi': 'χ', r'\psi': 'ψ', r'\omega': 'ω',
  // Uppercase greek.
  r'\Gamma': 'Γ', r'\Delta': 'Δ', r'\Theta': 'Θ', r'\Lambda': 'Λ',
  r'\Xi': 'Ξ', r'\Pi': 'Π', r'\Sigma': 'Σ', r'\Upsilon': 'Υ',
  r'\Phi': 'Φ', r'\Psi': 'Ψ', r'\Omega': 'Ω',
  // Operators & relations.
  r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±', r'\mp': '∓',
  r'\ast': '∗', r'\star': '⋆', r'\circ': '∘', r'\bullet': '•',
  r'\le': '≤', r'\leq': '≤', r'\ge': '≥', r'\geq': '≥', r'\ne': '≠',
  r'\neq': '≠', r'\equiv': '≡', r'\approx': '≈', r'\cong': '≅',
  r'\sim': '∼', r'\propto': '∝', r'\ll': '≪', r'\gg': '≫',
  // Big operators & calculus.
  r'\sum': '∑', r'\prod': '∏', r'\int': '∫', r'\oint': '∮',
  r'\partial': '∂', r'\nabla': '∇', r'\infty': '∞',
  // Sets & logic.
  r'\in': '∈', r'\notin': '∉', r'\subset': '⊂', r'\supset': '⊃',
  r'\subseteq': '⊆', r'\supseteq': '⊇', r'\cup': '∪', r'\cap': '∩',
  r'\emptyset': '∅', r'\forall': '∀', r'\exists': '∃', r'\neg': '¬',
  r'\wedge': '∧', r'\vee': '∨', r'\oplus': '⊕', r'\otimes': '⊗',
  r'\perp': '⊥', r'\parallel': '∥', r'\angle': '∠',
  // Arrows.
  r'\rightarrow': '→', r'\to': '→', r'\leftarrow': '←',
  r'\leftrightarrow': '↔', r'\Rightarrow': '⇒', r'\Leftarrow': '⇐',
  r'\Leftrightarrow': '⇔', r'\uparrow': '↑', r'\downarrow': '↓', r'\mapsto': '↦',
  // Misc letters/dots.
  r'\hbar': 'ℏ', r'\ell': 'ℓ', r'\Re': 'ℜ', r'\Im': 'ℑ', r'\aleph': 'ℵ',
  r'\sqrt': '√', r'\dots': '…', r'\ldots': '…',
  r'\cdots': '⋯', r'\langle': '⟨', r'\rangle': '⟩', r'\degree': '°',
};

/// Spacing macros → fractional-em widths (negative = ignored / zero).
const _spaces = <String, double>{
  r'\,': 0.17, r'\:': 0.22, r'\;': 0.28, r'\ ': 0.25,
  r'\!': 0.0, r'\quad': 1.0, r'\qquad': 2.0,
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
    final env = _readRawBrace(lx);
    // `array` takes a column-alignment spec argument, e.g. {l|c r}.
    final spec = env == 'array' ? _readRawBrace(lx) : '';
    return _parseEnv(lx, env, spec, style, m, color);
  }
  if (tok == r'\left') {
    return _leftRight(lx, style, m, color);
  }
  final space = _spaces[tok];
  if (space != null) {
    return _Box(style.fontSize * space, 0, 0, (a, b, c) {});
  }
  if (_functions.contains(tok)) {
    // Function names render upright with a thin trailing space (KaTeX).
    return _hbox([
      _glyph(tok.substring(1), style, m, color),
      _Box(style.fontSize * 0.16, 0, 0, (a, b, c) {}),
    ]);
  }
  final sym = _symbols[tok];
  final text = sym ?? (tok.startsWith(r'\') ? tok.substring(1) : tok);
  // KaTeX italicizes single-letter variables (and lowercase greek); numbers,
  // operators, multi-letter function names and `\text` stay upright.
  final isVar = text.length == 1 &&
      RegExp(r'[A-Za-zα-ω]').hasMatch(text) &&
      !(tok.startsWith(r'\') && sym == null);
  return _glyph(text, style, m, color, roman: !isVar);
}

const _functions = {
  r'\sin', r'\cos', r'\tan', r'\cot', r'\sec', r'\csc', r'\log', r'\ln',
  r'\exp', r'\lim', r'\min', r'\max', r'\det', r'\gcd', r'\deg', r'\arg',
  r'\sinh', r'\cosh', r'\tanh',
};

/// Maps a `\left`/`\right` delimiter token to the char `_drawDelim` knows;
/// `.` is the null (invisible) delimiter.
String _delimChar(String tok) => switch (tok) {
      '.' => '',
      r'\{' || r'\lbrace' => '{',
      r'\}' || r'\rbrace' => '}',
      r'\langle' => '(',
      r'\rangle' => ')',
      r'\lvert' || r'\vert' || r'\|' || r'\rvert' => '|',
      _ => tok.startsWith(r'\') ? '' : tok,
    };

/// `\left<d> ... \right<d>`: content flanked by delimiters auto-sized to its
/// height (drawn as paths via [_drawDelim]).
_Box _leftRight(
    _Lexer lx, TextStyleSpec style, TextMeasurer m, Color color) {
  final left = _delimChar(lx.next());
  final atoms = <_Box>[];
  var right = '';
  while (!lx.atEnd) {
    while (lx.peek() == ' ') {
      lx.next();
    }
    final save = lx.i;
    final tok = lx.next();
    if (tok == r'\right') {
      right = _delimChar(lx.next());
      break;
    }
    if (tok.isEmpty) break;
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
  final inner = _hbox(atoms);
  const padY = 2.0;
  final lw = _delimWidth(left, style.fontSize);
  final rw = _delimWidth(right, style.fontSize);
  final h = inner.ascent + inner.descent + padY * 2;
  return _Box(inner.width + lw + rw, inner.ascent + padY, inner.descent + padY,
      (x, baseline, out) {
    final top = baseline - inner.ascent - padY;
    if (left.isNotEmpty) _drawDelim(left, x, top, lw, h, true, color, out);
    inner.paint(x + lw, baseline, out);
    if (right.isNotEmpty) {
      _drawDelim(right, x + lw + inner.width, top, rw, h, false, color, out);
    }
  });
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
  // The radical is drawn as one connected path (checkmark up into the
  // overline), sized to the radicand — like KaTeX/flutter_math, not a glyph.
  final radW = style.fontSize * 0.55;
  const padL = 3.0;
  const padTop = 3.0;
  final sw = math.max(1.0, style.fontSize * 0.07);
  final w = radW + padL + inner.width + 3;
  final ascent = inner.ascent + padTop + sw;
  final descent = inner.descent;
  return _Box(w, ascent, descent, (x, baseline, out) {
    final top = baseline - inner.ascent - padTop;
    final bot = baseline + inner.descent;
    out.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(x, baseline - inner.ascent * 0.45)),
        LineTo(Point(x + radW * 0.35, bot)),
        LineTo(Point(x + radW * 0.7, top)),
        LineTo(Point(x + w, top)),
      ]),
      stroke: Stroke(color: color, width: sw),
    ));
    inner.paint(x + radW + padL, baseline, out);
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

_Box _parseEnv(_Lexer lx, String env, String colSpec, TextStyleSpec style,
    TextMeasurer m, Color color) {
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
  return _matrix(rows, env, colSpec, style, color);
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

_Box _matrix(List<List<_Box>> rows, String env, String colSpec,
    TextStyleSpec style, Color color) {
  final (left, right) = _delims[env] ?? ('', '');
  // cases is left-aligned; array follows its spec (left if it asks for `l`).
  final spec = colSpec.replaceAll(RegExp(r'[^lcr]'), '');
  final leftAlign = env == 'cases' ||
      (env == 'array' && spec.isNotEmpty && !spec.contains(RegExp('[cr]')));
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
  final leftDelimW = _delimWidth(left, style.fontSize);
  final rightDelimW = _delimWidth(right, style.fontSize);
  const pad = 4.0;
  final totalW = contentW + leftDelimW + rightDelimW + pad * 2;
  final half = contentH / 2;

  return _Box(totalW, half, half, (x, baseline, out) {
    final top = baseline - half;
    final contentX = x + leftDelimW + pad;
    if (left.isNotEmpty) {
      _drawDelim(left, x, top, leftDelimW, contentH, true, color, out);
    }
    if (right.isNotEmpty) {
      _drawDelim(
          right, x + totalW - rightDelimW, top, rightDelimW, contentH, false,
          color, out);
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

/// Allotted horizontal space for a delimiter; braces need more reach than
/// brackets/bars so their cusp shows.
double _delimWidth(String kind, double fontSize) => switch (kind) {
      '' => 0,
      '{' || '}' => fontSize * 0.45,
      '(' || ')' => fontSize * 0.34,
      _ => fontSize * 0.3,
    };

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
      // Proper curly brace: top/bottom tips curl to a vertical spine, with a
      // sharp middle cusp pointing outward (left). Arms are straight.
      final mid = top + h / 2;
      final sx = x + w * 0.62; // spine
      final r = (h * 0.16).clamp(2.0, h / 4);
      path([
        MoveTo(Point(x + w, top)),
        QuadTo(Point(sx, top), Point(sx, top + r)),
        LineTo(Point(sx, mid - r)),
        QuadTo(Point(sx, mid), Point(x, mid)),
        QuadTo(Point(sx, mid), Point(sx, mid + r)),
        LineTo(Point(sx, b - r)),
        QuadTo(Point(sx, b), Point(x + w, b)),
      ]);
    case '}':
      final mid = top + h / 2;
      final sx = x + w * 0.38; // spine
      final r = (h * 0.16).clamp(2.0, h / 4);
      path([
        MoveTo(Point(x, top)),
        QuadTo(Point(sx, top), Point(sx, top + r)),
        LineTo(Point(sx, mid - r)),
        QuadTo(Point(sx, mid), Point(x + w, mid)),
        QuadTo(Point(sx, mid), Point(sx, mid + r)),
        LineTo(Point(sx, b - r)),
        QuadTo(Point(sx, b), Point(x, b)),
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

/// Railroad / syntax diagram (`railroad-diagram`): EBNF rules rendered as
/// railroad tracks. Each `name = expr ;` is one row. The expression grammar is
/// parsed recursively into an AST supporting choice (`|`), sequence
/// (concatenation, optionally with `,`), grouping (`( ... )`), repetition
/// (`{ ... }` / `x*` / `x+`) and optional (`[ ... ]` / `x?`). Each construct
/// lays itself out as a box with an entry on the left and an exit on the right
/// sharing a single horizontal baseline; the caller threads them together.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

// ---------------------------------------------------------------------------
// Expression AST
// ---------------------------------------------------------------------------

/// Base class for railroad expression nodes.
sealed class RailroadExpr {
  const RailroadExpr();
}

/// A literal terminal, drawn as a rounded pill.
class RailroadTerminal extends RailroadExpr {
  const RailroadTerminal(this.text);
  final String text;
}

/// A reference to another rule, drawn as a rectangle.
class RailroadNonTerminal extends RailroadExpr {
  const RailroadNonTerminal(this.text);
  final String text;
}

/// Concatenation: items drawn left-to-right on one baseline.
class RailroadSequence extends RailroadExpr {
  const RailroadSequence(this.items);
  final List<RailroadExpr> items;
}

/// Alternation: branches stacked vertically with fork/join rails.
class RailroadChoice extends RailroadExpr {
  const RailroadChoice(this.options);
  final List<RailroadExpr> options;
}

/// Zero-or-more repetition (`{ x }` / `x*`): a loop arc above the item.
class RailroadRepetition extends RailroadExpr {
  const RailroadRepetition(this.child, {this.oneOrMore = false});
  final RailroadExpr child;

  /// When true the item is traversed at least once (`x+`): no skip ahead.
  final bool oneOrMore;
}

/// Zero-or-one (`[ x ]` / `x?`): a bypass arc routing around the item.
class RailroadOptional extends RailroadExpr {
  const RailroadOptional(this.child);
  final RailroadExpr child;
}

/// A special sequence (`? text ?`), drawn as a dashed-border rect.
class RailroadSpecial extends RailroadExpr {
  const RailroadSpecial(this.text);
  final String text;
}

/// An empty expression (e.g. an empty group), drawn as a straight rail.
class RailroadEmpty extends RailroadExpr {
  const RailroadEmpty();
}

class RailroadRule {
  RailroadRule(this.name, this.expr);
  final String name;
  final RailroadExpr expr;
}

class RailroadDiagram {
  const RailroadDiagram(this.rules, this.title);
  final List<RailroadRule> rules;
  final String? title;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

RailroadDiagram parseRailroad(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  var seenHeader = false;
  String? title;
  final body = StringBuffer();
  for (var line in lines) {
    // Strip `//` line comments (outside the EBNF comment forms).
    final c = line.indexOf('//');
    if (c >= 0) line = line.substring(0, c);
    final t = line.trim();
    if (t.isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^railroad(-diagram|-beta)?\b').hasMatch(t)) {
        throw const MermaidParseException('expected "railroad" header');
      }
      seenHeader = true;
      continue;
    }
    final tm = RegExp(r'^title\s+"?([^"]+)"?\s*$').firstMatch(t);
    if (tm != null) {
      title = tm.group(1)!.trim();
      continue;
    }
    body.write(' $t');
  }
  if (!seenHeader) throw const MermaidParseException('empty railroad source');

  // Strip EBNF block comments: `/* ... */` (W3C) and `(* ... *)` (ISO).
  var src = body.toString();
  src = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
  src = src.replaceAll(RegExp(r'\(\*.*?\*\)', dotAll: true), ' ');

  final rules = <RailroadRule>[];
  for (final stmt in _splitTop(src, ';')) {
    final s = stmt.trim();
    if (s.isEmpty) continue;
    final eq = s.indexOf('=');
    if (eq < 0) continue;
    final name = s.substring(0, eq).trim();
    final exprSrc = s.substring(eq + 1).trim();
    final expr = _ExprParser(exprSrc).parse();
    rules.add(RailroadRule(name, expr));
  }
  return RailroadDiagram(rules, title);
}

/// Token kinds for the expression parser.
enum _Tok { ident, string, lparen, rparen, lbrack, rbrack, lbrace, rbrace, bar, comma, star, plus, question, eof }

class _Token {
  _Token(this.kind, this.value);
  final _Tok kind;
  final String value;
}

/// Recursive-descent parser for a single rule's right-hand side.
///
/// Grammar (lowest to highest precedence):
///   choice   := sequence ( '|' sequence )*
///   sequence := postfix ( ','? postfix )*
///   postfix  := primary ( '*' | '+' | '?' )*
///   primary  := string | ident | '(' choice ')' | '{' choice '}' | '[' choice ']'
class _ExprParser {
  _ExprParser(String src) : _tokens = _lex(src);

  final List<_Token> _tokens;
  int _i = 0;

  _Token get _cur => _tokens[_i];
  _Token _advance() => _tokens[_i++];
  bool _match(_Tok k) {
    if (_cur.kind == k) {
      _i++;
      return true;
    }
    return false;
  }

  RailroadExpr parse() {
    if (_cur.kind == _Tok.eof) return const RailroadEmpty();
    final e = _parseChoice();
    return e;
  }

  RailroadExpr _parseChoice() {
    final options = <RailroadExpr>[_parseSequence()];
    while (_match(_Tok.bar)) {
      options.add(_parseSequence());
    }
    if (options.length == 1) return options.first;
    return RailroadChoice(options);
  }

  RailroadExpr _parseSequence() {
    final items = <RailroadExpr>[];
    while (_isTermStart(_cur.kind)) {
      items.add(_parsePostfix());
      // ISO concatenation comma is an optional separator.
      _match(_Tok.comma);
    }
    if (items.isEmpty) return const RailroadEmpty();
    if (items.length == 1) return items.first;
    return RailroadSequence(items);
  }

  RailroadExpr _parsePostfix() {
    var e = _parsePrimary();
    var changed = true;
    while (changed) {
      changed = true;
      switch (_cur.kind) {
        case _Tok.star:
          _advance();
          e = RailroadRepetition(e);
        case _Tok.plus:
          _advance();
          e = RailroadRepetition(e, oneOrMore: true);
        case _Tok.question:
          _advance();
          e = RailroadOptional(e);
        default:
          changed = false;
      }
    }
    return e;
  }

  RailroadExpr _parsePrimary() {
    final t = _cur;
    switch (t.kind) {
      case _Tok.string:
        _advance();
        return RailroadTerminal(t.value);
      case _Tok.ident:
        _advance();
        return RailroadNonTerminal(t.value);
      case _Tok.lparen:
        _advance();
        final inner = _parseChoice();
        _match(_Tok.rparen);
        return inner;
      case _Tok.lbrace:
        _advance();
        final inner = _parseChoice();
        _match(_Tok.rbrace);
        return RailroadRepetition(inner);
      case _Tok.lbrack:
        _advance();
        final inner = _parseChoice();
        _match(_Tok.rbrack);
        return RailroadOptional(inner);
      case _Tok.question:
        // Special sequence: `? text ?`. The opening `?` is in primary
        // position; gather raw token text up to the closing `?`.
        _advance();
        final buf = StringBuffer();
        while (_cur.kind != _Tok.question && _cur.kind != _Tok.eof) {
          if (buf.isNotEmpty) buf.write(' ');
          buf.write(_advance().value);
        }
        _match(_Tok.question); // closing `?`
        return RailroadSpecial(buf.toString());
      default:
        // Unexpected token: consume and treat as empty to stay robust.
        _advance();
        return const RailroadEmpty();
    }
  }

  static bool _isTermStart(_Tok k) =>
      k == _Tok.ident ||
      k == _Tok.string ||
      k == _Tok.lparen ||
      k == _Tok.lbrace ||
      k == _Tok.lbrack ||
      k == _Tok.question;

  static List<_Token> _lex(String s) {
    final out = <_Token>[];
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
        i++;
        continue;
      }
      if (ch == '"' || ch == "'") {
        final quote = ch;
        final buf = StringBuffer();
        i++;
        while (i < s.length && s[i] != quote) {
          buf.write(s[i]);
          i++;
        }
        i++; // closing quote
        out.add(_Token(_Tok.string, buf.toString()));
        continue;
      }
      switch (ch) {
        case '(':
          out.add(_Token(_Tok.lparen, ch));
          i++;
          continue;
        case ')':
          out.add(_Token(_Tok.rparen, ch));
          i++;
          continue;
        case '[':
          out.add(_Token(_Tok.lbrack, ch));
          i++;
          continue;
        case ']':
          out.add(_Token(_Tok.rbrack, ch));
          i++;
          continue;
        case '{':
          out.add(_Token(_Tok.lbrace, ch));
          i++;
          continue;
        case '}':
          out.add(_Token(_Tok.rbrace, ch));
          i++;
          continue;
        case '|':
          out.add(_Token(_Tok.bar, ch));
          i++;
          continue;
        case ',':
          out.add(_Token(_Tok.comma, ch));
          i++;
          continue;
        case '*':
          out.add(_Token(_Tok.star, ch));
          i++;
          continue;
        case '+':
          out.add(_Token(_Tok.plus, ch));
          i++;
          continue;
        case '?':
          out.add(_Token(_Tok.question, ch));
          i++;
          continue;
      }
      // Identifier: run of non-special, non-space characters.
      final start = i;
      while (i < s.length && !_isSpecial(s[i]) && !_isSpace(s[i])) {
        i++;
      }
      if (i == start) {
        i++; // safety: avoid infinite loop on stray char
        continue;
      }
      out.add(_Token(_Tok.ident, s.substring(start, i)));
    }
    out.add(_Token(_Tok.eof, ''));
    return out;
  }

  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';

  static bool _isSpecial(String c) =>
      c == '(' ||
      c == ')' ||
      c == '[' ||
      c == ']' ||
      c == '{' ||
      c == '}' ||
      c == '|' ||
      c == ',' ||
      c == '*' ||
      c == '+' ||
      c == '?' ||
      c == '"' ||
      c == "'";
}

/// Splits on [sep] at the top level (ignoring inside quotes/brackets).
List<String> _splitTop(String s, String sep) {
  final out = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (quote != null) {
      buf.write(ch);
      if (ch == quote) quote = null;
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      buf.write(ch);
    } else if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
      buf.write(ch);
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
      buf.write(ch);
    } else if (ch == sep && depth == 0) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

// Upstream DEFAULT_RAILROAD_CONFIG: horizontalSeparation 10,
// verticalSeparation 8, padding 10, arcRadius 10, strokeWidth 2.
const _hGap = 10.0, _vGap = 8.0, _pad = 10.0;
const _arc = 10.0; // corner radius for loop/bypass arcs (arcRadius)
const _strokeWidth = 2.0;

// Terminal corner radius is a fixed 10px (not a full pill).
const _terminalRadius = 10.0;

// Railroad colors are theme-derived. Upstream `styles.ts:buildThemeDefaults`
// maps the railroad palette onto shared theme variables (the hex constants in
// DEFAULT_RAILROAD_CONFIG are only fallbacks when a theme variable is absent):
//   terminalFill        <- secondBkg ?? secondaryColor   (theme.secondaryColor)
//   terminalTextColor   <- secondaryTextColor ?? textColor (theme.textColor)
//   nonTerminalFill     <- mainBkg ?? background          (theme.mainBkg)
//   nonTerminalStroke   <- primaryBorderColor ?? lineColor (theme.nodeBorder)
//   nonTerminalTextColor<- primaryTextColor ?? textColor  (theme.primaryTextColor)
//   lineColor/markerFill<- lineColor                      (theme.lineColor)
//   ruleNameColor       <- titleColor ?? textColor        (theme.titleColor)
// `specialFill`/`specialStroke` derive from tertiaryColor/tertiaryBorderColor,
// which the shared theme does not expose, so they stay inlined (diagram-specific
// fallbacks #F0E0FF / #8800CC from DEFAULT_RAILROAD_CONFIG).
const _specialFill = Color(0xfff0e0ff);
const _specialStroke = Color(0xff8800cc);

const _markerRadius = 5.0;

/// A laid-out fragment of a railroad track. Coordinates are local to the
/// fragment's own origin; [entryY] / [exitY] give the y of the rail where the
/// fragment connects on its left / right edge (both measured from local 0,0).
/// The track always enters at x=0 and exits at x=[width].
class _Frag {
  _Frag({
    required this.nodes,
    required this.width,
    required this.height,
    required this.entryY,
    required this.exitY,
  });
  final List<SceneNode> nodes;
  final double width;
  final double height;
  final double entryY;
  final double exitY;
}

class _Layouter {
  _Layouter(this.measurer, this.theme)
      : baseStyle = const TextStyleSpec(
          // Upstream railroad forces fontFamily: monospace, fontSize: 14.
          fontFamily: 'monospace',
          fontSize: 14,
        );
  final TextMeasurer measurer;
  final MermaidTheme theme;
  final TextStyleSpec baseStyle;

  Stroke get _rail => Stroke(color: theme.lineColor, width: _strokeWidth);

  List<SceneNode> _hLine(double x1, double x2, double y) => [
        SceneShape(
          geometry: PathGeometry([MoveTo(Point(x1, y)), LineTo(Point(x2, y))]),
          stroke: _rail,
        ),
      ];

  List<SceneNode> _path(List<PathCommand> cmds) =>
      [SceneShape(geometry: PathGeometry(cmds), stroke: _rail)];

  _Frag _box(String label, {required bool terminal}) {
    final ts = measurer.measure(label, baseStyle);
    // Upstream: width = textW + padding*2, height = textH + padding*2.
    final bw = ts.width + 2 * _pad;
    final bh = ts.height + 2 * _pad;
    final rect = Rect.fromLTWH(0, 0, bw, bh);
    final mid = bh / 2;
    // Terminal: rounded rect (rx=ry=10). Non-terminal: plain rect (square).
    final radius = terminal ? _terminalRadius : 0.0;
    // Theme-derived: terminal uses secondBkg/secondaryColor + secondary text;
    // non-terminal uses mainBkg + primaryBorder + primary text (see comment at
    // top of file mirroring upstream buildThemeDefaults).
    final fill = terminal ? theme.secondaryColor : theme.mainBkg;
    final stroke = terminal ? theme.lineColor : theme.nodeBorder;
    final textColor = terminal ? theme.textColor : theme.primaryTextColor;
    return _Frag(
      nodes: [
        SceneShape(
          geometry: RectGeometry(rect, rx: radius, ry: radius),
          fill: Fill(fill),
          stroke: Stroke(color: stroke, width: _strokeWidth),
        ),
        SceneText(
          text: label,
          bounds: Rect.fromCenter(rect.center, ts.width, ts.height),
          style: baseStyle,
          color: textColor,
        ),
      ],
      width: bw,
      height: bh,
      entryY: mid,
      exitY: mid,
    );
  }

  /// Special sequence (`? text ?`): dashed-border rect.
  _Frag _special(String text) {
    final label = '? $text ?';
    final ts = measurer.measure(label, baseStyle);
    final bw = ts.width + 2 * _pad;
    final bh = ts.height + 2 * _pad;
    final rect = Rect.fromLTWH(0, 0, bw, bh);
    final mid = bh / 2;
    return _Frag(
      nodes: [
        SceneShape(
          geometry: RectGeometry(rect),
          fill: const Fill(_specialFill),
          stroke: const Stroke(
            color: _specialStroke,
            width: _strokeWidth,
            dash: [5, 3],
          ),
        ),
        SceneText(
          text: label,
          bounds: Rect.fromCenter(rect.center, ts.width, ts.height),
          style: baseStyle,
          // Upstream `.railroad-special text` uses nonTerminalTextColor.
          color: theme.primaryTextColor,
        ),
      ],
      width: bw,
      height: bh,
      entryY: mid,
      exitY: mid,
    );
  }

  /// A short straight rail used for empty fragments.
  _Frag _stub() {
    const h = 14.0 + 2 * _pad; // approx box height for alignment
    return _Frag(
      nodes: _hLine(0, _hGap, h / 2),
      width: _hGap,
      height: h,
      entryY: h / 2,
      exitY: h / 2,
    );
  }

  _Frag layout(RailroadExpr e) => switch (e) {
        RailroadTerminal(:final text) => _box(text, terminal: true),
        RailroadNonTerminal(:final text) => _box(text, terminal: false),
        RailroadSpecial(:final text) => _special(text),
        RailroadEmpty() => _stub(),
        RailroadSequence(:final items) => _layoutSequence(items),
        RailroadChoice(:final options) => _layoutChoice(options),
        RailroadOptional(:final child) => _layoutOptional(child),
        RailroadRepetition(:final child, :final oneOrMore) =>
          _layoutRepetition(child, oneOrMore),
      };

  /// Shifts every node in [frag] by (dx, dy).
  List<SceneNode> _shift(_Frag frag, double dx, double dy) =>
      [for (final n in frag.nodes) translateSceneNode(n, dx, dy)];

  _Frag _layoutSequence(List<RailroadExpr> items) {
    if (items.isEmpty) return _stub();
    final frags = [for (final it in items) layout(it)];
    // Baseline: align all fragment entry rails to a common y.
    final entryAbove =
        frags.map((f) => f.entryY).reduce(math.max); // space above baseline
    final exitBelow = frags
        .map((f) => f.height - f.entryY)
        .reduce(math.max); // space below baseline
    final baseline = entryAbove;
    final height = entryAbove + exitBelow;

    final nodes = <SceneNode>[];
    var x = 0.0;
    for (var i = 0; i < frags.length; i++) {
      final f = frags[i];
      final dy = baseline - f.entryY;
      if (i > 0) {
        nodes.addAll(_hLine(x, x + _hGap, baseline));
        x += _hGap;
      }
      nodes.addAll(_shift(f, x, dy));
      // The next item connects from this fragment's exit; bring exit rail back
      // to the baseline with a short connector if it differs.
      final exitYAbs = dy + f.exitY;
      if ((exitYAbs - baseline).abs() > 0.01 && i < frags.length - 1) {
        nodes.addAll(_path([
          MoveTo(Point(x + f.width, exitYAbs)),
          LineTo(Point(x + f.width, baseline)),
        ]));
      }
      x += f.width;
    }
    return _Frag(
      nodes: nodes,
      width: x,
      height: height,
      entryY: baseline,
      exitY: baseline,
    );
  }

  _Frag _layoutChoice(List<RailroadExpr> options) {
    final frags = [for (final o in options) layout(o)];
    final innerW = frags.map((f) => f.width).reduce(math.max);
    // Upstream choice adds arcRadius*4 of horizontal room (2 each side).
    const lead = _arc * 2;

    final nodes = <SceneNode>[];
    // Lay options stacked top-to-bottom.
    var y = 0.0;
    final rowEntryY = <double>[]; // absolute entry-rail y per option
    final rowX = <double>[]; // left x of each centred fragment
    for (final f in frags) {
      final fx = lead + (innerW - f.width) / 2;
      rowX.add(fx);
      rowEntryY.add(y + f.entryY);
      nodes.addAll(_shift(f, fx, y));
      y += f.height + _vGap;
    }
    final totalH = y - _vGap;
    // Upstream: the through baseline is the vertical centre of the whole stack.
    final baseline = totalH / 2;
    final width = lead + innerW + lead;
    final rightEnd = width;

    for (var i = 0; i < frags.length; i++) {
      final f = frags[i];
      final ry = rowEntryY[i];
      final fx = rowX[i];
      // Connector from fork lead-in to fragment left, and fragment right to
      // join lead-out.
      nodes.addAll(_hLine(lead, fx, ry));
      nodes.addAll(_hLine(fx + f.width, lead + innerW, ry));

      if ((ry - baseline).abs() < 0.01) {
        // On the centre line: straight through rails.
        nodes.addAll(_hLine(0, lead, baseline));
        nodes.addAll(_hLine(lead + innerW, rightEnd, baseline));
      } else {
        // Fork down/up from centre baseline at x=0..lead into row ry.
        nodes.addAll(_forkDown(0, baseline, lead, ry));
        // Join: row ry back to baseline at right.
        nodes.addAll(_joinUp(lead + innerW, ry, rightEnd, baseline));
      }
    }

    return _Frag(
      nodes: nodes,
      width: width,
      height: totalH,
      entryY: baseline,
      exitY: baseline,
    );
  }

  /// Fork rail: from (x0, y0) on the centre baseline, curve toward row y1
  /// (which may be above or below the baseline) and run to (x1, y1).
  List<SceneNode> _forkDown(double x0, double y0, double x1, double y1) {
    final dir = y1 >= y0 ? 1.0 : -1.0; // +1 = below baseline, -1 = above
    final r = math.min(_arc, (y1 - y0).abs() / 2);
    return _path([
      MoveTo(Point(x0, y0)),
      // First quarter turn off the baseline.
      CubicTo(
        Point(x0 + r, y0),
        Point(x0 + r, y0),
        Point(x0 + r, y0 + dir * r),
      ),
      LineTo(Point(x0 + r, y1 - dir * r)),
      // Second quarter turn back to horizontal at the row.
      CubicTo(
        Point(x0 + r, y1),
        Point(x0 + r, y1),
        Point(x0 + 2 * r, y1),
      ),
      LineTo(Point(x1, y1)),
    ]);
  }

  /// Join rail: from (x0, y1) on a branch row, curve back to (x1, y0) on the
  /// centre baseline. The row may be above or below the baseline.
  List<SceneNode> _joinUp(double x0, double y1, double x1, double y0) {
    final dir = y1 >= y0 ? 1.0 : -1.0; // +1 = row below baseline
    final r = math.min(_arc, (y1 - y0).abs() / 2);
    return _path([
      MoveTo(Point(x0, y1)),
      LineTo(Point(x1 - 2 * r, y1)),
      CubicTo(
        Point(x1 - r, y1),
        Point(x1 - r, y1),
        Point(x1 - r, y1 - dir * r),
      ),
      LineTo(Point(x1 - r, y0 + dir * r)),
      CubicTo(
        Point(x1 - r, y0),
        Point(x1 - r, y0),
        Point(x1, y0),
      ),
    ]);
  }

  /// Optional `[ x ]` / `x?`: item on the baseline with a bypass arc above.
  _Frag _layoutOptional(RailroadExpr child) {
    final f = layout(child);
    // Upstream: element offset by arcRadius*2 each side, bypass rise arcHeight.
    const lead = _arc * 2;
    const bypassRise = _arc * 2; // how far above the baseline the bypass runs
    final baseline = bypassRise + f.entryY;
    final width = lead + f.width + lead;
    final nodes = <SceneNode>[];

    // Item, centred horizontally, sitting on the baseline.
    final dy = baseline - f.entryY;
    nodes.addAll(_shift(f, lead, dy));
    // In/out stubs to the item.
    nodes.addAll(_hLine(0, lead, baseline));
    nodes.addAll(_hLine(lead + f.width, width, baseline));

    // Bypass arc: from left baseline up, across the top, back down to right.
    final topY = baseline - bypassRise;
    nodes.addAll(_path([
      MoveTo(Point(0, baseline)),
      CubicTo(Point(_arc, baseline), Point(_arc, baseline),
          Point(_arc, baseline - _arc)),
      LineTo(Point(_arc, topY + _arc)),
      CubicTo(Point(_arc, topY), Point(_arc, topY), Point(_arc + _arc, topY)),
      LineTo(Point(width - 2 * _arc, topY)),
      CubicTo(Point(width - _arc, topY), Point(width - _arc, topY),
          Point(width - _arc, topY + _arc)),
      LineTo(Point(width - _arc, baseline - _arc)),
      CubicTo(Point(width - _arc, baseline), Point(width - _arc, baseline),
          Point(width, baseline)),
    ]));

    return _Frag(
      nodes: nodes,
      width: width,
      height: math.max(baseline + (f.height - f.entryY), baseline),
      entryY: baseline,
      exitY: baseline,
    );
  }

  /// Repetition `{ x }` / `x*` / `x+`: item on the baseline with a return arc.
  /// For zero-or-more the whole thing can be skipped via a bypass above; the
  /// return loop runs below. For one-or-more there is no skip.
  _Frag _layoutRepetition(RailroadExpr child, bool oneOrMore) {
    final f = layout(child);
    // Upstream: element offset by arcRadius*2 each side; loop/bypass arcHeight.
    const lead = _arc * 2;
    const loopDrop = _arc * 2; // how far below baseline the return arc runs
    const bypassRise = _arc * 2; // skip arc above (zero-or-more only)
    final topPad = oneOrMore ? 0.0 : bypassRise;
    final baseline = topPad + f.entryY;
    final width = lead + f.width + lead;
    final nodes = <SceneNode>[];

    final dy = baseline - f.entryY;
    nodes.addAll(_shift(f, lead, dy));
    nodes.addAll(_hLine(0, lead, baseline));
    nodes.addAll(_hLine(lead + f.width, width, baseline));

    // Return loop below: from right side of item back to left side.
    final botY = baseline + loopDrop;
    nodes.addAll(_path([
      MoveTo(Point(lead + f.width, baseline)),
      CubicTo(Point(lead + f.width + _arc, baseline),
          Point(lead + f.width + _arc, baseline),
          Point(lead + f.width + _arc, baseline + _arc)),
      LineTo(Point(lead + f.width + _arc, botY - _arc)),
      CubicTo(
          Point(lead + f.width + _arc, botY),
          Point(lead + f.width + _arc, botY),
          Point(lead + f.width, botY)),
      LineTo(Point(lead, botY)),
      CubicTo(Point(lead - _arc, botY), Point(lead - _arc, botY),
          Point(lead - _arc, botY - _arc)),
      LineTo(Point(lead - _arc, baseline + _arc)),
      CubicTo(Point(lead - _arc, baseline), Point(lead - _arc, baseline),
          Point(lead, baseline)),
    ]));

    if (!oneOrMore) {
      // Skip bypass above (zero traversals).
      final topY = baseline - bypassRise;
      nodes.addAll(_path([
        MoveTo(Point(0, baseline)),
        CubicTo(Point(_arc, baseline), Point(_arc, baseline),
            Point(_arc, baseline - _arc)),
        LineTo(Point(_arc, topY + _arc)),
        CubicTo(Point(_arc, topY), Point(_arc, topY), Point(_arc + _arc, topY)),
        LineTo(Point(width - 2 * _arc, topY)),
        CubicTo(Point(width - _arc, topY), Point(width - _arc, topY),
            Point(width - _arc, topY + _arc)),
        LineTo(Point(width - _arc, baseline - _arc)),
        CubicTo(Point(width - _arc, baseline), Point(width - _arc, baseline),
            Point(width, baseline)),
      ]));
    }

    final bottom = math.max(botY, baseline + (f.height - f.entryY));
    return _Frag(
      nodes: nodes,
      width: width,
      height: bottom,
      entryY: baseline,
      exitY: baseline,
    );
  }
}

RenderScene layoutRailroad(
  RailroadDiagram d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  // Upstream forces monospace / fontSize 14 for the whole diagram.
  final baseStyle =
      const TextStyleSpec(fontFamily: 'monospace', fontSize: 14);
  final nameStyle = baseStyle.copyWith(fontWeight: 700);
  final layouter = _Layouter(measurer, theme);
  final nodes = <SceneNode>[];
  var y = 0.0;

  // Rail / marker color is theme.lineColor; rule-name color is theme.titleColor
  // (upstream lineColor / titleColor; see buildThemeDefaults).
  final rail = Stroke(color: theme.lineColor, width: _strokeWidth);
  final markerFill = Fill(theme.lineColor);

  for (final rule in d.rules) {
    // Upstream: name label is "<name> =" on the rail baseline, to the left.
    final ruleName = '${rule.name} =';
    final ns = measurer.measure(ruleName, nameStyle);
    final nameWidth = ns.width + 20; // start-marker x
    final definitionX = nameWidth + 20;

    final frag = layouter.layout(rule.expr);
    // Baseline at least 20 from the rule top (upstream `Math.max(20, up)`).
    final baselineY = y + math.max(20.0, frag.entryY);
    final definitionY = baselineY - frag.entryY;

    final children = <SceneNode>[
      for (final n in frag.nodes)
        translateSceneNode(n, definitionX, definitionY),
    ];

    // Rule name label, vertically centred on the rail baseline.
    children.add(SceneText(
      text: ruleName,
      bounds: Rect.fromLTWH(0, baselineY - ns.height / 2, ns.width, ns.height),
      style: nameStyle,
      color: theme.titleColor,
      align: TextAlignH.left,
    ));

    // Start marker (filled circle) + line into the definition.
    children.add(SceneShape(
      geometry: CircleGeometry(Point(nameWidth, baselineY), _markerRadius),
      fill: markerFill,
    ));
    children.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(nameWidth + _markerRadius, baselineY)),
        LineTo(Point(definitionX, baselineY)),
      ]),
      stroke: rail,
    ));

    // End marker (filled circle) + line out of the definition.
    final endX = definitionX + frag.width + 10;
    children.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(definitionX + frag.width, baselineY)),
        LineTo(Point(endX - _markerRadius, baselineY)),
      ]),
      stroke: rail,
    ));
    children.add(SceneShape(
      geometry: CircleGeometry(Point(endX, baselineY), _markerRadius),
      fill: markerFill,
    ));

    nodes.add(SceneGroup(id: rule.name, children: children));

    // Advance below this rule (upstream: rule height + verticalSeparation).
    final ruleBottom = definitionY + frag.height;
    y = math.max(baselineY + _markerRadius, ruleBottom) + 2 * _pad + _vGap;
  }

  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 200, 80);
  final children = [...nodes];
  if (d.title != null && d.title!.isNotEmpty) {
    final style = nameStyle.copyWith(fontSize: theme.fontSize * 1.15);
    final ts = measurer.measure(d.title!, style);
    final node = SceneText(
      text: d.title!,
      bounds: Rect.fromLTWH(0, bounds.top - ts.height - 8, ts.width, ts.height),
      style: style,
      color: theme.titleColor,
      align: TextAlignH.left,
    );
    children.add(node);
    bounds = bounds.union(node.bounds);
  }
  const m = _pad; // outer margin = upstream padding (10)
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final n in children)
        translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

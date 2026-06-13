/// Railroad / syntax diagram (`railroad-diagram`): EBNF-ish rules rendered as
/// railroad tracks. Each `name = expr ;` is one row; `|` alternatives stack
/// vertically with fork/join rails, sequences run left-to-right, and
/// terminals/non-terminals are boxes.
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

class RailroadRule {
  RailroadRule(this.name, this.alternatives);
  final String name;

  /// Each alternative is a sequence of (text, isTerminal) items.
  final List<List<(String, bool)>> alternatives;
}

class RailroadDiagram {
  const RailroadDiagram(this.rules, this.title);
  final List<RailroadRule> rules;
  final String? title;
}

RailroadDiagram parseRailroad(String source) {
  final text = stripMetadata(source);
  // Rules end with `;`; join the body and split on `;`.
  final lines = text.split('\n');
  var seenHeader = false;
  String? title;
  final body = StringBuffer();
  for (var line in lines) {
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

  final rules = <RailroadRule>[];
  for (final stmt in body.toString().split(';')) {
    final s = stmt.trim();
    if (s.isEmpty) continue;
    final eq = s.indexOf('=');
    if (eq < 0) continue;
    final name = s.substring(0, eq).trim();
    final expr = s.substring(eq + 1).trim();
    final alts = <List<(String, bool)>>[];
    for (final alt in _splitTop(expr, '|')) {
      final seq = <(String, bool)>[];
      for (final tok in _tokens(alt)) {
        final terminal = tok.startsWith('"') || tok.startsWith("'");
        final label = terminal ? tok.substring(1, tok.length - 1) : tok;
        seq.add((label, terminal));
      }
      if (seq.isNotEmpty) alts.add(seq);
    }
    rules.add(RailroadRule(name, alts));
  }
  return RailroadDiagram(rules, title);
}

/// Splits on [sep] at the top level (ignoring inside quotes/parens).
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

List<String> _tokens(String s) {
  final out = <String>[];
  final re = RegExp(r'"[^"]*"|' r"'[^']*'" r'|[^\s]+');
  for (final m in re.allMatches(s.trim())) {
    out.add(m.group(0)!);
  }
  return out;
}

const _hGap = 26.0, _vGap = 18.0, _boxH = 30.0, _pad = 10.0;

RenderScene layoutRailroad(
  RailroadDiagram d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final nameStyle = baseStyle.copyWith(fontWeight: 700);
  final nodes = <SceneNode>[];
  var y = 0.0;

  for (final rule in d.rules) {
    // Rule name label.
    final ns = measurer.measure(rule.name, nameStyle);
    nodes.add(SceneText(
      text: rule.name,
      bounds: Rect.fromLTWH(0, y, ns.width, ns.height),
      style: nameStyle,
      color: theme.titleColor,
      align: TextAlignH.left,
    ));
    var ay = y + ns.height + 10;

    final startX = 20.0;
    // Measure alternative widths to align fork/join rails.
    var maxW = 0.0;
    final altWidths = <double>[];
    for (final alt in rule.alternatives) {
      var wsum = 0.0;
      for (final (label, _) in alt) {
        wsum += measurer.measure(label, baseStyle).width + 2 * _pad + _hGap;
      }
      altWidths.add(wsum);
      maxW = math.max(maxW, wsum);
    }
    final forkX = startX + 14;
    final joinX = forkX + maxW + 14;

    for (var ai = 0; ai < rule.alternatives.length; ai++) {
      final alt = rule.alternatives[ai];
      final rowY = ay + _boxH / 2;
      // Rails from fork to first box and last box to join.
      nodes.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(startX, y + ns.height + 10 + _boxH / 2)),
          LineTo(Point(forkX, y + ns.height + 10 + _boxH / 2)),
        ]),
        stroke: Stroke(color: theme.lineColor, width: 1.5),
      ));
      // Fork branch line.
      nodes.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(forkX, y + ns.height + 10 + _boxH / 2)),
          LineTo(Point(forkX, rowY)),
          LineTo(Point(forkX + 10, rowY)),
        ]),
        stroke: Stroke(color: theme.lineColor, width: 1.5),
      ));
      var x = forkX + 10;
      for (final (label, terminal) in alt) {
        final ts = measurer.measure(label, baseStyle);
        final bw = ts.width + 2 * _pad;
        final rect = Rect.fromLTWH(x, ay, bw, _boxH);
        nodes.add(SceneShape(
          geometry: RectGeometry(rect,
              rx: terminal ? _boxH / 2 : 4, ry: terminal ? _boxH / 2 : 4),
          fill: Fill(terminal ? const Color(0xffd7f0d7) : theme.mainBkg),
          stroke: Stroke(color: theme.nodeBorder),
        ));
        nodes.add(SceneText(
          text: label,
          bounds: Rect.fromCenter(rect.center, ts.width, ts.height),
          style: baseStyle,
          color: theme.textColor,
        ));
        // Connector to next.
        nodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(x + bw, rowY)),
            LineTo(Point(x + bw + _hGap, rowY)),
          ]),
          stroke: Stroke(color: theme.lineColor, width: 1.5),
        ));
        x += bw + _hGap;
      }
      // Branch into join.
      nodes.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(x, rowY)),
          LineTo(Point(joinX, rowY)),
          LineTo(Point(joinX, y + ns.height + 10 + _boxH / 2)),
        ]),
        stroke: Stroke(color: theme.lineColor, width: 1.5),
      ));
      ay += _boxH + _vGap;
    }
    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(joinX, y + ns.height + 10 + _boxH / 2)),
        LineTo(Point(joinX + 16, y + ns.height + 10 + _boxH / 2)),
      ]),
      stroke: Stroke(color: theme.lineColor, width: 1.5),
    ));
    y = ay + 24;
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
  const m = 16.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final n in children) translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

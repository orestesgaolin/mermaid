/// Hand-written parser for mermaid sequence diagrams.
///
/// Grammar reference: upstream `sequence/parser/sequenceDiagram.jison` and
/// semantics in `sequenceDb.ts`. Validated against cases ported from
/// `sequenceDiagram.spec.js`.
library;

import '../../detect.dart';
import '../../parse_error.dart';
import 'sequence_model.dart';

SequenceDiagram parseSequence(String source) {
  final title = frontmatterTitle(source);
  return _SequenceParser(stripMetadata(source), title).parse();
}

/// Longest-first so e.g. `-->>` wins over `-->`.
const _arrowTokens = <(String, SeqArrow)>[
  ('<<-->>', SeqArrow.bidirectionalDotted),
  ('<<->>', SeqArrow.bidirectionalSolid),
  ('-->>', SeqArrow.dottedArrow),
  ('->>', SeqArrow.solidArrow),
  ('--x', SeqArrow.dottedCross),
  ('--)', SeqArrow.dottedPoint),
  ('-->', SeqArrow.dottedOpen),
  ('-x', SeqArrow.solidCross),
  ('-)', SeqArrow.solidPoint),
  ('->', SeqArrow.solidOpen),
];

class _SequenceParser {
  _SequenceParser(this.text, this.frontTitle);

  final String text;
  final String? frontTitle;

  final participants = <String, SeqParticipant>{};
  final events = <SeqEvent>[];
  String? title;

  /// Open block kinds, for validating `else`/`and`/`option`/`end`.
  final _blockStack = <SeqBlockKind>[];

  /// Activation depth per participant (deactivating below zero is an error,
  /// matching upstream).
  final _activationDepth = <String, int>{};

  /// `box ... end` groups are parsed and discarded; `end` closes them too.
  var _openBoxes = 0;

  SequenceDiagram parse() {
    title = frontTitle;
    final lines = text.split('\n');
    var seenHeader = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (line.isEmpty) continue;
      // Strip trailing comment and `;` statement terminator.
      final comment = line.indexOf('%%');
      if (comment >= 0) line = line.substring(0, comment).trim();
      if (line.endsWith(';')) line = line.substring(0, line.length - 1).trim();
      if (line.isEmpty) continue;
      if (!seenHeader) {
        if (!RegExp(r'^sequenceDiagram\b').hasMatch(line)) {
          throw MermaidParseException('expected "sequenceDiagram" header',
              line: i + 1);
        }
        seenHeader = true;
        continue;
      }
      _parseStatement(line, i + 1);
    }
    if (!seenHeader) {
      throw const MermaidParseException('empty sequence diagram source');
    }
    if (_blockStack.isNotEmpty) {
      throw MermaidParseException(
          'unclosed "${_blockStack.last.name}" block');
    }
    return SequenceDiagram(
      participants: participants,
      events: events,
      title: title,
    );
  }

  void _parseStatement(String line, int n) {
    Match? m;

    m = RegExp(r'^(participant|actor)\s+(.+)$').firstMatch(line);
    if (m != null && !line.contains(RegExp(r'(<<-->>|<<->>|-->>|->>|--[x)>]|-[x)>])'))) {
      _declareParticipant(m.group(2)!.trim(), isActor: m.group(1) == 'actor');
      return;
    }

    // `create participant X` / `create actor X` — treated as a declaration;
    // `destroy X` is parsed and ignored (lifeline shortening not yet ported).
    m = RegExp(r'^create\s+(participant|actor)\s+(.+)$').firstMatch(line);
    if (m != null) {
      _declareParticipant(m.group(2)!.trim(), isActor: m.group(1) == 'actor');
      return;
    }
    if (RegExp(r'^destroy\s+').hasMatch(line)) return;

    m = RegExp(r'^(de)?activate\s+(.+)$').firstMatch(line);
    if (m != null) {
      _activation(m.group(2)!.trim(), active: m.group(1) == null, lineNo: n);
      return;
    }

    m = RegExp(r'^[Nn]ote\s+(right of|left of|over)\s+([^:]+):\s*(.*)$')
        .firstMatch(line);
    if (m != null) {
      final placement = switch (m.group(1)!) {
        'right of' => NotePlacement.rightOf,
        'left of' => NotePlacement.leftOf,
        _ => NotePlacement.over,
      };
      final targets = m.group(2)!.split(',').map((s) => s.trim()).toList();
      if (placement != NotePlacement.over && targets.length > 1) {
        throw MermaidParseException(
            'only "Note over" may span two participants', line: n);
      }
      for (final t in targets) {
        _ensureParticipant(t);
      }
      events.add(SeqNote(
        placement: placement,
        target: targets[0],
        target2: targets.length > 1 ? targets[1] : null,
        text: _normalizeText(m.group(3)!),
      ));
      return;
    }

    m = RegExp(r'^(loop|opt|alt|par|critical|break|rect)\b\s*(.*)$')
        .firstMatch(line);
    if (m != null) {
      final kind = switch (m.group(1)!) {
        'loop' => SeqBlockKind.loop,
        'opt' => SeqBlockKind.opt,
        'alt' => SeqBlockKind.alt,
        'par' => SeqBlockKind.par,
        'critical' => SeqBlockKind.critical,
        'break' => SeqBlockKind.breakBlock,
        _ => SeqBlockKind.rect,
      };
      final rest = _normalizeText(m.group(2)!);
      _blockStack.add(kind);
      events.add(kind == SeqBlockKind.rect
          ? SeqBlockStart(kind, '', color: rest.isEmpty ? null : rest)
          : SeqBlockStart(kind, rest));
      return;
    }

    m = RegExp(r'^(else|and|option)\b\s*(.*)$').firstMatch(line);
    if (m != null) {
      final keyword = m.group(1)!;
      final expected = switch (keyword) {
        'else' => SeqBlockKind.alt,
        'and' => SeqBlockKind.par,
        _ => SeqBlockKind.critical,
      };
      if (_blockStack.isEmpty || _blockStack.last != expected) {
        throw MermaidParseException(
            '"$keyword" outside of ${expected.name} block', line: n);
      }
      events.add(SeqBlockDivider(_normalizeText(m.group(2)!)));
      return;
    }

    if (RegExp(r'^box\b').hasMatch(line)) {
      // Participant grouping boxes are not rendered yet; participants inside
      // still register via their own statements.
      _openBoxes++;
      return;
    }

    if (line == 'end') {
      if (_openBoxes > 0) {
        _openBoxes--;
        return;
      }
      if (_blockStack.isEmpty) {
        throw MermaidParseException('"end" without open block', line: n);
      }
      _blockStack.removeLast();
      events.add(const SeqBlockEnd());
      return;
    }

    m = RegExp(r'^autonumber\b\s*(.*)$').firstMatch(line);
    if (m != null) {
      final rest = m.group(1)!.trim();
      if (rest == 'off') {
        events.add(const SeqAutonumber(on: false));
      } else {
        final nums = RegExp(r'\d+').allMatches(rest).toList();
        events.add(SeqAutonumber(
          on: true,
          start: nums.isNotEmpty ? int.parse(nums[0].group(0)!) : null,
          step: nums.length > 1 ? int.parse(nums[1].group(0)!) : null,
        ));
      }
      return;
    }

    m = RegExp(r'^title\s*:?\s+(.*)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      return;
    }

    // Accessibility and link metadata: parsed and discarded.
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(line)) return;
    if (RegExp(r'^(links?|properties|details)\s+').hasMatch(line)) return;

    if (_parseMessage(line, n)) return;

    throw MermaidParseException('unrecognized statement "$line"', line: n);
  }

  bool _parseMessage(String line, int n) {
    // Participant names cannot contain + - > < : , ; (upstream ACTOR token),
    // so the first arrow-ish character terminates the source name.
    for (final (token, arrow) in _arrowTokens) {
      final idx = line.indexOf(token);
      if (idx <= 0) continue;
      final from = line.substring(0, idx).trim();
      if (from.isEmpty || from.contains(RegExp(r'[+\->:<,;]'))) continue;
      var rest = line.substring(idx + token.length).trim();

      String? suffix;
      if (rest.startsWith('+') || rest.startsWith('-')) {
        suffix = rest[0];
        rest = rest.substring(1).trim();
      }
      String to;
      String msg;
      final colon = rest.indexOf(':');
      if (colon >= 0) {
        to = rest.substring(0, colon).trim();
        msg = rest.substring(colon + 1).trim();
      } else {
        to = rest;
        msg = '';
      }
      if (to.isEmpty || to.contains(RegExp(r'[+\->:<,;]'))) {
        throw MermaidParseException('expected participant after arrow',
            line: n);
      }
      _ensureParticipant(from);
      _ensureParticipant(to);
      events.add(SeqMessage(
        from: from,
        to: to,
        arrow: arrow,
        text: _normalizeText(msg),
      ));
      // `A->>+B` activates the receiver, `B-->>-A` deactivates the sender
      // (upstream signal rules).
      if (suffix == '+') _activation(to, active: true, lineNo: n);
      if (suffix == '-') _activation(from, active: false, lineNo: n);
      return true;
    }
    return false;
  }

  void _activation(String id, {required bool active, required int lineNo}) {
    _ensureParticipant(id);
    final depth = (_activationDepth[id] ?? 0) + (active ? 1 : -1);
    if (depth < 0) {
      // Mirrors upstream's "Trying to inactivate an inactive participant".
      throw MermaidParseException(
          'trying to deactivate inactive participant "$id"', line: lineNo);
    }
    _activationDepth[id] = depth;
    events.add(SeqActivation(id, active: active));
  }

  void _declareParticipant(String decl, {required bool isActor}) {
    final asMatch = RegExp(r'^(.+?)\s+as\s+(.+)$').firstMatch(decl);
    final id = (asMatch != null ? asMatch.group(1)! : decl).trim();
    final label =
        _normalizeText((asMatch != null ? asMatch.group(2)! : decl).trim());
    final existing = participants[id];
    participants[id] = SeqParticipant(
      id: id,
      label: label,
      isActor: isActor || (existing?.isActor ?? false),
    );
  }

  void _ensureParticipant(String id) {
    participants.putIfAbsent(
        id, () => SeqParticipant(id: id, label: _normalizeText(id)));
  }

  String _normalizeText(String s) {
    var out = s.trim();
    if (out.length >= 2 && out.startsWith('"') && out.endsWith('"')) {
      out = out.substring(1, out.length - 1);
    }
    return out
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .trim();
  }
}

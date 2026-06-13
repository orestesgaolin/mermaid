/// Hand-written parser for mermaid state diagrams (v1 and v2 headers).
///
/// Grammar reference: upstream `state/parser/stateDiagram.jison` and
/// `stateDb.ts`; validated against cases ported from stateDiagram.spec.js.
library;

import '../../detect.dart';
import '../../parse_error.dart';
import '../flowchart/flow_model.dart' show FlowDirection;
import 'state_model.dart';

StateDiagram parseStateDiagram(String source) {
  final title = frontmatterTitle(source);
  return _StateParser(stripMetadata(source), title).parse();
}

class _StateParser {
  _StateParser(this.text, this.frontTitle);

  final String text;
  final String? frontTitle;

  final states = <String, StateNode>{};
  final transitions = <StateTransition>[];
  final notes = <StateNote>[];
  final classDefs = <String, Map<String, String>>{};
  var direction = FlowDirection.tb;
  String? title;

  /// Stack of open composite state ids ('' = root scope).
  final _scope = <String>[''];

  /// Multiline `note left of X ... end note` accumulation.
  (StateNotePosition, String, StringBuffer)? _openNote;

  StateDiagram parse() {
    title = frontTitle;
    final lines = text.split('\n');
    var seenHeader = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      final comment = line.indexOf('%%');
      if (comment >= 0) line = line.substring(0, comment).trim();
      if (line.isEmpty) continue;
      if (!seenHeader) {
        if (!RegExp(r'^stateDiagram(-v2)?\b').hasMatch(line)) {
          throw MermaidParseException('expected "stateDiagram" header',
              line: i + 1);
        }
        seenHeader = true;
        continue;
      }
      _parseStatement(line, i + 1);
    }
    if (!seenHeader) {
      throw const MermaidParseException('empty state diagram source');
    }
    if (_scope.length > 1) {
      throw MermaidParseException('unclosed composite state "${_scope.last}"');
    }
    return StateDiagram(
      states: states,
      transitions: transitions,
      notes: notes,
      classDefs: classDefs,
      direction: direction,
      title: title,
    );
  }

  void _parseStatement(String line, int n) {
    if (_openNote != null) {
      if (line == 'end note') {
        final (pos, target, buf) = _openNote!;
        notes.add(StateNote(
            target: target, text: buf.toString().trim(), position: pos));
        _openNote = null;
      } else {
        _openNote!.$3.writeln(line);
      }
      return;
    }

    Match? m;

    if (line == '}') {
      if (_scope.length <= 1) {
        throw MermaidParseException('"}" without open composite state',
            line: n);
      }
      final closed = _scope.removeLast();
      final groups = _regions.remove(closed);
      if (groups != null && groups.length > 1) {
        states[closed] = states[closed]!.copyWith(
            regions: [for (final g in groups) if (g.isNotEmpty) g]);
      }
      return;
    }

    // Concurrency separator inside a composite: start a new region group.
    if (line == '--' && _scope.length > 1) {
      _regions[_scope.last]?.add(<String>[]);
      return;
    }

    m = RegExp(r'^direction\s+(TB|TD|BT|LR|RL)\s*$').firstMatch(line);
    if (m != null) {
      direction = switch (m.group(1)!) {
        'BT' => FlowDirection.bt,
        'LR' => FlowDirection.lr,
        'RL' => FlowDirection.rl,
        _ => FlowDirection.tb,
      };
      return;
    }

    // state <id> <<choice>> / <<fork>> / <<join>>
    m = RegExp(r'^state\s+(\S+)\s*(<<(choice|fork|join)>>|\[\[(fork|join)\]\])\s*$')
        .firstMatch(line);
    if (m != null) {
      final kind = switch (m.group(3) ?? m.group(4)!) {
        'choice' => StateKind.choice,
        'fork' => StateKind.fork,
        _ => StateKind.join,
      };
      final node = _ensure(m.group(1)!);
      states[node.id] = node.copyWith(kind: kind);
      return;
    }

    // state "description" as id [{]
    m = RegExp(r'^state\s+"([^"]*)"\s+as\s+(\S+?)\s*(\{)?\s*$').firstMatch(line);
    if (m != null) {
      final node = _ensure(m.group(2)!);
      states[node.id] = node.copyWith(label: _normalize(m.group(1)!));
      if (m.group(3) != null) _openComposite(node.id);
      return;
    }

    // state id [{]
    m = RegExp(r'^state\s+([^\s{]+)\s*(\{)?\s*$').firstMatch(line);
    if (m != null) {
      final node = _ensure(m.group(1)!);
      if (m.group(2) != null) _openComposite(node.id);
      return;
    }

    // note left of X : text  |  note right of X (multiline until `end note`)
    m = RegExp(r'^[Nn]ote\s+(left|right)\s+of\s+([^\s:]+)\s*(?::\s*(.*))?$')
        .firstMatch(line);
    if (m != null) {
      final pos = m.group(1) == 'left'
          ? StateNotePosition.leftOf
          : StateNotePosition.rightOf;
      _ensure(m.group(2)!);
      if (m.group(3) != null) {
        notes.add(StateNote(
            target: m.group(2)!,
            text: _normalize(m.group(3)!),
            position: pos));
      } else {
        _openNote = (pos, m.group(2)!, StringBuffer());
      }
      return;
    }

    m = RegExp(r'^classDef\s+(\S+)\s+(.+)$').firstMatch(line);
    if (m != null) {
      final styles = _parseStyles(m.group(2)!);
      for (final name in m.group(1)!.split(',')) {
        classDefs[name.trim()] = styles;
      }
      return;
    }

    m = RegExp(r'^class\s+([\w,\s]+?)\s+(\S+)\s*$').firstMatch(line);
    if (m != null) {
      for (final id in m.group(1)!.split(',')) {
        final node = _ensure(id.trim());
        states[node.id] =
            node.copyWith(cssClasses: [...node.cssClasses, m.group(2)!]);
      }
      return;
    }

    m = RegExp(r'^style\s+([\w,]+)\s+(.+)$').firstMatch(line);
    if (m != null) {
      for (final id in m.group(1)!.split(',')) {
        final node = _ensure(id.trim());
        states[node.id] =
            node.copyWith(styles: {...node.styles, ..._parseStyles(m.group(2)!)});
      }
      return;
    }

    if (RegExp(r'^(hide empty description|scale\s|click\s|acc(Title|Descr))')
        .hasMatch(line)) {
      return;
    }

    // Transition: A --> B : label
    m = RegExp(r'^(\[\*\]|[^\s-]\S*?)\s*-->\s*(\[\*\]|[^\s:]+)\s*(?::\s*(.*))?$')
        .firstMatch(line);
    if (m != null) {
      final from = _resolvePseudo(m.group(1)!, isSource: true);
      final to = _resolvePseudo(m.group(2)!, isSource: false);
      transitions.add(StateTransition(
        from: from,
        to: to,
        label: m.group(3) == null ? null : _normalize(m.group(3)!),
      ));
      return;
    }

    // `id : description` (appends on repeat, like upstream).
    m = RegExp(r'^([^\s:]+)\s*:\s*(.+)$').firstMatch(line);
    if (m != null) {
      final node = _ensure(m.group(1)!);
      final desc = _normalize(m.group(2)!);
      states[node.id] = node.copyWith(
        label: node.label == node.id ? desc : '${node.label}\n$desc',
      );
      return;
    }

    // Bare state mention (word-ish ids only, per upstream ID token).
    if (RegExp(r'^[\w.-]+$').hasMatch(line)) {
      _ensure(line);
      return;
    }

    throw MermaidParseException('unrecognized statement "$line"', line: n);
  }

  void _openComposite(String id) {
    states[id] = states[id]!.copyWith(kind: StateKind.composite);
    _scope.add(id);
    _regions[id] = [<String>[]];
  }

  /// `[*]` is a per-scope start (as source) or end (as target) pseudo-state;
  /// `[H]` / `[H*]` are per-scope shallow / deep history pseudo-states.
  String _resolvePseudo(String raw, {required bool isSource}) {
    if (raw == '[H]' || raw == '[H*]') {
      final scope = _scope.last;
      final deep = raw == '[H*]';
      final id = '__history_${deep ? 'deep_' : ''}$scope';
      if (!states.containsKey(id)) {
        states[id] = StateNode(
          id: id,
          label: '',
          kind: deep ? StateKind.historyDeep : StateKind.history,
          parent: scope.isEmpty ? null : scope,
        );
        _attachToScope(id);
      }
      return id;
    }
    if (raw != '[*]') return _ensure(raw).id;
    final scope = _scope.last;
    final id = isSource ? '__start_$scope' : '__end_$scope';
    if (!states.containsKey(id)) {
      states[id] = StateNode(
        id: id,
        label: '',
        kind: isSource ? StateKind.start : StateKind.end,
        parent: scope.isEmpty ? null : scope,
      );
      _attachToScope(id);
    }
    return id;
  }

  StateNode _ensure(String id) {
    final existing = states[id];
    if (existing != null) return existing;
    final node = StateNode(
      id: id,
      label: _normalize(id),
      parent: _scope.last.isEmpty ? null : _scope.last,
    );
    states[id] = node;
    _attachToScope(id);
    return node;
  }

  /// Region groups per open composite scope; finalized into the node's
  /// `regions` on close (only kept when more than one group exists).
  final _regions = <String, List<List<String>>>{};

  void _attachToScope(String id) {
    final scope = _scope.last;
    if (scope.isEmpty) return;
    final parent = states[scope]!;
    states[scope] = parent.copyWith(children: [...parent.children, id]);
    final groups = _regions[scope];
    if (groups != null) groups.last.add(id);
  }

  String _normalize(String s) => s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .trim();

  Map<String, String> _parseStyles(String text) {
    final out = <String, String>{};
    var depth = 0;
    final parts = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == ',' && depth == 0) {
        parts.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    parts.add(buf.toString());
    for (final part in parts) {
      final i = part.indexOf(':');
      if (i <= 0) continue;
      out[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return out;
  }
}

/// Hand-written parser for mermaid ER diagrams.
///
/// Grammar reference: upstream `er/parser/erDiagram.jison` and `erDb.ts`;
/// validated against cases ported from erDiagram.spec.js.
library;

import '../../detect.dart';
import '../../parse_error.dart';
import '../flowchart/flow_model.dart' show FlowDirection;
import 'er_model.dart';

ErDiagram parseErDiagram(String source) {
  final title = frontmatterTitle(source);
  return _ErParser(stripMetadata(source), title).parse();
}

/// Cardinality tokens, left-of-line and right-of-line spellings.
const _leftCards = <(String, ErCardinality)>[
  ('|o', ErCardinality.zeroOrOne),
  ('||', ErCardinality.onlyOne),
  ('}o', ErCardinality.zeroOrMore),
  ('}|', ErCardinality.oneOrMore),
];
const _rightCards = <(String, ErCardinality)>[
  ('o|', ErCardinality.zeroOrOne),
  ('||', ErCardinality.onlyOne),
  ('o{', ErCardinality.zeroOrMore),
  ('|{', ErCardinality.oneOrMore),
];

class _ErParser {
  _ErParser(this.text, this.frontTitle);

  final String text;
  final String? frontTitle;

  final entities = <String, ErEntity>{};
  final relationships = <ErRelationship>[];
  final classDefs = <String, List<String>>{};
  var direction = FlowDirection.tb;
  String? title;

  /// Entity id whose `{ ... }` attribute block is open.
  String? _openEntity;

  ErDiagram parse() {
    title = frontTitle;
    final lines = text.split('\n');
    var seenHeader = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      final comment = line.indexOf('%%');
      if (comment >= 0) line = line.substring(0, comment).trim();
      if (line.isEmpty) continue;
      if (!seenHeader) {
        if (!RegExp(r'^erDiagram\b').hasMatch(line)) {
          throw MermaidParseException('expected "erDiagram" header',
              line: i + 1);
        }
        seenHeader = true;
        continue;
      }
      _parseStatement(line, i + 1);
    }
    if (!seenHeader) {
      throw const MermaidParseException('empty ER diagram source');
    }
    if (_openEntity != null) {
      throw MermaidParseException('unclosed attribute block on "$_openEntity"');
    }
    return ErDiagram(
      entities: entities,
      relationships: relationships,
      direction: direction,
      title: title,
      classDefs: classDefs,
    );
  }

  void _parseStatement(String line, int n) {
    if (_openEntity != null) {
      if (line == '}') {
        _openEntity = null;
        return;
      }
      _parseAttribute(_openEntity!, line, n);
      return;
    }

    Match? m;

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

    if (RegExp(r'^(accTitle|accDescr)\s*[:{]').hasMatch(line)) return;
    m = RegExp(r'^title\s+(.*)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      return;
    }

    // Styling directives (erDb.addCssStyles / addClass / setClass).
    m = RegExp(r'^classDef\s+([\w-]+)\s+(.+)$').firstMatch(line);
    if (m != null) {
      classDefs[m.group(1)!] = _splitStyles(m.group(2)!);
      return;
    }
    m = RegExp(r'^style\s+([\wÀ-￿-]+)\s+(.+)$').firstMatch(line);
    if (m != null) {
      final id = m.group(1)!;
      final entity = entities[id];
      if (entity != null) {
        entities[id] = entity.copyWith(cssStyles: _splitStyles(m.group(2)!));
      }
      return;
    }
    m = RegExp(r'^class\s+([\w,\s-]+?)\s+([\w-]+)\s*$').firstMatch(line);
    if (m != null) {
      final className = m.group(2)!;
      for (final raw in m.group(1)!.split(',')) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        final entity = entities[id];
        if (entity != null) {
          entities[id] =
              entity.copyWith(cssClasses: [...entity.cssClasses, className]);
        }
      }
      return;
    }

    if (_parseRelationship(line, n)) return;

    // Entity declaration: NAME, "QUOTED NAME", alias[Label], with optional `{`.
    m = RegExp(r'^("([^"]+)"|[\wÀ-￿-]+)\s*(\[([^\]]+)\])?\s*(\{)?\s*$')
        .firstMatch(line);
    if (m != null) {
      final id = m.group(2) ?? m.group(1)!;
      var label = m.group(4)?.trim() ?? id;
      if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
        label = label.substring(1, label.length - 1);
      }
      final existing = entities[id];
      entities[id] = (existing ?? ErEntity(id: id, label: id)).copyWith(
        label: m.group(4) != null ? label : existing?.label ?? id,
      );
      if (m.group(5) != null) _openEntity = id;
      return;
    }

    throw MermaidParseException('unrecognized statement "$line"', line: n);
  }

  /// `A ||--o{ B : label` plus the word form
  /// `A only one to zero or more B : label`.
  bool _parseRelationship(String line, int n) {
    var m = RegExp(
            r'^("([^"]+)"|[\wÀ-￿-]+)\s*(\S+)\s+("([^"]+)"|[\wÀ-￿-]+)\s*(?::\s*(.*))?$')
        .firstMatch(line);
    (ErCardinality, bool, ErCardinality)? rel;
    if (m != null) rel = _parseRelToken(m.group(3)!);
    if (rel == null) {
      // Word form: <entity> <card words> to|optionally to <card words> <entity>.
      const words = <String, ErCardinality>{
        'only one': ErCardinality.onlyOne,
        'one': ErCardinality.onlyOne,
        'zero or one': ErCardinality.zeroOrOne,
        'one or zero': ErCardinality.zeroOrOne,
        'zero or more': ErCardinality.zeroOrMore,
        'zero or many': ErCardinality.zeroOrMore,
        'many(0)': ErCardinality.zeroOrMore,
        'many': ErCardinality.zeroOrMore,
        '0+': ErCardinality.zeroOrMore,
        'one or more': ErCardinality.oneOrMore,
        'one or many': ErCardinality.oneOrMore,
        'many(1)': ErCardinality.oneOrMore,
        '1+': ErCardinality.oneOrMore,
      };
      final cardPattern = words.keys.map(RegExp.escape).join('|');
      m = RegExp(r'^("([^"]+)"|[\wÀ-￿-]+)\s+'
              '($cardPattern)\\s+(to|optionally to)\\s+($cardPattern)'
              r'\s+("([^"]+)"|[\wÀ-￿-]+)\s*(?::\s*(.*))?$')
          .firstMatch(line);
      if (m == null) return false;
      final fromId = m.group(2) ?? m.group(1)!;
      final toId = m.group(7) ?? m.group(6)!;
      _ensure(fromId);
      _ensure(toId);
      relationships.add(ErRelationship(
        from: fromId,
        to: toId,
        cardFrom: words[m.group(3)!]!,
        cardTo: words[m.group(5)!]!,
        identifying: m.group(4) == 'to',
        label: (m.group(8) ?? '').trim(),
      ));
      return true;
    }
    final (cardFrom, identifying, cardTo) = rel;
    final sm = m!; // symbol-form match (rel != null implies m != null)

    final fromId = sm.group(2) ?? sm.group(1)!;
    final toId = sm.group(5) ?? sm.group(4)!;
    _ensure(fromId);
    _ensure(toId);
    var label = (sm.group(6) ?? '').trim();
    if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
      label = label.substring(1, label.length - 1);
    }
    relationships.add(ErRelationship(
      from: fromId,
      to: toId,
      cardFrom: cardFrom,
      cardTo: cardTo,
      identifying: identifying,
      label: label,
    ));
    return true;
  }

  (ErCardinality, bool, ErCardinality)? _parseRelToken(String token) {
    for (final (left, cardFrom) in _leftCards) {
      if (!token.startsWith(left)) continue;
      for (final (right, cardTo) in _rightCards) {
        if (!token.endsWith(right)) continue;
        final mid =
            token.substring(left.length, token.length - right.length);
        final identifying = switch (mid) {
          '--' => true,
          '..' || '.-' || '-.' => false,
          _ => true,
        };
        if (!RegExp(r'^(--|\.\.|\.-|-\.)$').hasMatch(mid)) continue;
        return (cardFrom, identifying, cardTo);
      }
    }
    return null;
  }

  /// Attribute row: `type name [PK|FK|UK[, ...]] ["comment"]`.
  void _parseAttribute(String entityId, String line, int n) {
    var rest = line.trim();
    String? comment;
    final commentMatch = RegExp(r'"([^"]*)"\s*$').firstMatch(rest);
    if (commentMatch != null) {
      comment = commentMatch.group(1);
      rest = rest.substring(0, commentMatch.start).trim();
    }
    final parts = rest.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      throw MermaidParseException(
          'expected "type name" attribute in "$entityId"', line: n);
    }
    final keys = <String>[];
    while (parts.length > 2 &&
        RegExp(r'^(PK|FK|UK)(,(PK|FK|UK))*$').hasMatch(parts.last)) {
      keys.insertAll(0, parts.removeLast().split(','));
    }
    final type = _convertGenerics(parts.first);
    final name = parts.sublist(1).join(' ');
    final entity = entities[entityId]!;
    entities[entityId] = entity.copyWith(attributes: [
      ...entity.attributes,
      ErAttribute(type: type, name: name, keys: keys, comment: comment),
    ]);
  }

  String _convertGenerics(String s) {
    if (!s.contains('~')) return s;
    final out = StringBuffer();
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      if (s[i] != '~') {
        out.write(s[i]);
        continue;
      }
      final next = i + 1 < s.length ? s[i + 1] : '';
      if (next.isNotEmpty && next != '~' &&
          RegExp(r'[A-Za-z0-9_(]').hasMatch(next)) {
        out.write('<');
        depth++;
      } else if (depth > 0) {
        out.write('>');
        depth--;
      } else {
        out.write('~');
      }
    }
    return out.toString();
  }

  /// Splits a CSS style string (`fill:#f00,stroke:#000`) into `k:v` entries.
  List<String> _splitStyles(String s) => [
        for (final part in s.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];

  void _ensure(String id) {
    entities.putIfAbsent(id, () => ErEntity(id: id, label: id));
  }
}

/// Hand-written parser for mermaid class diagrams.
///
/// Grammar reference: upstream `class/parser/classDiagram.jison` and
/// semantics in `classDb.ts`; validated against cases ported from
/// `classDiagram.spec.ts`.
library;

import '../../detect.dart';
import '../../parse_error.dart';
import '../flowchart/flow_model.dart' show FlowDirection;
import 'class_model.dart';

ClassDiagram parseClassDiagram(String source) {
  final title = frontmatterTitle(source);
  return _ClassParser(stripMetadata(source), title).parse();
}

class _ClassParser {
  _ClassParser(this.text, this.frontTitle);

  final String text;
  final String? frontTitle;

  final classes = <String, ClassNode>{};
  final relations = <ClassRelation>[];
  final namespaces = <ClassNamespace>[];
  final notes = <ClassNote>[];
  final classDefs = <String, Map<String, String>>{};
  var direction = FlowDirection.tb;
  String? title;

  /// Non-null while inside `class X { ... }`.
  String? _openClass;

  /// Open `namespace N { ... }` blocks (nesting allowed); each entry is
  /// (id, label, members).
  final _namespaceStack = <(String, String, List<String>)>[];

  ClassDiagram parse() {
    title = frontTitle;
    final lines = text.split('\n');
    var seenHeader = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      final comment = line.indexOf('%%');
      if (comment >= 0) line = line.substring(0, comment).trim();
      if (line.isEmpty) continue;
      if (!seenHeader) {
        if (!RegExp(r'^classDiagram(-v2)?\b').hasMatch(line)) {
          throw MermaidParseException('expected "classDiagram" header',
              line: i + 1);
        }
        seenHeader = true;
        continue;
      }
      _parseStatement(line, i + 1);
    }
    if (!seenHeader) {
      throw const MermaidParseException('empty class diagram source');
    }
    if (_openClass != null || _namespaceStack.isNotEmpty) {
      throw const MermaidParseException('unclosed "{" block');
    }
    return ClassDiagram(
      classes: classes,
      relations: relations,
      namespaces: namespaces,
      notes: notes,
      classDefs: classDefs,
      direction: direction,
      title: title,
    );
  }

  void _parseStatement(String line, int n) {
    // Inside a class body: members, annotations, closing brace.
    if (_openClass != null) {
      if (line == '}') {
        _openClass = null;
        return;
      }
      final annotation = RegExp(r'^<<\s*(.+?)\s*>>$').firstMatch(line);
      if (annotation != null) {
        _annotate(_openClass!, annotation.group(1)!);
        return;
      }
      _addMember(_openClass!, line);
      return;
    }

    if (_namespaceStack.isNotEmpty && line == '}') {
      final (id, label, members) = _namespaceStack.removeLast();
      namespaces.add(
          ClassNamespace(id: id, label: label, classIds: List.of(members)));
      // A nested namespace's classes also belong to the enclosing one for
      // cluster sizing purposes.
      if (_namespaceStack.isNotEmpty) {
        _namespaceStack.last.$3.addAll(members);
      }
      return;
    }

    Match? m;

    m = RegExp(r'^namespace\s+([^\s{\[]+)\s*(?:\["([^"]*)"\])?\s*\{$')
        .firstMatch(line);
    if (m != null) {
      _namespaceStack.add((m.group(1)!, m.group(2) ?? m.group(1)!, []));
      return;
    }

    m = RegExp(r'^class\s+([^\s{:\[]+)\s*(\["([^"]*)"\])?\s*([^{]*?)\s*(\{)?\s*$')
        .firstMatch(line);
    if (m != null && !m.group(4)!.startsWith(':')) {
      final id = _stripGenerics(m.group(1)!);
      final node = _ensure(m.group(1)!);
      if (m.group(3) != null) {
        classes[id] = node.copyWith(label: m.group(3)!);
      } else if (m.group(4)!.isNotEmpty) {
        // Trailing generic text: `class People List~List~Person~~` displays
        // the full converted text as the label.
        classes[id] = node.copyWith(
            label:
                _convertGenerics('${m.group(1)!} ${m.group(4)!}'.trim()));
      }
      if (m.group(5) != null) _openClass = id;
      if (_namespaceStack.isNotEmpty) _namespaceStack.last.$3.add(id);
      return;
    }

    // `class X:::cssClass`
    m = RegExp(r'^class\s+([^\s:]+):::(\S+)\s*$').firstMatch(line);
    if (m != null) {
      final node = _ensure(m.group(1)!);
      classes[node.id] =
          node.copyWith(cssClasses: [...node.cssClasses, m.group(2)!]);
      if (_namespaceStack.isNotEmpty) _namespaceStack.last.$3.add(node.id);
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

    m = RegExp(r'^<<\s*(.+?)\s*>>\s+(\S+)\s*$').firstMatch(line);
    if (m != null) {
      _annotate(_stripGenerics(m.group(2)!), m.group(1)!);
      return;
    }

    m = RegExp(r'^note\s+for\s+(\S+)\s+"([^"]*)"\s*$').firstMatch(line);
    if (m != null) {
      notes.add(ClassNote(
          text: _normalize(m.group(2)!),
          forClass: _stripGenerics(m.group(1)!)));
      return;
    }
    m = RegExp(r'^note\s+"([^"]*)"\s*$').firstMatch(line);
    if (m != null) {
      notes.add(ClassNote(text: _normalize(m.group(1)!)));
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

    m = RegExp(r'^cssClass\s+"([^"]*)"\s+(\S+)\s*$').firstMatch(line);
    if (m != null) {
      for (final id in m.group(1)!.split(',')) {
        final node = _ensure(id.trim());
        classes[node.id] =
            node.copyWith(cssClasses: [...node.cssClasses, m.group(2)!]);
      }
      return;
    }

    m = RegExp(r'^style\s+(\S+)\s+(.+)$').firstMatch(line);
    if (m != null) {
      final node = _ensure(m.group(1)!);
      classes[node.id] = node.copyWith(
          styles: {...node.styles, ..._parseStyles(m.group(2)!)});
      return;
    }

    // click/link/callback: keep the URL when present, otherwise discard.
    m = RegExp(r'^(click|link)\s+(\S+)\s+(.*)$').firstMatch(line);
    if (m != null) {
      final node = _ensure(m.group(2)!);
      final url = RegExp(r'"([^"]*)"').firstMatch(
          m.group(3)!.replaceFirst(RegExp(r'^(href|call)\s+'), ''));
      if (url != null && m.group(3)!.contains('href') ||
          m.group(1) == 'link') {
        classes[node.id] = node.copyWith(link: url?.group(1));
      }
      return;
    }
    if (RegExp(r'^callback\s+').hasMatch(line)) return;
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(line)) return;

    m = RegExp(r'^title\s+(.*)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      return;
    }

    if (_parseRelation(line, n)) return;

    // `X : +member` colon syntax.
    m = RegExp(r'^([^\s:]+)\s*:\s*(.+)$').firstMatch(line);
    if (m != null) {
      _addMember(_stripGenerics(m.group(1)!), m.group(2)!);
      if (_namespaceStack.isNotEmpty) {
        _namespaceStack.last.$3.add(_stripGenerics(m.group(1)!));
      }
      return;
    }

    throw MermaidParseException('unrecognized statement "$line"', line: n);
  }

  // --- relations -------------------------------------------------------------

  /// `A "card" <relation> "card" B : label` where relation is
  /// [type1]line[type2], line `--` or `..`.
  static final _relationRe = RegExp(
      r'^(\S+)\s*(?:"([^"]*)")?\s*' // from + optional cardinality
      r'(<\||[*o<]|\(\))?(--|\.\.)(\|>|[*o>]|\(\))?' // relation token
      r'\s*(?:"([^"]*)")?\s*(\S+?)\s*(?::\s*(.+))?$' // cardinality + to + label
      );

  bool _parseRelation(String line, int n) {
    final m = _relationRe.firstMatch(line);
    if (m == null) return false;
    if (m.group(3) == null && m.group(5) == null && m.group(4) == null) {
      return false;
    }
    final endFrom = switch (m.group(3)) {
      '<|' => RelationEnd.extension,
      '*' => RelationEnd.composition,
      'o' => RelationEnd.aggregation,
      '<' => RelationEnd.arrow,
      '()' => RelationEnd.lollipop,
      _ => RelationEnd.none,
    };
    final endTo = switch (m.group(5)) {
      '|>' => RelationEnd.extension,
      '*' => RelationEnd.composition,
      'o' => RelationEnd.aggregation,
      '>' => RelationEnd.arrow,
      '()' => RelationEnd.lollipop,
      _ => RelationEnd.none,
    };
    final from = _ensure(m.group(1)!);
    final to = _ensure(m.group(7)!);
    relations.add(ClassRelation(
      from: from.id,
      to: to.id,
      endFrom: endFrom,
      endTo: endTo,
      dotted: m.group(4) == '..',
      cardFrom: m.group(2),
      cardTo: m.group(6),
      label: m.group(8) == null ? null : _normalize(m.group(8)!),
    ));
    return true;
  }

  // --- members ----------------------------------------------------------------

  void _addMember(String rawId, String raw) {
    final id = _stripGenerics(rawId);
    final node = _ensure(rawId);
    var text = raw.trim();
    if (RegExp(r'^<<.*>>$').hasMatch(text)) {
      _annotate(id, text.substring(2, text.length - 2).trim());
      return;
    }
    var isStatic = false;
    var isAbstract = false;
    if (text.endsWith(r'$')) {
      isStatic = true;
      text = text.substring(0, text.length - 1);
    } else if (text.endsWith('*')) {
      isAbstract = true;
      text = text.substring(0, text.length - 1);
    }
    // Pull the visibility prefix off before generics conversion so the `~`
    // package-visibility marker is not mistaken for a generic bracket.
    var visibility = '';
    var body = text.trim();
    if (body.isNotEmpty && RegExp(r'[+\-#~]').hasMatch(body[0])) {
      visibility = body[0];
      body = body.substring(1);
    }
    final member = ClassMember(
      text: '$visibility${_convertGenerics(body.trim())}',
      isStatic: isStatic,
      isAbstract: isAbstract,
    );
    // Upstream rule: anything containing `(` is a method.
    if (text.contains('(')) {
      classes[id] = node.copyWith(methods: [...node.methods, member]);
    } else {
      classes[id] = node.copyWith(attributes: [...node.attributes, member]);
    }
  }

  void _annotate(String id, String annotation) {
    final node = _ensure(id);
    classes[node.id] =
        node.copyWith(annotations: [...node.annotations, annotation]);
  }

  ClassNode _ensure(String rawId) {
    final id = _stripGenerics(rawId);
    return classes.putIfAbsent(
      id,
      () => ClassNode(id: id, label: _convertGenerics(rawId)),
    );
  }

  /// `List~T~` → id `List`; the display label keeps the converted generics.
  String _stripGenerics(String s) {
    final i = s.indexOf('~');
    return i < 0 ? s : s.substring(0, i);
  }

  /// `List~int~` → `List<int>`, nesting included
  /// (`List~List~Person~~` → `List<List<Person>>`): a `~` opens a generic
  /// when followed by an identifier character, otherwise it closes one.
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
      final opens = depth == 0 ||
          RegExp(r'[A-Za-z0-9_]').hasMatch(next);
      if (opens && next != '~' && next.isNotEmpty) {
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

  String _normalize(String s) => s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .trim();

  Map<String, String> _parseStyles(String text) {
    final styles = <String, String>{};
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
      styles[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return styles;
  }
}

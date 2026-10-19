/// Hand-written recursive descent parser for mermaid flowchart syntax.
///
/// Grammar reference: upstream `flowchart/parser/flow.jison` and the
/// semantics in `flowDb.ts` (notably `destructEndLink` for edge tokens).
/// Behavior is validated against test cases ported from the upstream
/// `flow-*.spec.js` suites.
library;

import 'dart:typed_data';

import '../../detect.dart';
import '../../directives.dart';
import '../../parse_error.dart';
import 'flow_model.dart';

/// Parses flowchart source (including optional frontmatter, directives and
/// `%%` comments) into a [FlowGraph].
///
/// Throws [MermaidParseException] on syntax errors.
FlowGraph parseFlowchart(String source) {
  final title = frontmatterTitle(source);
  final text = stripMetadata(source);
  final inheritDir =
      resolveDiagramConfig(source, 'flowchart')['inheritDir'] == true;
  return _FlowParser(text, title, inheritDir).parse();
}

class _Statement {
  _Statement(this.text, this.line);
  final String text;
  final int line;
}

class _OpenSubgraph {
  _OpenSubgraph(this.id, this.title, this.parentIndex);
  final String id;
  final String title;
  final int? parentIndex;
  final List<String> nodeIds = [];
  FlowDirection? direction;
  int? listIndex;
}

class _EdgeSpec {
  _EdgeSpec({
    required this.stroke,
    required this.headFrom,
    required this.headTo,
    required this.minLen,
    this.label,
  });

  final EdgeStroke stroke;
  final ArrowHead headFrom;
  final ArrowHead headTo;
  final int minLen;
  final String? label;
}

// Statement and token patterns, compiled once.
final _header = RegExp(r'^(graph|flowchart-elk|flowchart)\b\s*(.*)$');
final _headerDirection = RegExp(r'^(TB|TD|BT|LR|RL|>|<|\^|v)(?=\s|$)');
final _accDescrOpen = RegExp(r'accDescr\s*$');
final _subgraphKeyword = RegExp(r'^subgraph\b');
final _directionStatement = RegExp(r'^direction\s+(TB|TD|BT|LR|RL)\s*$');
final _classDefKeyword = RegExp(r'^classDef\b');
final _classKeyword = RegExp(r'^class\b');
final _styleKeyword = RegExp(r'^style\b');
final _linkStyleKeyword = RegExp(r'^linkStyle\b');
final _clickKeyword = RegExp(r'^click\b');
final _accessibility = RegExp(r'^acc(Title|Descr)\s*[:{]');
final _subgraphIdTitle = RegExp(r'^([^\s\[\]"]+)\s*\[(.*)\]\s*$');
final _quotedTitle = RegExp(r'^"[^"]*"$');
final _classDefStatement = RegExp(r'^classDef\s+([^\s]+)\s+(.+)$');
final _classStatement = RegExp(r'^class\s+([^\s]+)\s+([^\s]+)\s*$');
final _styleStatement = RegExp(r'^style\s+([^\s]+)\s+(.+)$');
final _linkStyleStatement = RegExp(r'^linkStyle\s+([\d,\s]+|default)\s+(.+)$');
final _interpolate = RegExp(r'^interpolate\s+(\w+)\s*');
final _clickStatement = RegExp(r'^click\s+(\S+)\s+([\s\S]*)$');
final _hrefKeyword = RegExp(r'^href\s+');
final _clickUrl = RegExp(r'^"([^"]*)"\s*(?:"([^"]*)")?');
final _attributeKeyChar = RegExp(r'[A-Za-z0-9_-]');
final _attributeValueChar = RegExp(r'[^,}]');
final _solidTextLinkEnd = RegExp(r'(-{2,}[-xo>])');
final _dottedTextLinkEnd = RegExp(r'(\.+-[xo>]?)');
final _thickTextLinkEnd = RegExp(r'(={2,}[=xo>]?)');
final _space = RegExp(r'\s');
final _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
final _legacyIcon = RegExp(r'fa[bklrs]?:fa-[\w-]+');
final _blanks = RegExp(r'[ \t]+');

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

class _FlowParser {
  _FlowParser(this.text, this.title, this.inheritDir);

  final String text;
  final String? title;
  final bool inheritDir;

  final nodes = <String, FlowNode>{};
  final edges = <FlowEdge>[];
  final subgraphs = <FlowSubgraph>[];
  final classDefs = <String, Map<String, String>>{};
  final _defaultLinkStyles = <String, String>{};

  /// Link tokens (`-->`, `-.->`, ...) seen so far and their classification.
  final _edgeSpecs = <String, _EdgeSpec>{};
  var direction = FlowDirection.tb;
  var _anonSubgraphCount = 0;

  final _openSubgraphs = <_OpenSubgraph>[];

  /// Subgraph list under construction; entries are placed at their open-order
  /// index and filled in when the block closes.
  final _builtSubgraphs = <FlowSubgraph?>[];

  FlowGraph parse() {
    final statements = _splitStatements(text);
    if (statements.isEmpty) {
      throw const MermaidParseException('empty flowchart source');
    }
    final header = statements.first;
    final headerMatch = _header.firstMatch(header.text.trim());
    if (headerMatch == null) {
      throw MermaidParseException(
        'expected "graph" or "flowchart" header, got "${header.text.trim()}"',
        line: header.line,
      );
    }
    final rest = headerMatch.group(2)!.trim();
    final remainder = _parseDirection(rest);
    if (remainder.isNotEmpty) {
      _parseStatement(_Statement(remainder, header.line));
    }
    for (final st in statements.skip(1)) {
      _parseStatement(st);
    }
    if (_openSubgraphs.isNotEmpty) {
      throw MermaidParseException(
        'unclosed subgraph "${_openSubgraphs.last.title}"',
      );
    }
    final finalEdges =
        (_defaultLinkStyles.isEmpty && _defaultInterpolate == null)
        ? edges
        : [
            for (final e in edges)
              e.copyWith(
                styles: {..._defaultLinkStyles, ...e.styles},
                interpolate: e.interpolate ?? _defaultInterpolate,
              ),
          ];
    return FlowGraph(
      direction: direction,
      nodes: nodes,
      edges: finalEdges,
      subgraphs: _builtSubgraphs.whereType<FlowSubgraph>().toList(),
      classDefs: classDefs,
      title: title,
    );
  }

  /// Parses the direction token after the header keyword; returns whatever
  /// trails it on the same statement.
  String _parseDirection(String rest) {
    if (rest.isEmpty) return '';
    const dirs = {
      'TB': FlowDirection.tb,
      'TD': FlowDirection.tb,
      'BT': FlowDirection.bt,
      'LR': FlowDirection.lr,
      'RL': FlowDirection.rl,
      // Legacy single-char directions.
      '>': FlowDirection.lr,
      '<': FlowDirection.rl,
      '^': FlowDirection.bt,
      'v': FlowDirection.tb,
    };
    final m = _headerDirection.firstMatch(rest);
    if (m == null) return rest;
    direction = dirs[m.group(1)]!;
    return rest.substring(m.end).trim();
  }

  /// The ASCII characters that [_splitStatements] acts on:
  /// `\n " % [ ( { ] ) } ;`.
  static final _splitSpecial = () {
    final table = Uint8List(0x80);
    for (final c in '\n"%[({])};'.codeUnits) {
      table[c] = 1;
    }
    return table;
  }();

  /// Splits the source into statements at newlines and top-level `;`,
  /// respecting quotes and bracket nesting, dropping inline `%%` comments,
  /// and keeping `accDescr { ... }` blocks together.
  ///
  /// Statements are copied as substrings of [text]; the buffer is used only
  /// when a statement is not one contiguous range (comments, `accDescr`
  /// blocks that span lines).
  List<_Statement> _splitStatements(String text) {
    final out = <_Statement>[];
    final buf = StringBuffer();
    var bufLine = 1;
    var line = 1;
    var depth = 0;
    var inQuote = false;
    var inAccBlock = false;
    // Start of the range of [text] not yet copied into [buf].
    var start = 0;

    void flush(int end) {
      final String s;
      if (buf.isEmpty) {
        s = _trimmedSubstring(text, start, end);
      } else {
        buf.write(text.substring(start, end));
        s = buf.toString().trim();
        buf.clear();
      }
      if (s.isNotEmpty) out.add(_Statement(s, bufLine));
      bufLine = line;
    }

    final n = text.length;
    final special = _splitSpecial;
    for (var i = 0; i < n; i++) {
      final c = text.codeUnitAt(i);
      // Only the characters in [_splitSpecial] change the state; all others
      // stay in the current range.
      if (c >= 0x80 || special[c] == 0) continue;
      if (c == 0x0a) {
        // \n
        line++;
        if (inAccBlock) {
          buf
            ..write(text.substring(start, i))
            ..write(' ');
          start = i + 1;
          continue;
        }
        // Quoted strings (e.g. click tooltips) may span lines.
        if (inQuote) continue;
        flush(i);
        start = i + 1;
        continue;
      }
      if (inQuote) {
        if (c == 0x22) inQuote = false;
        continue;
      }
      switch (c) {
        case 0x22: // "
          inQuote = true;
        case 0x25 when i + 1 < n && text.codeUnitAt(i + 1) == 0x25: // %%
          // Inline comment: skip to end of line.
          buf.write(text.substring(start, i));
          while (i + 1 < n && text.codeUnitAt(i + 1) != 0x0a) {
            i++;
          }
          start = i + 1;
        case 0x5b || 0x28: // [ (
          depth++;
        case 0x7b: // {
          buf.write(text.substring(start, i));
          start = i;
          if (_accDescrOpen.hasMatch(buf.toString())) {
            inAccBlock = true;
          } else {
            depth++;
          }
        case 0x5d || 0x29: // ] )
          // Clamp: the asymmetric shape `A>text]` closes a bracket it never
          // opened, which must not swallow the following `;`.
          if (depth > 0) depth--;
        case 0x7d: // }
          if (inAccBlock) {
            inAccBlock = false;
          } else if (depth > 0) {
            depth--;
          }
        case 0x3b when depth == 0: // ;
          flush(i);
          start = i + 1;
      }
    }
    flush(n);
    return out;
  }

  /// `text.substring(start, end).trim()`, with one allocation when the ends
  /// are ASCII.
  static String _trimmedSubstring(String text, int start, int end) {
    while (start < end && _isAsciiSpace(text.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isAsciiSpace(text.codeUnitAt(end - 1))) {
      end--;
    }
    final s = text.substring(start, end);
    if (start < end &&
        (text.codeUnitAt(start) >= 0x80 || text.codeUnitAt(end - 1) >= 0x80)) {
      return s.trim();
    }
    return s;
  }

  static bool _isAsciiSpace(int c) => c == 0x20 || (c >= 0x09 && c <= 0x0d);

  void _parseStatement(_Statement st) {
    final s = st.text;
    if (s.isEmpty) return;
    // Keyword statements are rare: a cheap prefix check skips their patterns
    // for the node and link chains that make up most statements.
    switch (s.codeUnitAt(0)) {
      // The first letters of `subgraph`, `end`, `direction`, `classDef`,
      // `class`, `click`, `style`, `linkStyle` and `acc...`.
      case 0x73 || 0x65 || 0x64 || 0x63 || 0x6c || 0x61:
        if (_parseKeywordStatement(st)) return;
    }
    _parseChain(st);
  }

  /// Parses [st] when it is a keyword statement; returns false for a node
  /// and link chain.
  bool _parseKeywordStatement(_Statement st) {
    final s = st.text;
    if (s.startsWith('subgraph') && _subgraphKeyword.hasMatch(s)) {
      _openSubgraph(s.substring('subgraph'.length).trim(), st.line);
      return true;
    }
    if (s == 'end') {
      _closeSubgraph(st.line);
      return true;
    }
    final dir = s.startsWith('direction')
        ? _directionStatement.firstMatch(s)
        : null;
    if (dir != null) {
      const dirs = {
        'TB': FlowDirection.tb,
        'TD': FlowDirection.tb,
        'BT': FlowDirection.bt,
        'LR': FlowDirection.lr,
        'RL': FlowDirection.rl,
      };
      if (_openSubgraphs.isNotEmpty) {
        if (!inheritDir) {
          _openSubgraphs.last.direction = dirs[dir.group(1)]!;
        }
      } else {
        direction = dirs[dir.group(1)]!;
      }
      return true;
    }
    if (s.startsWith('classDef') && _classDefKeyword.hasMatch(s)) {
      _parseClassDef(s, st.line);
      return true;
    }
    if (s.startsWith('class') && _classKeyword.hasMatch(s)) {
      _parseClassStatement(s, st.line);
      return true;
    }
    if (s.startsWith('style') && _styleKeyword.hasMatch(s)) {
      _parseStyleStatement(s, st.line);
      return true;
    }
    if (s.startsWith('linkStyle') && _linkStyleKeyword.hasMatch(s)) {
      _parseLinkStyle(s, st.line);
      return true;
    }
    if (s.startsWith('click') && _clickKeyword.hasMatch(s)) {
      _parseClick(s, st.line);
      return true;
    }
    // Accessibility statements are parsed and discarded for now.
    return s.startsWith('acc') && _accessibility.hasMatch(s);
  }

  // --- subgraphs ------------------------------------------------------------

  void _openSubgraph(String header, int line) {
    String id;
    String titleText;
    final bracket = _subgraphIdTitle.firstMatch(header);
    if (bracket != null) {
      id = bracket.group(1)!;
      titleText = _normalizeLabel(bracket.group(2)!);
    } else if (header.isEmpty) {
      id = 'subGraph${_anonSubgraphCount++}';
      titleText = '';
    } else if (_quotedTitle.hasMatch(header)) {
      titleText = _normalizeLabel(header);
      id = 'subGraph${_anonSubgraphCount++}';
    } else if (!header.contains(' ')) {
      id = header;
      titleText = header;
    } else {
      id = 'subGraph${_anonSubgraphCount++}';
      titleText = _normalizeLabel(header);
    }
    final parentIndex = _openSubgraphs.isEmpty
        ? null
        : _openSubgraphs.last.listIndex;
    final open = _OpenSubgraph(id, titleText, parentIndex)
      ..listIndex = _builtSubgraphs.length;
    _builtSubgraphs.add(null);
    _openSubgraphs.add(open);
  }

  void _closeSubgraph(int line) {
    if (_openSubgraphs.isEmpty) {
      throw MermaidParseException('"end" without open subgraph', line: line);
    }
    final open = _openSubgraphs.removeLast();
    // A node belongs to the first subgraph that closes with it listed, as in
    // upstream FlowDB.addSubGraph (makeUniq). A nested subgraph closes before
    // its parent, so the innermost one wins; among siblings the earlier one
    // wins, also when a later subgraph mentions the node in an edge.
    final claimed = <String>{
      for (final sg in _builtSubgraphs)
        if (sg != null) ...sg.nodeIds,
    };
    _builtSubgraphs[open.listIndex!] = FlowSubgraph(
      id: open.id,
      title: open.title,
      nodeIds: [
        for (final id in open.nodeIds)
          if (!claimed.contains(id)) id,
      ],
      direction: open.direction,
      parentIndex: open.parentIndex,
    );
  }

  // --- keyword statements -----------------------------------------------------

  void _parseClassDef(String s, int line) {
    final m = _classDefStatement.firstMatch(s);
    if (m == null) {
      throw MermaidParseException('malformed classDef', line: line);
    }
    final styles = _parseStyles(m.group(2)!);
    for (final name in m.group(1)!.split(',')) {
      classDefs[name.trim()] = styles;
    }
  }

  void _parseClassStatement(String s, int line) {
    final m = _classStatement.firstMatch(s);
    if (m == null) {
      throw MermaidParseException('malformed class statement', line: line);
    }
    final className = m.group(2)!;
    for (final id in m.group(1)!.split(',')) {
      final nodeId = id.trim();
      // `class` may also target subgraph ids; subgraph classes are not
      // modeled yet, so only known/auto-created node ids are updated.
      if (_builtSubgraphs.any((sg) => sg?.id == nodeId) ||
          _openSubgraphs.any((sg) => sg.id == nodeId)) {
        continue;
      }
      final node = _ensureNode(nodeId);
      nodes[nodeId] = node.copyWith(classes: [...node.classes, className]);
    }
  }

  void _parseStyleStatement(String s, int line) {
    final m = _styleStatement.firstMatch(s);
    if (m == null) {
      throw MermaidParseException('malformed style statement', line: line);
    }
    final id = m.group(1)!;
    final node = _ensureNode(id);
    nodes[id] = node.copyWith(
      styles: {...node.styles, ..._parseStyles(m.group(2)!)},
    );
  }

  void _parseLinkStyle(String s, int line) {
    final m = _linkStyleStatement.firstMatch(s);
    if (m == null) {
      throw MermaidParseException('malformed linkStyle statement', line: line);
    }
    var styleText = m.group(2)!.trim();
    // `interpolate <curve>` selects the edge curve (basis/linear/step/...).
    String? curve;
    final interp = _interpolate.firstMatch(styleText);
    if (interp != null) {
      curve = interp.group(1);
      styleText = styleText.substring(interp.end).trim();
    }
    final styles = styleText.isEmpty
        ? <String, String>{}
        : _parseStyles(styleText);
    final indexText = m.group(1)!.trim();
    // `linkStyle default` applies to every edge; per-index styles override
    // it (merged at the end of parse()).
    if (indexText == 'default') {
      _defaultLinkStyles.addAll(styles);
      if (curve != null) _defaultInterpolate = curve;
      return;
    }
    for (final part in indexText.split(',')) {
      final i = int.tryParse(part.trim());
      if (i == null || i < 0 || i >= edges.length) {
        throw MermaidParseException(
          'linkStyle index $part out of range (have ${edges.length} links)',
          line: line,
        );
      }
      edges[i] = edges[i].copyWith(
        styles: {...edges[i].styles, ...styles},
        interpolate: curve,
      );
    }
  }

  String? _defaultInterpolate;

  void _parseClick(String s, int line) {
    // click <id> href "url" ["tooltip"] | click <id> "url" ["tooltip"]
    // click <id> call fn() | click <id> callback — parsed, ignored.
    // [\s\S] because quoted tooltips may contain newlines.
    final m = _clickStatement.firstMatch(s);
    if (m == null) {
      throw MermaidParseException('malformed click statement', line: line);
    }
    final id = m.group(1)!;
    var rest = m.group(2)!.trim();
    rest = rest.replaceFirst(_hrefKeyword, '');
    final url = _clickUrl.firstMatch(rest);
    if (url != null) {
      final node = _ensureNode(id);
      nodes[id] = node.copyWith(link: url.group(1), tooltip: url.group(2));
    }
    // Anything else (callback / call fn()) is intentionally discarded.
  }

  Map<String, String> _parseStyles(String text) {
    final styles = <String, String>{};
    for (final part in _splitTopLevel(text, ',')) {
      final i = part.indexOf(':');
      if (i <= 0) continue;
      styles[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return styles;
  }

  /// Splits on [sep] outside of parentheses (e.g. `fill:rgb(1,2,3)`).
  List<String> _splitTopLevel(String text, String sep) {
    final out = <String>[];
    var depth = 0;
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == sep && depth == 0) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }

  // --- node/edge chains -------------------------------------------------------

  void _parseChain(_Statement st) {
    final scanner = _Scanner(st.text, st.line);
    var sources = _parseNodeGroup(scanner);
    while (true) {
      scanner.skipWs();
      if (scanner.atEnd) break;
      final edge = _tryParseEdge(scanner);
      if (edge == null) {
        throw MermaidParseException(
          'expected link or end of statement near "${scanner.rest(12)}"',
          line: st.line,
        );
      }
      final targets = _parseNodeGroup(scanner);
      for (final from in sources) {
        for (final to in targets) {
          edges.add(
            FlowEdge(
              from: from,
              to: to,
              label: edge.label,
              stroke: edge.stroke,
              headFrom: edge.headFrom,
              headTo: edge.headTo,
              minLen: edge.minLen,
            ),
          );
        }
      }
      sources = targets;
    }
  }

  List<String> _parseNodeGroup(_Scanner sc) {
    final ids = <String>[_parseNode(sc)];
    while (true) {
      sc.skipWs();
      if (sc.tryConsume('&')) {
        ids.add(_parseNode(sc));
      } else {
        return ids;
      }
    }
  }

  String _parseNode(_Scanner sc) {
    sc.skipWs();
    final id = sc.readNodeId();
    if (id.isEmpty) {
      throw MermaidParseException(
        'expected node id near "${sc.rest(12)}"',
        line: sc.line,
      );
    }
    _ensureNode(id);

    // `:::class` may come before or after the shape declaration.
    var shapeParsed = false;
    while (true) {
      if (sc.tryConsume(':::')) {
        final cls = sc.readNodeId();
        if (cls.isEmpty) {
          throw MermaidParseException(
            'expected class name after ":::"',
            line: sc.line,
          );
        }
        final node = nodes[id]!;
        nodes[id] = node.copyWith(classes: [...node.classes, cls]);
      } else if (!shapeParsed && sc.tryConsume('@{')) {
        _parseNodeAttributes(id, sc);
        shapeParsed = true;
      } else if (!shapeParsed) {
        final shape = _tryParseShape(sc);
        if (shape == null) break;
        final (kind, rawLabel) = shape;
        final label = _normalizeLabel(rawLabel);
        nodes[id] = nodes[id]!.copyWith(
          label: label.isEmpty ? id : label,
          shape: kind,
          markdown: _isMarkdownLabel(rawLabel),
        );
        shapeParsed = true;
      } else {
        break;
      }
    }

    if (_openSubgraphs.isNotEmpty) {
      final members = _openSubgraphs.last.nodeIds;
      if (!members.contains(id)) members.add(id);
    }
    return id;
  }

  /// Parses the v11 `@{ key: value, ... }` node attribute object (the `@{`
  /// has already been consumed). Recognized keys: `shape`, `label`; others
  /// (icon, form, w, h, ...) are parsed and ignored.
  void _parseNodeAttributes(String id, _Scanner sc) {
    String? shapeName;
    String? label;
    String? icon;
    while (true) {
      sc.skipWs();
      if (sc.tryConsume('}')) break;
      if (sc.atEnd) {
        throw MermaidParseException(
          'unterminated "@{" attributes on "$id"',
          line: sc.line,
        );
      }
      final key = sc.readWhile(_attributeKeyChar).trim();
      sc.skipWs();
      if (!sc.tryConsume(':')) {
        throw MermaidParseException(
          'expected ":" after "@{" attribute key "$key"',
          line: sc.line,
        );
      }
      sc.skipWs();
      String value;
      if (sc.tryConsume('"')) {
        final (_, quoted) = sc.readUntil(['"']);
        value = quoted;
      } else {
        value = sc.readWhile(_attributeValueChar).trim();
      }
      switch (key) {
        case 'shape':
          shapeName = value;
        case 'label':
          label = value;
        case 'icon':
          icon = value;
        default:
          break; // Recognized-but-unsupported attribute; ignored.
      }
      sc.skipWs();
      sc.tryConsume(',');
    }
    var node = nodes[id]!;
    if (shapeName != null) {
      final shape = _v11Shapes[shapeName];
      if (shape == null && !_knownUnsupportedV11Shapes.contains(shapeName)) {
        throw MermaidParseException(
          'unknown shape "$shapeName"',
          line: sc.line,
        );
      }
      // Unsupported-but-valid v11 shapes fall back to a plain rectangle.
      node = node.copyWith(shape: shape ?? FlowNodeShape.rect);
    }
    if (label != null) {
      final normalized = _normalizeLabel(label);
      node = node.copyWith(
        label: normalized.isEmpty ? id : normalized,
        markdown: _isMarkdownLabel(label),
      );
    }
    if (icon != null) {
      node = node.copyWith(
        icon: icon,
        shape: shapeName == null ? FlowNodeShape.rounded : null,
      );
    }
    nodes[id] = node;
  }

  /// v11 shape names/aliases (rendering-elements/shapes.ts) mapped onto the
  /// geometries we support.
  static const _v11Shapes = <String, FlowNodeShape>{
    'rect': FlowNodeShape.rect,
    'rectangle': FlowNodeShape.rect,
    'proc': FlowNodeShape.rect,
    'process': FlowNodeShape.rect,
    'square': FlowNodeShape.rect,
    'rounded': FlowNodeShape.rounded,
    'event': FlowNodeShape.rounded,
    'stadium': FlowNodeShape.stadium,
    'terminal': FlowNodeShape.stadium,
    'pill': FlowNodeShape.stadium,
    'fr-rect': FlowNodeShape.subroutine,
    'subprocess': FlowNodeShape.subroutine,
    'subproc': FlowNodeShape.subroutine,
    'framed-rectangle': FlowNodeShape.subroutine,
    'subroutine': FlowNodeShape.subroutine,
    'cyl': FlowNodeShape.cylinder,
    'db': FlowNodeShape.cylinder,
    'database': FlowNodeShape.cylinder,
    'cylinder': FlowNodeShape.cylinder,
    'datastore': FlowNodeShape.cylinder,
    'data-store': FlowNodeShape.cylinder,
    'lin-cyl': FlowNodeShape.cylinder,
    'disk': FlowNodeShape.cylinder,
    'lined-cylinder': FlowNodeShape.cylinder,
    'h-cyl': FlowNodeShape.cylinder,
    'das': FlowNodeShape.cylinder,
    'horizontal-cylinder': FlowNodeShape.cylinder,
    'circle': FlowNodeShape.circle,
    'circ': FlowNodeShape.circle,
    'sm-circ': FlowNodeShape.circle,
    'start': FlowNodeShape.circle,
    'small-circle': FlowNodeShape.circle,
    'f-circ': FlowNodeShape.circle,
    'junction': FlowNodeShape.circle,
    'filled-circle': FlowNodeShape.circle,
    'fr-circ': FlowNodeShape.doubleCircle,
    'stop': FlowNodeShape.doubleCircle,
    'framed-circle': FlowNodeShape.doubleCircle,
    'dbl-circ': FlowNodeShape.doubleCircle,
    'double-circle': FlowNodeShape.doubleCircle,
    'diam': FlowNodeShape.diamond,
    'decision': FlowNodeShape.diamond,
    'diamond': FlowNodeShape.diamond,
    'question': FlowNodeShape.diamond,
    'hex': FlowNodeShape.hexagon,
    'hexagon': FlowNodeShape.hexagon,
    'prepare': FlowNodeShape.hexagon,
    'lean-r': FlowNodeShape.leanRight,
    'lean-right': FlowNodeShape.leanRight,
    'in-out': FlowNodeShape.leanRight,
    'lean-l': FlowNodeShape.leanLeft,
    'lean-left': FlowNodeShape.leanLeft,
    'out-in': FlowNodeShape.leanLeft,
    'trap-b': FlowNodeShape.trapezoid,
    'priority': FlowNodeShape.trapezoid,
    'trapezoid-bottom': FlowNodeShape.trapezoid,
    'trapezoid': FlowNodeShape.trapezoid,
    'trap-t': FlowNodeShape.invTrapezoid,
    'manual': FlowNodeShape.invTrapezoid,
    'trapezoid-top': FlowNodeShape.invTrapezoid,
    'inv-trapezoid': FlowNodeShape.invTrapezoid,
    'odd': FlowNodeShape.asymmetric,
    // v11 geometries (rendering-elements/shapes.ts).
    'doc': FlowNodeShape.document,
    'document': FlowNodeShape.document,
    'lin-doc': FlowNodeShape.document,
    'lined-document': FlowNodeShape.document,
    'docs': FlowNodeShape.document,
    'documents': FlowNodeShape.document,
    'st-doc': FlowNodeShape.document,
    'stacked-document': FlowNodeShape.document,
    'tag-doc': FlowNodeShape.document,
    'tagged-document': FlowNodeShape.document,
    'tri': FlowNodeShape.triangle,
    'triangle': FlowNodeShape.triangle,
    'extract': FlowNodeShape.triangle,
    'flip-tri': FlowNodeShape.flippedTriangle,
    'flipped-triangle': FlowNodeShape.flippedTriangle,
    'manual-file': FlowNodeShape.flippedTriangle,
    'sl-rect': FlowNodeShape.slopedRect,
    'sloped-rectangle': FlowNodeShape.slopedRect,
    'manual-input': FlowNodeShape.slopedRect,
    'notch-rect': FlowNodeShape.card,
    'card': FlowNodeShape.card,
    'notched-rectangle': FlowNodeShape.card,
    'notch-pent': FlowNodeShape.notchedPentagon,
    'loop-limit': FlowNodeShape.notchedPentagon,
    'notched-pentagon': FlowNodeShape.notchedPentagon,
    'bolt': FlowNodeShape.bolt,
    'lightning-bolt': FlowNodeShape.bolt,
    'com-link': FlowNodeShape.bolt,
    'hourglass': FlowNodeShape.hourglass,
    'collate': FlowNodeShape.hourglass,
    'lin-rect': FlowNodeShape.linedRect,
    'lined-rectangle': FlowNodeShape.linedRect,
    'lined-process': FlowNodeShape.linedRect,
    'lin-proc': FlowNodeShape.linedRect,
    'shaded-process': FlowNodeShape.linedRect,
    'st-rect': FlowNodeShape.linedRect,
    'stacked-rectangle': FlowNodeShape.linedRect,
    'processes': FlowNodeShape.linedRect,
    'procs': FlowNodeShape.linedRect,
    'div-rect': FlowNodeShape.dividedRect,
    'div-proc': FlowNodeShape.dividedRect,
    'divided-rectangle': FlowNodeShape.dividedRect,
    'divided-process': FlowNodeShape.dividedRect,
    'win-pane': FlowNodeShape.windowPane,
    'internal-storage': FlowNodeShape.windowPane,
    'window-pane': FlowNodeShape.windowPane,
    'cross-circ': FlowNodeShape.crossedCircle,
    'crossed-circle': FlowNodeShape.crossedCircle,
    'summary': FlowNodeShape.crossedCircle,
    'fork': FlowNodeShape.forkJoin,
    'join': FlowNodeShape.forkJoin,
    'text': FlowNodeShape.textShape,
    // Closest existing geometry for the remaining v11 names.
    'delay': FlowNodeShape.rounded,
    'half-rounded-rectangle': FlowNodeShape.rounded,
    'curv-trap': FlowNodeShape.trapezoid,
    'curved-trapezoid': FlowNodeShape.trapezoid,
    'display': FlowNodeShape.trapezoid,
    'brace': FlowNodeShape.rect,
    'brace-l': FlowNodeShape.rect,
    'brace-r': FlowNodeShape.rect,
    'braces': FlowNodeShape.rect,
    'comment': FlowNodeShape.rect,
    'tag-rect': FlowNodeShape.card,
    'tagged-rectangle': FlowNodeShape.card,
    'tag-proc': FlowNodeShape.card,
    'tagged-process': FlowNodeShape.card,
    'flag': FlowNodeShape.rect,
    'paper-tape': FlowNodeShape.document,
    'bow-rect': FlowNodeShape.rect,
    'bow-tie-rectangle': FlowNodeShape.rect,
    'stored-data': FlowNodeShape.cylinder,
  };

  /// Valid v11 shapes whose geometry we don't draw specially; they render as
  /// rectangles rather than failing the parse. (`icon` is handled by the icon
  /// feature; `image` has no image source support yet.)
  static const _knownUnsupportedV11Shapes = <String>{'icon', 'image'};

  /// Bracket-delimited node shapes; openers are matched longest-first.
  (FlowNodeShape, String)? _tryParseShape(_Scanner sc) {
    // (opener, closers): the matched closer can refine the shape
    // (lean vs trapezoid).
    if (sc.atEnd) return null;
    final first = sc.text.codeUnitAt(sc.pos);
    switch (first) {
      case 0x28 || 0x5b || 0x7b || 0x3e: // ( [ { >
        break;
      default:
        return null;
    }
    // The plain rectangle `[label]` is by far the most common shape: take it
    // when no longer `[` opener can match.
    if (first == 0x5b) {
      final at = sc.pos + 1;
      final second = at < sc.text.length ? sc.text.codeUnitAt(at) : -1;
      if (second != 0x5b && // [
          second != 0x28 && // (
          second != 0x2f && // /
          second != 0x5c) {
        // \
        sc.pos = at;
        return (FlowNodeShape.rect, sc.readUntil(const [']']).$2);
      }
    }
    if (sc.tryConsume('(((')) {
      return (FlowNodeShape.doubleCircle, sc.readUntil(const [')))']).$2);
    }
    if (sc.tryConsume('((')) {
      return (FlowNodeShape.circle, sc.readUntil(const ['))']).$2);
    }
    if (sc.tryConsume('([')) {
      return (FlowNodeShape.stadium, sc.readUntil(const ['])']).$2);
    }
    if (sc.tryConsume('(-')) {
      return (FlowNodeShape.ellipse, sc.readUntil(const ['-)']).$2);
    }
    if (sc.tryConsume('(')) {
      return (FlowNodeShape.rounded, sc.readUntil(const [')']).$2);
    }
    if (sc.tryConsume('[[')) {
      return (FlowNodeShape.subroutine, sc.readUntil(const [']]']).$2);
    }
    if (sc.tryConsume('[(')) {
      return (FlowNodeShape.cylinder, sc.readUntil(const [')]']).$2);
    }
    if (sc.tryConsume('[/')) {
      final (closer, label) = sc.readUntil(const ['/]', r'\]']);
      return (
        closer == '/]' ? FlowNodeShape.leanRight : FlowNodeShape.trapezoid,
        label,
      );
    }
    if (sc.tryConsume(r'[\')) {
      final (closer, label) = sc.readUntil(const [r'\]', '/]']);
      return (
        closer == r'\]' ? FlowNodeShape.leanLeft : FlowNodeShape.invTrapezoid,
        label,
      );
    }
    if (sc.tryConsume('[')) {
      return (FlowNodeShape.rect, sc.readUntil(const [']']).$2);
    }
    if (sc.tryConsume('{{')) {
      return (FlowNodeShape.hexagon, sc.readUntil(const ['}}']).$2);
    }
    if (sc.tryConsume('{')) {
      return (FlowNodeShape.diamond, sc.readUntil(const ['}']).$2);
    }
    if (sc.tryConsume('>')) {
      return (FlowNodeShape.asymmetric, sc.readUntil(const [']']).$2);
    }
    return null;
  }

  // --- edges -------------------------------------------------------------------

  _EdgeSpec? _tryParseEdge(_Scanner sc) {
    sc.skipWs();
    // Text-form links: `-- label -->`, `-. label .->`, `== label ==>`.
    final textForm = sc.tryTextLinkStart();
    if (textForm != null) {
      final (startHead, kind) = textForm;
      final endPattern = switch (kind) {
        '--' => _solidTextLinkEnd,
        '-.' => _dottedTextLinkEnd,
        _ => _thickTextLinkEnd,
      };
      final (label, endToken) = sc.readEdgeText(endPattern);
      final spec = _destructEdgeToken(endToken, sc.line);
      return _withStartHead(spec, startHead, _normalizeLabel(label), sc.line);
    }

    final token = sc.tryLinkToken();
    if (token == null) return null;
    final spec = _edgeSpecs[token] ??= _destructEdgeToken(token, sc.line);

    // Optional `|label|` after the link.
    sc.skipWs();
    if (!sc.tryConsume('|')) return spec;
    final (_, raw) = sc.readUntil(const ['|']);
    final label = _normalizeLabel(raw);
    return _EdgeSpec(
      stroke: spec.stroke,
      headFrom: spec.headFrom,
      headTo: spec.headTo,
      minLen: spec.minLen,
      label: label,
    );
  }

  /// Port of upstream flowDb.destructEndLink: classifies an edge token like
  /// `-->`, `<-->`, `x-.-x`, `==>`, `~~~` into stroke/heads/length.
  _EdgeSpec _destructEdgeToken(String token, int line) {
    var str = token.trim();
    var line0 = str.substring(0, str.length - 1);
    var headTo = ArrowHead.none;
    var headFrom = ArrowHead.none;

    switch (str[str.length - 1]) {
      case 'x':
        headTo = ArrowHead.cross;
        if (str.startsWith('x')) {
          headFrom = ArrowHead.cross;
          line0 = line0.substring(1);
        }
      case '>':
        headTo = ArrowHead.point;
        if (str.startsWith('<')) {
          headFrom = ArrowHead.point;
          line0 = line0.substring(1);
        }
      case 'o':
        headTo = ArrowHead.circle;
        if (str.startsWith('o')) {
          headFrom = ArrowHead.circle;
          line0 = line0.substring(1);
        }
      default:
        // Open link: the unconditional last-char strip above already gives
        // e.g. `---` -> `--` (length 1), matching upstream.
        break;
    }

    var stroke = EdgeStroke.normal;
    var length = line0.length - 1;
    if (line0.startsWith('=')) stroke = EdgeStroke.thick;
    if (line0.startsWith('~')) stroke = EdgeStroke.invisible;
    final dots = '.'.allMatches(line0).length;
    if (dots > 0) {
      stroke = EdgeStroke.dotted;
      length = dots;
    }
    if (!_validEdgeCore(line0)) {
      throw MermaidParseException('malformed link "$token"', line: line);
    }
    return _EdgeSpec(
      stroke: stroke,
      headFrom: headFrom,
      headTo: headTo,
      minLen: length,
    );
  }

  bool _validEdgeCore(String core) {
    // Dotted cores may be a single `.` (from `-. text .-`).
    if (_isDottedCore(core)) return true;
    if (core.length < 2) return false;
    return _repeats(core, 0x2d) || // -
        _repeats(core, 0x3d) || // =
        _repeats(core, 0x7e); // ~
  }

  /// Matches `^-?\.+-?$`.
  static bool _isDottedCore(String core) {
    var start = 0;
    var end = core.length;
    if (end > 0 && core.codeUnitAt(0) == 0x2d) start++;
    if (end > start && core.codeUnitAt(end - 1) == 0x2d) end--;
    if (start == end) return false;
    for (var i = start; i < end; i++) {
      if (core.codeUnitAt(i) != 0x2e) return false;
    }
    return true;
  }

  /// Whether [core] is one or more [char]s.
  static bool _repeats(String core, int char) {
    if (core.isEmpty) return false;
    for (var i = 0; i < core.length; i++) {
      if (core.codeUnitAt(i) != char) return false;
    }
    return true;
  }

  _EdgeSpec _withStartHead(
    _EdgeSpec end,
    String? startHead,
    String label,
    int line,
  ) {
    var headFrom = end.headFrom;
    if (startHead != null) {
      headFrom = switch (startHead) {
        '<' => ArrowHead.point,
        'x' => ArrowHead.cross,
        _ => ArrowHead.circle,
      };
    }
    return _EdgeSpec(
      stroke: end.stroke,
      headFrom: headFrom,
      headTo: end.headTo,
      minLen: end.minLen,
      label: label.isEmpty ? null : label,
    );
  }

  // --- helpers -------------------------------------------------------------

  FlowNode _ensureNode(String id) =>
      nodes.putIfAbsent(id, () => FlowNode(id: id, label: id));

  bool _isMarkdownLabel(String raw) {
    final s = raw.trim();
    if (s.length < 4 || !s.startsWith('"') || !s.endsWith('"')) return false;
    final inner = s.substring(1, s.length - 1).trim();
    return inner.length >= 2 && inner.startsWith('`') && inner.endsWith('`');
  }

  /// Mirrors how mermaid.js shows label HTML (htmlLabels, default
  /// `securityLevel: strict`): `sanitizeText` keeps the markup and the browser
  /// renders it. The emphasis tags `<b>`/`<strong>` and `<i>`/`<em>` become
  /// the canonical `<b>`/`<i>` that the layout paints as bold and italic runs.
  /// Every other tag is removed and its text kept, as the browser shows the
  /// text of an element it does not style here; script-like elements lose
  /// their text too, as DOMPurify removes it. A `<` that does not start a tag
  /// (`a < b`) stays literal text.
  static String _normalizeHtmlTags(String s) {
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
          out.write(closing ? '</b>' : '<b>');
        case 'i' || 'em':
          out.write(closing ? '</i>' : '<i>');
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

  String _normalizeLabel(String raw) {
    var s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    // Markdown string syntax: "`text`" — keep the text, drop the backticks.
    if (s.length >= 2 && s.startsWith('`') && s.endsWith('`')) {
      s = s.substring(1, s.length - 1);
    }
    // One scan finds whether HTML markup (`<br>`, `<b>`, ...) or a legacy
    // `fa:` icon is possible.
    var hasLt = false;
    var hasFa = false;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x3c) {
        hasLt = true;
      } else if (c == 0x66 && i + 1 < s.length && s.codeUnitAt(i + 1) == 0x61) {
        hasFa = true;
      }
    }
    if (hasLt) {
      s = s.replaceAll(_lineBreak, '\n');
      if (s.contains('<')) s = _normalizeHtmlTags(s);
      // Removing `<br>` can join an `f` and an `a`.
      hasFa = s.contains('fa');
    }
    if (!hasFa) return s.trim();
    final withoutLegacyIcons = s.replaceAll(
      _legacyIcon,
      '',
    );
    if (withoutLegacyIcons != s) {
      s = withoutLegacyIcons.replaceAll(_blanks, ' ');
    }
    return s.trim();
  }
}

/// Character scanner over a single statement.
class _Scanner {
  _Scanner(this.text, this.line);

  final String text;
  final int line;
  var pos = 0;

  bool get atEnd => pos >= text.length;

  String rest(int n) => text.substring(pos, (pos + n).clamp(0, text.length));

  void skipWs() {
    final n = text.length;
    while (pos < n) {
      final c = text.codeUnitAt(pos);
      if (c != 0x20 && c != 0x09) break;
      pos++;
    }
  }

  bool tryConsume(String s) {
    // The first code unit rejects most candidates before the full compare.
    if (pos >= text.length || text.codeUnitAt(pos) != s.codeUnitAt(0)) {
      return false;
    }
    if (s.length == 1 || text.startsWith(s, pos)) {
      pos += s.length;
      return true;
    }
    return false;
  }

  /// Matches `([<xo])?(--|-\.|==)(?=\s)` (the start of a text-form link)
  /// at [pos]. On a match, moves past it and returns (start head, `--` /
  /// `-.` / `==`).
  (String?, String)? tryTextLinkStart() {
    final n = text.length;
    var p = pos;
    if (p >= n) return null;
    String? head;
    final c0 = text.codeUnitAt(p);
    if (c0 == 0x3c || c0 == 0x78 || c0 == 0x6f) {
      // < x o
      head = text[p];
      p++;
    }
    if (p + 2 >= n || !_isSpaceAt(p + 2)) return null;
    final a = text.codeUnitAt(p);
    final b = text.codeUnitAt(p + 1);
    final String kind;
    if (a == 0x2d && b == 0x2d) {
      kind = '--';
    } else if (a == 0x2d && b == 0x2e) {
      kind = '-.';
    } else if (a == 0x3d && b == 0x3d) {
      kind = '==';
    } else {
      return null;
    }
    pos = p + 2;
    return (head, kind);
  }

  /// Matches the link token `([<xo])?([-=~.]{2,})([xo>])?` at [pos]. On a
  /// match, moves past it and returns the token.
  String? tryLinkToken() {
    final n = text.length;
    var p = pos;
    if (p >= n) return null;
    final c0 = text.codeUnitAt(p);
    if (c0 == 0x3c || c0 == 0x78 || c0 == 0x6f) p++; // < x o
    final coreStart = p;
    while (p < n && _isLinkCore(text.codeUnitAt(p))) {
      p++;
    }
    // Without the optional head the core would have to start at a `<xo`
    // character, which is not a core character: no other match exists.
    if (p - coreStart < 2) return null;
    if (p < n) {
      final c = text.codeUnitAt(p);
      if (c == 0x78 || c == 0x6f || c == 0x3e) p++; // x o >
    }
    final token = text.substring(pos, p);
    pos = p;
    return token;
  }

  /// `[-=~.]`
  static bool _isLinkCore(int c) =>
      c == 0x2d || c == 0x3d || c == 0x7e || c == 0x2e;

  /// Whether the code unit at [i] matches the regex class `\s`.
  bool _isSpaceAt(int i) {
    final c = text.codeUnitAt(i);
    if (c < 0x80) return c == 0x20 || (c >= 0x09 && c <= 0x0d);
    return _space.hasMatch(text[i]);
  }

  /// Consumes characters while they match [charClass].
  String readWhile(RegExp charClass) {
    final start = pos;
    while (!atEnd && charClass.hasMatch(text[pos])) {
      pos++;
    }
    return text.substring(start, pos);
  }

  static final _idChar = RegExp(
    r'[\p{L}\p{N}_!#$%&*+.?\\/'
    "'"
    r']',
    unicode: true,
  );

  /// [_idChar] for the code unit [u] at [at], with an ASCII fast path (ids
  /// are mostly ASCII).
  bool _isIdUnit(int u, int at) {
    if (u >= 0x80) return _idChar.hasMatch(text[at]);
    return (u >= 0x61 && u <= 0x7a) || // a-z
        (u >= 0x41 && u <= 0x5a) || // A-Z
        (u >= 0x30 && u <= 0x39) || // 0-9
        _isAsciiIdPunctuation(u);
  }

  /// The ASCII punctuation in [_idChar]: `_ ! # $ % & * + . ? \ / '`.
  static bool _isAsciiIdPunctuation(int u) => switch (u) {
    0x5f || 0x21 || 0x23 || 0x24 || 0x25 || 0x26 || 0x2a || 0x2b => true,
    0x2e || 0x3f || 0x5c || 0x2f || 0x27 => true,
    _ => false,
  };

  /// Mirrors upstream NODE_STRING: `-` only when not followed by `>`, `-` or
  /// `.` (so ids may contain dashes without eating links), `=` only when not
  /// followed by `=`.
  String readNodeId() {
    final start = pos;
    final n = text.length;
    while (pos < n) {
      final c = text.codeUnitAt(pos);
      if (c == 0x2d) {
        // Dash stays in the id only when it cannot start a link token.
        if (pos + 1 >= n) break;
        final next = text.codeUnitAt(pos + 1);
        if (next == 0x3e || next == 0x2d || next == 0x2e) break; // > - .
        pos++;
        continue;
      }
      if (c == 0x3d) {
        // =
        if (pos + 1 < n && text.codeUnitAt(pos + 1) == 0x3d) break;
        pos++;
        continue;
      }
      if (_isIdUnit(c, pos)) {
        pos++;
        continue;
      }
      break;
    }
    return text.substring(start, pos);
  }

  /// Reads label content until one of [closers] (longest first), honoring
  /// quoted segments. Returns (closer, content).
  ///
  /// The content is every character between the start and the closer, so it
  /// is one substring of [text].
  (String, String) readUntil(List<String> closers) {
    if (closers.length == 1 && closers[0].length == 1) {
      return _readUntilUnit(closers[0]);
    }
    final sorted = closers.length == 1
        ? closers
        : ([...closers]..sort((a, b) => b.length.compareTo(a.length)));
    final start = pos;
    final n = text.length;
    var inQuote = false;
    while (pos < n) {
      final c = text.codeUnitAt(pos);
      if (inQuote) {
        if (c == 0x22) inQuote = false;
        pos++;
        continue;
      }
      // Closers win over quote-starts so `"` itself can act as a closer.
      for (final closer in sorted) {
        if (closer.codeUnitAt(0) == c && text.startsWith(closer, pos)) {
          final content = text.substring(start, pos);
          pos += closer.length;
          return (closer, content);
        }
      }
      if (c == 0x22) inQuote = true;
      pos++;
    }
    throw MermaidParseException(
      'unterminated "${closers.first}" label in "$text"',
      line: line,
    );
  }

  /// [readUntil] for a single one-character [closer].
  (String, String) _readUntilUnit(String closer) {
    final unit = closer.codeUnitAt(0);
    final start = pos;
    final n = text.length;
    var inQuote = false;
    while (pos < n) {
      final c = text.codeUnitAt(pos);
      if (inQuote) {
        if (c == 0x22) inQuote = false;
      } else if (c == unit) {
        // The closer wins over a quote-start, as in [readUntil].
        final content = text.substring(start, pos);
        pos++;
        return (closer, content);
      } else if (c == 0x22) {
        inQuote = true;
      }
      pos++;
    }
    throw MermaidParseException(
      'unterminated "$closer" label in "$text"',
      line: line,
    );
  }

  /// For text-form links: reads the label until [endPattern] (which must be
  /// preceded by whitespace), consuming the end token. Returns (label, token).
  (String, String) readEdgeText(RegExp endPattern) {
    final buf = StringBuffer();
    var inQuote = false;
    while (!atEnd) {
      final c = text[pos];
      if (inQuote) {
        buf.write(c);
        if (c == '"') inQuote = false;
        pos++;
        continue;
      }
      if (c == '"') {
        inQuote = true;
        buf.write(c);
        pos++;
        continue;
      }
      if (c == ' ' || c == '\t') {
        final after = pos + 1;
        final m = endPattern.matchAsPrefix(text, _skipWsFrom(after));
        if (m != null) {
          pos = m.end;
          return (buf.toString(), m.group(1)!);
        }
      }
      buf.write(c);
      pos++;
    }
    throw MermaidParseException(
      'unterminated link text in "$text"',
      line: line,
    );
  }

  int _skipWsFrom(int i) {
    while (i < text.length && (text[i] == ' ' || text[i] == '\t')) {
      i++;
    }
    return i;
  }
}

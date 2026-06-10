/// Hand-written recursive descent parser for mermaid flowchart syntax.
///
/// Grammar reference: upstream `flowchart/parser/flow.jison` and the
/// semantics in `flowDb.ts` (notably `destructEndLink` for edge tokens).
/// Behavior is validated against test cases ported from the upstream
/// `flow-*.spec.js` suites.
library;

import '../../detect.dart';
import '../../parse_error.dart';
import 'flow_model.dart';

/// Parses flowchart source (including optional frontmatter, directives and
/// `%%` comments) into a [FlowGraph].
///
/// Throws [MermaidParseException] on syntax errors.
FlowGraph parseFlowchart(String source) {
  final title = frontmatterTitle(source);
  final text = stripMetadata(source);
  return _FlowParser(text, title).parse();
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

class _FlowParser {
  _FlowParser(this.text, this.title);

  final String text;
  final String? title;

  final nodes = <String, FlowNode>{};
  final edges = <FlowEdge>[];
  final subgraphs = <FlowSubgraph>[];
  final classDefs = <String, Map<String, String>>{};
  final _defaultLinkStyles = <String, String>{};
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
    final headerMatch =
        RegExp(r'^(graph|flowchart-elk|flowchart)\b\s*(.*)$').firstMatch(header.text.trim());
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
    final finalEdges = _defaultLinkStyles.isEmpty
        ? edges
        : [
            for (final e in edges)
              e.copyWith(styles: {..._defaultLinkStyles, ...e.styles}),
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
    final m = RegExp(r'^(TB|TD|BT|LR|RL|>|<|\^|v)(?=\s|$)').firstMatch(rest);
    if (m == null) return rest;
    direction = dirs[m.group(1)]!;
    return rest.substring(m.end).trim();
  }

  /// Splits the source into statements at newlines and top-level `;`,
  /// respecting quotes and bracket nesting, dropping inline `%%` comments,
  /// and keeping `accDescr { ... }` blocks together.
  List<_Statement> _splitStatements(String text) {
    final out = <_Statement>[];
    final buf = StringBuffer();
    var bufLine = 1;
    var line = 1;
    var depth = 0;
    var inQuote = false;
    var inAccBlock = false;

    void flush() {
      final s = buf.toString().trim();
      if (s.isNotEmpty) out.add(_Statement(s, bufLine));
      buf.clear();
      bufLine = line;
    }

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '\n') {
        line++;
        if (inAccBlock) {
          buf.write(' ');
          continue;
        }
        // Quoted strings (e.g. click tooltips) may span lines.
        if (inQuote) {
          buf.write('\n');
          continue;
        }
        flush();
        continue;
      }
      if (inQuote) {
        buf.write(c);
        if (c == '"') inQuote = false;
        continue;
      }
      switch (c) {
        case '"':
          inQuote = true;
          buf.write(c);
        case '%' when i + 1 < text.length && text[i + 1] == '%':
          // Inline comment: skip to end of line.
          while (i + 1 < text.length && text[i + 1] != '\n') {
            i++;
          }
        case '[' || '(':
          depth++;
          buf.write(c);
        case '{':
          if (RegExp(r'accDescr\s*$').hasMatch(buf.toString())) {
            inAccBlock = true;
          } else {
            depth++;
          }
          buf.write(c);
        case ']' || ')':
          // Clamp: the asymmetric shape `A>text]` closes a bracket it never
          // opened, which must not swallow the following `;`.
          if (depth > 0) depth--;
          buf.write(c);
        case '}':
          if (inAccBlock) {
            inAccBlock = false;
          } else if (depth > 0) {
            depth--;
          }
          buf.write(c);
        case ';' when depth == 0:
          flush();
        default:
          buf.write(c);
      }
    }
    flush();
    return out;
  }

  void _parseStatement(_Statement st) {
    final s = st.text;
    if (s.isEmpty) return;
    if (RegExp(r'^subgraph\b').hasMatch(s)) {
      _openSubgraph(s.substring('subgraph'.length).trim(), st.line);
      return;
    }
    if (RegExp(r'^end$').hasMatch(s)) {
      _closeSubgraph(st.line);
      return;
    }
    final dir = RegExp(r'^direction\s+(TB|TD|BT|LR|RL)\s*$').firstMatch(s);
    if (dir != null) {
      const dirs = {
        'TB': FlowDirection.tb,
        'TD': FlowDirection.tb,
        'BT': FlowDirection.bt,
        'LR': FlowDirection.lr,
        'RL': FlowDirection.rl,
      };
      if (_openSubgraphs.isNotEmpty) {
        _openSubgraphs.last.direction = dirs[dir.group(1)]!;
      } else {
        direction = dirs[dir.group(1)]!;
      }
      return;
    }
    if (RegExp(r'^classDef\b').hasMatch(s)) {
      _parseClassDef(s, st.line);
      return;
    }
    if (RegExp(r'^class\b').hasMatch(s)) {
      _parseClassStatement(s, st.line);
      return;
    }
    if (RegExp(r'^style\b').hasMatch(s)) {
      _parseStyleStatement(s, st.line);
      return;
    }
    if (RegExp(r'^linkStyle\b').hasMatch(s)) {
      _parseLinkStyle(s, st.line);
      return;
    }
    if (RegExp(r'^click\b').hasMatch(s)) {
      _parseClick(s, st.line);
      return;
    }
    // Accessibility statements are parsed and discarded for now.
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(s)) return;
    _parseChain(st);
  }

  // --- subgraphs ------------------------------------------------------------

  void _openSubgraph(String header, int line) {
    String id;
    String titleText;
    final bracket =
        RegExp(r'^([^\s\[\]"]+)\s*\[(.*)\]\s*$').firstMatch(header);
    if (bracket != null) {
      id = bracket.group(1)!;
      titleText = _normalizeLabel(bracket.group(2)!);
    } else if (header.isEmpty) {
      id = 'subGraph${_anonSubgraphCount++}';
      titleText = '';
    } else if (RegExp(r'^"[^"]*"$').hasMatch(header)) {
      titleText = _normalizeLabel(header);
      id = 'subGraph${_anonSubgraphCount++}';
    } else if (!header.contains(' ')) {
      id = header;
      titleText = header;
    } else {
      id = 'subGraph${_anonSubgraphCount++}';
      titleText = _normalizeLabel(header);
    }
    final parentIndex =
        _openSubgraphs.isEmpty ? null : _openSubgraphs.last.listIndex;
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
    _builtSubgraphs[open.listIndex!] = FlowSubgraph(
      id: open.id,
      title: open.title,
      nodeIds: open.nodeIds,
      direction: open.direction,
      parentIndex: open.parentIndex,
    );
  }

  // --- keyword statements -----------------------------------------------------

  void _parseClassDef(String s, int line) {
    final m = RegExp(r'^classDef\s+([^\s]+)\s+(.+)$').firstMatch(s);
    if (m == null) {
      throw MermaidParseException('malformed classDef', line: line);
    }
    final styles = _parseStyles(m.group(2)!);
    for (final name in m.group(1)!.split(',')) {
      classDefs[name.trim()] = styles;
    }
  }

  void _parseClassStatement(String s, int line) {
    final m = RegExp(r'^class\s+([^\s]+)\s+([^\s]+)\s*$').firstMatch(s);
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
    final m = RegExp(r'^style\s+([^\s]+)\s+(.+)$').firstMatch(s);
    if (m == null) {
      throw MermaidParseException('malformed style statement', line: line);
    }
    final id = m.group(1)!;
    final node = _ensureNode(id);
    nodes[id] =
        node.copyWith(styles: {...node.styles, ..._parseStyles(m.group(2)!)});
  }

  void _parseLinkStyle(String s, int line) {
    final m = RegExp(r'^linkStyle\s+([\d,\s]+|default)\s+(.+)$').firstMatch(s);
    if (m == null) {
      throw MermaidParseException('malformed linkStyle statement', line: line);
    }
    var styleText = m.group(2)!.trim();
    // `interpolate <curve>` is accepted and ignored (curve choice is a
    // renderer concern; we always use curveBasis like upstream's default).
    final interp = RegExp(r'^interpolate\s+\w+\s*').firstMatch(styleText);
    if (interp != null) styleText = styleText.substring(interp.end).trim();
    if (styleText.isEmpty) return;
    final styles = _parseStyles(styleText);
    final indexText = m.group(1)!.trim();
    // `linkStyle default` applies to every edge; per-index styles override
    // it (merged at the end of parse()).
    if (indexText == 'default') {
      _defaultLinkStyles.addAll(styles);
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
      edges[i] = edges[i].copyWith(styles: {...edges[i].styles, ...styles});
    }
  }

  void _parseClick(String s, int line) {
    // click <id> href "url" ["tooltip"] | click <id> "url" ["tooltip"]
    // click <id> call fn() | click <id> callback — parsed, ignored.
    // [\s\S] because quoted tooltips may contain newlines.
    final m = RegExp(r'^click\s+(\S+)\s+([\s\S]*)$').firstMatch(s);
    if (m == null) {
      throw MermaidParseException('malformed click statement', line: line);
    }
    final id = m.group(1)!;
    var rest = m.group(2)!.trim();
    rest = rest.replaceFirst(RegExp(r'^href\s+'), '');
    final url = RegExp(r'^"([^"]*)"\s*(?:"([^"]*)")?').firstMatch(rest);
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
          edges.add(FlowEdge(
            from: from,
            to: to,
            label: edge.label,
            stroke: edge.stroke,
            headFrom: edge.headFrom,
            headTo: edge.headTo,
            minLen: edge.minLen,
          ));
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
          throw MermaidParseException('expected class name after ":::"',
              line: sc.line);
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
    while (true) {
      sc.skipWs();
      if (sc.tryConsume('}')) break;
      if (sc.atEnd) {
        throw MermaidParseException('unterminated "@{" attributes on "$id"',
            line: sc.line);
      }
      final key = sc.readWhile(RegExp(r'[A-Za-z0-9_-]')).trim();
      sc.skipWs();
      if (!sc.tryConsume(':')) {
        throw MermaidParseException(
            'expected ":" after "@{" attribute key "$key"',
            line: sc.line);
      }
      sc.skipWs();
      String value;
      if (sc.tryConsume('"')) {
        final (_, quoted) = sc.readUntil(['"']);
        value = quoted;
      } else {
        value = sc.readWhile(RegExp(r'[^,}]')).trim();
      }
      switch (key) {
        case 'shape':
          shapeName = value;
        case 'label':
          label = value;
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
        throw MermaidParseException('unknown shape "$shapeName"', line: sc.line);
      }
      // Unsupported-but-valid v11 shapes fall back to a plain rectangle.
      node = node.copyWith(shape: shape ?? FlowNodeShape.rect);
    }
    if (label != null) {
      final normalized = _normalizeLabel(label);
      node = node.copyWith(label: normalized.isEmpty ? id : normalized);
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
  };

  /// Valid v11 shapes whose geometry we have not ported yet; they render as
  /// rectangles rather than failing the parse.
  static const _knownUnsupportedV11Shapes = <String>{
    'text', 'notch-rect', 'card', 'notched-rectangle', //
    'lin-rect', 'lined-rectangle', 'lined-process', 'lin-proc',
    'shaded-process', 'fork', 'join', 'hourglass', 'collate', 'brace',
    'comment', 'brace-l', 'brace-r', 'braces', 'bolt', 'com-link',
    'lightning-bolt', 'doc', 'document', 'delay', 'half-rounded-rectangle',
    'curv-trap', 'curved-trapezoid', 'display', 'div-rect', 'div-proc',
    'divided-rectangle', 'divided-process', 'tri', 'extract', 'triangle',
    'win-pane', 'internal-storage', 'window-pane', 'notch-pent',
    'loop-limit', 'notched-pentagon', 'flip-tri', 'manual-file',
    'flipped-triangle', 'sl-rect', 'manual-input', 'sloped-rectangle',
    'docs', 'documents', 'st-doc', 'stacked-document', 'st-rect',
    'processes', 'procs', 'stacked-rectangle', 'flag', 'paper-tape',
    'bow-rect', 'bow-tie-rectangle', 'stored-data', 'cross-circ',
    'crossed-circle', 'summary', 'tag-doc', 'tagged-document', 'tag-rect',
    'tag-proc', 'tagged-rectangle', 'tagged-process', 'lin-doc',
    'lined-document', 'icon', 'image',
  };

  /// Bracket-delimited node shapes; openers are matched longest-first.
  (FlowNodeShape, String)? _tryParseShape(_Scanner sc) {
    // (opener, closers): the matched closer can refine the shape
    // (lean vs trapezoid).
    if (sc.tryConsume('(((')) {
      return (FlowNodeShape.doubleCircle, sc.readUntil([')))']).$2);
    }
    if (sc.tryConsume('((')) {
      return (FlowNodeShape.circle, sc.readUntil(['))']).$2);
    }
    if (sc.tryConsume('([')) {
      return (FlowNodeShape.stadium, sc.readUntil(['])']).$2);
    }
    if (sc.tryConsume('(-')) {
      return (FlowNodeShape.ellipse, sc.readUntil(['-)']).$2);
    }
    if (sc.tryConsume('(')) {
      return (FlowNodeShape.rounded, sc.readUntil([')']).$2);
    }
    if (sc.tryConsume('[[')) {
      return (FlowNodeShape.subroutine, sc.readUntil([']]']).$2);
    }
    if (sc.tryConsume('[(')) {
      return (FlowNodeShape.cylinder, sc.readUntil([')]']).$2);
    }
    if (sc.tryConsume('[/')) {
      final (closer, label) = sc.readUntil(['/]', r'\]']);
      return (
        closer == '/]' ? FlowNodeShape.leanRight : FlowNodeShape.trapezoid,
        label,
      );
    }
    if (sc.tryConsume(r'[\')) {
      final (closer, label) = sc.readUntil([r'\]', '/]']);
      return (
        closer == r'\]' ? FlowNodeShape.leanLeft : FlowNodeShape.invTrapezoid,
        label,
      );
    }
    if (sc.tryConsume('[')) {
      return (FlowNodeShape.rect, sc.readUntil([']']).$2);
    }
    if (sc.tryConsume('{{')) {
      return (FlowNodeShape.hexagon, sc.readUntil(['}}']).$2);
    }
    if (sc.tryConsume('{')) {
      return (FlowNodeShape.diamond, sc.readUntil(['}']).$2);
    }
    if (sc.tryConsume('>')) {
      return (FlowNodeShape.asymmetric, sc.readUntil([']']).$2);
    }
    return null;
  }

  // --- edges -------------------------------------------------------------------

  _EdgeSpec? _tryParseEdge(_Scanner sc) {
    sc.skipWs();
    // Text-form links: `-- label -->`, `-. label .->`, `== label ==>`.
    final textForm = sc.tryMatch(RegExp(r'([<xo])?(--|-\.|==)(?=\s)'));
    if (textForm != null) {
      final startHead = textForm.group(1);
      final endPattern = switch (textForm.group(2)!) {
        '--' => RegExp(r'(-{2,}[-xo>])'),
        '-.' => RegExp(r'(\.+-[xo>]?)'),
        _ => RegExp(r'(={2,}[=xo>]?)'),
      };
      final (label, endToken) = sc.readEdgeText(endPattern);
      final spec = _destructEdgeToken(endToken, sc.line);
      return _withStartHead(spec, startHead, _normalizeLabel(label), sc.line);
    }

    final m = sc.tryMatch(RegExp(r'([<xo])?([-=~.]{2,})([xo>])?'));
    if (m == null) return null;
    final token = m.group(0)!;
    final spec = _destructEdgeToken(token, sc.line);

    // Optional `|label|` after the link.
    String? label;
    sc.skipWs();
    if (sc.tryConsume('|')) {
      final (_, raw) = sc.readUntil(['|']);
      label = _normalizeLabel(raw);
    }
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
    if (RegExp(r'^-?\.+-?$').hasMatch(core)) return true;
    if (core.length < 2) return false;
    if (RegExp(r'^-+$').hasMatch(core)) return true;
    if (RegExp(r'^=+$').hasMatch(core)) return true;
    return RegExp(r'^~+$').hasMatch(core);
  }

  _EdgeSpec _withStartHead(
      _EdgeSpec end, String? startHead, String label, int line) {
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

  String _normalizeLabel(String raw) {
    var s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    // Markdown string syntax: "`text`" — keep the text, drop the backticks.
    if (s.length >= 2 && s.startsWith('`') && s.endsWith('`')) {
      s = s.substring(1, s.length - 1);
    }
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
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

  String rest(int n) =>
      text.substring(pos, (pos + n).clamp(0, text.length));

  void skipWs() {
    while (!atEnd && (text[pos] == ' ' || text[pos] == '\t')) {
      pos++;
    }
  }

  bool tryConsume(String s) {
    if (text.startsWith(s, pos)) {
      pos += s.length;
      return true;
    }
    return false;
  }

  Match? tryMatch(RegExp re) {
    final m = re.matchAsPrefix(text, pos);
    if (m != null) pos = m.end;
    return m;
  }

  /// Consumes characters while they match [charClass].
  String readWhile(RegExp charClass) {
    final start = pos;
    while (!atEnd && charClass.hasMatch(text[pos])) {
      pos++;
    }
    return text.substring(start, pos);
  }

  static final _idChar = RegExp(r'[\p{L}\p{N}_!#$%&*+.?\\/' "'" r']', unicode: true);

  /// Mirrors upstream NODE_STRING: `-` only when not followed by `>`, `-` or
  /// `.` (so ids may contain dashes without eating links), `=` only when not
  /// followed by `=`.
  String readNodeId() {
    final start = pos;
    while (!atEnd) {
      final c = text[pos];
      final next = pos + 1 < text.length ? text[pos + 1] : null;
      if (c == '-') {
        // Dash stays in the id only when it cannot start a link token.
        if (next == null || next == '>' || next == '-' || next == '.') break;
        pos++;
        continue;
      }
      if (c == '=') {
        if (next == '=') break;
        pos++;
        continue;
      }
      if (_idChar.hasMatch(c)) {
        pos++;
        continue;
      }
      break;
    }
    return text.substring(start, pos);
  }

  /// Reads label content until one of [closers] (longest first), honoring
  /// quoted segments. Returns (closer, content).
  (String, String) readUntil(List<String> closers) {
    final sorted = [...closers]..sort((a, b) => b.length.compareTo(a.length));
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
      // Closers win over quote-starts so `"` itself can act as a closer.
      for (final closer in sorted) {
        if (text.startsWith(closer, pos)) {
          pos += closer.length;
          return (closer, buf.toString());
        }
      }
      if (c == '"') {
        inQuote = true;
        buf.write(c);
        pos++;
        continue;
      }
      buf.write(c);
      pos++;
    }
    throw MermaidParseException(
      'unterminated "${closers.first}" label in "$text"',
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

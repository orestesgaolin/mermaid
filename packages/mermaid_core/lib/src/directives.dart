/// `%%{init: ...}%%` directive and frontmatter `config:` handling: resolves
/// the effective theme for a diagram source, mirroring upstream's
/// theme + themeVariables semantics for the variables this port models.
library;

import 'dart:convert';

import 'package:elk/elk.dart' as elk;

import 'color.dart';
import 'theme/theme.dart';

/// Returns [base] adjusted by any `%%{init}%%` directive or frontmatter
/// `config.theme` in [source]. A named `theme` replaces [base];
/// `themeVariables` are applied on top.
MermaidTheme resolveTheme(String source, MermaidTheme base) {
  var theme = base;
  Map<String, Object?>? themeVariables;

  // Frontmatter: `config:\n  theme: dark\n  themeVariables:\n    primaryColor: ...`
  final fm = RegExp(r'^\s*---[ \t]*\n([\s\S]*?)\n[ \t]*---[ \t]*\n')
      .firstMatch(source.replaceAll('\r\n', '\n'));
  if (fm != null) {
    final body = fm.group(1)!;
    final m = RegExp(r'^\s*theme:\s*(\w+)\s*$', multiLine: true).firstMatch(body);
    if (m != null) theme = MermaidTheme.named(m.group(1)!);
    final fmVars = _frontmatterThemeVariables(body);
    if (fmVars.isNotEmpty) themeVariables = {...?themeVariables, ...fmVars};
  }

  // Merge ALL `%%{init}%%` directives, not just the first: the website (and
  // users) may have a separate `{'layout': 'elk'}` directive *before* the
  // theme one, so reading only the first would miss `theme: dark`.
  for (final directive in RegExp(r'%%\{\s*init(?:ialize)?\s*:\s*([\s\S]*?)\s*\}%%')
      .allMatches(source)) {
    final config = _looseJson(directive.group(1)!);
    if (config is Map) {
      final name = config['theme'];
      if (name is String) theme = MermaidTheme.named(name);
      final vars = config['themeVariables'];
      if (vars is Map) {
        themeVariables = {...?themeVariables, ...vars.map((k, v) => MapEntry('$k', v))};
      }
    }
  }

  if (themeVariables != null) {
    theme = _applyVariables(theme, themeVariables);
  }
  return theme;
}

/// Rendering options resolved from `%%{init}%%` / frontmatter `config:`
/// that are not part of the theme: the visual [look] and its sketch seed.
class LookConfig {
  const LookConfig({this.look = 'classic', this.handDrawnSeed = 0});

  final String look;
  final int handDrawnSeed;

  bool get isHandDrawn => look == 'handDrawn';
}

/// Extracts `look` / `handDrawnSeed` from an `%%{init}%%` directive or
/// frontmatter `config:` block in [source].
LookConfig resolveLook(String source) {
  var look = 'classic';
  var seed = 0;

  final text = source.replaceAll('\r\n', '\n');
  final fm = RegExp(r'^\s*---[ \t]*\n([\s\S]*?)\n[ \t]*---[ \t]*\n')
      .firstMatch(text);
  if (fm != null) {
    final body = fm.group(1)!;
    final lm =
        RegExp(r'^\s*look:\s*(\w+)\s*$', multiLine: true).firstMatch(body);
    if (lm != null) look = lm.group(1)!;
    final sm = RegExp(r'^\s*handDrawnSeed:\s*(\d+)\s*$', multiLine: true)
        .firstMatch(body);
    if (sm != null) seed = int.tryParse(sm.group(1)!) ?? 0;
  }

  // Merge every `%%{init}%%` directive (mermaid.js merges them too), so a
  // look directive is honoured even alongside a separate layout/theme one.
  for (final m in RegExp(r'%%\{\s*init(?:ialize)?\s*:\s*([\s\S]*?)\s*\}%%')
      .allMatches(text)) {
    final config = _looseJson(m.group(1)!);
    if (config is Map) {
      if (config['look'] is String) look = config['look'] as String;
      final s = config['handDrawnSeed'];
      if (s is num) seed = s.toInt();
    }
  }
  return LookConfig(look: look, handDrawnSeed: seed);
}

/// Resolves a diagram-specific config object from frontmatter and every init
/// directive. Later values replace earlier values, matching Mermaid's config
/// merge order.
Map<String, Object?> resolveDiagramConfig(String source, String diagramKey) {
  final result = <String, Object?>{};
  final text = source.replaceAll('\r\n', '\n');

  final fm = RegExp(r'^\s*---[ \t]*\n([\s\S]*?)\n[ \t]*---[ \t]*\n')
      .firstMatch(text);
  if (fm != null) {
    result.addAll(_frontmatterConfigBlock(fm.group(1)!, diagramKey));
  }

  for (final match
      in RegExp(
        r'%%\{\s*init(?:ialize)?\s*:\s*([\s\S]*?)\s*\}%%',
      ).allMatches(text)) {
    final config = _looseJson(match.group(1)!);
    if (config is! Map || config[diagramKey] is! Map) continue;
    result.addAll(
      (config[diagramKey] as Map).map((key, value) => MapEntry('$key', value)),
    );
  }
  return Map.unmodifiable(result);
}

/// Resolves the layout engine name (`dagre` default, or `elk` / `tidy-tree`)
/// from `layout:` in an `%%{init}%%` directive or frontmatter `config:`. Also
/// honours upstream's `flowchart.defaultRenderer: 'elk'` and recognizes the
/// `flowchart-elk` diagram keyword (handled by the caller).
String resolveLayout(String source, {String defaultLayout = 'dagre'}) {
  var layout = defaultLayout;
  final text = source.replaceAll('\r\n', '\n');
  // The `flowchart-elk` keyword selects the elk engine.
  if (RegExp(r'(?:^|\n)\s*flowchart-elk\b').hasMatch(text)) layout = 'elk';
  final fm = RegExp(r'^\s*---[ \t]*\n([\s\S]*?)\n[ \t]*---[ \t]*\n')
      .firstMatch(text);
  if (fm != null) {
    final lm = RegExp(r'^\s*layout:\s*([\w-]+)\s*$', multiLine: true)
        .firstMatch(fm.group(1)!);
    if (lm != null) layout = lm.group(1)!;
    // Upstream `flowchart.defaultRenderer: elk` (YAML frontmatter form).
    final dr = RegExp(r'''^\s*defaultRenderer:\s*['"]?elk['"]?\s*$''',
            multiLine: true, caseSensitive: false)
        .firstMatch(fm.group(1)!);
    if (dr != null) layout = 'elk';
  }
  for (final m in RegExp(r'%%\{\s*init(?:ialize)?\s*:\s*([\s\S]*?)\s*\}%%')
      .allMatches(text)) {
    final config = _looseJson(m.group(1)!);
    if (config is Map && config['layout'] is String) {
      layout = config['layout'] as String;
    }
    // Upstream `{flowchart: {defaultRenderer: 'elk'}}` selects the elk engine.
    final flow = config is Map ? config['flowchart'] : null;
    if (flow is Map && flow['defaultRenderer'] is String) {
      if ((flow['defaultRenderer'] as String).toLowerCase() == 'elk') {
        layout = 'elk';
      }
    }
  }
  return layout;
}

/// Resolves ELK layered options from `config.elk` in an `%%{init}%%` directive
/// or frontmatter. Unspecified knobs keep ELK's defaults (Brandes–Köpf
/// placement, `spacing.baseValue` 40 — matching upstream mermaid-layout-elk).
elk.ElkLayoutOptions resolveElkConfig(String source) {
  final text = source.replaceAll('\r\n', '\n');
  Map<String, dynamic> elkCfg = {};
  void merge(Object? config) {
    if (config is Map && config['elk'] is Map) {
      elkCfg.addAll((config['elk'] as Map).cast<String, dynamic>());
    }
  }

  final fm = RegExp(r'^\s*---[ \t]*\n([\s\S]*?)\n[ \t]*---[ \t]*\n')
      .firstMatch(text);
  if (fm != null) {
    final cfg = _looseJson('{${fm.group(1)!}}');
    if (cfg is Map && cfg['config'] is Map) merge(cfg['config']);
    merge(cfg);
  }
  for (final m in RegExp(r'%%\{\s*init(?:ialize)?\s*:\s*([\s\S]*?)\s*\}%%')
      .allMatches(text)) {
    merge(_looseJson(m.group(1)!));
  }

  return elk.ElkLayoutOptions(
    nodePlacement: _enumByName(
        elkCfg['nodePlacementStrategy'], elk.ElkNodePlacement.values,
        fallback: elk.ElkNodePlacement.brandesKoepf),
    fixedAlignment: _elkAlignment(elkCfg['nodePlacementAlignment']),
    mergeEdges: elkCfg['mergeEdges'] == true,
    considerModelOrder: _elkModelOrder(elkCfg['considerModelOrder']),
    cycleBreaking: _elkCycleBreaking(elkCfg['cycleBreakingStrategy']),
    forceNodeModelOrder: elkCfg['forceNodeModelOrder'] == true,
  );
}

T _enumByName<T extends Enum>(Object? raw, List<T> values, {required T fallback}) {
  if (raw is! String) return fallback;
  final key = raw.replaceAll('_', '').toLowerCase();
  for (final v in values) {
    if (v.name.toLowerCase() == key) return v;
  }
  return fallback;
}

elk.ElkFixedAlignment _elkAlignment(Object? raw) {
  if (raw is! String) return elk.ElkFixedAlignment.none;
  return switch (raw.toUpperCase()) {
    'LEFTUP' => elk.ElkFixedAlignment.leftUp,
    'LEFTDOWN' => elk.ElkFixedAlignment.leftDown,
    'RIGHTUP' => elk.ElkFixedAlignment.rightUp,
    'RIGHTDOWN' => elk.ElkFixedAlignment.rightDown,
    'BALANCED' => elk.ElkFixedAlignment.balanced,
    _ => elk.ElkFixedAlignment.none,
  };
}

elk.ElkConsiderModelOrder _elkModelOrder(Object? raw) {
  if (raw is! String) return elk.ElkConsiderModelOrder.none;
  return switch (raw.toUpperCase()) {
    'NODES_AND_EDGES' => elk.ElkConsiderModelOrder.nodesAndEdges,
    'PREFER_EDGES' => elk.ElkConsiderModelOrder.preferEdges,
    'PREFER_NODES' => elk.ElkConsiderModelOrder.preferNodes,
    _ => elk.ElkConsiderModelOrder.none,
  };
}

elk.ElkCycleBreaking _elkCycleBreaking(Object? raw) {
  if (raw is! String) return elk.ElkCycleBreaking.greedy;
  return switch (raw.toUpperCase()) {
    'DEPTH_FIRST' => elk.ElkCycleBreaking.depthFirst,
    'INTERACTIVE' => elk.ElkCycleBreaking.interactive,
    'MODEL_ORDER' => elk.ElkCycleBreaking.modelOrder,
    'GREEDY_MODEL_ORDER' => elk.ElkCycleBreaking.greedyModelOrder,
    _ => elk.ElkCycleBreaking.greedy,
  };
}

/// Parses a nested `themeVariables:` block out of frontmatter YAML, e.g.
///   config:
///     themeVariables:
///       primaryColor: "#ff0000"
///       lineColor: '#00ff00'
/// Returns the key→value map (values unquoted). Empty if absent.
Map<String, Object?> _frontmatterThemeVariables(String body) {
  final lines = body.split('\n');
  final out = <String, Object?>{};
  var inBlock = false;
  int? blockIndent;
  for (final raw in lines) {
    if (raw.trim().isEmpty) continue;
    final indent = raw.length - raw.trimLeft().length;
    final line = raw.trim();
    if (!inBlock) {
      if (RegExp(r'^themeVariables:\s*$').hasMatch(line)) {
        inBlock = true;
        blockIndent = indent;
      }
      continue;
    }
    // The block ends at the first line indented at or below `themeVariables:`.
    if (indent <= blockIndent!) break;
    final m = RegExp(r'^([A-Za-z_]\w*)\s*:\s*(.+)$').firstMatch(line);
    if (m == null) continue;
    var v = m.group(2)!.trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    out[m.group(1)!] = v;
  }
  return out;
}

/// A `key: value` line. Keys may contain hyphens and dots so real-world names
/// survive (`Bio-conversion` in a sankey `nodeColors:` block, `chart.width`).
final RegExp _yamlEntry = RegExp(r'^([A-Za-z0-9_][\w.-]*)\s*:\s*(.+)$');

/// A `key:` line that opens a nested block.
final RegExp _yamlBlockKey = RegExp(r'^([A-Za-z0-9_][\w.-]*)\s*:\s*$');

Map<String, Object?> _frontmatterConfigBlock(String body, String name) {
  final lines = body.split('\n');
  final out = <String, Object?>{};
  int? configIndent;
  int? diagramIndent;
  int? propertyIndent;
  String? nestedProperty;
  for (final raw in lines) {
    if (raw.trim().isEmpty) continue;
    final indent = raw.length - raw.trimLeft().length;
    final line = _stripYamlComment(raw.trim());
    if (line.isEmpty) continue;
    if (configIndent == null) {
      if (line == 'config:') configIndent = indent;
      continue;
    }
    if (indent <= configIndent) break;
    if (diagramIndent == null) {
      if (line == '$name:') diagramIndent = indent;
      continue;
    }
    if (indent <= diagramIndent) break;
    propertyIndent ??= indent;
    if (indent == propertyIndent) {
      nestedProperty = null;
      final nested = _yamlBlockKey.firstMatch(line);
      if (nested != null) {
        nestedProperty = nested.group(1)!;
        out[nestedProperty] = <String, Object?>{};
        continue;
      }
      final match = _yamlEntry.firstMatch(line);
      if (match != null) {
        out[match.group(1)!] = _parseYamlScalar(match.group(2)!.trim());
      }
    } else if (indent > propertyIndent && nestedProperty != null) {
      final match = _yamlEntry.firstMatch(line);
      if (match != null) {
        (out[nestedProperty]! as Map<String, Object?>)[match.group(1)!] =
            _parseYamlScalar(match.group(2)!.trim());
      }
    }
  }
  return out;
}

/// Removes a trailing YAML comment from [value].
///
/// As in YAML, `#` opens a comment only at the start of the text or after a
/// space or tab, and never inside single or double quotes. So `800 # note`
/// becomes `800`, while `'#ff0000'` and `sha#1` are returned unchanged.
String _stripYamlComment(String value) {
  String? quote;
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (quote != null) {
      if (c == quote) quote = null;
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      continue;
    }
    if (c == '#' && (i == 0 || value[i - 1] == ' ' || value[i - 1] == '\t')) {
      return value.substring(0, i).trimRight();
    }
  }
  return value;
}

/// Splits a flow-collection body on top-level commas, ignoring commas inside
/// quotes or nested braces/brackets.
List<String> _splitFlowEntries(String body) {
  final out = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var depth = 0;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (quote != null) {
      buffer.write(c);
      if (c == quote) quote = null;
      continue;
    }
    switch (c) {
      case '"':
      case "'":
        quote = c;
        buffer.write(c);
      case '{':
      case '[':
        depth++;
        buffer.write(c);
      case '}':
      case ']':
        depth--;
        buffer.write(c);
      case ',' when depth == 0:
        out.add(buffer.toString());
        buffer.clear();
      default:
        buffer.write(c);
    }
  }
  if (buffer.isNotEmpty) out.add(buffer.toString());
  return out;
}

/// Parses a flow-style mapping such as `{width: 800, linkColor: gradient}`.
/// Entries that are not `key: value` are skipped; values are parsed with
/// [_parseYamlScalar], so nested flow mappings work too.
Map<String, Object?> _parseFlowMap(String value) {
  final out = <String, Object?>{};
  for (final entry in _splitFlowEntries(value.substring(1, value.length - 1))) {
    final match = _yamlEntry.firstMatch(entry.trim());
    if (match == null) continue;
    out[match.group(1)!] = _parseYamlScalar(match.group(2)!.trim());
  }
  return out;
}

Object? _parseYamlScalar(String raw) {
  final value = _stripYamlComment(raw).trim();
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1);
  }
  if (value.length >= 2 && value.startsWith('{') && value.endsWith('}')) {
    return _parseFlowMap(value);
  }
  if (value.isEmpty || value == 'null' || value == '~') return null;
  if (value == 'true') return true;
  if (value == 'false') return false;
  return num.tryParse(value) ?? value;
}

/// Mermaid directives use loose JSON (single quotes, bare keys); normalize
/// before decoding. Returns null when it still cannot be parsed.
Object? _looseJson(String text) {
  var t = text.trim();
  t = t.replaceAll("'", '"');
  t = t.replaceAllMapped(
    RegExp(r'([{,]\s*)([A-Za-z_][\w-]*)\s*:'),
    (m) => '${m[1]}"${m[2]}":',
  );
  try {
    return jsonDecode(t);
  } catch (_) {
    return null;
  }
}

MermaidTheme _applyVariables(MermaidTheme theme, Map<String, Object?> vars) {
  Color? color(String key) {
    final v = vars[key];
    return v is String ? Color.tryParse(v) : null;
  }

  // primaryColor drives the node fill family unless overridden explicitly
  // (upstream theme-base recalculates mainBkg etc. from primaryColor).
  final primary = color('primaryColor');
  final primaryBorder = color('primaryBorderColor');
  final primaryText = color('primaryTextColor');
  final fontSizeRaw = vars['fontSize'];
  final fontSize = fontSizeRaw is num
      ? fontSizeRaw.toDouble()
      : fontSizeRaw is String
          ? double.tryParse(fontSizeRaw.replaceAll(RegExp(r'px$'), ''))
          : null;

  return theme.copyWith(
    background: color('background'),
    primaryColor: primary,
    primaryTextColor: primaryText,
    primaryBorderColor: primaryBorder,
    secondaryColor: color('secondaryColor'),
    lineColor: color('lineColor'),
    arrowheadColor: color('arrowheadColor') ?? color('lineColor'),
    textColor: color('textColor') ?? primaryText,
    nodeBorder: color('nodeBorder') ?? primaryBorder,
    mainBkg: color('mainBkg') ?? primary,
    clusterBkg: color('clusterBkg') ?? color('secondaryColor'),
    clusterBorder: color('clusterBorder'),
    titleColor: color('titleColor') ?? color('textColor'),
    edgeLabelBackground: color('edgeLabelBackground'),
    fontFamily: vars['fontFamily'] is String ? vars['fontFamily'] as String : null,
    fontSize: fontSize,
  );
}

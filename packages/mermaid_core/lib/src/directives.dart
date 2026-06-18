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

/// Resolves the layout engine name (`dagre` default, or `elk` / `tidy-tree`)
/// from `layout:` in an `%%{init}%%` directive or frontmatter `config:`. Also
/// recognizes the `flowchart-elk` diagram keyword (handled by the caller).
String resolveLayout(String source) {
  var layout = 'dagre';
  final text = source.replaceAll('\r\n', '\n');
  // The `flowchart-elk` keyword selects the elk engine.
  if (RegExp(r'(?:^|\n)\s*flowchart-elk\b').hasMatch(text)) layout = 'elk';
  final fm = RegExp(r'^\s*---[ \t]*\n([\s\S]*?)\n[ \t]*---[ \t]*\n')
      .firstMatch(text);
  if (fm != null) {
    final lm = RegExp(r'^\s*layout:\s*([\w-]+)\s*$', multiLine: true)
        .firstMatch(fm.group(1)!);
    if (lm != null) layout = lm.group(1)!;
  }
  for (final m in RegExp(r'%%\{\s*init(?:ialize)?\s*:\s*([\s\S]*?)\s*\}%%')
      .allMatches(text)) {
    final config = _looseJson(m.group(1)!);
    if (config is Map && config['layout'] is String) {
      layout = config['layout'] as String;
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

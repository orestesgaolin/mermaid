/// `mermaid_dart` command-line tool: renders a mermaid diagram to SVG (pure
/// Dart) or PNG (by piping the SVG through a rasterizer found on PATH —
/// rsvg-convert, resvg or ImageMagick).
///
/// Examples:
///   mermaid_dart diagram.mmd                 # SVG to stdout
///   mermaid_dart diagram.mmd -o out.svg
///   mermaid_dart diagram.mmd -o out.png      # format inferred from extension
///   cat diagram.mmd | mermaid_dart -f png -o out.png
///   mermaid_dart diagram.mmd --theme dark
library;

import 'dart:io';

import 'package:mermaid_core/mermaid_core.dart';

const _usage = '''
mermaid_dart — render mermaid diagrams to SVG/PNG (pure Dart core)

Usage: mermaid_dart [options] [input.mmd]

  -o, --output <file>   Write output to <file> (default: stdout).
  -f, --format <fmt>    svg | png. Default: inferred from --output's
                        extension, else svg.
  -t, --theme <name>    Base theme: default | dark | forest | neutral.
                        (A %%{init}%% / frontmatter theme in the source
                        still overrides this.)
  -h, --help            Show this help.

With no input file, the diagram source is read from stdin.

PNG output requires one of these rasterizers on your PATH:
  rsvg-convert  |  resvg  |  magick/convert (ImageMagick)
''';

int main(List<String> args) {
  String? input;
  String? output;
  String? format;
  var themeName = 'default';

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String value() => ++i < args.length
        ? args[i]
        : _fail('missing value for "$a"');
    switch (a) {
      case '-h':
      case '--help':
        stdout.writeln(_usage);
        return 0;
      case '-o':
      case '--output':
        output = value();
      case '-f':
      case '--format':
        format = value().toLowerCase();
      case '-t':
      case '--theme':
        themeName = value();
      default:
        if (a.startsWith('-')) _fail('unknown option "$a"');
        if (input != null) _fail('multiple input files given');
        input = a;
    }
  }

  // Resolve format: explicit flag, else output extension, else svg.
  format ??= switch (output?.toLowerCase()) {
    final o? when o.endsWith('.png') => 'png',
    final o? when o.endsWith('.svg') => 'svg',
    _ => 'svg',
  };
  if (format != 'svg' && format != 'png') _fail('unknown format "$format"');

  final src =
      input != null ? File(input).readAsStringSync() : _readAllStdin();

  final String svg;
  try {
    final mermaid = Mermaid(
      measurer: const ApproximateTextMeasurer(),
      theme: MermaidTheme.named(themeName),
    );
    svg = renderSceneToSvg(mermaid.render(src));
  } on MermaidParseException catch (e) {
    return _fail('parse error: ${e.message}'
        '${e.line != null ? ' (line ${e.line})' : ''}');
  } catch (e) {
    return _fail('render failed: $e');
  }

  if (format == 'svg') {
    if (output != null) {
      File(output).writeAsStringSync(svg);
    } else {
      stdout.write(svg);
    }
    return 0;
  }

  // PNG: write SVG to a temp file and run a rasterizer.
  if (output == null) _fail('PNG output requires --output <file.png>');
  final tmp = File(
      '${Directory.systemTemp.path}/mermaid_dart_${pid}_${DateTime.now().microsecondsSinceEpoch}.svg');
  tmp.writeAsStringSync(svg);
  try {
    if (!_rasterize(tmp.path, output)) {
      return _fail('no SVG rasterizer found on PATH. Install one of: '
          'rsvg-convert, resvg, or ImageMagick (magick/convert).');
    }
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
  return 0;
}

/// Tries known rasterizers in order; returns true on the first success.
bool _rasterize(String svgPath, String pngPath) {
  final candidates = <List<String>>[
    ['rsvg-convert', '-b', 'white', svgPath, '-o', pngPath],
    ['resvg', svgPath, pngPath],
    ['magick', '-background', 'white', svgPath, pngPath],
    ['convert', '-background', 'white', svgPath, pngPath],
  ];
  for (final cmd in candidates) {
    if (_which(cmd.first) == null) continue;
    final r = Process.runSync(cmd.first, cmd.sublist(1));
    if (r.exitCode == 0) return true;
  }
  return false;
}

String? _which(String name) {
  final tool = Platform.isWindows ? 'where' : 'which';
  final r = Process.runSync(tool, [name]);
  if (r.exitCode != 0) return null;
  final out = (r.stdout as String).trim();
  return out.isEmpty ? null : out.split('\n').first;
}

String _readAllStdin() {
  final buf = StringBuffer();
  String? line;
  while ((line = stdin.readLineSync(retainNewlines: true)) != null) {
    buf.write(line);
  }
  return buf.toString();
}

Never _fail(String message) {
  stderr.writeln('mermaid_dart: $message');
  exit(64);
}

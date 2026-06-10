/// Renders a mermaid source file to SVG on stdout (pure Dart, no Flutter).
///
/// Usage: dart run tool/render_svg.dart diagram.mmd > out.svg
library;

import 'dart:io';

import 'package:mermaid_core/mermaid_core.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/render_svg.dart <file.mmd>');
    exitCode = 64;
    return;
  }
  final source = File(args.first).readAsStringSync();
  const mermaid = Mermaid(measurer: ApproximateTextMeasurer());
  stdout.writeln(renderSceneToSvg(mermaid.render(source)));
}

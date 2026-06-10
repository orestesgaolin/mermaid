/// Runs the full detect → parse → layout pipeline over every upstream demo
/// corpus in test/fixtures/upstream_* and reports per-file pass/fail.
///
/// Usage: dart run tool/validate_corpus.dart [-v] [dir-substring]
library;

import 'dart:io';

import 'package:mermaid_core/mermaid_core.dart';

void main(List<String> args) {
  final verbose = args.contains('-v');
  final filter = args.where((a) => a != '-v').firstOrNull;
  final dirs = Directory('test/fixtures')
      .listSync()
      .whereType<Directory>()
      .where((d) => d.uri.pathSegments[d.uri.pathSegments.length - 2]
          .startsWith('upstream_'))
      .where((d) => filter == null || d.path.contains(filter))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final mermaid = const Mermaid(measurer: ApproximateTextMeasurer());

  var total = 0;
  final failures = <String>[];
  for (final dir in dirs) {
    final dirName = dir.uri.pathSegments[dir.uri.pathSegments.length - 2];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mmd'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      total++;
      final name = '$dirName/${file.uri.pathSegments.last}';
      try {
        final scene = mermaid.render(file.readAsStringSync());
        if (verbose) {
          stdout.writeln('PASS $name '
              '(${scene.size.width.round()}x${scene.size.height.round()})');
        }
      } catch (e) {
        failures.add('FAIL $name: ${e.toString().split('\n').first}');
      }
    }
  }
  stdout.writeln(
      '\n$total fixtures: ${total - failures.length} pass, ${failures.length} fail');
  failures.forEach(stdout.writeln);
  if (failures.isNotEmpty) exitCode = 1;
}

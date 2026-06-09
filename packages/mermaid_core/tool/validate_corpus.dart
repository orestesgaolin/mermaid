/// Runs the full parse → layout pipeline over the upstream demo corpus in
/// test/fixtures/upstream_flowcharts and reports per-file pass/fail.
///
/// Usage: dart run tool/validate_corpus.dart [-v]
library;

import 'dart:io';

import 'package:mermaid_core/mermaid_core.dart';

void main(List<String> args) {
  final verbose = args.contains('-v');
  final dir = Directory('test/fixtures/upstream_flowcharts');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mmd')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final mermaid = Mermaid(measurer: const ApproximateTextMeasurer());

  var parseFail = 0;
  var layoutFail = 0;
  final failures = <String>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final source = file.readAsStringSync();
    try {
      final graph = parseFlowchart(source);
      try {
        final scene = mermaid.render(source);
        if (verbose) {
          stdout.writeln(
              'PASS $name (${graph.nodes.length} nodes, ${graph.edges.length} edges, '
              '${scene.size.width.round()}x${scene.size.height.round()})');
        }
      } catch (e) {
        layoutFail++;
        failures.add('LAYOUT $name: $e');
      }
    } catch (e) {
      parseFail++;
      failures.add('PARSE  $name: ${e.toString().split('\n').first}');
    }
  }
  stdout.writeln('\n${files.length} fixtures: '
      '${files.length - parseFail - layoutFail} pass, '
      '$parseFail parse failures, $layoutFail layout failures');
  failures.forEach(stdout.writeln);
  if (failures.isNotEmpty) exitCode = 1;
}

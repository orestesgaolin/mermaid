import 'dart:io';
import 'package:mermaid_core/mermaid_core.dart';

void main(List<String> args) {
  final src = File(args[0]).readAsStringSync();
  try {
    final g = parseFlowchart(src);
    stdout.writeln('parsed: ${g.nodes.length} nodes ${g.edges.length} edges');
    final scene = const Mermaid(measurer: ApproximateTextMeasurer()).render(src);
    stdout.writeln('layout ok ${scene.size}');
  } catch (e, st) {
    stdout.writeln('ERROR: $e');
    stdout.writeln(st.toString().split('\n').take(6).join('\n'));
  }
}

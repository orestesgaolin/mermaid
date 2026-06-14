/// Hand-written parser for mermaid pie charts.
///
/// Grammar reference: upstream `pie` langium grammar / pieParser.ts.
library;

import '../../detect.dart';
import '../../parse_error.dart';
import 'pie_model.dart';

PieChart parsePieChart(String source) {
  final frontTitle = frontmatterTitle(source);
  final text = stripMetadata(source);
  final lines = text.split('\n');
  String? title = frontTitle;
  var showData = false;
  final slices = <PieSlice>[];
  // Upstream addSection stores sections in a Map: a repeated label is ignored
  // (first value wins). Track seen labels to mirror that first-wins dedup.
  final seenLabels = <String>{};
  var seenHeader = false;

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.isEmpty) continue;

    if (!seenHeader) {
      final m =
          RegExp(r'^pie(\s+showData)?(\s+title\s+(.+))?\s*$').firstMatch(line);
      if (m == null) {
        throw MermaidParseException('expected "pie" header', line: i + 1);
      }
      showData = m.group(1) != null;
      if (m.group(3) != null) title = m.group(3)!.trim();
      seenHeader = true;
      continue;
    }

    var m = RegExp(r'^showData\s*$').firstMatch(line);
    if (m != null) {
      showData = true;
      continue;
    }
    m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      continue;
    }
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(line)) continue;

    m = RegExp(r'^"([^"]*)"\s*:\s*([0-9.]+)\s*$').firstMatch(line);
    if (m != null) {
      final value = double.tryParse(m.group(2)!);
      if (value == null || value < 0) {
        throw MermaidParseException('invalid pie value "${m.group(2)}"',
            line: i + 1);
      }
      final label = m.group(1)!;
      if (seenLabels.add(label)) {
        slices.add(PieSlice(label: label, value: value));
      }
      continue;
    }

    throw MermaidParseException('unrecognized statement "$line"', line: i + 1);
  }
  if (!seenHeader) {
    throw const MermaidParseException('empty pie chart source');
  }
  return PieChart(slices: slices, title: title, showData: showData);
}

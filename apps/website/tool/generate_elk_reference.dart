import 'dart:convert';
import 'dart:io';

import 'package:website/elk_demos.dart';
import 'package:website/elk_reference.dart';

Future<void> main() async {
  final examples = buildElkExamples();
  final temporary = await Directory.systemTemp.createTemp('elk-reference-');
  try {
    final input = File('${temporary.path}/input.json');
    final output = File('${temporary.path}/output.json');
    input.writeAsStringSync(
      jsonEncode([
        for (final example in examples)
          {'title': example.title, 'input': elkGraphToJson(example.graph)},
      ]),
    );
    final process = await Process.run('node', [
      'tool/generate_elk_reference.mjs',
      input.path,
      output.path,
    ]);
    stdout.write(process.stdout);
    stderr.write(process.stderr);
    if (process.exitCode != 0) exitCode = process.exitCode;
    if (process.exitCode != 0) return;

    final raw = output.readAsStringSync();
    if (raw.contains("'''")) {
      throw StateError('Generated JSON cannot be embedded in a raw literal');
    }
    final target = File('lib/generated/elk_reference_data.g.dart');
    target.writeAsStringSync('''
// GENERATED FILE. Run `dart run tool/generate_elk_reference.dart`.
import 'dart:convert';

final Map<String, dynamic> elkReferenceData =
    (jsonDecode(r\'\'\'$raw\'\'\') as Map).cast<String, dynamic>();
''');
    stdout.writeln('Wrote ${target.path}.');
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

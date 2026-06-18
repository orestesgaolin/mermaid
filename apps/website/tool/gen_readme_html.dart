// Renders packages/elk/README.md to HTML and bakes it into
// lib/generated/elk_readme.g.dart, so the /elk page can show the canonical
// package docs (options table, examples, validation) on the website. Run from
// the website package root after editing the README:
//
//   dart run tool/gen_readme_html.dart
import 'dart:io';

import 'package:markdown/markdown.dart' as md;

void main() {
  final scriptDir = File.fromUri(Platform.script).parent.path; // apps/website/tool
  final readme = File('$scriptDir/../../../packages/elk/README.md');
  if (!readme.existsSync()) {
    stderr.writeln('README not found at ${readme.path}');
    exit(1);
  }

  // Drop the leading "# elk" H1 — the page already has that title.
  final lines = readme.readAsLinesSync();
  final body = (lines.isNotEmpty && lines.first.startsWith('# '))
      ? lines.skip(1).join('\n')
      : lines.join('\n');

  // GitHub-flavored: tables + fenced code blocks.
  final html = md.markdownToHtml(body, extensionSet: md.ExtensionSet.gitHubWeb);

  if (html.contains("'''")) {
    stderr.writeln("README HTML contains ''' — adjust the generator quoting.");
    exit(1);
  }

  final out = File('$scriptDir/../lib/generated/elk_readme.g.dart');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync('''
// GENERATED — do not edit. Source: packages/elk/README.md
// Regenerate: dart run tool/gen_readme_html.dart
library;

/// The elk README rendered to HTML (minus its top-level title).
const elkReadmeHtml = r\'\'\'
$html\'\'\';
''');
  stdout.writeln('Wrote ${out.path} (${html.length} chars of HTML).');
}

/// Builds the image corpus used by the local Mermaid parity review.
///
/// This is a generator, not a test: it lives outside `apps/demo/test/` so a
/// plain `flutter test` does not spend ~5 s writing a ~9 MB corpus. The
/// `_test.dart` suffix is kept so the Flutter test runner can host it.
///
/// Run from the workspace root:
///
///   fvm flutter test apps/demo/tool/parity_review_test.dart -r expanded
///   fvm dart run tool/parity_review/build_report.dart
///
/// Output is written to `build/parity_review` (gitignored). Flutter PNGs use
/// the same FlutterTextMeasurer and ScenePainter pipeline as the package
/// itself. The corpus itself is shared with the cheap render smoke test in
/// `apps/demo/test/render_corpus_smoke_test.dart`.
///
/// macOS only: the review compares against Mermaid.js rasterized with system
/// fonts, so the run fails fast if those fonts are missing rather than
/// rasterizing with Flutter's solid-block Ahem test glyphs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import '../test/support/parity_corpus.dart';
import '../test/support/workspace.dart';

/// Mermaid.js version used for the reference renders.
///
/// Keep in sync with the same constant in
/// `tool/parity_review/build_report.dart` (different package, so the literal
/// cannot be shared) — the capture page and the report must compare against
/// one and the same upstream build.
const _mermaidJsVersion = '11.17.2';

/// System fonts the review corpus needs, keyed by the family the renderer
/// asks for. Without these the PNGs are rasterized with Ahem test glyphs and
/// the whole corpus is useless for a visual comparison.
const _requiredFonts = <String, String>{
  'trebuchet ms': '/System/Library/Fonts/Supplemental/Trebuchet MS.ttf',
  'Arial Unicode MS': '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  'monospace': '/System/Library/Fonts/SFNSMono.ttf',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final missing = _requiredFonts.entries
        .where((entry) => !File(entry.value).existsSync())
        .toList();
    if (missing.isNotEmpty) {
      throw StateError(
        'Cannot build the parity review corpus: the following system fonts '
        'are missing, so every PNG would be rasterized with Flutter\'s Ahem '
        'test glyphs:\n'
        '${missing.map((e) => '  - ${e.key}: ${e.value}').join('\n')}\n'
        'This generator is macOS only. Run it on macOS, or point '
        '_requiredFonts at equivalent local font files.',
      );
    }
    for (final entry in _requiredFonts.entries) {
      final bytes = File(entry.value).readAsBytesSync();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });

  test('builds the parity review batch', () async {
    final root = workspaceRoot();
    final output = Directory('${root.path}/build/parity_review');
    final assets = Directory('${output.path}/assets')
      ..createSync(recursive: true);
    final cases = loadParityCases(root);
    final manifest = <Map<String, Object?>>[];

    for (final entry in cases) {
      final record = <String, Object?>{
        'id': entry.id,
        'title': entry.title,
        'family': entry.family,
        'origin': entry.origin,
        'source': entry.source,
      };

      try {
        final scene = const core.Mermaid(
          measurer: FlutterTextMeasurer(),
        ).render(entry.source);
        final pngName = '${entry.id}.flutter.png';
        final dimensions = await _paintFlutterPng(
          scene,
          File('${assets.path}/$pngName'),
        );
        record
          ..['flutterPath'] = 'assets/$pngName'
          ..['flutterWidth'] = dimensions.$1
          ..['flutterHeight'] = dimensions.$2;
      } catch (error, stack) {
        record['flutterError'] = '$error\n$stack';
      }

      try {
        final scene = const core.Mermaid(
          measurer: core.ApproximateTextMeasurer(),
        ).render(entry.source);
        final svgName = '${entry.id}.core.svg';
        File(
          '${assets.path}/$svgName',
        ).writeAsStringSync(core.renderSceneToSvg(scene));
        record['corePath'] = 'assets/$svgName';
      } catch (error, stack) {
        record['coreError'] = '$error\n$stack';
      }

      manifest.add(record);
    }

    const encoder = JsonEncoder.withIndent('  ');
    File(
      '${output.path}/manifest.json',
    ).writeAsStringSync(encoder.convert(manifest));
    File(
      '${output.path}/capture.html',
    ).writeAsStringSync(_capturePage(manifest));

    expect(
      manifest.where((entry) => entry.containsKey('flutterError')),
      isEmpty,
    );
    expect(manifest.where((entry) => entry.containsKey('coreError')), isEmpty);
  });
}

Future<(int, int)> _paintFlutterPng(core.RenderScene scene, File output) async {
  const padding = 24.0;
  final naturalWidth = scene.size.width + padding * 2;
  final naturalHeight = scene.size.height + padding * 2;
  final scale = math.min(
    1.5,
    math.min(3000 / naturalWidth, 2200 / naturalHeight),
  );
  final width = math.max(1, (naturalWidth * scale).ceil());
  final height = math.max(1, (naturalHeight * scale).ceil());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xffffffff),
  );
  canvas
    ..scale(scale)
    ..translate(padding, padding);
  ScenePainter(
    scene,
  ).paint(canvas, ui.Size(scene.size.width, scene.size.height));
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  output.writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
  return (width, height);
}

String _capturePage(List<Map<String, Object?>> manifest) {
  final cases = jsonEncode([
    for (final entry in manifest)
      {'id': entry['id'], 'title': entry['title'], 'source': entry['source']},
  ]).replaceAll('</script', r'<\/script');
  return '''<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>Mermaid.js reference capture</title>
<style>
  body { font: 14px system-ui; margin: 24px; background: #f4f6f7; }
  article { margin: 0 0 20px; padding: 16px; background: white; }
  .reference { min-height: 80px; }
  .error { color: #a32020; white-space: pre-wrap; }
</style>
<body>
<h1>Mermaid.js reference capture</h1>
<p id="status">Starting…</p>
<main id="cases"></main>
<script type="module">
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@$_mermaidJsVersion/dist/mermaid.esm.min.mjs';
mermaid.initialize({ startOnLoad: false, theme: 'default' });
const cases = $cases;
const main = document.querySelector('#cases');
const results = [];
for (let index = 0; index < cases.length; index++) {
  const item = cases[index];
  const article = document.createElement('article');
  article.dataset.id = item.id;
  article.innerHTML = `<h2>\${index + 1}. \${item.title}</h2><div class="reference"></div>`;
  main.append(article);
  const target = article.querySelector('.reference');
  try {
    const rendered = await mermaid.render(`parity-\${index}`, item.source);
    target.innerHTML = rendered.svg;
    results.push({ id: item.id, ok: true });
  } catch (error) {
    target.classList.add('error');
    target.textContent = String(error);
    document.getElementById(`dparity-\${index}`)?.remove();
    results.push({ id: item.id, ok: false, error: String(error) });
  }
  document.querySelector('#status').textContent = `Rendered \${index + 1} / \${cases.length}`;
}
window.__parityResults = results;
window.__parityReady = true;
</script>
</body>
</html>''';
}

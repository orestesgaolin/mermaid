/// Builds the image corpus used by the local Mermaid parity review.
///
/// Run from the workspace root:
///
///   fvm flutter test apps/demo/test/parity_review_test.dart -r expanded
///
/// Output is written to build/parity_review. Flutter PNGs use the same
/// FlutterTextMeasurer and ScenePainter pipeline as the package itself.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:mermaid_samples/mermaid_samples.dart';

const _curatedIds = <String>[
  'subgraphs',
  'math',
  'block',
  'architecture',
  'kanban',
  'cynefin',
  'ishikawa',
  'eventmodeling',
  'railroad',
  'radar',
  'treemap',
  'venn',
  'wardley',
  'handdrawn',
];

// The largest checked-in upstream fixture for each covered diagram family.
// Together with the curated cases above this gives a broad, deliberately
// complex first batch without asking a reviewer to inspect all 220 cases.
const _fixturePaths = <String>[
  'packages/mermaid_core/test/fixtures/upstream_c4/05.mmd',
  'packages/mermaid_core/test/fixtures/upstream_class/11.mmd',
  'packages/mermaid_core/test/fixtures/upstream_er/03.mmd',
  'packages/mermaid_core/test/fixtures/upstream_flowcharts/07.mmd',
  'packages/mermaid_core/test/fixtures/upstream_gantt/08.mmd',
  'packages/mermaid_core/test/fixtures/upstream_git/33.mmd',
  'packages/mermaid_core/test/fixtures/upstream_journey/01.mmd',
  'packages/mermaid_core/test/fixtures/upstream_mindmap/01.mmd',
  'packages/mermaid_core/test/fixtures/upstream_packet/03.mmd',
  'packages/mermaid_core/test/fixtures/upstream_pie/01.mmd',
  'packages/mermaid_core/test/fixtures/upstream_quadrant/02.mmd',
  'packages/mermaid_core/test/fixtures/upstream_requirement/02.mmd',
  'packages/mermaid_core/test/fixtures/upstream_sankey/03.mmd',
  'packages/mermaid_core/test/fixtures/upstream_sequence/01.mmd',
  'packages/mermaid_core/test/fixtures/upstream_state/05.mmd',
  'packages/mermaid_core/test/fixtures/upstream_timeline/03.mmd',
  'packages/mermaid_core/test/fixtures/upstream_xychart/18.mmd',
];

class _ParityCase {
  const _ParityCase({
    required this.id,
    required this.title,
    required this.family,
    required this.origin,
    required this.source,
  });

  final String id;
  final String title;
  final String family;
  final String origin;
  final String source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    const path = '/System/Library/Fonts/Supplemental/Trebuchet MS.ttf';
    if (File(path).existsSync()) {
      final bytes = File(path).readAsBytesSync();
      final loader = FontLoader('trebuchet ms')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    const symbolsPath =
        '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
    if (File(symbolsPath).existsSync()) {
      final bytes = File(symbolsPath).readAsBytesSync();
      final loader = FontLoader('Arial Unicode MS')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    const monoPath = '/System/Library/Fonts/SFNSMono.ttf';
    if (File(monoPath).existsSync()) {
      final bytes = File(monoPath).readAsBytesSync();
      final loader = FontLoader('monospace')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });

  test('builds the first parity review batch', () async {
    final root = _workspaceRoot();
    final output = Directory('${root.path}/build/parity_review');
    final assets = Directory('${output.path}/assets')
      ..createSync(recursive: true);
    final cases = _loadCases(root);
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

    expect(manifest, hasLength(31));
    expect(
      manifest.where((entry) => entry.containsKey('flutterError')),
      isEmpty,
    );
    expect(manifest.where((entry) => entry.containsKey('coreError')), isEmpty);
  });
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (Directory('${current.path}/packages/mermaid_core').existsSync() &&
        Directory('${current.path}/apps/demo').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the Mermaid workspace root.');
    }
    current = parent;
  }
}

List<_ParityCase> _loadCases(Directory root) {
  final result = <_ParityCase>[];
  for (final id in _curatedIds) {
    final sample = samples.singleWhere((sample) => sample.id == id);
    result.add(
      _ParityCase(
        id: 'curated-$id',
        title: sample.name,
        family: id,
        origin: 'packages/mermaid_samples:$id',
        source: sample.source.trim(),
      ),
    );
  }
  for (final path in _fixturePaths) {
    final file = File('${root.path}/$path');
    final directory = file.parent.path.split('/').last;
    final family = directory.replaceFirst('upstream_', '');
    final fixture = file.uri.pathSegments.last.replaceFirst('.mmd', '');
    result.add(
      _ParityCase(
        id: 'upstream-$family-$fixture',
        title: '${_titleCase(family)} fixture $fixture',
        family: family,
        origin: path,
        source: file.readAsStringSync().trim(),
      ),
    );
  }
  return result;
}

String _titleCase(String value) => value
    .split(RegExp(r'[_-]'))
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

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
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
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

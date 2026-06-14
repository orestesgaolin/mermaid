/// Generates the pub.dev screenshots for `mermaid_flutter` by painting a
/// curated set of shared samples through the real Flutter `ScenePainter`
/// (the same pipeline the package ships), on a white background at 2x.
///
/// Run with: `flutter test test/screenshots_test.dart` from `apps/demo`.
/// Output lands in `packages/mermaid_flutter/doc/screenshots/`, which the
/// `screenshots:` field of mermaid_flutter/pubspec.yaml points at.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:mermaid_samples/mermaid_samples.dart';

// Sample ids (from mermaid_samples) to capture, in carousel order. The first
// becomes the package thumbnail on pub.dev, so it leads with a plain flowchart.
const _shots = <String>[
  'flowchart',
  'sequence',
  'class',
  'state',
  'git',
  'pie',
  'xychart',
  'mindmap',
  'sankey',
];

String _sourceFor(String id) =>
    samples.firstWhere((s) => s.id == id).source;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Use the real font so the rendered text matches the live app.
    const path = '/System/Library/Fonts/Supplemental/Trebuchet MS.ttf';
    if (File(path).existsSync()) {
      final bytes = File(path).readAsBytesSync();
      final loader = FontLoader('trebuchet ms')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });

  final outDir = Directory('../../packages/mermaid_flutter/doc/screenshots');

  for (final id in _shots) {
    test('screenshot: $id', () async {
      final scene =
          core.Mermaid(measurer: const FlutterTextMeasurer()).render(_sourceFor(id));
      expect(scene.size.width, greaterThan(0));

      const scale = 2.0;
      const pad = 16.0;
      final w = (scene.size.width + pad * 2) * scale;
      final h = (scene.size.height + pad * 2) * scale;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      // White backdrop so the PNG reads cleanly on pub.dev (light + dark UI).
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint()..color = const ui.Color(0xffffffff),
      );
      canvas.scale(scale);
      canvas.translate(pad, pad);
      ScenePainter(scene)
          .paint(canvas, ui.Size(scene.size.width, scene.size.height));
      final image =
          await recorder.endRecording().toImage(w.ceil(), h.ceil());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      outDir.createSync(recursive: true);
      File('${outDir.path}/$id.png')
          .writeAsBytesSync(png!.buffer.asUint8List());
    });
  }
}

/// Generates the pub.dev screenshots for `mermaid_flutter` by painting a
/// curated set of shared samples through the real Flutter `ScenePainter`
/// (the same pipeline the package ships), on a white background at 2x.
///
/// By default this only renders and verifies the PNGs — it writes nothing, so
/// a plain `flutter test` never dirties the tracked screenshots.
///
/// To regenerate the tracked PNGs, run from `apps/demo` (macOS, real system
/// fonts required):
///
///   MERMAID_WRITE_SCREENSHOTS=1 fvm flutter test test/screenshots_test.dart
///
/// Output lands in `<workspace root>/packages/mermaid_flutter/doc/screenshots/`,
/// which the `screenshots:` field of mermaid_flutter/pubspec.yaml points at.
/// The path is resolved against the located workspace root, not against the
/// current directory, so the command works from any directory in the
/// workspace.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:mermaid_samples/mermaid_samples.dart';

import 'support/workspace.dart';

/// Set `MERMAID_WRITE_SCREENSHOTS=1` to overwrite the tracked PNGs.
const _writeEnvVar = 'MERMAID_WRITE_SCREENSHOTS';

/// The real UI font, so the written PNGs match the live app instead of
/// Flutter's Ahem test glyphs.
const _uiFontFamily = 'trebuchet ms';
const _uiFontPath = '/System/Library/Fonts/Supplemental/Trebuchet MS.ttf';

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

String _sourceFor(String id) => samples.firstWhere((s) => s.id == id).source;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final writing = Platform.environment[_writeEnvVar] == '1';

  setUpAll(() async {
    final font = File(_uiFontPath);
    if (!font.existsSync()) {
      // Only a run that overwrites the tracked PNGs depends on the real font;
      // a verification run is allowed to rasterize with test glyphs.
      if (writing) {
        throw StateError(
          'Cannot regenerate the pub.dev screenshots: the UI font '
          '"$_uiFontPath" is missing, so the PNGs would be rasterized with '
          'Flutter\'s Ahem test glyphs. Run this on macOS.',
        );
      }
      return;
    }
    final loader = FontLoader(_uiFontFamily)
      ..addFont(Future.value(ByteData.view(font.readAsBytesSync().buffer)));
    await loader.load();
  });

  final outDir = Directory(
    '${workspaceRoot().path}/packages/mermaid_flutter/doc/screenshots',
  );

  for (final id in _shots) {
    test('screenshot: $id', () async {
      final scene = core.Mermaid(
        measurer: const FlutterTextMeasurer(),
      ).render(_sourceFor(id));
      expect(scene.size.width, greaterThan(0));
      expect(scene.size.height, greaterThan(0));

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
      ScenePainter(
        scene,
      ).paint(canvas, ui.Size(scene.size.width, scene.size.height));
      final image = await recorder.endRecording().toImage(w.ceil(), h.ceil());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = png!.buffer.asUint8List();

      // Always exercise the pipeline end to end: the encoded bytes must be a
      // decodable PNG of the requested size.
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);
      addTearDown(codec.dispose);
      expect(frame.image.width, w.ceil());
      expect(frame.image.height, h.ceil());

      if (!writing) return;
      outDir.createSync(recursive: true);
      File('${outDir.path}/$id.png').writeAsBytesSync(bytes);
    });
  }
}

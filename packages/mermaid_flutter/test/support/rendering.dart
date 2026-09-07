import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Caller owns the returned image; the intermediate codec is always disposed.
Future<ui.Image> decodePng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Explicit evidence paths are retained. Default temporary output is removed
/// after the test. Both render suites use the same environment variable.
Directory evidenceDir() {
  const define = String.fromEnvironment('MERMAID_EVIDENCE_DIR');
  final path = define.isNotEmpty
      ? define
      : Platform.environment['MERMAID_EVIDENCE_DIR'];
  if (path != null && path.isNotEmpty) {
    return Directory(path)..createSync(recursive: true);
  }
  final directory = Directory.systemTemp.createTempSync('mermaid-evidence-');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

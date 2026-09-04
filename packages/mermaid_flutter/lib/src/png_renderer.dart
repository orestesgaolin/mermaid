/// Headless PNG rendering for Flutter runners.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mermaid_core/mermaid_core.dart' as core;

import 'flutter_text_measurer.dart';
import 'scene_painter.dart';

const double _maxPixelRatio = 8;
const int _maxImageDimension = 16384;
const int _maxPixelCount = 64 * 1024 * 1024;

/// Parses and renders Mermaid source to PNG bytes without mounting widgets.
///
/// Flowchart [nodePaintOverrides] and [linkPaintOverrides] use the same
/// paint-only restyling path as `MermaidDiagram` and do not change geometry.
///
/// This API requires a Flutter runner such as `flutter test` or
/// `flutter_tester`; it is not available in a pure Dart VM process.
Future<Uint8List> renderToPng(
  String source, {
  double pixelRatio = 2,
  core.MermaidTheme? theme,
  Map<String, core.FlowNodePaintOverride> nodePaintOverrides = const {},
  Map<int, core.FlowLinkPaintOverride> linkPaintOverrides = const {},
}) async {
  _validatePixelRatio(pixelRatio);
  final resolvedTheme = theme ?? core.MermaidTheme.defaultTheme;
  final baseScene = core.Mermaid(
    measurer: const FlutterTextMeasurer(),
    theme: resolvedTheme,
  ).render(source);
  final scene = core.applyFlowchartPaintOverrides(
    baseScene,
    nodes: nodePaintOverrides,
    links: linkPaintOverrides,
  );
  return _rasterize(scene, pixelRatio);
}

/// Renders an existing scene to PNG bytes without mounting widgets.
///
/// The output has the scene's logical size multiplied by [pixelRatio], rounded
/// up to complete pixels. Ratios above 8 and output dimensions above 16384
/// pixels, or images above 64 Mi pixels, are rejected before rasterization to
/// avoid common GPU texture and memory limits.
Future<Uint8List> renderSceneToPng(
  core.RenderScene scene, {
  double pixelRatio = 2,
}) async {
  _validatePixelRatio(pixelRatio);
  return _rasterize(scene, pixelRatio);
}

/// Rasterizes [scene] with an already validated [pixelRatio].
Future<Uint8List> _rasterize(core.RenderScene scene, double pixelRatio) async {
  if (!scene.size.width.isFinite ||
      !scene.size.height.isFinite ||
      scene.size.width <= 0 ||
      scene.size.height <= 0) {
    throw ArgumentError.value(
      scene.size,
      'scene.size',
      'Width and height must be finite and greater than zero.',
    );
  }

  final scaledWidth = scene.size.width * pixelRatio;
  final scaledHeight = scene.size.height * pixelRatio;
  if (!scaledWidth.isFinite || !scaledHeight.isFinite) {
    throw ArgumentError(
      'PNG output dimensions cannot be represented for scene size '
      '${scene.size.width}x${scene.size.height} at pixelRatio $pixelRatio. '
      'Reduce pixelRatio or scene size.',
    );
  }
  final width = scaledWidth.ceil();
  final height = scaledHeight.ceil();
  if (width > _maxImageDimension || height > _maxImageDimension) {
    throw ArgumentError(
      'PNG output would be ${width}x$height pixels; each dimension must be '
      'no greater than $_maxImageDimension. Reduce pixelRatio or scene size.',
    );
  }
  final pixelCount = width * height;
  if (pixelCount > _maxPixelCount) {
    throw ArgumentError(
      'PNG output would contain $pixelCount pixels; the maximum is '
      '$_maxPixelCount. Reduce pixelRatio or scene size.',
    );
  }

  final recorder = ui.PictureRecorder();
  ui.Picture? picture;
  ui.Image? image;
  try {
    final canvas = ui.Canvas(recorder)..scale(pixelRatio);
    ScenePainter(
      scene,
    ).paint(canvas, ui.Size(scene.size.width, scene.size.height));
    picture = recorder.endRecording();
    image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError(
        'Flutter encoded no PNG data for a ${width}x$height image.',
      );
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
  }
}

void _validatePixelRatio(double pixelRatio) {
  if (!pixelRatio.isFinite || pixelRatio <= 0 || pixelRatio > _maxPixelRatio) {
    throw RangeError.value(
      pixelRatio,
      'pixelRatio',
      'Must be finite, greater than zero, and no greater than '
          '$_maxPixelRatio.',
    );
  }
}

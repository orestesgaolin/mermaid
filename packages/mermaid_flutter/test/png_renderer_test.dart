import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'renders source to a scaled non-empty PNG without pumping widgets',
    () async {
      const source = 'flowchart LR\n  A[Start] --> B[Finish]';
      const pixelRatio = 2.0;
      final scene = core.Mermaid(
        measurer: const FlutterTextMeasurer(),
      ).render(source);

      final png = await renderToPng(source, pixelRatio: pixelRatio);
      expect(png.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);

      final image = await _decodePng(png);
      addTearDown(image.dispose);
      expect(image.width, (scene.size.width * pixelRatio).ceil());
      expect(image.height, (scene.size.height * pixelRatio).ceil());
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(rgba, isNotNull);
      final bytes = rgba!.buffer.asUint8List(
        rgba.offsetInBytes,
        rgba.lengthInBytes,
      );
      expect(
        _hasMoreThanOneVisibleColor(bytes),
        isTrue,
        reason: 'the PNG contains rendered diagram content, not one flat color',
      );
    },
  );

  test('validates ratio, dimensions, and preserves parse errors', () async {
    const scene = core.RenderScene(size: core.Size(100, 50), nodes: []);
    for (final ratio in [0.0, -1.0, 8.01, double.nan, double.infinity]) {
      await expectLater(
        renderSceneToPng(scene, pixelRatio: ratio),
        throwsA(isA<RangeError>()),
      );
    }
    await expectLater(
      renderToPng('not valid mermaid', pixelRatio: 0),
      throwsA(isA<RangeError>()),
    );
    await expectLater(
      renderSceneToPng(
        const core.RenderScene(size: core.Size(3000, 10), nodes: []),
        pixelRatio: 8,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('24000x80'),
        ),
      ),
    );
    await expectLater(
      renderToPng('graph TD\nthis is not valid mermaid'),
      throwsA(isA<core.MermaidParseException>()),
    );
    await expectLater(
      renderSceneToPng(
        const core.RenderScene(size: core.Size(9000, 9000), nodes: []),
        pixelRatio: 1,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('81000000 pixels'),
        ),
      ),
    );
    await expectLater(
      renderSceneToPng(
        const core.RenderScene(size: core.Size(double.maxFinite, 1), nodes: []),
        pixelRatio: 8,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('cannot be represented'),
        ),
      ),
    );
  });

  testWidgets('headless bytes match the on-screen MermaidDiagram output', (
    tester,
  ) async {
    const source = 'flowchart TD\n  A[Start] -->|next| B{Ready?}';
    const theme = core.MermaidTheme.darkTheme;
    const pixelRatio = 1.0;
    const nodeOverrides = {
      'B': core.FlowNodePaintOverride(
        fill: core.Color(0xFF123456),
        stroke: core.Color(0xFFABCDEF),
        strokeWidth: 4,
      ),
    };
    const linkOverrides = {
      0: core.FlowLinkPaintOverride(
        stroke: core.Color(0xFFFF8800),
        strokeWidth: 5,
      ),
    };
    final headlessImage = (await tester.runAsync(
      () async => _decodePng(
        await renderToPng(
          source,
          pixelRatio: pixelRatio,
          theme: theme,
          nodePaintOverrides: nodeOverrides,
          linkPaintOverrides: linkOverrides,
        ),
      ),
    ))!;
    addTearDown(headlessImage.dispose);
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundaryKey,
            child: const MermaidDiagram(
              source: source,
              theme: theme,
              nodePaintOverrides: nodeOverrides,
              linkPaintOverrides: linkOverrides,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byKey(boundaryKey),
      matchesReferenceImage(headlessImage),
    );
  });
}

Future<ui.Image> _decodePng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

bool _hasMoreThanOneVisibleColor(Uint8List rgba) {
  int? first;
  for (var offset = 0; offset < rgba.length; offset += 4) {
    if (rgba[offset + 3] == 0) continue;
    final color = rgba[offset] << 16 | rgba[offset + 1] << 8 | rgba[offset + 2];
    first ??= color;
    if (color != first) return true;
  }
  return false;
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

/// A small hand-built scene exercising every node kind the painter supports:
/// a rounded rect with text, a polygon, and a dashed cubic path.
core.RenderScene buildTestScene() {
  return const core.RenderScene(
    size: core.Size(240, 200),
    background: core.Color(0xffffffff),
    nodes: [
      core.SceneGroup(
        id: 'node-a',
        semanticLabel: 'Node A',
        children: [
          core.SceneShape(
            geometry: core.RectGeometry(
              core.Rect.fromLTWH(20, 20, 120, 44),
              rx: 6,
              ry: 6,
            ),
            fill: core.Fill(core.Color(0xffececff)),
            stroke: core.Stroke(color: core.Color(0xff9370db)),
          ),
          core.SceneText(
            text: 'Hello',
            bounds: core.Rect.fromLTWH(28, 32, 104, 20),
            style: core.TextStyleSpec(
              fontFamily: '"trebuchet ms", verdana, arial, sans-serif',
              fontSize: 16,
            ),
            color: core.Color(0xff333333),
          ),
        ],
      ),
      core.SceneShape(
        geometry: core.PolygonGeometry([
          core.Point(80, 100),
          core.Point(140, 130),
          core.Point(80, 160),
          core.Point(20, 130),
        ]),
        fill: core.Fill(core.Color(0xffffffde)),
        stroke: core.Stroke(color: core.Color(0xffaaaa33), width: 2),
      ),
      core.SceneShape(
        geometry: core.PathGeometry([
          core.MoveTo(core.Point(150, 40)),
          core.CubicTo(
            core.Point(190, 40),
            core.Point(190, 130),
            core.Point(150, 130),
          ),
          core.QuadTo(core.Point(170, 160), core.Point(220, 160)),
          core.LineTo(core.Point(220, 180)),
        ]),
        stroke: core.Stroke(
          color: core.Color(0xff333333),
          width: 1.5,
          dash: [4, 4],
        ),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScenePainter', () {
    testWidgets('paints a hand-built scene without throwing', (tester) async {
      final scene = buildTestScene();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: scene.size.width,
              height: scene.size.height,
              child: CustomPaint(painter: ScenePainter(scene)),
            ),
          ),
        ),
      );

      // Painting happened during the pumped frame; no exception means every
      // geometry/text node was translated successfully.
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);

      // The frame completed and nothing left the pipeline dirty.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('repaints only when the scene identity changes', (
      tester,
    ) async {
      final scene = buildTestScene();
      final samePainter = ScenePainter(scene);
      expect(samePainter.shouldRepaint(ScenePainter(scene)), isFalse);

      // Non-const construction yields a distinct identity.
      final otherScene = core.RenderScene(
        size: const core.Size(10, 10),
        nodes: const [],
      );
      expect(ScenePainter(otherScene).shouldRepaint(samePainter), isTrue);
    });

    test(
      'multiply compositing keeps overlapping lanes distinguishable',
      () async {
        core.RenderScene scene(core.SceneBlendMode mode) => core.RenderScene(
          size: const core.Size(20, 20),
          background: const core.Color(0xffffffff),
          nodes: [
            core.SceneShape(
              geometry: const core.PathGeometry([
                core.MoveTo(core.Point(0, 10)),
                core.LineTo(core.Point(20, 10)),
              ]),
              stroke: const core.Stroke(
                color: core.Color(0x80ff0000),
                width: 8,
                gradient: core.SceneGradient(
                  core.Point(0, 10),
                  core.Point(20, 10),
                  [core.Color(0x80ff0000), core.Color(0x80ffff00)],
                ),
              ),
              blendMode: mode,
            ),
            core.SceneShape(
              geometry: const core.PathGeometry([
                core.MoveTo(core.Point(10, 0)),
                core.LineTo(core.Point(10, 20)),
              ]),
              stroke: const core.Stroke(
                color: core.Color(0x800000ff),
                width: 8,
                gradient: core.SceneGradient(
                  core.Point(10, 0),
                  core.Point(10, 20),
                  [core.Color(0x800000ff), core.Color(0x8000ffff)],
                ),
              ),
              blendMode: mode,
            ),
          ],
        );

        final normal = await _pixelAt(
          scene(core.SceneBlendMode.normal),
          10,
          10,
        );
        final multiply = await _pixelAt(
          scene(core.SceneBlendMode.multiply),
          10,
          10,
        );

        expect(multiply, isNot(normal));
        expect(
          multiply.computeLuminance(),
          lessThan(normal.computeLuminance()),
          reason: 'multiply must darken the crossing instead of covering it',
        );
      },
    );
  });

  group('FlutterTextMeasurer', () {
    const measurer = FlutterTextMeasurer();
    const style = core.TextStyleSpec(
      fontFamily: '"trebuchet ms", verdana, arial, sans-serif',
      fontSize: 16,
    );

    test('longer text measures wider', () {
      final hello = measurer.measure('Hello', style);
      final hi = measurer.measure('Hi', style);
      expect(hello.width, greaterThan(hi.width));
      expect(hello.height, equals(hi.height));
    });

    test('explicit newlines increase height', () {
      final single = measurer.measure('line one', style);
      final multi = measurer.measure('line one\nline two', style);
      expect(multi.height, greaterThan(single.height));
    });

    test('maxWidth soft-wraps long text', () {
      const text = 'several words that will definitely wrap';
      final unconstrained = measurer.measure(text, style);
      final wrapped = measurer.measure(text, style, maxWidth: 80);
      expect(wrapped.width, lessThanOrEqualTo(80));
      expect(wrapped.height, greaterThan(unconstrained.height));
    });

    test('measured flowchart labels keep their height when painted', () {
      for (final text in [
        'cb1 pop → remove Tela B',
        'cb2 pop → remove dialog de opcoes',
        'sobra o dialog de opcoes\nTela B nunca aparece',
      ]) {
        final measured = measurer.measure(text, style, maxWidth: 200);
        final painter = TextPainter(
          text: TextSpan(text: text, style: textStyleFromSpec(style)),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(minWidth: measured.width + 1, maxWidth: measured.width + 1);
        expect(
          painter.height,
          lessThanOrEqualTo(measured.height),
          reason: text,
        );
        painter.dispose();
      }
    });

    test('flowchart boxes contain labels after resolved wrapping', () {
      const source = '''flowchart TB
  subgraph COM["COM await — funciona por acidente"]
    direction TB
    C1["cb1 pop → remove loading"] --> C2["cb2 pop → remove dialog de opcoes"]
  end''';
      final scene = core.Mermaid(measurer: measurer).render(source);

      core.SceneGroup group(String id, List<core.SceneNode> nodes) {
        for (final node in nodes) {
          if (node case core.SceneGroup(:final children)) {
            if (node.id == id) return node;
            try {
              return group(id, children);
            } on StateError {
              // Continue searching sibling groups.
            }
          }
        }
        throw StateError('No scene group $id');
      }

      for (final id in ['C1', 'C2']) {
        final node = group(id, scene.nodes);
        final rect =
            (node.children.whereType<core.SceneShape>().first.geometry
                    as core.RectGeometry)
                .rect;
        final text = node.children.whereType<core.SceneText>().single.bounds;
        final label = node.children.whereType<core.SceneText>().single;
        final measured = measurer.measure(label.text, style);
        expect(
          text.width,
          greaterThanOrEqualTo(measured.width),
          reason: '$id should contain its resolved label lines',
        );
        expect(
          rect.contains(core.Point(text.left, text.top)),
          isTrue,
          reason: '$id label top-left',
        );
        expect(
          rect.contains(core.Point(text.right, text.bottom)),
          isTrue,
          reason: '$id label bottom-right',
        );
      }
    });

    testWidgets('flowchart identifier breaks are explicit before painting', (
      tester,
    ) async {
      const source = '''flowchart TD
  br_recommendation_summary["br_recommendation_summary"]''';
      final scene = core.Mermaid(measurer: measurer).render(source);
      final node = scene.nodes.whereType<core.SceneGroup>().singleWhere(
        (group) => group.id == 'br_recommendation_summary',
      );
      final label = node.children.whereType<core.SceneText>().single;

      final lines = label.text.split('\n');
      expect(lines.length, greaterThan(1));
      expect(lines.join(), 'br_recommendation_summary');
      expect(lines, everyElement(isNotEmpty));
      expect(lines.last.length, greaterThan(1));
      expect(lines.any((line) => line.endsWith('_')), isTrue);
      expect(node.semanticLabel, 'br_recommendation_summary');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CustomPaint(
            painter: ScenePainter(scene),
            size: Size(scene.size.width, scene.size.height),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('font family parsing', () {
    test('strips quotes, keeps order, drops generic keywords', () {
      final parsed = parseCssFontFamily(
        '"trebuchet ms", verdana, arial, sans-serif',
      );
      expect(parsed.family, 'trebuchet ms');
      expect(parsed.fallback, ['verdana', 'arial']);
    });

    test('only a generic keyword yields no family', () {
      final parsed = parseCssFontFamily('sans-serif');
      expect(parsed.family, isNull);
      expect(parsed.fallback, isEmpty);
    });

    test('retains monospace for platform font resolution', () {
      final parsed = parseCssFontFamily('monospace');
      expect(parsed.family, 'monospace');
      expect(parsed.fallback, isEmpty);
    });

    test('symbol fallbacks follow the source families without repeating', () {
      final symbols = textStyleFromSpec(
        const core.TextStyleSpec(fontFamily: 'trebuchet ms', fontSize: 16),
      ).fontFamilyFallback!;
      expect(symbols, isNotEmpty, reason: 'symbol families are appended');

      final withCss = textStyleFromSpec(
        core.TextStyleSpec(
          fontFamily: '"trebuchet ms", verdana, "${symbols.first}"',
          fontSize: 16,
        ),
      ).fontFamilyFallback!;
      expect(
        withCss.take(1),
        ['verdana'],
        reason: 'the source list keeps priority over platform symbol fonts',
      );
      expect(withCss, containsAll(symbols));
      expect(
        withCss.toSet(),
        hasLength(withCss.length),
        reason: 'a family named by the source is not appended twice',
      );
    });
  });
}

Future<ui.Color> _pixelAt(core.RenderScene scene, int x, int y) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  ScenePainter(
    scene,
  ).paint(canvas, ui.Size(scene.size.width, scene.size.height));
  final image = await recorder.endRecording().toImage(
    scene.size.width.ceil(),
    scene.size.height.ceil(),
  );
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (y * image.width + x) * 4;
    return ui.Color.fromARGB(
      rgba!.getUint8(offset + 3),
      rgba.getUint8(offset),
      rgba.getUint8(offset + 1),
      rgba.getUint8(offset + 2),
    );
  } finally {
    image.dispose();
  }
}

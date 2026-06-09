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

    testWidgets('repaints only when the scene identity changes',
        (tester) async {
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
  });

  group('font family parsing', () {
    test('strips quotes, keeps order, drops generic keywords', () {
      final parsed =
          parseCssFontFamily('"trebuchet ms", verdana, arial, sans-serif');
      expect(parsed.family, 'trebuchet ms');
      expect(parsed.fallback, ['verdana', 'arial']);
    });

    test('only a generic keyword yields no family', () {
      final parsed = parseCssFontFamily('sans-serif');
      expect(parsed.family, isNull);
      expect(parsed.fallback, isEmpty);
    });
  });
}

import 'package:elk/elk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website/elk_demos.dart';
import 'package:website/elk_stress_examples.dart';

void main() {
  for (final example in elkStressExamples) {
    test('demo layout: ${example.title}', () {
      final result = const ElkLayered().layout(example.graph);
      expect(result.width.isFinite && result.height.isFinite, isTrue);
      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
      final expectedEdges = <String>{};
      void collect(List<ElkNode> nodes, List<ElkEdge> edges) {
        expectedEdges.addAll(edges.map((e) => e.id));
        for (final node in nodes) {
          collect(node.children, node.edges);
        }
      }

      collect(example.graph.children, example.graph.edges);
      expect(result.edges.map((e) => e.id).toSet(), expectedEdges);
      for (final edge in result.edges) {
        expect(edge.sections, isNotEmpty, reason: edge.id);
        for (final section in edge.sections) {
          final points = section.points;
          for (final point in points) {
            expect(point.x, inInclusiveRange(-0.001, result.width + 0.001));
            expect(point.y, inInclusiveRange(-0.001, result.height + 0.001));
          }
          for (var i = 1; i < points.length; i++) {
            expect(
              (points[i].x - points[i - 1].x).abs() < 0.001 ||
                  (points[i].y - points[i - 1].y).abs() < 0.001,
              isTrue,
              reason: '${edge.id} segment $i',
            );
          }
        }
      }
    });
  }

  test('gallery renders every example with local SVG marker references', () {
    final demos = buildElkDemos();
    final ids = <String>{};
    for (final demo in demos) {
      final markers = RegExp(
        r'<marker id="([^"]+)"',
      ).allMatches(demo.svg).map((m) => m.group(1)!).toSet();
      for (final marker in markers) {
        expect(
          ids.add(marker),
          isTrue,
          reason: 'Markers must not resolve to a different diagram',
        );
      }
      for (final ref in RegExp(
        r'marker-end="url\(#([^)]+)\)"',
      ).allMatches(demo.svg)) {
        expect(markers, contains(ref.group(1)));
      }
      expect(demo.svg, isNot(contains('NaN')));
      expect(demo.svg, isNot(contains('Infinity')));
    }
  });
}

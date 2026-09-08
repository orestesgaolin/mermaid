import 'package:elk/elk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website/elk_demos.dart';
import 'package:website/elk_reference.dart';
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

  test('gallery preserves all route sections at a shared coordinate scale', () {
    final demos = buildElkDemos();
    final examples = buildElkExamples();
    final markerIds = <String>{};
    for (final demo in demos) {
      expect(demo.referenceError, isNull, reason: demo.title);
      expect(demo.referenceSvg, isNotNull, reason: demo.title);
      final viewBox = RegExp(r'viewBox="([^"]+)"');
      expect(
        viewBox.firstMatch(demo.svg)!.group(1),
        viewBox.firstMatch(demo.referenceSvg!)!.group(1),
        reason: 'Both layouts must retain the same coordinate scale',
      );
      final reference = elkReferenceFor(
        examples.singleWhere((e) => e.title == demo.title),
      );
      final dart = const ElkLayered().layout(
        ElkGraph.fromJson(reference.input),
      );
      for (final pair in [
        (demo.svg, dart),
        (demo.referenceSvg!, reference.result!),
      ]) {
        final (svg, result) = pair;
        expect(
          RegExp('<polyline ').allMatches(svg).length,
          result.edges.fold<int>(
            0,
            (count, edge) => count + edge.sections.length,
          ),
          reason: 'No compound or branching route sections may be dropped',
        );
        final marker = RegExp(
          r'<marker id="([^"]+)"',
        ).firstMatch(svg)!.group(1)!;
        expect(
          markerIds.add(marker),
          isTrue,
          reason: 'Each comparison panel must resolve its own marker',
        );
        final markedEdges = <String, int>{};
        for (final path in RegExp(r'<polyline [^>]+>').allMatches(svg)) {
          final tag = path.group(0)!;
          if (!tag.contains('marker-end=')) continue;
          expect(tag, contains('marker-end="url(#$marker)"'));
          final id = RegExp(
            r'data-edge-id="([^"]+)"',
          ).firstMatch(tag)!.group(1)!;
          markedEdges.update(id, (count) => count + 1, ifAbsent: () => 1);
        }
        for (final edge in result.edges) {
          expect(
            markedEdges[edge.id],
            1,
            reason:
                '${demo.title}: ${edge.id} must mark its target once, '
                'including split hierarchy routes and self loops',
          );
        }
        expect(svg, isNot(contains('NaN')));
        expect(svg, isNot(contains('Infinity')));
      }
    }
  });
}

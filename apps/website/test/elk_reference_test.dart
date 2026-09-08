import 'package:elk/elk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website/elk_demos.dart';
import 'package:website/elk_reference.dart';
import 'package:website/generated/elk_reference_data.g.dart';

void main() {
  test('all examples have fresh successful elkjs 0.9.3 references', () {
    final examples = buildElkExamples();
    expect(examples, hasLength(9));
    for (final example in examples) {
      final reference = elkReferenceFor(example);
      expect(reference.elkjsVersion, '0.9.3', reason: example.title);
      expect(reference.error, isNull, reason: example.title);
      expect(reference.result, isNotNull, reason: example.title);
      // elkReferenceFor performs the structural freshness check. Node's JSON
      // writer may normalize integral doubles (110.0) to integers (110).

      // Dart is deliberately run from the same materialized JSON passed to
      // elkjs, rather than from the source object used by the catalog.
      final dartResult = const ElkLayered().layout(
        ElkGraph.fromJson(reference.input),
      );
      _expectFinite(dartResult, '${example.title} Dart');
      _expectOrthogonal(dartResult, '${example.title} Dart');
      final decodedInput = ElkGraph.fromJson(reference.input);
      expect(
        decodedInput.layoutOptions.fixedAlignment,
        example.graph.layoutOptions.fixedAlignment,
      );
      expect(
        decodedInput.layoutOptions.direction,
        example.graph.layoutOptions.direction,
      );
      expect(
        decodedInput.layoutOptions.cycleBreaking,
        example.graph.layoutOptions.cycleBreaking,
      );
      expect(
        decodedInput.layoutOptions.mergeEdges,
        example.graph.layoutOptions.mergeEdges,
      );
      expect(
        decodedInput.layoutOptions.resolvedNodeNode,
        example.graph.layoutOptions.resolvedNodeNode,
      );
      final dartEdges = dartResult.edges.map((edge) => edge.id).toSet();
      expect(
        reference.result!.edges.map((edge) => edge.id).toSet(),
        dartEdges,
        reason: 'Both engines must retain the same input edges',
      );
      _expectFinite(reference.result!, '${example.title} elkjs');
      _expectOrthogonal(reference.result!, example.title);
    }
  });

  test(
    'serializer materializes fair routing, hierarchy, and spacing inputs',
    () {
      final input = elkGraphToJson(buildElkExamples().first.graph);
      final options = (input['layoutOptions'] as Map).cast<String, dynamic>();
      expect(options['elk.edgeRouting'], 'ORTHOGONAL');
      expect(options['elk.randomSeed'], 1);
      expect(options['elk.hierarchyHandling'], 'INCLUDE_CHILDREN');
      expect(options['elk.spacing.nodeNode'], 40);
      expect(options['elk.spacing.edgeNode'], 20);
      expect(options['elk.layered.spacing.nodeNodeBetweenLayers'], 40);
      expect(options['elk.layered.spacing.edgeNodeBetweenLayers'], 20);
      expect(options['elk.layered.spacing.edgeEdgeBetweenLayers'], 10);
    },
  );

  test('decoder retains every section and applies nested edge containers', () {
    final example = buildElkExamples().singleWhere(
      (item) => item.title == 'Nested services in three directions',
    );
    final raw = (elkReferenceData[example.title] as Map)
        .cast<String, dynamic>();
    final output = (raw['output'] as Map).cast<String, dynamic>();
    final reference = elkReferenceFor(example).result!;

    var rawSections = 0;
    Map<String, dynamic>? nestedEdge;
    double expectedX = 0;
    double expectedY = 0;
    void walk(Map<String, dynamic> node, double dx, double dy) {
      for (final edge
          in node['edges'] is List ? node['edges'] as List : const []) {
        final value = (edge as Map).cast<String, dynamic>();
        rawSections += (value['sections'] as List?)?.length ?? 0;
        if ((dx != 0 || dy != 0) && nestedEdge == null) {
          nestedEdge = value;
          expectedX = dx;
          expectedY = dy;
        }
      }
      for (final child
          in node['children'] is List ? node['children'] as List : const []) {
        final value = (child as Map).cast<String, dynamic>();
        walk(value, dx + _num(value['x']), dy + _num(value['y']));
      }
    }

    walk(output, 0, 0);
    expect(
      reference.edges.expand((edge) => edge.sections),
      hasLength(rawSections),
    );
    expect(nestedEdge, isNotNull);
    final rawSection = (nestedEdge!['sections'] as List).first as Map;
    final rawStart = rawSection['startPoint'] as Map;
    final decoded = reference.edges
        .singleWhere((edge) => edge.id == nestedEdge!['id'])
        .sections
        .first
        .startPoint;
    expect(decoded.x, closeTo(_num(rawStart['x']) + expectedX, 0.001));
    expect(decoded.y, closeTo(_num(rawStart['y']) + expectedY, 0.001));
  });
}

void _expectFinite(ElkResult result, String name) {
  expect(result.width.isFinite && result.height.isFinite, isTrue, reason: name);
  for (final node in result.nodesById.values) {
    expect(
      [
        node.x,
        node.y,
        node.width,
        node.height,
      ].every((value) => value.isFinite),
      isTrue,
      reason: '$name ${node.id}',
    );
  }
  for (final edge in result.edges) {
    for (final point in edge.sections.expand((section) => section.points)) {
      expect(
        point.x.isFinite && point.y.isFinite,
        isTrue,
        reason: '$name ${edge.id}',
      );
    }
  }
}

void _expectOrthogonal(ElkResult result, String name) {
  for (final edge in result.edges) {
    for (final section in edge.sections) {
      final points = section.points;
      for (var index = 1; index < points.length; index++) {
        final a = points[index - 1];
        final b = points[index];
        expect(
          (a.x - b.x).abs() < 0.001 || (a.y - b.y).abs() < 0.001,
          isTrue,
          reason: '$name ${edge.id}: $a -> $b',
        );
      }
    }
  }
}

double _num(Object? value) => (value as num).toDouble();

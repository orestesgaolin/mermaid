import 'dart:convert';
import 'dart:io';

import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  test('unrouted cross-boundary labels have no fabricated position', () {
    ElkGraph graph(ElkHierarchyHandling mode) => ElkGraph(
      layoutOptions: ElkLayoutOptions(hierarchyHandling: mode),
      children: const [
        ElkNode(
          id: 'group',
          children: [ElkNode(id: 'inside', width: 80, height: 40)],
        ),
        ElkNode(id: 'outside', width: 80, height: 40),
      ],
      edges: const [
        ElkEdge(
          id: 'cross',
          sources: ['inside'],
          targets: ['outside'],
          labels: [ElkLabel(text: 'handoff', width: 50, height: 12)],
        ),
      ],
    );
    final included = const ElkLayered().layout(
      graph(ElkHierarchyHandling.includeChildren),
    );
    expect(included.edges.single.sections, isNotEmpty);
    expect(included.edges.single.labels.single.text, 'handoff');
    final separated = const ElkLayered().layout(
      graph(ElkHierarchyHandling.separateChildren),
    );
    expect(separated.edges.single.id, 'cross');
    expect(separated.edges.single.sections, isEmpty);
    expect(
      separated.edges.single.labels,
      isEmpty,
      reason: 'An unrouted label must not become drawable geometry at (0,0)',
    );
  });
  final fixture = [
    File('test/fixtures/hierarchy_handling_elkjs.json'),
    File('packages/elk/test/fixtures/hierarchy_handling_elkjs.json'),
  ].firstWhere((file) => file.existsSync());
  final data = jsonDecode(fixture.readAsStringSync()) as Map;
  for (final entry in data['cases'] as List) {
    // Upstream throws for a nested separated scope under INCLUDE_CHILDREN.
    // The public integration suite covers Dart's documented empty-section
    // result for this case; there is no upstream layout to compare here.
    if (entry['error'] != null) continue;
    test('elkjs ${data['elkjsVersion']} routing scope: ${entry['name']}', () {
      final input = Map<String, dynamic>.from(entry['input'] as Map);
      final result = const ElkLayered().layout(ElkGraph.fromJson(input));
      final expectedRoutes = <String, bool>{};
      void collect(Map node) {
        for (final edge in node['edges'] as List? ?? const []) {
          expectedRoutes[edge['id'] as String] =
              (edge['sections'] as List? ?? const []).isNotEmpty;
        }
        for (final child in node['children'] as List? ?? const []) {
          collect(child as Map);
        }
      }

      collect(entry['output'] as Map);
      final actual = {for (final edge in result.edges) edge.id: edge};
      for (final item in expectedRoutes.entries) {
        expect(
          actual,
          contains(item.key),
          reason: 'Retain input edge identity',
        );
        expect(
          actual[item.key]!.sections.isNotEmpty,
          item.value,
          reason: '${item.key} must respect the same hierarchy boundary',
        );
      }
      for (final edge in result.edges) {
        for (final section in edge.sections) {
          final points = section.points;
          for (var i = 1; i < points.length; i++) {
            expect(
              (points[i].x - points[i - 1].x).abs() < 0.001 ||
                  (points[i].y - points[i - 1].y).abs() < 0.001,
              isTrue,
              reason: '${edge.id} must remain orthogonal',
            );
          }
        }
      }
    });
  }
}

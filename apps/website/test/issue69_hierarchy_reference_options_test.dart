import 'package:elk/elk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website/elk_reference.dart';

void main() {
  test('hierarchy-only nested options inherit the parent direction', () {
    const graph = ElkGraph(
      layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
      children: [
        ElkNode(
          id: 'group',
          layoutOptions: ElkLayoutOptions(
            hierarchyHandling: ElkHierarchyHandling.inherit,
          ),
          children: [
            ElkNode(id: 'a', width: 50, height: 30),
            ElkNode(id: 'b', width: 50, height: 30),
          ],
          edges: [
            ElkEdge(id: 'ab', sources: ['a'], targets: ['b']),
          ],
        ),
      ],
    );

    final json = elkGraphToJson(graph);
    final group = ((json['children'] as List).single as Map)
        .cast<String, dynamic>();
    final nestedOptions = (group['layoutOptions'] as Map)
        .cast<String, dynamic>();
    expect(nestedOptions['elk.hierarchyHandling'], 'INHERIT');
    expect(nestedOptions, isNot(contains('elk.direction')));

    final decoded = ElkGraph.fromJson(json);
    expect(
      decoded.children.single.layoutOptions!.hierarchyHandlingOverride,
      ElkHierarchyHandling.inherit,
    );
    expect(decoded.children.single.layoutOptions!.directionOverride, isNull);

    final result = const ElkLayered().layout(decoded);
    expect(result.nodesById['b']!.x, greaterThan(result.nodesById['a']!.x));
    expect(result.edges.single.sections, hasLength(1));
  });
}

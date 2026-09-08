import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  test('mergeEdges shares implicit fan-out and fan-in ports', () {
    final unmerged = _layout(false);
    final merged = _layout(true);

    expect(_fanOutStarts(unmerged).toSet(), hasLength(3));
    expect(_fanInEnds(unmerged).toSet(), hasLength(3));
    expect(_fanOutStarts(merged).toSet(), hasLength(1));
    expect(_fanInEnds(merged).toSet(), hasLength(1));
    expect(
      merged.edges.expand((edge) => edge.junctionPoints),
      isNotEmpty,
      reason: 'shared orthogonal trunks expose their branch junctions',
    );
  });

  test('mergeEdges preserves separate declared ports', () {
    final result = const ElkLayered().layout(
      ElkGraph(
        layoutOptions: ElkLayoutOptions(
          direction: ElkDirection.right,
          mergeEdges: true,
        ),
        children: [
          ElkNode(
            id: 's',
            width: 60,
            height: 36,
            ports: [
              ElkPort(id: 'upper', side: ElkPortSide.east),
              ElkPort(id: 'lower', side: ElkPortSide.east),
            ],
          ),
          ElkNode(id: 'a', width: 60, height: 36),
          ElkNode(id: 'b', width: 60, height: 36),
        ],
        edges: [
          ElkEdge(id: 'upper-a', sources: ['upper'], targets: ['a']),
          ElkEdge(id: 'lower-b', sources: ['lower'], targets: ['b']),
        ],
      ),
    );

    final starts = result.edges
        .map(
          (edge) => (
            edge.sections.single.startPoint.x,
            edge.sections.single.startPoint.y,
          ),
        )
        .toSet();
    expect(starts, hasLength(2));
  });
}

ElkResult _layout(bool mergeEdges) => const ElkLayered().layout(
  ElkGraph(
    layoutOptions: ElkLayoutOptions(
      direction: ElkDirection.right,
      mergeEdges: mergeEdges,
    ),
    children: [
      ElkNode(id: 's', width: 60, height: 36),
      ElkNode(id: 'a', width: 60, height: 36),
      ElkNode(id: 'b', width: 60, height: 36),
      ElkNode(id: 'c', width: 60, height: 36),
      ElkNode(id: 'm1', width: 60, height: 36),
      ElkNode(id: 'm2', width: 60, height: 36),
      ElkNode(id: 'm3', width: 60, height: 36),
      ElkNode(id: 't', width: 60, height: 36),
    ],
    edges: [
      ElkEdge(id: 's-a', sources: ['s'], targets: ['a']),
      ElkEdge(id: 's-b', sources: ['s'], targets: ['b']),
      ElkEdge(id: 's-c', sources: ['s'], targets: ['c']),
      ElkEdge(id: 'm1-t', sources: ['m1'], targets: ['t']),
      ElkEdge(id: 'm2-t', sources: ['m2'], targets: ['t']),
      ElkEdge(id: 'm3-t', sources: ['m3'], targets: ['t']),
    ],
  ),
);

List<(double, double)> _fanOutStarts(ElkResult result) => [
  for (final edge in result.edges.take(3))
    (edge.sections.single.startPoint.x, edge.sections.single.startPoint.y),
];

List<(double, double)> _fanInEnds(ElkResult result) => [
  for (final edge in result.edges.skip(3))
    (edge.sections.single.endPoint.x, edge.sections.single.endPoint.y),
];

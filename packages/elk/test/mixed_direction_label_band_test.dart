import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  for (final root in ElkDirection.values) {
    for (final platform in [ElkDirection.down, ElkDirection.up]) {
      for (final workers in [ElkDirection.left, ElkDirection.right]) {
        test('$root/$platform/$workers title bands keep routes orthogonal', () {
          _expectOrthogonal(
            const ElkLayered().layout(_fixture(root, platform, workers)),
          );
        });
      }
    }
  }
}

void _expectOrthogonal(ElkResult result) {
  final nodes = result.nodesById;
  final endpoints = <String, (String, String)>{
    'handoff': ('workerA', 'workerB'),
    'dispatch': ('workers', 'cache'),
    'complete': ('workerB', 'response'),
  };
  for (final edge in result.edges) {
    final points = edge.sections.single.points;
    for (var i = 1; i < points.length; i++) {
      expect(
        points[i - 1].x == points[i].x || points[i - 1].y == points[i].y,
        isTrue,
        reason: '${edge.id} segment $i: ${points[i - 1]} -> ${points[i]}',
      );
    }
    final endpoint = endpoints[edge.id]!;
    expect(_onBorder(points.first, nodes[endpoint.$1]!), isTrue);
    expect(_onBorder(points.last, nodes[endpoint.$2]!), isTrue);
  }
  expect(
    result.edges
        .singleWhere((edge) => edge.id == 'complete')
        .labels
        .map((label) => label.text),
    unorderedEquals(['result', '200']),
  );
}

ElkGraph _fixture(
  ElkDirection root,
  ElkDirection platform,
  ElkDirection workers,
) => ElkGraph(
  layoutOptions: ElkLayoutOptions(direction: root),
  children: [
    ElkNode(
      id: 'platform',
      layoutOptions: ElkLayoutOptions(direction: platform),
      labels: [ElkLabel(text: 'Service platform', width: 44, height: 14)],
      children: [
        ElkNode(
          id: 'workers',
          layoutOptions: ElkLayoutOptions(direction: workers),
          labels: [ElkLabel(text: 'Worker pool', width: 40, height: 12)],
          children: [
            ElkNode(id: 'workerA', width: 40, height: 20),
            ElkNode(id: 'workerB', width: 40, height: 20),
          ],
          edges: [
            ElkEdge(id: 'handoff', sources: ['workerA'], targets: ['workerB']),
          ],
        ),
        ElkNode(id: 'cache', width: 52, height: 22),
      ],
      edges: [
        ElkEdge(id: 'dispatch', sources: ['workers'], targets: ['cache']),
      ],
    ),
    ElkNode(id: 'response', width: 48, height: 30),
  ],
  edges: [
    ElkEdge(
      id: 'complete',
      sources: ['workerB'],
      targets: ['response'],
      labels: [
        ElkLabel(
          text: 'result',
          width: 34,
          height: 12,
          placement: ElkEdgeLabelPlacement.tail,
        ),
        ElkLabel(
          text: '200',
          width: 22,
          height: 12,
          placement: ElkEdgeLabelPlacement.head,
        ),
      ],
    ),
  ],
);

bool _onBorder(ElkPoint point, ElkPositionedNode node) {
  const epsilon = 1e-6;
  final withinX =
      point.x >= node.x - epsilon && point.x <= node.x + node.width + epsilon;
  final withinY =
      point.y >= node.y - epsilon && point.y <= node.y + node.height + epsilon;
  return (withinY &&
          ((point.x - node.x).abs() <= epsilon ||
              (point.x - node.x - node.width).abs() <= epsilon)) ||
      (withinX &&
          ((point.y - node.y).abs() <= epsilon ||
              (point.y - node.y - node.height).abs() <= epsilon));
}

// A runnable example: lay out a small graph with a cluster and print the
// resulting node positions and orthogonal edge routes.
import 'package:elk_layout/elk_layout.dart';

void main() {
  final result = const ElkLayered().layout(ElkGraph(
    layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
    children: [
      ElkNode(id: 'start', width: 90, height: 40),
      ElkNode(id: 'group', children: [
        ElkNode(id: 'a', width: 80, height: 40),
        ElkNode(id: 'b', width: 80, height: 40),
      ]),
      ElkNode(id: 'end', width: 90, height: 40),
    ],
    edges: [
      ElkEdge(id: 'e1', sources: ['start'], targets: ['a']),
      ElkEdge(id: 'e2', sources: ['start'], targets: ['b']),
      ElkEdge(id: 'e3', sources: ['a'], targets: ['end']),
      ElkEdge(id: 'e4', sources: ['b'], targets: ['end']),
    ],
  ));

  print('graph: ${result.width.toStringAsFixed(0)} x '
      '${result.height.toStringAsFixed(0)}');
  print('\nnodes (absolute):');
  result.nodesById.forEach((id, n) {
    print('  $id: (${n.x.toStringAsFixed(1)}, ${n.y.toStringAsFixed(1)}) '
        '${n.width.toStringAsFixed(0)}x${n.height.toStringAsFixed(0)}');
  });

  print('\nedges (orthogonal routes):');
  for (final e in result.edges) {
    final pts = e.sections.first.points
        .map((p) => '(${p.x.toStringAsFixed(0)},${p.y.toStringAsFixed(0)})')
        .join(' → ');
    print('  ${e.id}: $pts');
  }
}

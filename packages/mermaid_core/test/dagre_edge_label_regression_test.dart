import 'package:mermaid_core/src/vendor/dagre/dart_dagre.dart';
import 'package:test/test.dart';

void main() {
  test('LR layout rotates a centered edge label with its edge', () {
    final graph = DagreGraph()
      ..addNode(DagreNode('A', width: 80, height: 40))
      ..addNode(DagreNode('B', width: 80, height: 40))
      ..addEdge(
        DagreEdge(
          'A',
          'B',
          id: 'e0',
          width: 60,
          height: 20,
          labelPos: LabelPosition.center,
        ),
      );

    final result = layout(graph, DagreConfig(rankDir: RankDir.ltr));
    final a = result.graph.nodeMap['A']!.position!.center;
    final b = result.graph.nodeMap['B']!.position!.center;
    final edge = result.graph.findEdgeById('e0')!;

    expect(edge.labelX, inExclusiveRange(a.x, b.x));
    expect(edge.labelY, closeTo((a.y + b.y) / 2, 0.001));
  });
}

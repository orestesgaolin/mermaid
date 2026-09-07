import 'package:mermaid_core/mermaid_core.dart';
import 'package:mermaid_core/src/vendor/dagre/dart_dagre.dart' as dagre;
import 'package:test/test.dart';

import 'support/scene.dart';

const _mermaid = Mermaid(measurer: ApproximateTextMeasurer());

Rect _bounds(RenderScene scene, String id) => sceneBounds(
  groupsOf(scene.nodes).singleWhere((group) => group.id == id).children,
)!;

void main() {
  test('Dagre safely lays out a zero-length same-rank constraint', () {
    final adjacent = dagre.DagreGraph()
      ..addNode(dagre.DagreNode('note', width: 80, height: 40))
      ..addNode(dagre.DagreNode('class', width: 80, height: 40))
      ..addEdge(dagre.DagreEdge('note', 'class', minLen: 0));
    final ordinary = dagre.DagreGraph()
      ..addNode(dagre.DagreNode('note', width: 80, height: 40))
      ..addNode(dagre.DagreNode('class', width: 80, height: 40))
      ..addEdge(dagre.DagreEdge('note', 'class'));

    final adjacentResult = dagre.layout(adjacent, dagre.DagreConfig());
    final ordinaryResult = dagre.layout(ordinary, dagre.DagreConfig());
    double rankDistance(dagre.DagreResult result) =>
        (result.graph.nodeMap['note']!.position!.center.y -
                result.graph.nodeMap['class']!.position!.center.y)
            .abs();

    expect(
      rankDistance(adjacentResult),
      lessThan(rankDistance(ordinaryResult)),
    );
    expect(adjacentResult.graph.edgeMap.values.single.points, isEmpty);
  });

  for (final direction in ['TB', 'BT', 'LR', 'RL']) {
    test('attached note stays adjacent in $direction layout', () {
      final scene = _mermaid.render('''
classDiagram
direction $direction
namespace Accounts {
  class Account
  class Ledger
}
note for Account "Stores balance"
Account --> Ledger
''');
      final note = _bounds(scene, '__note0');
      final account = _bounds(scene, 'Account');
      final ledger = _bounds(scene, 'Ledger');

      if (direction == 'TB' || direction == 'BT') {
        expect(
          (note.center.y - account.center.y).abs(),
          lessThan((ledger.center.y - account.center.y).abs()),
        );
      } else {
        expect(
          (note.center.x - account.center.x).abs(),
          lessThan((ledger.center.x - account.center.x).abs()),
        );
      }
      expect(
        shapesOf(scene.nodes).where(
          (shape) =>
              shape.geometry is PathGeometry && shape.stroke?.dash != null,
        ),
        isNotEmpty,
      );
      final namespace = _bounds(scene, 'namespace_Accounts');
      expect(namespace.contains(account.center), isTrue);
      expect(namespace.contains(ledger.center), isTrue);
    });
  }
}

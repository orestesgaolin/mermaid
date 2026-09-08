import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  test('model-order option changes feedback direction through public JSON', () {
    final greedy = const ElkLayered().layout(_modelOrderFixture(const {}));
    final modelOrder = const ElkLayered().layout(
      _modelOrderFixture(const {
        'org.eclipse.elk.layered.cycleBreaking.strategy': 'MODEL_ORDER',
      }),
    );

    // The n2 <-> n4 cycle is broken in input order under MODEL_ORDER. That
    // puts n0 before n2; greedy chooses the opposite feedback direction.
    expect(
      modelOrder.nodesById['n0']!.x,
      lessThan(modelOrder.nodesById['n2']!.x),
    );
    expect(greedy.nodesById['n0']!.x, greaterThan(greedy.nodesById['n2']!.x));
    expect(_overlapCount(modelOrder), 0);
  });

  test('depth-first option produces its DFS feedback layout', () {
    final greedy = const ElkLayered().layout(
      _depthFirstFixture(ElkCycleBreaking.greedy),
    );
    final depthFirst = const ElkLayered().layout(
      _depthFirstFixture(ElkCycleBreaking.depthFirst),
    );

    // The antiparallel n0 <-> n3 pair is reached from n0. DFS reverses the
    // n3 -> n0 back edge and moves n0 to the final layer; greedy peels n0 near
    // the first layer on this graph.
    expect(
      depthFirst.nodesById['n0']!.x,
      greaterThan(greedy.nodesById['n0']!.x),
    );
    expect(depthFirst.nodesById['n3']!.x, lessThan(greedy.nodesById['n3']!.x));
    expect(_overlapCount(depthFirst), 0);
  });

  test(
    'interactive option preserves supplied positions in every direction',
    () {
      ElkResult layout(
        ElkDirection direction,
        ({double x, double y}) a,
        ({double x, double y}) c,
      ) => const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(
            direction: direction,
            cycleBreaking: ElkCycleBreaking.interactive,
          ),
          children: [
            ElkNode(id: 'a', x: a.x, y: a.y, width: 20, height: 20),
            const ElkNode(id: 'b', x: 100, y: 100, width: 20, height: 20),
            ElkNode(id: 'c', x: c.x, y: c.y, width: 20, height: 20),
          ],
          edges: const [
            ElkEdge(id: 'ab', sources: ['a'], targets: ['b']),
            ElkEdge(id: 'bc', sources: ['b'], targets: ['c']),
            ElkEdge(id: 'ca', sources: ['c'], targets: ['a']),
          ],
        ),
      );

      final right = layout(
        ElkDirection.right,
        (x: 0, y: 100),
        (x: 200, y: 100),
      );
      final left = layout(ElkDirection.left, (x: 200, y: 100), (x: 0, y: 100));
      final down = layout(ElkDirection.down, (x: 100, y: 0), (x: 100, y: 200));
      final up = layout(ElkDirection.up, (x: 100, y: 200), (x: 100, y: 0));

      expect(right.nodesById['a']!.x, lessThan(right.nodesById['c']!.x));
      expect(left.nodesById['a']!.x, greaterThan(left.nodesById['c']!.x));
      expect(down.nodesById['a']!.y, lessThan(down.nodesById['c']!.y));
      expect(up.nodesById['a']!.y, greaterThan(up.nodesById['c']!.y));
      expect([right, left, down, up].map(_overlapCount), everyElement(0));
    },
  );

  test('model-order routes antiparallel compound boundary edges', () {
    final result = const ElkLayered().layout(
      ElkGraph(
        layoutOptions: ElkLayoutOptions(
          direction: ElkDirection.right,
          cycleBreaking: ElkCycleBreaking.modelOrder,
        ),
        children: [
          ElkNode(
            id: 'cluster',
            children: [ElkNode(id: 'inner', width: 40, height: 30)],
          ),
          ElkNode(id: 'outer', width: 50, height: 30),
        ],
        edges: [
          ElkEdge(id: 'out', sources: ['inner'], targets: ['outer']),
          ElkEdge(id: 'back', sources: ['outer'], targets: ['inner']),
        ],
      ),
    );

    expect(result.edges.map((edge) => edge.id), containsAll(['out', 'back']));
    expect(result.edges.every((edge) => edge.sections.isNotEmpty), isTrue);
    expect(_overlapCount(result), 0);
  });
}

ElkGraph _modelOrderFixture(Map<String, dynamic> cycleOptions) =>
    ElkGraph.fromJson({
      'layoutOptions': {'elk.direction': 'RIGHT', ...cycleOptions},
      'children': const [
        {'id': 'n0', 'width': 47, 'height': 56},
        {'id': 'n1', 'width': 28, 'height': 22},
        {'id': 'n2', 'width': 40, 'height': 67},
        {'id': 'n3', 'width': 53, 'height': 26},
        {'id': 'n4', 'width': 39, 'height': 54},
      ],
      'edges': const [
        {
          'id': 'e2-0',
          'sources': ['n2'],
          'targets': ['n0'],
        },
        {
          'id': 'e2-4',
          'sources': ['n2'],
          'targets': ['n4'],
        },
        {
          'id': 'e3-0',
          'sources': ['n3'],
          'targets': ['n0'],
        },
        {
          'id': 'e3-2',
          'sources': ['n3'],
          'targets': ['n2'],
        },
        {
          'id': 'e4-2',
          'sources': ['n4'],
          'targets': ['n2'],
        },
      ],
    });

ElkGraph _depthFirstFixture(ElkCycleBreaking strategy) => ElkGraph(
  layoutOptions: ElkLayoutOptions(
    direction: ElkDirection.right,
    cycleBreaking: strategy,
  ),
  children: const [
    ElkNode(id: 'n0', width: 22, height: 31),
    ElkNode(id: 'n1', width: 79, height: 60),
    ElkNode(id: 'n2', width: 48, height: 48),
    ElkNode(id: 'n3', width: 78, height: 38),
    ElkNode(id: 'n4', width: 46, height: 33),
  ],
  edges: const [
    ElkEdge(id: 'e0-1', sources: ['n0'], targets: ['n1']),
    ElkEdge(id: 'e0-3', sources: ['n0'], targets: ['n3']),
    ElkEdge(id: 'e2-3', sources: ['n2'], targets: ['n3']),
    ElkEdge(id: 'e3-0', sources: ['n3'], targets: ['n0']),
    ElkEdge(id: 'e3-4', sources: ['n3'], targets: ['n4']),
  ],
);

int _overlapCount(ElkResult result) {
  var count = 0;
  for (var i = 0; i < result.children.length; i++) {
    final a = result.children[i];
    for (var j = i + 1; j < result.children.length; j++) {
      final b = result.children[j];
      if (a.x < b.x + b.width &&
          a.x + a.width > b.x &&
          a.y < b.y + b.height &&
          a.y + a.height > b.y) {
        count++;
      }
    }
  }
  return count;
}

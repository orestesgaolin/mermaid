import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  test('canonical JSON parses every model-order strategy', () {
    for (final entry in {
      'NONE': ElkConsiderModelOrder.none,
      'NODES_AND_EDGES': ElkConsiderModelOrder.nodesAndEdges,
      'PREFER_EDGES': ElkConsiderModelOrder.preferEdges,
      'PREFER_NODES': ElkConsiderModelOrder.preferNodes,
    }.entries) {
      final options = ElkLayoutOptions.fromElkJson({
        'org.eclipse.elk.layered.considerModelOrder.strategy': entry.key,
      });
      expect(options.considerModelOrder, entry.value);
    }
  });

  test('edge- and node-preferred strategies produce distinct layer orders', () {
    final edgePreferred = const ElkLayered().layout(
      _fixture(ElkConsiderModelOrder.preferEdges),
    );
    final nodePreferred = const ElkLayered().layout(
      _fixture(ElkConsiderModelOrder.preferNodes),
    );

    expect(
      _layerOrder(edgePreferred, ['n3', 'n4', 'n5']),
      isNot(_layerOrder(nodePreferred, ['n3', 'n4', 'n5'])),
    );
  });

  test('node and edge conflict follows the selected preference', () {
    ElkResult layout(ElkConsiderModelOrder strategy) =>
        const ElkLayered().layout(
          ElkGraph(
            layoutOptions: ElkLayoutOptions(
              direction: ElkDirection.right,
              considerModelOrder: strategy,
            ),
            children: [
              ElkNode(id: 'a', width: 30, height: 20),
              ElkNode(id: 'b', width: 30, height: 20),
              ElkNode(id: 'c', width: 30, height: 20),
              ElkNode(id: 'd', width: 30, height: 20),
              ElkNode(id: 'e', width: 30, height: 20),
            ],
            edges: [
              ElkEdge(id: 'ae', sources: ['a'], targets: ['e']),
              ElkEdge(id: 'ad', sources: ['a'], targets: ['d']),
              ElkEdge(id: 'bc', sources: ['b'], targets: ['c']),
            ],
          ),
        );

    final nodesAndEdges = layout(ElkConsiderModelOrder.nodesAndEdges);
    final preferNodes = layout(ElkConsiderModelOrder.preferNodes);
    expect(
      nodesAndEdges.nodesById['e']!.y,
      lessThan(nodesAndEdges.nodesById['d']!.y),
    );
    expect(
      preferNodes.nodesById['d']!.y,
      lessThan(preferNodes.nodesById['e']!.y),
    );
  });

  test(
    'canonical JSON strategy reaches the same public layout as typed API',
    () {
      final json = const ElkLayered().layout(
        ElkGraph.fromJson({
          ..._fixtureJson,
          'layoutOptions': {
            'elk.direction': 'RIGHT',
            'org.eclipse.elk.layered.considerModelOrder.strategy':
                'PREFER_EDGES',
          },
        }),
      );
      final typed = const ElkLayered().layout(
        _fixture(ElkConsiderModelOrder.preferEdges),
      );

      expect(_positions(json), _positions(typed));
    },
  );
}

ElkGraph _fixture(ElkConsiderModelOrder strategy) {
  final base = ElkGraph.fromJson(_fixtureJson);
  return ElkGraph(
    id: base.id,
    layoutOptions: ElkLayoutOptions(
      direction: ElkDirection.right,
      considerModelOrder: strategy,
    ),
    children: base.children,
    edges: base.edges,
  );
}

List<String> _layerOrder(ElkResult result, List<String> ids) {
  final nodes = [for (final id in ids) result.nodesById[id]!]
    ..sort((a, b) => a.y.compareTo(b.y));
  return [for (final node in nodes) node.id];
}

Map<String, (double, double)> _positions(ElkResult result) => {
  for (final node in result.children) node.id: (node.x, node.y),
};

final _fixtureJson = <String, Object>{
  'id': 'root',
  'children': [
    for (final id in const ['n0', 'n1', 'n2', 'n3', 'n4', 'n5', 'n7', 'n8'])
      {'id': id, 'width': 30, 'height': 20},
  ],
  'edges': [
    {
      'id': 'e1',
      'sources': ['n0'],
      'targets': ['n2'],
    },
    {
      'id': 'e4',
      'sources': ['n1'],
      'targets': ['n5'],
    },
    {
      'id': 'e5',
      'sources': ['n1'],
      'targets': ['n7'],
    },
    {
      'id': 'e7',
      'sources': ['n2'],
      'targets': ['n3'],
    },
    {
      'id': 'e8',
      'sources': ['n2'],
      'targets': ['n4'],
    },
    {
      'id': 'e9',
      'sources': ['n2'],
      'targets': ['n5'],
    },
    {
      'id': 'e11',
      'sources': ['n3'],
      'targets': ['n7'],
    },
    {
      'id': 'e12',
      'sources': ['n3'],
      'targets': ['n8'],
    },
  ],
};

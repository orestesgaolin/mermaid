import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  test(
    'default INCLUDE_CHILDREN preserves mixed directions and cross routes',
    () {
      final result = const ElkLayered().layout(_graph());

      _expectInternalDown(result);
      expect(
        result.nodesById['after']!.x,
        greaterThan(result.nodesById['group']!.x),
      );
      expect(_sections(result, 'ab'), 1);
      expect(_sections(result, 'root-ab'), 1);
      expect(_sections(result, 'enter'), 1);
      expect(_sections(result, 'exit'), 1);
    },
  );

  for (final handling in [
    ElkHierarchyHandling.separateChildren,
    ElkHierarchyHandling.inherit,
  ]) {
    test('root ${handling.name} lays children separately from cross edges', () {
      final result = const ElkLayered().layout(_graph(root: handling));

      _expectInternalDown(result);
      expect(_sections(result, 'ab'), 1);
      expect(_sections(result, 'root-ab'), 1);
      expect(_sections(result, 'enter'), 0);
      expect(_sections(result, 'exit'), 0);
    });
  }

  test('nested INHERIT and absent handling inherit root INCLUDE_CHILDREN', () {
    final inherited = const ElkLayered().layout(
      _graph(nested: ElkHierarchyHandling.inherit),
    );
    final absent = const ElkLayered().layout(_graph());

    for (final result in [inherited, absent]) {
      _expectInternalDown(result);
      expect(_sections(result, 'ab'), 1);
      expect(_sections(result, 'root-ab'), 1);
      expect(_sections(result, 'enter'), 1);
      expect(_sections(result, 'exit'), 1);
    }
  });

  test('typed hierarchy-only nested options inherit the parent direction', () {
    final result = const ElkLayered().layout(
      ElkGraph(
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
      ),
    );
    expect(result.nodesById['b']!.x, greaterThan(result.nodesById['a']!.x));
  });

  test('JSON hierarchy-only nested options inherit the parent direction', () {
    final result = const ElkLayered().layout(
      ElkGraph.fromJson({
        'layoutOptions': {'elk.direction': 'RIGHT'},
        'children': [
          {
            'id': 'group',
            'layoutOptions': {'elk.hierarchyHandling': 'INHERIT'},
            'children': [
              {'id': 'a', 'width': 50, 'height': 30},
              {'id': 'b', 'width': 50, 'height': 30},
            ],
            'edges': [
              {
                'id': 'ab',
                'sources': ['a'],
                'targets': ['b'],
              },
            ],
          },
        ],
      }),
    );
    expect(result.nodesById['b']!.x, greaterThan(result.nodesById['a']!.x));
  });

  test('nested SEPARATE_CHILDREN safely leaves cross edges unrouted', () {
    // elkjs throws UnsupportedGraphException for this mixed scope. Dart keeps
    // the public edges with no sections so callers can inspect the result.
    final result = const ElkLayered().layout(
      _graph(nested: ElkHierarchyHandling.separateChildren),
    );
    expect(_sections(result, 'ab'), 1);
    expect(_sections(result, 'root-ab'), 1);
    expect(_sections(result, 'enter'), 0);
    expect(_sections(result, 'exit'), 0);
  });

  for (final direction in ElkDirection.values) {
    for (final side in ElkPortSide.values) {
      for (final nestedDeclaration in [false, true]) {
        test(
          '${direction.name} ${side.name} boundary port routes a '
          '${nestedDeclaration ? 'nested' : 'root'}-declared direct edge',
          () {
            final result = const ElkLayered().layout(
              _boundaryGraph(
                direction: direction,
                side: side,
                nestedDeclaration: nestedDeclaration,
              ),
            );
            final group = result.nodesById['group']!;
            final port = group.ports.single;
            final section = result.edges
                .singleWhere((edge) => edge.id == 'to-leaf')
                .sections
                .single;
            final start = section.startPoint;

            // The edge travels inward, so elkjs uses the port face adjoining
            // the compound content rather than its outward face.
            switch (side) {
              case ElkPortSide.north:
                expect(start.y, closeTo(group.y + port.y + port.height, 0.001));
              case ElkPortSide.south:
                expect(start.y, closeTo(group.y + port.y, 0.001));
              case ElkPortSide.east:
                expect(start.x, closeTo(group.x + port.x, 0.001));
              case ElkPortSide.west:
                expect(start.x, closeTo(group.x + port.x + port.width, 0.001));
            }
            _expectOrthogonal(section.points);
          },
        );
      }
    }

    for (final side in [ElkPortSide.north, ElkPortSide.south]) {
      for (final nestedDeclaration in [false, true]) {
        test('${direction.name} ${side.name} does not route through a second '
            'separate boundary when declared '
            '${nestedDeclaration ? 'nested' : 'at root'}', () {
          final result = const ElkLayered().layout(
            _boundaryGraph(
              direction: direction,
              side: side,
              nestedDeclaration: nestedDeclaration,
              deep: true,
            ),
          );
          expect(_sections(result, 'to-leaf'), 0);
        });
      }
    }
  }

  test('ELK JSON hierarchy aliases select root handling', () {
    for (final key in [
      'hierarchyHandling',
      'elk.hierarchyHandling',
      'org.eclipse.elk.hierarchyHandling',
    ]) {
      final graph = ElkGraph.fromJson({
        'id': 'root',
        'layoutOptions': {key: 'SEPARATE_CHILDREN'},
        'children': [
          {'id': 'before', 'width': 50, 'height': 30},
          {
            'id': 'group',
            'layoutOptions': {'elk.direction': 'DOWN'},
            'children': [
              {'id': 'a', 'width': 50, 'height': 30},
              {'id': 'b', 'width': 50, 'height': 30},
            ],
            'edges': [
              {
                'id': 'ab',
                'sources': ['a'],
                'targets': ['b'],
              },
            ],
          },
          {'id': 'after', 'width': 50, 'height': 30},
        ],
        'edges': [
          {
            'id': 'enter',
            'sources': ['before'],
            'targets': ['a'],
          },
          {
            'id': 'exit',
            'sources': ['b'],
            'targets': ['after'],
          },
        ],
      });
      final result = const ElkLayered().layout(graph);
      expect(_sections(result, 'ab'), 1, reason: key);
      expect(_sections(result, 'enter'), 0, reason: key);
      expect(_sections(result, 'exit'), 0, reason: key);
    }
  });
}

ElkGraph _graph({
  ElkHierarchyHandling root = ElkHierarchyHandling.includeChildren,
  ElkHierarchyHandling? nested,
}) => ElkGraph(
  layoutOptions: ElkLayoutOptions(
    direction: ElkDirection.right,
    hierarchyHandling: root,
  ),
  children: [
    const ElkNode(id: 'before', width: 50, height: 30),
    ElkNode(
      id: 'group',
      layoutOptions: nested == null
          ? const ElkLayoutOptions(direction: ElkDirection.down)
          : ElkLayoutOptions(
              direction: ElkDirection.down,
              hierarchyHandling: nested,
            ),
      children: const [
        ElkNode(id: 'a', width: 50, height: 30),
        ElkNode(id: 'b', width: 50, height: 30),
      ],
      edges: const [
        ElkEdge(id: 'ab', sources: ['a'], targets: ['b']),
      ],
    ),
    const ElkNode(id: 'after', width: 50, height: 30),
  ],
  edges: const [
    ElkEdge(id: 'root-ab', sources: ['a'], targets: ['b']),
    ElkEdge(id: 'enter', sources: ['before'], targets: ['a']),
    ElkEdge(id: 'exit', sources: ['b'], targets: ['after']),
  ],
);

ElkGraph _boundaryGraph({
  required ElkDirection direction,
  required ElkPortSide side,
  required bool nestedDeclaration,
  bool deep = false,
}) {
  final leaf = const ElkNode(id: 'leaf', width: 50, height: 30);
  final edge = const ElkEdge(
    id: 'to-leaf',
    sources: ['boundary'],
    targets: ['leaf'],
  );
  final group = ElkNode(
    id: 'group',
    layoutOptions: ElkLayoutOptions(
      direction: direction,
      hierarchyHandling: ElkHierarchyHandling.separateChildren,
    ),
    ports: [ElkPort(id: 'boundary', side: side, width: 10, height: 8)],
    children: deep
        ? [
            ElkNode(
              id: 'inner',
              layoutOptions: ElkLayoutOptions(
                direction: direction,
                hierarchyHandling: ElkHierarchyHandling.separateChildren,
              ),
              children: [leaf],
            ),
          ]
        : [leaf],
    edges: nestedDeclaration ? [edge] : const [],
  );
  return ElkGraph(
    layoutOptions: ElkLayoutOptions(
      direction: direction,
      hierarchyHandling: ElkHierarchyHandling.separateChildren,
    ),
    children: [group],
    edges: nestedDeclaration ? const [] : [edge],
  );
}

void _expectOrthogonal(List<ElkPoint> points) {
  for (var index = 1; index < points.length; index++) {
    final previous = points[index - 1];
    final current = points[index];
    expect(
      (current.x - previous.x).abs() < 0.001 ||
          (current.y - previous.y).abs() < 0.001,
      isTrue,
      reason: 'segment $previous -> $current is diagonal',
    );
  }
}

void _expectInternalDown(ElkResult result) {
  expect(result.nodesById['b']!.y, greaterThan(result.nodesById['a']!.y));
}

int _sections(ElkResult result, String id) =>
    result.edges.singleWhere((edge) => edge.id == id).sections.length;

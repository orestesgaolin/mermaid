import 'package:elk/elk.dart';
import 'package:test/test.dart';

Map<String, dynamic> _graph(Map<String, dynamic> options) => {
  'id': 'root',
  'layoutOptions': {'elk.direction': 'RIGHT', ...options},
  'children': [
    for (final id in ['a', 'b', 'c']) {'id': id, 'width': 40, 'height': 20},
  ],
  'edges': [
    for (final id in ['b', 'c'])
      {
        'id': 'a$id',
        'sources': ['a'],
        'targets': [id],
      },
  ],
};

ElkResult _layout(Map<String, dynamic> options) =>
    const ElkLayered().layout(ElkGraph.fromJson(_graph(options)));

List<Object> _geometry(ElkResult result) => [
  for (final node in result.children)
    [node.id, node.x, node.y, node.width, node.height],
  for (final edge in result.edges)
    [
      edge.id,
      for (final section in edge.sections)
        [
          for (final point in section.points) [point.x, point.y],
        ],
    ],
];

void main() {
  for (final prefix in ['', 'elk.', 'org.eclipse.elk.']) {
    test('$prefix node spacing reaches the layout', () {
      final result = _layout({'${prefix}spacing.nodeNode': 100});
      final children = result.children.where((n) => n.id != 'a').toList()
        ..sort((a, b) => a.y.compareTo(b.y));
      expect(children.last.y - children.first.y - children.first.height, 100);
    });

    test('$prefix base spacing reaches both layout axes', () {
      final result = _layout({'${prefix}spacing.baseValue': 100});
      final a = result.children.singleWhere((n) => n.id == 'a');
      final b = result.children.singleWhere((n) => n.id == 'b');
      final c = result.children.singleWhere((n) => n.id == 'c');
      expect(b.x - a.x - a.width, greaterThanOrEqualTo(100));
      expect((b.y - c.y).abs() - b.height, 100);
    });

    test('$prefix layered spacing reaches successive layers', () {
      final result = _layout({
        '${prefix}layered.spacing.nodeNodeBetweenLayers': '100',
      });
      final a = result.children.singleWhere((n) => n.id == 'a');
      final b = result.children.singleWhere((n) => n.id == 'b');
      expect(b.x - a.x - a.width, greaterThanOrEqualTo(100));
      expect(
        _geometry(result),
        _geometry(_layout({'spacing.nodeNodeBetweenLayers': 100})),
      );
    });
  }

  test('canonical options take precedence over shorter aliases', () {
    final result = _layout({
      'spacing.nodeNode': 10,
      'elk.spacing.nodeNode': 25,
      'org.eclipse.elk.spacing.nodeNode': 100,
      'direction': 'LEFT',
      'org.eclipse.elk.direction': 'DOWN',
    });
    final a = result.children.singleWhere((n) => n.id == 'a');
    final b = result.children.singleWhere((n) => n.id == 'b');
    final c = result.children.singleWhere((n) => n.id == 'c');
    expect(b.y, greaterThan(a.y));
    expect((b.x - c.x).abs() - b.width, 100);
  });

  test('canonical nested direction overrides parent without changing size', () {
    final graph = _graph({});
    graph['children'] = [
      {
        'id': 'cluster',
        'layoutOptions': {'org.eclipse.elk.direction': 'DOWN'},
        'children': (graph['children'] as List).take(2).toList(),
        'edges': [(graph['edges'] as List).first],
      },
    ];
    graph['edges'] = [];
    final result = const ElkLayered().layout(ElkGraph.fromJson(graph));
    final children = result.children.single.children;
    expect(children[1].y, greaterThan(children[0].y));
    expect(children[1].x, children[0].x);
    expect(
      children.map((n) => (n.width, n.height)),
      everyElement((40.0, 20.0)),
    );
  });
}

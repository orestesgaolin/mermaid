import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  test('fixed alignment selects distinct BK compactions without overlaps', () {
    final signatures = <String>{};

    for (final alignment in ElkFixedAlignment.values) {
      final result = _layout(
        ElkLayoutOptions(
          direction: ElkDirection.right,
          fixedAlignment: alignment,
        ),
      );
      signatures.add(_signature(result));
      _expectNoNodeOverlaps(result);
      _expectOrthogonalRoutes(result);
    }

    // The same ordered fixture produces five compactions in elkjs 0.9.3.
    expect(signatures, hasLength(5));
  });

  test('default placement remains the NONE compaction', () {
    final defaultResult = _layout(
      const ElkLayoutOptions(direction: ElkDirection.right),
    );
    final explicitNone = _layout(
      const ElkLayoutOptions(
        direction: ElkDirection.right,
        fixedAlignment: ElkFixedAlignment.none,
      ),
    );

    expect(_signature(defaultResult), _signature(explicitNone));
  });

  for (final entry in const {
    'org.eclipse.elk.layered.nodePlacement.bk.fixedAlignment': 'LEFTUP',
    'elk.layered.nodePlacement.bk.fixedAlignment': 'LEFTDOWN',
    'layered.nodePlacement.bk.fixedAlignment': 'BALANCED',
  }.entries) {
    test('ELK JSON ${entry.key} controls rendered geometry', () {
      final parsed = ElkLayoutOptions.fromElkJson({
        'elk.direction': 'RIGHT',
        entry.key: entry.value,
      });
      final result = _layout(parsed);
      final expected = _layout(
        ElkLayoutOptions(
          direction: ElkDirection.right,
          fixedAlignment: switch (entry.value) {
            'LEFTUP' => ElkFixedAlignment.leftUp,
            'LEFTDOWN' => ElkFixedAlignment.leftDown,
            _ => ElkFixedAlignment.balanced,
          },
        ),
      );
      final none = _layout(
        const ElkLayoutOptions(
          direction: ElkDirection.right,
          fixedAlignment: ElkFixedAlignment.none,
        ),
      );

      expect(_signature(result), _signature(expected));
      expect(_signature(result), isNot(_signature(none)));
    });
  }
}

ElkResult _layout(ElkLayoutOptions options) => const ElkLayered().layout(
  ElkGraph(layoutOptions: options, children: _children, edges: _edges),
);

const _children = [
  ElkNode(id: 'n0', width: 52, height: 32),
  ElkNode(id: 'n1', width: 69, height: 40),
  ElkNode(id: 'n2', width: 87, height: 38),
  ElkNode(id: 'n3', width: 47, height: 67),
  ElkNode(id: 'n4', width: 76, height: 27),
  ElkNode(id: 'n5', width: 87, height: 75),
  ElkNode(id: 'n6', width: 67, height: 25),
  ElkNode(id: 'n7', width: 42, height: 80),
];

const _edges = [
  ElkEdge(id: 'e0-3', sources: ['n0'], targets: ['n3']),
  ElkEdge(id: 'e1-4', sources: ['n1'], targets: ['n4']),
  ElkEdge(id: 'e1-6', sources: ['n1'], targets: ['n6']),
  ElkEdge(id: 'e2-3', sources: ['n2'], targets: ['n3']),
  ElkEdge(id: 'e2-4', sources: ['n2'], targets: ['n4']),
  ElkEdge(id: 'e3-4', sources: ['n3'], targets: ['n4']),
  ElkEdge(id: 'e3-5', sources: ['n3'], targets: ['n5']),
  ElkEdge(id: 'e3-6', sources: ['n3'], targets: ['n6']),
  ElkEdge(id: 'e4-7', sources: ['n4'], targets: ['n7']),
  ElkEdge(id: 'e5-7', sources: ['n5'], targets: ['n7']),
];

String _signature(ElkResult result) => [
  for (final node in result.children)
    '${node.id}:${node.x.toStringAsFixed(3)},${node.y.toStringAsFixed(3)}',
  for (final edge in result.edges)
    '${edge.id}:${edge.sections.expand((section) => section.points).map((p) => '${p.x.toStringAsFixed(3)},${p.y.toStringAsFixed(3)}').join(';')}',
].join('|');

void _expectNoNodeOverlaps(ElkResult result) {
  for (var i = 0; i < result.children.length; i++) {
    for (var j = i + 1; j < result.children.length; j++) {
      final a = result.children[i];
      final b = result.children[j];
      expect(
        a.x + a.width <= b.x ||
            b.x + b.width <= a.x ||
            a.y + a.height <= b.y ||
            b.y + b.height <= a.y,
        isTrue,
        reason: '${a.id} overlaps ${b.id}',
      );
    }
  }
}

void _expectOrthogonalRoutes(ElkResult result) {
  for (final edge in result.edges) {
    for (final section in edge.sections) {
      final points = section.points;
      for (var i = 1; i < points.length; i++) {
        expect(
          points[i - 1].x == points[i].x || points[i - 1].y == points[i].y,
          isTrue,
          reason: '${edge.id}: $points',
        );
      }
    }
  }
}

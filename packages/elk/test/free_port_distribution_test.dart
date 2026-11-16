import 'package:elk/elk.dart';
import 'package:test/test.dart';

List<double> _sourceOffsets(ElkResult res, String node) {
  final n = res.nodesById[node]!;
  return [
    for (final e in res.edges)
      if (e.id.startsWith(node)) e.sections.first.startPoint.x - n.x,
  ]..sort();
}

void main() {
  group('free ports use ELK DISTRIBUTED alignment', () {
    ElkResult layout() => const ElkLayered().layout(
      ElkGraph(
        layoutOptions: const ElkLayoutOptions(direction: ElkDirection.down),
        children: [
          const ElkNode(id: 'S', width: 30, height: 30),
          for (final id in ['a', 'b', 'c', 'd', 'e'])
            ElkNode(id: id, width: 40, height: 30),
          const ElkNode(id: 'R', width: 200, height: 40),
          for (final id in ['r1', 'r2']) ElkNode(id: id, width: 40, height: 30),
        ],
        edges: [
          for (final t in ['a', 'b', 'c', 'd', 'e'])
            ElkEdge(id: 'S$t', sources: ['S'], targets: [t]),
          for (final t in ['r1', 'r2'])
            ElkEdge(id: 'R$t', sources: ['R'], targets: [t]),
        ],
      ),
    );

    test('ports split a wide side into equal parts, as elkjs does', () {
      final offsets = _sourceOffsets(layout(), 'R');
      expect(offsets[0], closeTo(200 / 3, 1e-6));
      expect(offsets[1], closeTo(400 / 3, 1e-6));
    });

    test('a crowded side keeps equal gaps below the port-port spacing', () {
      expect(_sourceOffsets(layout(), 'S'), [5.0, 10.0, 15.0, 20.0, 25.0]);
    });

    test('an edge between two layers routes with at most two bends', () {
      final res = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: const ElkLayoutOptions(direction: ElkDirection.down),
          children: [
            for (final id in ['A', 'B']) ElkNode(id: id, width: 71, height: 50),
            for (final id in ['C', 'D', 'E'])
              ElkNode(id: id, width: 72, height: 50),
          ],
          edges: [
            for (final (s, t) in [
              ('A', 'C'),
              ('A', 'D'),
              ('B', 'C'),
              ('B', 'D'),
              ('A', 'E'),
              ('B', 'E'),
            ])
              ElkEdge(id: '$s$t', sources: [s], targets: [t]),
          ],
        ),
      );
      for (final e in res.edges) {
        expect(
          e.sections.first.points.length,
          lessThanOrEqualTo(4),
          reason: '${e.id} jogs',
        );
      }
    });
  });

  group('free ports inside spacing.portsSurrounding', () {
    List<double> offsets(double top, double bottom) => _sourceOffsets(
      const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(
            direction: ElkDirection.down,
            spacingPortsSurroundingTop: top,
            spacingPortsSurroundingBottom: bottom,
          ),
          children: [
            const ElkNode(id: 'R', width: 140, height: 40),
            for (final id in ['a', 'b', 'c'])
              ElkNode(id: id, width: 40, height: 30),
          ],
          edges: [
            for (final t in ['a', 'b', 'c'])
              ElkEdge(id: 'R$t', sources: ['R'], targets: [t]),
          ],
        ),
      ),
      'R',
    );

    void expectOffsets(List<double> actual, List<double> expected) {
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i], closeTo(expected[i], 1e-6));
      }
    }

    test('distribute between the margins, as elkjs 0.12.1 does', () {
      expectOffsets(offsets(12, 12), [40.5, 70, 99.5]);
    });

    test('each margin applies to its own end of the side', () {
      expectOffsets(offsets(12, 0), [43.25, 75.5, 107.75]);
      expectOffsets(offsets(0, 12), [32.25, 64.5, 96.75]);
    });
  });
}

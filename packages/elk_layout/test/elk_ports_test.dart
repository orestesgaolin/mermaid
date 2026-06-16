import 'package:elk_layout/elk_layout.dart';
import 'package:test/test.dart';

void main() {
  group('Phase: ports', () {
    test('edges anchor at distinct ports on the source border', () {
      // src has two output ports; each edge should leave from its own port,
      // at distinct points on src's east border (RIGHT flow).
      final res = const ElkLayered().layout(ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
        children: [
          ElkNode(id: 'src', width: 80, height: 80, ports: [
            ElkPort(id: 'p1'),
            ElkPort(id: 'p2'),
          ]),
          ElkNode(id: 'a', width: 80, height: 40),
          ElkNode(id: 'b', width: 80, height: 40),
        ],
        edges: [
          ElkEdge(id: 'e1', sources: ['p1'], targets: ['a']),
          ElkEdge(id: 'e2', sources: ['p2'], targets: ['b']),
        ],
      ));

      final src = res.nodesById['src']!;
      // Two positioned ports on src, both on its right border (x == width).
      expect(src.ports, hasLength(2));
      for (final p in src.ports) {
        expect(p.x, closeTo(src.width, 0.5), reason: 'port on east border');
      }
      // The two ports sit at different heights.
      expect((src.ports[0].y - src.ports[1].y).abs(), greaterThan(1.0));

      // Each edge's start point matches one of the (absolute) port positions.
      final portYs = src.ports.map((p) => src.y + p.y).toSet();
      for (final e in res.edges) {
        final start = e.sections.first.startPoint;
        expect(start.x, closeTo(src.x + src.width, 0.6));
        expect(portYs.any((y) => (y - start.y).abs() < 0.6), isTrue,
            reason: 'edge ${e.id} starts at a port');
      }
      // Distinct start Ys → the fan-out is separated, not a shared bus.
      final startYs = res.edges.map((e) => e.sections.first.startPoint.y).toSet();
      expect(startYs, hasLength(2));
    });

    test('explicit port side is honored', () {
      // Flow is DOWN (so the inferred outgoing side would be south), but the
      // port declares EAST — the explicit side must win.
      final res = const ElkLayered().layout(ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
        children: [
          ElkNode(id: 'n', width: 80, height: 80, ports: [
            ElkPort(id: 'np', side: ElkPortSide.east),
          ]),
          ElkNode(id: 'm', width: 80, height: 40),
        ],
        edges: [ElkEdge(id: 'e', sources: ['np'], targets: ['m'])],
      ));
      final n = res.nodesById['n']!;
      expect(n.ports.single.x, closeTo(n.width, 0.5)); // east border
    });
  });
}

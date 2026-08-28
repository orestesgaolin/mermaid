import 'package:elk/elk.dart';
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

    test('explicit north and south port sides are honored for UP flow', () {
      // UP flow transposes the layout and mirrors output Y,
      // and that mirror flips NORTH and SOUTH:
      // the declared north port is the outgoing side,
      // so the edge must leave the top border of node `n`.
      final res = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: .up),
          children: [
            ElkNode(
              id: 'n',
              width: 80,
              height: 40,
              ports: [
                ElkPort(id: 'north', side: .north),
                ElkPort(id: 'south', side: .south),
              ],
            ),
            ElkNode(id: 'm', width: 80, height: 40),
          ],
          edges: [
            ElkEdge(id: 'e', sources: ['north'], targets: ['m']),
          ],
        ),
      );

      final n = res.nodesById['n']!;
      final portsById = {for (final port in n.ports) port.id: port};
      // Validate the north port sits on the top border.
      expect(portsById['north']!.y, closeTo(0, 0.5));
      // Validate the south port sits on the bottom border.
      expect(portsById['south']!.y, closeTo(n.height, 0.5));
      // Validate that node `m` is placed above node `n`,
      // confirming the layout really flows upward.
      expect(res.nodesById['m']!.y, lessThan(n.y));

      // Validate the edge leaves the top border of node `n`.
      final start = res.edges.single.sections.first.startPoint;
      expect(start.y, closeTo(n.y, 0.6));
    });
  });
}

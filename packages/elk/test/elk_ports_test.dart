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

    for (final direction in ElkDirection.values) {
      test('all explicit sides stay on their border for $direction', () {
        final res = const ElkLayered().layout(ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: direction),
          children: [
            ElkNode(id: 'n', width: 100, height: 80, ports: [
              ElkPort(id: 'north', width: 10, height: 8, side: .north),
              ElkPort(id: 'east', width: 10, height: 8, side: .east),
              ElkPort(id: 'south', width: 10, height: 8, side: .south),
              ElkPort(id: 'west', width: 10, height: 8, side: .west),
            ]),
          ],
        ));

        final n = res.nodesById['n']!;
        final ports = {for (final p in n.ports) p.id: p};
        expect(ports['north']!.y + ports['north']!.height, closeTo(0, 0.5));
        expect(ports['east']!.x, closeTo(n.width, 0.5));
        expect(ports['south']!.y, closeTo(n.height, 0.5));
        expect(ports['west']!.x + ports['west']!.width, closeTo(0, 0.5));
      });
    }

    test('multiple north and south ports are spaced and route independently', () {
      final res = const ElkLayered().layout(ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: .right),
        children: [
          ElkNode(id: 'top1', width: 40, height: 30),
          ElkNode(id: 'top2', width: 40, height: 30),
          ElkNode(id: 'hub', width: 120, height: 80, ports: [
            ElkPort(id: 'n1', width: 10, height: 8, side: .north),
            ElkPort(id: 'n2', width: 10, height: 8, side: .north),
            ElkPort(id: 's1', width: 10, height: 8, side: .south),
            ElkPort(id: 's2', width: 10, height: 8, side: .south),
          ]),
          ElkNode(id: 'bottom1', width: 40, height: 30),
          ElkNode(id: 'bottom2', width: 40, height: 30),
        ],
        edges: [
          ElkEdge(id: 'n1e', sources: ['n1'], targets: ['top1']),
          ElkEdge(id: 'n2e', sources: ['n2'], targets: ['top2']),
          ElkEdge(id: 's1e', sources: ['s1'], targets: ['bottom1']),
          ElkEdge(id: 's2e', sources: ['s2'], targets: ['bottom2']),
        ],
      ));

      final hub = res.nodesById['hub']!;
      final ports = {for (final p in hub.ports) p.id: p};
      for (final ids in [('n1', 'n2'), ('s1', 's2')]) {
        expect((ports[ids.$1]!.x - ports[ids.$2]!.x).abs(),
            greaterThanOrEqualTo(20),
            reason: '${ids.$1}/${ids.$2} need port width plus spacing');
      }
      expect(ports['n1']!.y + ports['n1']!.height, closeTo(0, 0.5));
      expect(ports['n2']!.y + ports['n2']!.height, closeTo(0, 0.5));
      expect(ports['s1']!.y, closeTo(hub.height, 0.5));
      expect(ports['s2']!.y, closeTo(hub.height, 0.5));

      for (final pair in [
        ('n1', 'n2', 'top1', 'top2'),
        ('s1', 's2', 'bottom1', 'bottom2'),
      ]) {
        final portOrder = ports[pair.$1]!.x.compareTo(ports[pair.$2]!.x);
        final nodeOrder = res.nodesById[pair.$3]!.y
            .compareTo(res.nodesById[pair.$4]!.y);
        expect(portOrder, nodeOrder,
            reason: '${pair.$1}/${pair.$2} must follow connected node order');
      }

      final anchors = <String, ElkPoint>{
        for (final edge in res.edges)
          edge.id: edge.sections.single.startPoint,
      };
      expect(anchors['n1e']!.x, isNot(closeTo(anchors['n2e']!.x, 0.5)));
      expect(anchors['s1e']!.x, isNot(closeTo(anchors['s2e']!.x, 0.5)));
    });

    test('external-port surrounding spacing expands nested layout bounds', () {
      ElkResult layout(double surrounding) => const ElkLayered().layout(ElkGraph(
            layoutOptions: ElkLayoutOptions(
              direction: .right,
              spacingPortsSurroundingTop: surrounding,
              spacingPortsSurroundingBottom: surrounding,
            ),
            children: [
              ElkNode(id: 'outside', width: 60, height: 30),
              ElkNode(id: 'outer', children: [
                ElkNode(id: 'leaf', width: 60, height: 30),
              ]),
            ],
            edges: [
              ElkEdge(id: 'cross', sources: ['outside'], targets: ['leaf']),
            ],
          ));

      final compact = layout(0);
      final spaced = layout(24);
      expect(spaced.nodesById['outer']!.height,
          greaterThan(compact.nodesById['outer']!.height));
      expect(spaced.height, greaterThan(compact.height));
      final edge = spaced.edges.singleWhere((e) => e.id == 'cross');
      expect(edge.sections.single.endPoint.x,
          closeTo(spaced.nodesById['leaf']!.x, 0.75),
          reason: 'fixed external port must still join the leaf route');
    });
  });
}

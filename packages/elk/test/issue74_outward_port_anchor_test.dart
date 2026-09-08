import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  for (final direction in ElkDirection.values) {
    for (final side in ElkPortSide.values) {
      test(
        '${direction.name} routes ${side.name} port from its outward face',
        () {
          final result = const ElkLayered().layout(
            ElkGraph(
              layoutOptions: ElkLayoutOptions(direction: direction),
              children: [
                ElkNode(
                  id: 'source',
                  width: 80,
                  height: 60,
                  ports: [ElkPort(id: 'out', side: side, width: 10, height: 8)],
                ),
                ElkNode(id: 'target', width: 60, height: 40),
              ],
              edges: [
                ElkEdge(id: 'edge', sources: ['out'], targets: ['target']),
              ],
            ),
          );
          final source = result.nodesById['source']!;
          final port = source.ports.single;
          final start = result.edges.single.sections.single.startPoint;

          switch (side) {
            case ElkPortSide.north:
              expect(start.y, closeTo(source.y + port.y, 0.001));
            case ElkPortSide.south:
              expect(start.y, closeTo(source.y + port.y + port.height, 0.001));
            case ElkPortSide.east:
              expect(start.x, closeTo(source.x + port.x + port.width, 0.001));
            case ElkPortSide.west:
              expect(start.x, closeTo(source.x + port.x, 0.001));
          }
        },
      );
    }
  }

  test('same-side self-loop uses both outward port faces', () {
    final result = const ElkLayered().layout(
      ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
        children: [
          ElkNode(
            id: 'node',
            width: 80,
            height: 60,
            ports: [
              ElkPort(id: 'out', side: ElkPortSide.north, width: 10, height: 8),
              ElkPort(id: 'in', side: ElkPortSide.north, width: 10, height: 8),
            ],
          ),
        ],
        edges: [
          ElkEdge(id: 'loop', sources: ['out'], targets: ['in']),
        ],
      ),
    );
    final node = result.nodesById['node']!;
    final ports = {for (final port in node.ports) port.id: port};
    final section = result.edges.single.sections.single;
    expect(section.startPoint.y, closeTo(node.y + ports['out']!.y, 0.001));
    expect(section.endPoint.y, closeTo(node.y + ports['in']!.y, 0.001));
  });
}

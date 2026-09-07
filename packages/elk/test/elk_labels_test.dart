import 'package:elk/elk.dart';
import 'package:test/test.dart';

ElkGraph labelled(ElkDirection direction) => ElkGraph(
  layoutOptions: ElkLayoutOptions(direction: direction, spacingLabelLabel: 3),
  children: const [
    ElkNode(
      id: 'a',
      width: 100,
      height: 70,
      labelPlacement: ElkNodeLabelPlacement.center,
      labels: [ElkLabel(text: 'Source', width: 40, height: 12)],
      ports: [
        ElkPort(
          id: 'out',
          side: ElkPortSide.east,
          labels: [ElkLabel(text: 'output', width: 24, height: 10)],
        ),
      ],
    ),
    ElkNode(
      id: 'b',
      width: 100,
      height: 70,
      labelPlacement: ElkNodeLabelPlacement.center,
      labels: [ElkLabel(text: 'Target', width: 40, height: 12)],
    ),
  ],
  edges: const [
    ElkEdge(
      id: 'e',
      sources: ['out'],
      targets: ['b'],
      thickness: 6,
      labels: [
        ElkLabel(text: 'center', width: 35, height: 12),
        ElkLabel(
          text: 'below',
          width: 30,
          height: 10,
          side: ElkLabelSide.below,
        ),
        ElkLabel(
          text: 'tail',
          width: 24,
          height: 10,
          placement: ElkEdgeLabelPlacement.tail,
        ),
        ElkLabel(
          text: 'head',
          width: 24,
          height: 10,
          placement: ElkEdgeLabelPlacement.head,
        ),
      ],
    ),
  ],
);

bool overlaps(ElkPositionedLabel a, ElkPositionedLabel b) =>
    a.x < b.x + b.width &&
    b.x < a.x + a.width &&
    a.y < b.y + b.height &&
    b.y < a.y + a.height;

void main() {
  test(
    'edge thickness increases label clearance by half the stroke change',
    () {
      double clearance(double thickness) {
        final result = const ElkLayered().layout(
          ElkGraph(
            layoutOptions: const ElkLayoutOptions(
              direction: ElkDirection.right,
            ),
            children: const [
              ElkNode(id: 'a', width: 80, height: 50),
              ElkNode(id: 'b', width: 80, height: 50),
            ],
            edges: [
              ElkEdge(
                id: 'e',
                sources: const ['a'],
                targets: const ['b'],
                thickness: thickness,
                labels: const [ElkLabel(text: 'center', width: 30, height: 10)],
              ),
            ],
          ),
        );
        final edge = result.edges.single,
            label = result.edges.single.labels.single;
        return edge.sections.single.startPoint.y - label.y - label.height;
      }

      expect(clearance(10) - clearance(0), closeTo(5, 0.001));
    },
  );
  test(
    'self-loop center labels follow routed loop and expand graph bounds',
    () {
      final result = const ElkLayered().layout(
        const ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
          children: [ElkNode(id: 'a', width: 80, height: 50)],
          edges: [
            ElkEdge(
              id: 'loop',
              sources: ['a'],
              targets: ['a'],
              labels: [ElkLabel(text: 'retry', width: 30, height: 10)],
            ),
          ],
        ),
      );
      final node = result.nodesById['a']!,
          label = result.edges.single.labels.single;
      expect(label.y + label.height, lessThan(node.y));
      expect(label.y, greaterThanOrEqualTo(0));
      expect(result.height, greaterThan(node.height));
    },
  );
  for (final direction in ElkDirection.values) {
    test('port label corners match elkjs for $direction', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: direction),
          children: [
            ElkNode(
              id: 'n',
              width: 100,
              height: 80,
              ports: [
                for (final side in ElkPortSide.values)
                  ElkPort(
                    id: side.name,
                    side: side,
                    width: 10,
                    height: 8,
                    labels: const [
                      ElkLabel(text: 'port', width: 24, height: 10),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
      for (final port in result.children.single.ports) {
        final label = port.labels.single;
        expect(label.x, closeTo(port.id == 'west' ? -25 : 11, 0.001));
        expect(label.y, closeTo(port.id == 'north' ? -11 : 9, 0.001));
      }
    });
    test('deep head/tail labels follow original endpoints for $direction', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: direction),
          children: const [
            ElkNode(id: 'outside', width: 60, height: 40),
            ElkNode(
              id: 'outer',
              children: [
                ElkNode(
                  id: 'inner',
                  children: [ElkNode(id: 'leaf', width: 50, height: 30)],
                ),
              ],
            ),
          ],
          edges: const [
            ElkEdge(
              id: 'e',
              sources: ['outside'],
              targets: ['leaf'],
              labels: [
                ElkLabel(
                  text: 'tail',
                  width: 16,
                  height: 8,
                  placement: ElkEdgeLabelPlacement.tail,
                ),
                ElkLabel(
                  text: 'head',
                  width: 16,
                  height: 8,
                  placement: ElkEdgeLabelPlacement.head,
                ),
              ],
            ),
          ],
        ),
      );
      final edge = result.edges.single,
          route = result.edges.single.sections.single;
      double distance(ElkPositionedLabel l, ElkPoint p) =>
          (l.x + l.width / 2 - p.x).abs() + (l.y + l.height / 2 - p.y).abs();
      final head = edge.labels.singleWhere((l) => l.text == 'head'),
          tail = edge.labels.singleWhere((l) => l.text == 'tail');
      expect(
        distance(head, route.endPoint),
        lessThan(distance(head, route.startPoint)),
      );
      expect(
        distance(tail, route.startPoint),
        lessThan(distance(tail, route.endPoint)),
      );
    });
  }
  for (final direction in ElkDirection.values) {
    test(
      '$direction retains node/port labels and places edge labels by role',
      () {
        final result = const ElkLayered().layout(labelled(direction));
        final a = result.nodesById['a']!, b = result.nodesById['b']!;
        expect(a.labels.single.text, 'Source');
        expect(a.labels.single.x, closeTo(30, 0.001));
        expect(a.labels.single.y, closeTo(29, 0.001));
        expect(b.labels.single.text, 'Target');
        final port = a.ports.single;
        expect(port.labels.single.text, 'output');
        expect(port.x + port.labels.single.x, greaterThanOrEqualTo(a.width));
        final edge = result.edges.single;
        expect(
          edge.labels.map((l) => l.text),
          unorderedEquals(['center', 'below', 'tail', 'head']),
        );
        final labels = {for (final l in edge.labels) l.text: l};
        for (final label in edge.labels) {
          expect(
            [
              label.x,
              label.y,
              label.width,
              label.height,
            ].every((v) => v.isFinite),
            isTrue,
          );
          expect(label.x, greaterThanOrEqualTo(0));
          expect(label.y, greaterThanOrEqualTo(0));
          expect(label.x + label.width, lessThanOrEqualTo(result.width));
          expect(label.y + label.height, lessThanOrEqualTo(result.height));
          for (final node in result.nodesById.values) {
            expect(
              label.x < node.x + node.width &&
                  label.x + label.width > node.x &&
                  label.y < node.y + node.height &&
                  label.y + label.height > node.y,
              isFalse,
              reason:
                  '${label.text} must not overlap ${node.id} for $direction',
            );
          }
        }
        expect(overlaps(labels['center']!, labels['below']!), isFalse);
        double distance(ElkPositionedLabel l, ElkPoint p) =>
            (l.x + l.width / 2 - p.x).abs() + (l.y + l.height / 2 - p.y).abs();
        expect(
          distance(labels['tail']!, edge.sections.single.startPoint),
          lessThan(distance(labels['tail']!, edge.sections.single.endPoint)),
        );
        expect(
          distance(labels['head']!, edge.sections.single.endPoint),
          lessThan(distance(labels['head']!, edge.sections.single.startPoint)),
        );
      },
    );
  }
  test('elkjs JSON label roles and spacing reach layout output', () {
    final input = ElkGraph.fromJson({
      'id': 'root',
      'layoutOptions': {'elk.direction': 'RIGHT', 'elk.spacing.edgeLabel': 8},
      'children': [
        {'id': 'a', 'width': 60, 'height': 40},
        {'id': 'b', 'width': 60, 'height': 40},
      ],
      'edges': [
        {
          'id': 'e',
          'sources': ['a'],
          'targets': ['b'],
          'labels': [
            {
              'text': 'head',
              'width': 20,
              'height': 10,
              'layoutOptions': {'elk.edgeLabels.placement': 'HEAD'},
            },
            {
              'text': 'below',
              'width': 20,
              'height': 10,
              'layoutOptions': {
                'elk.layered.edgeLabels.sideSelection': 'ALWAYS_DOWN',
              },
            },
          ],
        },
      ],
    });
    final result = const ElkLayered().layout(input);
    expect(
      result.edges.single.labels.map((l) => l.text),
      unorderedEquals(['head', 'below']),
    );
    final head = result.edges.single.labels.singleWhere(
      (l) => l.text == 'head',
    );
    expect(head.x + head.width, lessThan(result.nodesById['b']!.x));
  });
}

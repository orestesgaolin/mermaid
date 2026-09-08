import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  group('measured output bounds', () {
    for (final direction in ElkDirection.values) {
      test('contain an unlabeled root self-loop for $direction', () {
        final result = const ElkLayered().layout(
          ElkGraph(
            layoutOptions: ElkLayoutOptions(direction: direction),
            children: [ElkNode(id: 'node', width: 80, height: 50)],
            edges: [
              ElkEdge(
                id: 'loop',
                sources: ['node'],
                targets: ['node'],
                thickness: 6,
              ),
            ],
          ),
        );

        final node = result.nodesById['node']!;
        final edge = result.edges.single;
        expect(_onBorder(edge.sections.single.startPoint, node), isTrue);
        expect(_onBorder(edge.sections.single.endPoint, node), isTrue);
        expect(
          edge.sections.single.points,
          everyElement(_strokeInsideResult(result, 3)),
        );
        expect(result.height, greaterThan(node.height));
      });

      test('contain nonzero ports on every side for $direction', () {
        final result = const ElkLayered().layout(
          ElkGraph(
            layoutOptions: ElkLayoutOptions(direction: direction),
            children: [
              ElkNode(
                id: 'node',
                width: 100,
                height: 80,
                ports: [
                  ElkPort(
                    id: 'north',
                    side: ElkPortSide.north,
                    width: 10,
                    height: 8,
                  ),
                  ElkPort(
                    id: 'south',
                    side: ElkPortSide.south,
                    width: 10,
                    height: 8,
                  ),
                  ElkPort(
                    id: 'east',
                    side: ElkPortSide.east,
                    width: 10,
                    height: 8,
                  ),
                  ElkPort(
                    id: 'west',
                    side: ElkPortSide.west,
                    width: 10,
                    height: 8,
                  ),
                ],
              ),
            ],
          ),
        );

        final node = result.nodesById['node']!;
        for (final port in node.ports) {
          expect(
            _rectInsideResult(
              result,
              node.x + port.x,
              node.y + port.y,
              port.width,
              port.height,
            ),
            isTrue,
            reason: '${port.id} must be inside $direction output bounds',
          );
        }
      });
    }

    for (final rootDirection in ElkDirection.values) {
      for (final childDirection in ElkDirection.values) {
        test(
          'contain nested routes and ports for $rootDirection/$childDirection',
          () {
            final result = const ElkLayered().layout(
              ElkGraph(
                layoutOptions: ElkLayoutOptions(direction: rootDirection),
                children: [
                  ElkNode(
                    id: 'cluster',
                    layoutOptions: ElkLayoutOptions(direction: childDirection),
                    children: [
                      ElkNode(
                        id: 'node',
                        width: 80,
                        height: 50,
                        ports: [
                          ElkPort(
                            id: 'north',
                            side: ElkPortSide.north,
                            width: 10,
                            height: 8,
                          ),
                          ElkPort(
                            id: 'south',
                            side: ElkPortSide.south,
                            width: 10,
                            height: 8,
                          ),
                          ElkPort(
                            id: 'east',
                            side: ElkPortSide.east,
                            width: 10,
                            height: 8,
                          ),
                          ElkPort(
                            id: 'west',
                            side: ElkPortSide.west,
                            width: 10,
                            height: 8,
                          ),
                        ],
                      ),
                    ],
                    edges: [
                      ElkEdge(
                        id: 'loop',
                        sources: ['node'],
                        targets: ['node'],
                        thickness: 4,
                        labels: [ElkLabel(text: 'loop', width: 24, height: 9)],
                      ),
                    ],
                  ),
                ],
              ),
            );

            final cluster = result.nodesById['cluster']!;
            final node = result.nodesById['node']!;
            final edge = result.edges.single;
            expect(_onBorder(edge.sections.single.startPoint, node), isTrue);
            expect(_onBorder(edge.sections.single.endPoint, node), isTrue);
            for (final point in edge.sections.single.points) {
              expect(_pointStrokeInsideResult(result, point, 2), isTrue);
              expect(_strokeInsideNode(point, cluster, 2), isTrue);
            }
            for (final label in edge.labels) {
              expect(_labelRectInsideResult(result, label), isTrue);
              expect(
                _rectInsideNode(
                  label.x,
                  label.y,
                  label.width,
                  label.height,
                  cluster,
                ),
                isTrue,
              );
            }
            for (final port in node.ports) {
              final x = node.x + port.x;
              final y = node.y + port.y;
              expect(
                _rectInsideResult(result, x, y, port.width, port.height),
                isTrue,
              );
              expect(
                _rectInsideNode(x, y, port.width, port.height, cluster),
                isTrue,
              );
            }
          },
        );
      }
    }

    test('contain the full stroke of an unlabeled cross-hierarchy edge', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
          children: [
            ElkNode(
              id: 'cluster',
              layoutOptions: ElkLayoutOptions(direction: ElkDirection.left),
              children: [ElkNode(id: 'inside', width: 40, height: 24)],
            ),
            ElkNode(id: 'outside', width: 40, height: 24),
          ],
          edges: [
            ElkEdge(
              id: 'cross',
              sources: ['inside'],
              targets: ['outside'],
              thickness: 30,
            ),
          ],
        ),
      );

      final edge = result.edges.single;
      final inside = result.nodesById['inside']!;
      final outside = result.nodesById['outside']!;
      expect(_onBorder(edge.sections.single.startPoint, inside), isTrue);
      expect(_onBorder(edge.sections.single.endPoint, outside), isTrue);
      expect(
        edge.sections.single.points,
        everyElement(_strokeInsideResult(result, 15)),
      );
    });
  });
}

Matcher _strokeInsideResult(ElkResult result, double halfThickness) =>
    predicate<ElkPoint>(
      (point) => _pointStrokeInsideResult(result, point, halfThickness),
      'stroke extent inside ${result.width} x ${result.height}',
    );

bool _pointStrokeInsideResult(
  ElkResult result,
  ElkPoint point,
  double halfThickness,
) =>
    point.x - halfThickness >= 0 &&
    point.y - halfThickness >= 0 &&
    point.x + halfThickness <= result.width &&
    point.y + halfThickness <= result.height;

bool _labelRectInsideResult(ElkResult result, ElkPositionedLabel label) =>
    _rectInsideResult(result, label.x, label.y, label.width, label.height);

bool _rectInsideResult(
  ElkResult result,
  double x,
  double y,
  double width,
  double height,
) =>
    x >= 0 &&
    y >= 0 &&
    x + width <= result.width &&
    y + height <= result.height;

bool _strokeInsideNode(
  ElkPoint point,
  ElkPositionedNode node,
  double halfThickness,
) =>
    point.x - halfThickness >= node.x &&
    point.y - halfThickness >= node.y &&
    point.x + halfThickness <= node.x + node.width &&
    point.y + halfThickness <= node.y + node.height;

bool _rectInsideNode(
  double x,
  double y,
  double width,
  double height,
  ElkPositionedNode node,
) =>
    x >= node.x &&
    y >= node.y &&
    x + width <= node.x + node.width &&
    y + height <= node.y + node.height;

bool _onBorder(ElkPoint point, ElkPositionedNode node) {
  const epsilon = 1e-6;
  final withinX =
      point.x >= node.x - epsilon && point.x <= node.x + node.width + epsilon;
  final withinY =
      point.y >= node.y - epsilon && point.y <= node.y + node.height + epsilon;
  return (withinY &&
          ((point.x - node.x).abs() <= epsilon ||
              (point.x - node.x - node.width).abs() <= epsilon)) ||
      (withinX &&
          ((point.y - node.y).abs() <= epsilon ||
              (point.y - node.y - node.height).abs() <= epsilon));
}

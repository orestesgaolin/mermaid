import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  const spacing = 20.0;

  group('nodeSelfLoop starts beyond nonzero port rectangles', () {
    for (final direction in ElkDirection.values) {
      for (final side in ElkPortSide.values) {
        test('${direction.name} ${side.name}', () {
          final result = _layout(direction, side, side, spacing);
          _expectClearance(result, side, spacing);
        });
      }
    }
  });

  for (final direction in ElkDirection.values) {
    test('${direction.name} adjacent north/east sides', () {
      final result = _layout(
        direction,
        ElkPortSide.north,
        ElkPortSide.east,
        spacing,
      );
      _expectClearance(result, ElkPortSide.north, spacing);
      _expectClearance(result, ElkPortSide.east, spacing);
    });

    test('${direction.name} opposing north/south sides', () {
      final result = _layout(
        direction,
        ElkPortSide.north,
        ElkPortSide.south,
        spacing,
      );
      _expectClearance(result, ElkPortSide.north, spacing);
      _expectClearance(result, ElkPortSide.south, spacing);
    });
  }
}

ElkResult _layout(
  ElkDirection direction,
  ElkPortSide sourceSide,
  ElkPortSide targetSide,
  double spacing,
) {
  return const ElkLayered().layout(
    ElkGraph.fromJson({
      'id': 'root',
      'layoutOptions': {
        'elk.algorithm': 'layered',
        'elk.direction': direction.name.toUpperCase(),
        'elk.edgeRouting': 'ORTHOGONAL',
        'elk.spacing.nodeSelfLoop': spacing,
      },
      'children': [
        {
          'id': 'node',
          'width': 80,
          'height': 60,
          'layoutOptions': {'elk.portConstraints': 'FIXED_SIDE'},
          'ports': [
            {
              'id': 'out',
              'width': 8,
              'height': 8,
              'layoutOptions': {'elk.port.side': sourceSide.name.toUpperCase()},
            },
            {
              'id': 'in',
              'width': 8,
              'height': 8,
              'layoutOptions': {'elk.port.side': targetSide.name.toUpperCase()},
            },
          ],
        },
      ],
      'edges': [
        {
          'id': 'loop',
          'sources': ['out'],
          'targets': ['in'],
          'labels': [
            {'text': 'retry', 'width': 30, 'height': 12},
          ],
        },
      ],
    }),
  );
}

void _expectClearance(ElkResult result, ElkPortSide side, double expected) {
  final node = result.nodesById['node']!;
  final points = result.edges.single.sections.single.points;
  final ports = node.ports.where((port) {
    final onSide = switch (side) {
      ElkPortSide.north => port.y + port.height <= 0,
      ElkPortSide.south => port.y >= node.height,
      ElkPortSide.east => port.x >= node.width,
      ElkPortSide.west => port.x + port.width <= 0,
    };
    return onSide;
  });
  expect(ports, isNotEmpty);

  final outwardFace = switch (side) {
    ElkPortSide.north =>
      node.y + ports.map((port) => port.y).reduce((a, b) => a < b ? a : b),
    ElkPortSide.south =>
      node.y +
          ports
              .map((port) => port.y + port.height)
              .reduce((a, b) => a > b ? a : b),
    ElkPortSide.east =>
      node.x +
          ports
              .map((port) => port.x + port.width)
              .reduce((a, b) => a > b ? a : b),
    ElkPortSide.west =>
      node.x + ports.map((port) => port.x).reduce((a, b) => a < b ? a : b),
  };
  final routeFace = switch (side) {
    ElkPortSide.north =>
      points.map((point) => point.y).reduce((a, b) => a < b ? a : b),
    ElkPortSide.south =>
      points.map((point) => point.y).reduce((a, b) => a > b ? a : b),
    ElkPortSide.east =>
      points.map((point) => point.x).reduce((a, b) => a > b ? a : b),
    ElkPortSide.west =>
      points.map((point) => point.x).reduce((a, b) => a < b ? a : b),
  };
  final clearance = switch (side) {
    ElkPortSide.north || ElkPortSide.west => outwardFace - routeFace,
    ElkPortSide.south || ElkPortSide.east => routeFace - outwardFace,
  };
  expect(clearance, closeTo(expected, 0.001));

  final bounds = (0.0, 0.0, result.width, result.height);
  for (final point in points) {
    expect(point.x, inInclusiveRange(bounds.$1, bounds.$3));
    expect(point.y, inInclusiveRange(bounds.$2, bounds.$4));
  }
  expect(result.edges.single.labels.single.text, 'retry');
}

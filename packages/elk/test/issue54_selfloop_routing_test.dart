import 'package:elk/src/layered/intermediate_selfloops.dart';
import 'package:elk/src/layered/intermediate_sizing.dart';
import 'package:elk/src/layered/lgraph.dart';
import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  test('non-fixed nodes grow to contain labels and port groups', () {
    final graph = LGraph()..setProperty(spacingPortPort, 8.0);
    final layer = Layer(graph);
    graph.layers.add(layer);
    final node = LNode(graph)
      ..size.x = 20
      ..size.y = 10
      ..setProperty(nodeSizeFixed, false);
    layer.nodes.add(node);
    node.labels.add(
      LLabel('large')
        ..size.x = 90
        ..size.y = 25,
    );
    for (var i = 0; i < 3; i++) {
      node.ports.add(
        LPort(node)
          ..side = PortSide.east
          ..size.y = 12,
      );
    }

    LabelAndNodeSizeProcessor().process(graph);

    expect(node.size.x, greaterThanOrEqualTo(90));
    expect(node.size.y, greaterThanOrEqualTo(52));
    expect(
      node.ports.last.position.y + node.ports.last.size.y,
      lessThanOrEqualTo(node.size.y),
    );
  });

  test('ELK JSON exposes non-fixed sizing and straightness strategy', () {
    final node = ElkNode.fromJson({
      'id': 'n',
      'layoutOptions': {
        'elk.nodeSize.constraints': 'NODE_LABELS PORTS MINIMUM_SIZE'
      },
    });
    final options = ElkLayoutOptions.fromElkJson({
      'elk.layered.nodePlacement.bk.edgeStraightening': 'IMPROVE_STRAIGHTNESS',
    });
    expect(node.fixedSize, isFalse);
    expect(node.sizeForLabels, isTrue);
    expect(node.sizeForPorts, isTrue);
    expect(node.preserveMinimumSize, isTrue);
    expect(options.improveStraightness, isTrue);
  });

  test('public layout returns the grown non-fixed node size', () {
    final result = const ElkLayered().layout(const ElkGraph(children: [
      ElkNode(
        id: 'n',
        width: 20,
        height: 10,
        fixedSize: false,
        labels: [ElkLabel(text: 'wide', width: 90, height: 25)],
        ports: [
          ElkPort(id: 'p1', side: ElkPortSide.east, height: 12),
          ElkPort(id: 'p2', side: ElkPortSide.east, height: 12),
          ElkPort(id: 'p3', side: ElkPortSide.east, height: 12),
        ],
      ),
    ]));
    final node = result.nodesById['n']!;
    expect(node.width, greaterThanOrEqualTo(90));
    expect(node.height, greaterThanOrEqualTo(56));
  });

  for (final direction in ElkDirection.values) {
    test('non-fixed sizing contains stacked labels in ${direction.name}', () {
      final nodeInput = ElkNode.fromJson({
        'id': 'n',
        'layoutOptions': {'elk.nodeSize.constraints': 'NODE_LABELS'},
        'labels': [
          {'text': 'first', 'width': 70, 'height': 20},
          {'text': 'second', 'width': 80, 'height': 20},
        ],
      });
      final result = const ElkLayered().layout(ElkGraph(
        layoutOptions: const ElkLayoutOptions(spacingLabelLabel: 3),
        children: [
          nodeInput,
        ],
      ).copyWithDirection(direction));
      final node = result.nodesById['n']!;
      expect(node.width, greaterThanOrEqualTo(80));
      expect(node.height, greaterThanOrEqualTo(40));
      for (final label in node.labels) {
        expect(label.x, inInclusiveRange(0, node.width - label.width));
        expect(label.y, inInclusiveRange(0, node.height - label.height));
      }
    });
  }

  test('IMPROVE_STRAIGHTNESS changes the active elkjs oracle fixture', () {
    const children = [
      ElkNode(id: 'n0', width: 52, height: 32),
      ElkNode(id: 'n1', width: 69, height: 40),
      ElkNode(id: 'n2', width: 87, height: 38),
      ElkNode(id: 'n3', width: 47, height: 67),
      ElkNode(id: 'n4', width: 76, height: 27),
      ElkNode(id: 'n5', width: 87, height: 75),
      ElkNode(id: 'n6', width: 67, height: 25),
      ElkNode(id: 'n7', width: 42, height: 80),
    ];
    const edges = [
      ElkEdge(id: 'e03', sources: ['n0'], targets: ['n3']),
      ElkEdge(id: 'e14', sources: ['n1'], targets: ['n4']),
      ElkEdge(id: 'e16', sources: ['n1'], targets: ['n6']),
      ElkEdge(id: 'e23', sources: ['n2'], targets: ['n3']),
      ElkEdge(id: 'e24', sources: ['n2'], targets: ['n4']),
      ElkEdge(id: 'e34', sources: ['n3'], targets: ['n4']),
      ElkEdge(id: 'e35', sources: ['n3'], targets: ['n5']),
      ElkEdge(id: 'e36', sources: ['n3'], targets: ['n6']),
      ElkEdge(id: 'e46', sources: ['n4'], targets: ['n7']),
      ElkEdge(id: 'e57', sources: ['n5'], targets: ['n7']),
    ];
    var changed = false;
    var straightened = false;
    for (final alignment in ElkFixedAlignment.values) {
      final regular = const ElkLayered().layout(ElkGraph(
        layoutOptions: ElkLayoutOptions(
          direction: ElkDirection.right, fixedAlignment: alignment),
        children: children, edges: edges));
      final improved = const ElkLayered().layout(ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: ElkDirection.right,
          fixedAlignment: alignment, improveStraightness: true),
        children: children, edges: edges));
      changed |= '${[for (final n in regular.children) (n.x, n.y)]}' !=
          '${[for (final n in improved.children) (n.x, n.y)]}';
      int straight(ElkResult result) => result.edges.where((edge) {
        final points = edge.sections.single.points;
        return points.every(
          (point) => (point.y - points.first.y).abs() < 0.01,
        );
      }).length;
      straightened |= straight(improved) > straight(regular);
      for (var i = 0; i < improved.children.length; i++) {
        for (var j = i + 1; j < improved.children.length; j++) {
          final a = improved.children[i], b = improved.children[j];
          expect(a.x + a.width <= b.x || b.x + b.width <= a.x ||
              a.y + a.height <= b.y || b.y + b.height <= a.y, isTrue);
        }
      }
    }
    expect(changed, isTrue);
    expect(straightened, isTrue);
  });

  for (final direction in ElkDirection.values) {
    test('node-id self-loop defaults to NORTH in ${direction.name}', () {
      final result = const ElkLayered().layout(ElkGraph(
        children: [ElkNode(id: 'n', width: 80, height: 40)],
        edges: [ElkEdge(id: 'loop', sources: ['n'], targets: ['n'])],
      ).copyWithDirection(direction));
      final node = result.nodesById['n']!;
      final section = result.edges.single.sections.single;
      expect(section.points.every((point) => point.y <= node.y), isTrue,
          reason: '${direction.name}: ${section.points}, node y=${node.y}');
    });

    test('public layout routes multi-side self-loops in ${direction.name}', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(),
          children: [
            ElkNode(
              id: 'n',
              width: 120,
              height: 70,
              ports: [
                ElkPort(id: 'north', side: ElkPortSide.north),
                ElkPort(id: 'east', side: ElkPortSide.east),
                ElkPort(id: 'south', side: ElkPortSide.south),
                ElkPort(id: 'west', side: ElkPortSide.west),
              ],
            ),
          ],
          edges: [
            ElkEdge(id: 'corner', sources: ['north'], targets: ['east']),
            ElkEdge(id: 'opposing', sources: ['north'], targets: ['south']),
            ElkEdge(id: 'west', sources: ['west'], targets: ['west']),
          ],
        ).copyWithDirection(direction),
      );
      final node = result.nodesById['n']!;
      expect(result.edges, hasLength(3));
      for (final edge in result.edges) {
        expect(edge.sections.single.bendPoints, isNotEmpty);
        expect(
          edge.sections.single.bendPoints.every(
            (point) =>
                point.x <= node.x ||
                point.x >= node.x + node.width ||
                point.y <= node.y ||
                point.y >= node.y + node.height,
          ),
          isTrue,
          reason:
              '${edge.id}: node=(${node.x},${node.y},${node.width},${node.height}) '
              'bends=${edge.sections.single.bendPoints}',
        );
      }
    });
  }

  test('routes same-side loops on every side with configured spacing', () {
    final graph = LGraph()
      ..setProperty(selfLoopNodeSpacing, 17.0)
      ..setProperty(selfLoopEdgeSpacing, 13.0);
    final node = LNode(graph)
      ..size.x = 100
      ..size.y = 60;
    graph.layerlessNodes.add(node);

    for (final side in [
      PortSide.north,
      PortSide.east,
      PortSide.south,
      PortSide.west,
    ]) {
      _loop(node, side, side, '${side.name}0');
      _loop(node, side, side, '${side.name}1');
    }

    SelfLoopPreProcessor().process(graph);
    expect(node.margin.top, 30);
    expect(node.margin.right, 30);
    expect(node.margin.bottom, 30);
    expect(node.margin.left, 30);
    SelfLoopRouter().process(graph);
    SelfLoopPostProcessor().process(graph);

    final edges = node.outgoingEdges.toList();
    for (var i = 0; i < edges.length; i += 2) {
      final first = edges[i].bendPoints.points;
      final second = edges[i + 1].bendPoints.points;
      expect(first, hasLength(2));
      final side = edges[i].source!.side;
      final a = side == PortSide.north || side == PortSide.south
          ? first.first.y
          : first.first.x;
      final b = side == PortSide.north || side == PortSide.south
          ? second.first.y
          : second.first.x;
      expect((a - b).abs(), 13);
    }
  });

  test('corner and opposing loops stay outside the node', () {
    final graph = LGraph()..setProperty(selfLoopNodeSpacing, 15.0);
    final node = LNode(graph)
      ..size.x = 100
      ..size.y = 60;
    graph.layerlessNodes.add(node);
    final corner = _loop(node, PortSide.north, PortSide.east, 'corner');
    final opposing = _loop(node, PortSide.north, PortSide.south, 'opposing');

    SelfLoopPreProcessor().process(graph);
    SelfLoopRouter().process(graph);
    SelfLoopPostProcessor().process(graph);

    expect(corner.bendPoints.points, hasLength(3));
    expect(opposing.bendPoints.points, hasLength(4));
    for (final edge in [corner, opposing]) {
      for (final point in edge.bendPoints.points) {
        expect(
          point.x <= 0 || point.x >= 100 || point.y <= 0 || point.y >= 60,
          isTrue,
        );
      }
    }
  });
}

extension on ElkGraph {
  ElkGraph copyWithDirection(ElkDirection direction) => ElkGraph(
    id: id,
    layoutOptions: ElkLayoutOptions(direction: direction),
    children: children,
    edges: edges,
  );
}

LEdge _loop(LNode node, PortSide sourceSide, PortSide targetSide, String id) {
  final source = LPort(node)..side = sourceSide;
  final target = LPort(node)..side = targetSide;
  _position(source, sourceSide, node);
  _position(target, targetSide, node);
  node.ports.addAll([source, target]);
  final edge = LEdge()..identifier = id;
  edge.source = source;
  edge.target = target;
  return edge;
}

void _position(LPort port, PortSide side, LNode node) {
  switch (side) {
    case PortSide.north:
      port.position.x = 30;
    case PortSide.south:
      port.position
        ..x = 70
        ..y = node.size.y;
    case PortSide.east:
      port.position
        ..x = node.size.x
        ..y = 20;
    case PortSide.west:
      port.position.y = 40;
    case PortSide.undefined:
      break;
  }
}

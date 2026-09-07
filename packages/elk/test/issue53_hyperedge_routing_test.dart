import 'package:elk/elk.dart';
import 'package:elk/src/layered/intermediate_edges.dart';
import 'package:elk/src/layered/lgraph.dart';
import 'package:elk/src/layered/p5_orthogonal_routing.dart';
import 'package:elk/src/layered/p3_layer_sweep_crossing_minimizer.dart';
import 'package:test/test.dart';

void main() {
  test('crossing minimizer preserves in-layer successor constraint', () {
    final graph = LGraph();
    final left = Layer(graph);
    final right = Layer(graph);
    graph.layers.addAll([left, right]);
    final top = _node(graph, left, 0, 0)..identifier = 'top';
    final bottom = _node(graph, left, 0, 40)..identifier = 'bottom';
    final first = _node(graph, right, 0, 0)..identifier = 'first';
    final second = _node(graph, right, 0, 40)..identifier = 'second';
    first.setProperty(inLayerSuccessors, [second]);
    LEdge()
      ..source = _port(top, PortSide.east, 0)
      ..target = _port(second, PortSide.west, 0);
    LEdge()
      ..source = _port(bottom, PortSide.east, 0)
      ..target = _port(first, PortSide.west, 0);

    LayerSweepCrossingMinimizer().process(graph);

    expect(right.nodes.map((node) => node.identifier), ['first', 'second']);
  });

  test('barycenter associate inherits its partner edge weight', () {
    final graph = LGraph();
    final left = Layer(graph);
    final right = Layer(graph);
    graph.layers.addAll([left, right]);
    final top = _node(graph, left, 0, 0);
    final bottom = _node(graph, left, 0, 40);
    final connected = _node(graph, right, 0, 0)..identifier = 'connected';
    final associate = _node(graph, right, 0, 20)..identifier = 'associate';
    final lower = _node(graph, right, 0, 40)..identifier = 'lower';
    associate.setProperty(barycenterAssociates, [connected]);
    LEdge()
      ..source = _port(top, PortSide.east, 0)
      ..target = _port(connected, PortSide.west, 0);
    LEdge()
      ..source = _port(bottom, PortSide.east, 0)
      ..target = _port(lower, PortSide.west, 0);

    LayerSweepCrossingMinimizer().process(graph);

    final identifiers = right.nodes.map((node) => node.identifier).toList();
    expect(
      (identifiers.indexOf('connected') - identifiers.indexOf('associate'))
          .abs(),
      1,
    );
    expect(
      identifiers.indexOf('associate'),
      lessThan(identifiers.indexOf('lower')),
    );
  });

  test('orthogonal hyperedge emits one deduplicated junction point', () {
    final graph = LGraph();
    final left = Layer(graph);
    final right = Layer(graph);
    graph.layers.addAll([left, right]);
    final source = _node(graph, left, 0, 0);
    final targets = [
      _node(graph, right, 0, 0),
      _node(graph, right, 0, 20),
      _node(graph, right, 0, 40),
    ];
    final sourcePort = _port(source, PortSide.east, 20);
    final edges = <LEdge>[];
    for (final target in targets) {
      final edge = LEdge()
        ..source = sourcePort
        ..target = _port(target, PortSide.west, 0);
      edges.add(edge);
    }

    OrthogonalRoutingGenerator().process(graph);

    final points = [
      for (final edge in edges) ...?edge.getProperty(junctionPoints)?.points,
    ];
    expect(points, hasLength(1));
    expect(points.single.y, 20);
    expect(edges.where((edge) => edge.bendPoints.length == 2), hasLength(2));
  });

  test('critical dependency cycle splits a segment instead of dropping it', () {
    final graph = LGraph();
    final left = Layer(graph);
    final right = Layer(graph);
    graph.layers.addAll([left, right]);
    final sourceA = _node(graph, left, 0, 0);
    final sourceB = _node(graph, left, 0, 10);
    final targetA = _node(graph, right, 0, 10);
    final targetB = _node(graph, right, 0, 0);
    final edgeA = LEdge()
      ..source = _port(sourceA, PortSide.east, 0)
      ..target = _port(targetA, PortSide.west, 0);
    final edgeB = LEdge()
      ..source = _port(sourceB, PortSide.east, 0)
      ..target = _port(targetB, PortSide.west, 0);

    OrthogonalRoutingGenerator().process(graph);

    expect(
      [edgeA.bendPoints.length, edgeB.bendPoints.length],
      contains(4),
      reason: 'one trunk is split around the critical overlap cycle',
    );
    for (final edge in [edgeA, edgeB]) {
      expect(edge.bendPoints.points.every((point) => point.x.isFinite), isTrue);
    }
  });

  test('long-edge join merges and deduplicates segment junctions', () {
    final graph = LGraph();
    final layers = [Layer(graph), Layer(graph), Layer(graph)];
    graph.layers.addAll(layers);
    final source = _node(graph, layers[0], 0, 0);
    final target = _node(graph, layers[2], 100, 20);
    final edge = LEdge()
      ..source = _port(source, PortSide.east, 0)
      ..target = _port(target, PortSide.west, 0);
    edge.setProperty(junctionPoints, KVectorChain()..add(KVector(20, 10)));

    LongEdgeSplitter().process(graph);
    final dummy = layers[1].nodes.single;
    final continuation = dummy.ports
        .singleWhere((port) => port.side == PortSide.east)
        .outgoingEdges
        .single;
    expect(continuation.getProperty(junctionPoints), isNull);
    continuation.setProperty(
      junctionPoints,
      KVectorChain()
        ..add(KVector(20, 10))
        ..add(KVector(70, 15)),
    );

    LongEdgeJoiner().process(graph);

    expect(edge.target?.node, target);
    expect(
      edge
          .getProperty(junctionPoints)
          ?.points
          .map((point) => (point.x, point.y))
          .toList(),
      [(20, 10), (70, 15)],
    );
  });

  group('public hyperedge layout', () {
    for (final direction in ElkDirection.values) {
      test('restores one multi-endpoint edge for $direction', () {
        final result = const ElkLayered().layout(
          ElkGraph(
            layoutOptions: ElkLayoutOptions(direction: direction),
            children: [
              ElkNode(id: 's1', width: 60, height: 30),
              ElkNode(id: 's2', width: 60, height: 30),
              ElkNode(id: 't1', width: 60, height: 30),
              ElkNode(id: 't2', width: 60, height: 30),
            ],
            edges: [
              ElkEdge(
                id: 'hyper',
                sources: ['s1', 's2'],
                targets: ['t1', 't2'],
                labels: [ElkLabel(text: 'shared', width: 36, height: 12)],
              ),
            ],
          ),
        );

        final edge = result.edges.single;
        expect(edge.id, 'hyper');
        expect(edge.sections, hasLength(4));
        expect(edge.labels.map((label) => label.text), ['shared']);
        expect(edge.junctionPoints, isNotEmpty);
        expect(
          result.children.expand((node) => node.ports),
          isEmpty,
          reason: 'synthetic expansion ports must not leak into the result',
        );
        final sources = [result.nodesById['s1']!, result.nodesById['s2']!];
        final targets = [result.nodesById['t1']!, result.nodesById['t2']!];
        for (final section in edge.sections) {
          expect(
            sources.any((node) => _onBorder(section.startPoint, node)),
            isTrue,
          );
          expect(
            targets.any((node) => _onBorder(section.endPoint, node)),
            isTrue,
          );
          expect(section.points, hasLength(greaterThanOrEqualTo(2)));
          for (var index = 1; index < section.points.length; index++) {
            final previous = section.points[index - 1];
            final current = section.points[index];
            expect(
              previous.x == current.x || previous.y == current.y,
              isTrue,
              reason: '$direction route segment must be orthogonal',
            );
          }
        }
        expect(
          edge.junctionPoints.map((point) => (point.x, point.y)).toSet(),
          hasLength(edge.junctionPoints.length),
        );
      });
    }

    test('restores a cross-hierarchy hyperedge with absolute routes', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          children: [
            ElkNode(
              id: 'left',
              children: [
                ElkNode(id: 's1', width: 60, height: 30),
                ElkNode(id: 's2', width: 60, height: 30),
              ],
            ),
            ElkNode(
              id: 'right',
              children: [
                ElkNode(id: 't1', width: 60, height: 30),
                ElkNode(id: 't2', width: 60, height: 30),
              ],
            ),
          ],
          edges: [
            ElkEdge(
              id: 'nested-hyper',
              sources: ['s1', 's2'],
              targets: ['t1', 't2'],
            ),
          ],
        ),
      );

      final edge = result.edges.single;
      expect(edge.id, 'nested-hyper');
      expect(edge.sections, hasLength(4));
      expect(edge.junctionPoints, isNotEmpty);
      for (final section in edge.sections) {
        for (final point in section.points) {
          expect(point.x, inInclusiveRange(0, result.width));
          expect(point.y, inInclusiveRange(0, result.height));
        }
      }
    });
  });

  group('public crossing constraints', () {
    test('resolves node-ID successor references through ElkLayered', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
          children: [
            ElkNode(id: 'top', width: 40, height: 20),
            ElkNode(id: 'bottom', width: 40, height: 20),
            ElkNode(
              id: 'first',
              width: 40,
              height: 20,
              inLayerSuccessors: ['second'],
            ),
            ElkNode(id: 'second', width: 40, height: 20),
          ],
          edges: [
            ElkEdge(id: 'a', sources: ['top'], targets: ['second']),
            ElkEdge(id: 'b', sources: ['bottom'], targets: ['first']),
          ],
        ),
      );

      expect(
        result.nodesById['first']!.y,
        lessThan(result.nodesById['second']!.y),
      );
    });

    test('resolves node-ID barycenter associates through ElkLayered', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
          children: [
            ElkNode(id: 'top', width: 40, height: 20),
            ElkNode(id: 'bottom', width: 40, height: 20),
            ElkNode(id: 'connected', width: 40, height: 20),
            ElkNode(
              id: 'associate',
              width: 40,
              height: 20,
              barycenterAssociates: ['connected'],
            ),
            ElkNode(id: 'lower', width: 40, height: 20),
          ],
          edges: [
            ElkEdge(id: 'a', sources: ['top'], targets: ['connected']),
            ElkEdge(id: 'b', sources: ['bottom'], targets: ['lower']),
          ],
        ),
      );

      final connected = result.nodesById['connected']!;
      final associate = result.nodesById['associate']!;
      final lower = result.nodesById['lower']!;
      expect(
        (connected.y - associate.y).abs(),
        lessThan(lower.y - associate.y),
      );
    });
  });
}

bool _onBorder(ElkPoint point, ElkPositionedNode node) {
  const tolerance = 1e-6;
  final withinX =
      point.x >= node.x - tolerance &&
      point.x <= node.x + node.width + tolerance;
  final withinY =
      point.y >= node.y - tolerance &&
      point.y <= node.y + node.height + tolerance;
  final onVertical =
      (point.x - node.x).abs() <= tolerance ||
      (point.x - node.x - node.width).abs() <= tolerance;
  final onHorizontal =
      (point.y - node.y).abs() <= tolerance ||
      (point.y - node.y - node.height).abs() <= tolerance;
  return (withinY && onVertical) || (withinX && onHorizontal);
}

LNode _node(LGraph graph, Layer layer, double x, double y) {
  final node = LNode(graph)
    ..layer = layer
    ..position.x = x
    ..position.y = y
    ..size.x = 20
    ..size.y = 20;
  layer.nodes.add(node);
  return node;
}

LPort _port(LNode node, PortSide side, double y) {
  final port = LPort(node)
    ..side = side
    ..position.x = side == PortSide.east ? node.size.x : 0
    ..position.y = y;
  node.ports.add(port);
  return port;
}

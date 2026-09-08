import 'package:elk/src/layered/intermediate_constraints.dart';
import 'package:elk/src/layered/lgraph.dart';
import 'package:elk/src/layered/p1_cycle_breakers.dart';
import 'package:elk/src/layered/p1_greedy_cycle_breaker.dart';
import 'package:elk/src/layered/p3_layer_sweep_crossing_minimizer.dart'
    show modelOrder;
import 'package:test/test.dart';

void main() {
  test('depth-first reverses the DFS back edge of a cycle', () {
    final fixture = _cycle();

    DepthFirstCycleBreaker().process(fixture.graph);

    expect(_orientation(fixture.edges['ca']!), ('a', 'c'));
    expect(fixture.edges['ca']!.reversed, isTrue);
    expect(_isAcyclic(fixture.graph), isTrue);
  });

  test('model-order reverses every edge against declaration order', () {
    final fixture = _cycle();

    ModelOrderCycleBreaker().process(fixture.graph);

    expect(_orientation(fixture.edges['ab']!), ('a', 'b'));
    expect(_orientation(fixture.edges['bc']!), ('b', 'c'));
    expect(_orientation(fixture.edges['ca']!), ('a', 'c'));
    expect(_isAcyclic(fixture.graph), isTrue);
  });

  test('interactive preserves the supplied left-to-right drawing', () {
    final fixture = _cycle();
    fixture.nodes['a']!.position.x = 200;
    fixture.nodes['b']!.position.x = 100;
    fixture.nodes['c']!.position.x = 0;

    InteractiveCycleBreaker().process(fixture.graph);

    expect(_orientation(fixture.edges['ab']!), ('b', 'a'));
    expect(_orientation(fixture.edges['bc']!), ('c', 'b'));
    expect(_orientation(fixture.edges['ca']!), ('c', 'a'));
    expect(_isAcyclic(fixture.graph), isTrue);
  });

  test('interactive compares node centers when widths differ', () {
    final graph = LGraph();
    final wide = _node(graph, 'wide', 0)
      ..position.x = 0
      ..size.x = 200;
    final narrow = _node(graph, 'narrow', 1)
      ..position.x = 50
      ..size.x = 20;
    final edge = _edge(wide, narrow);

    InteractiveCycleBreaker().process(graph);

    // Although narrow's top-left is to the right, its center (60) is left of
    // wide's center (100), so preserving the drawing reverses this edge.
    expect(_orientation(edge), ('narrow', 'wide'));
  });

  test(
    'greedy model-order resolves equal-outflow candidates by model order',
    () {
      final graph = LGraph();
      final high = _node(graph, 'high', 9);
      final low = _node(graph, 'low', 1);
      final breaker = GreedyModelOrderCycleBreaker();

      expect(breaker.chooseNodeWithMaxOutflow([high, low]), same(low));
      expect(
        GreedyCycleBreaker().chooseNodeWithMaxOutflow([high, low]),
        same(high),
      );
    },
  );

  test('model-order places FIRST before normal and LAST after normal', () {
    final firstGraph = LGraph();
    final normalBeforeFirst = _node(firstGraph, 'normal', 0);
    final first = _node(firstGraph, 'first', 1)
      ..setProperty(layerConstraint, LayerConstraint.firstSeparate);
    final towardFirst = _edge(normalBeforeFirst, first);

    ModelOrderCycleBreaker().process(firstGraph);

    expect(_orientation(towardFirst), ('first', 'normal'));

    final lastGraph = LGraph();
    final last = _node(lastGraph, 'last', 0)
      ..setProperty(layerConstraint, LayerConstraint.lastSeparate);
    final normalAfterLast = _node(lastGraph, 'normal', 1);
    final fromLast = _edge(last, normalAfterLast);

    ModelOrderCycleBreaker().process(lastGraph);

    expect(_orientation(fromLast), ('normal', 'last'));
  });

  test('model-order handles constrained generated nodes without raw order', () {
    final graph = LGraph();
    final dummy = LNode(graph)
      ..identifier = 'dummy'
      ..setProperty(layerConstraint, LayerConstraint.firstSeparate);
    dummy.ports.add(LPort(dummy));
    graph.layerlessNodes.add(dummy);
    final normal = _node(graph, 'normal', 0);
    final edge = _edge(normal, dummy);

    ModelOrderCycleBreaker().process(graph);

    expect(_orientation(edge), ('dummy', 'normal'));
  });

  test('greedy model-order applies FIRST constraint before raw order', () {
    final graph = LGraph();
    final first = _node(graph, 'first', 9)
      ..setProperty(layerConstraint, LayerConstraint.firstSeparate);
    final normal = _node(graph, 'normal', 0);

    expect(
      GreedyModelOrderCycleBreaker().chooseNodeWithMaxOutflow([first, normal]),
      same(first),
    );
  });
}

({LGraph graph, Map<String, LNode> nodes, Map<String, LEdge> edges}) _cycle() {
  final graph = LGraph();
  final nodes = <String, LNode>{
    'a': _node(graph, 'a', 0),
    'b': _node(graph, 'b', 1),
    'c': _node(graph, 'c', 2),
  };
  final edges = <String, LEdge>{
    'ab': _edge(nodes['a']!, nodes['b']!),
    'bc': _edge(nodes['b']!, nodes['c']!),
    'ca': _edge(nodes['c']!, nodes['a']!),
  };
  return (graph: graph, nodes: nodes, edges: edges);
}

LNode _node(LGraph graph, String id, int order) {
  final node = LNode(graph)..identifier = id;
  node.setProperty(modelOrder, order);
  node.ports.add(LPort(node));
  graph.layerlessNodes.add(node);
  return node;
}

LEdge _edge(LNode source, LNode target) {
  final edge = LEdge();
  edge.source = source.ports.single;
  edge.target = target.ports.single;
  return edge;
}

(String, String) _orientation(LEdge edge) =>
    (edge.source!.node.identifier!, edge.target!.node.identifier!);

bool _isAcyclic(LGraph graph) {
  final visited = <LNode>{};
  final active = <LNode>{};
  bool visit(LNode node) {
    if (active.contains(node)) return false;
    if (!visited.add(node)) return true;
    active.add(node);
    for (final edge in node.outgoingEdges) {
      if (!edge.isSelfLoop && !visit(edge.target!.node)) return false;
    }
    active.remove(node);
    return true;
  }

  return graph.layerlessNodes.every(visit);
}

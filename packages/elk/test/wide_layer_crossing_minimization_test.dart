import 'dart:math';

import 'package:elk/elk.dart';
import 'package:test/test.dart';

/// A graph whose middle layers are wide, like a project with a few hundred
/// tasks per stage.
///
/// Sorting such a layer used to merge the model-order transitive closure on
/// every comparison, which costs O(n² log n × closure size) and took 27 s on a
/// 150-node layer before that bookkeeping was limited to the strategies that
/// read it (`preferNodeOrder`).
void main() {
  // Only `nodesAndEdges` and `preferNodes` read the closure. `preferEdges`
  // sorts by barycenter like `none`, so it must not pay for it either.
  for (final strategy in [
    ElkConsiderModelOrder.none,
    ElkConsiderModelOrder.preferEdges,
  ]) {
    test(
      'lays out a graph with wide layers (model order: ${strategy.name})',
      () {
        final graph = _wideLayerGraph(strategy);
        final stopwatch = Stopwatch()..start();
        final result = const ElkLayered().layout(graph);
        stopwatch.stop();

        expect(result.children, hasLength(graph.children.length));
        expect(result.width, greaterThan(0));
        expect(result.height, greaterThan(0));
        // The layout itself takes ~0.1 s; the bound only catches the return of
        // the per-comparison closure bookkeeping, which pushes it past 5 s.
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      },
    );
  }
}

ElkGraph _wideLayerGraph(ElkConsiderModelOrder strategy) {
  const widths = [40, 80, 150, 150, 80, 20];
  final random = Random(7);
  final layers = <List<String>>[];
  var next = 0;

  for (final width in widths) {
    layers.add([
      for (var i = 0; i < width; i++) 't${(next++).toString().padLeft(4, '0')}',
    ]);
  }

  final edges = <(String, String)>[];
  for (var k = 1; k < layers.length; k++) {
    for (final node in layers[k]) {
      edges.add((node, layers[k - 1][random.nextInt(layers[k - 1].length)]));
      if (random.nextBool()) {
        edges.add((node, layers[k - 1][random.nextInt(layers[k - 1].length)]));
      }
    }
  }

  return ElkGraph(
    layoutOptions: ElkLayoutOptions(
      direction: ElkDirection.right,
      spacingNodeNode: 40,
      spacingNodeNodeBetweenLayers: 100,
      mergeEdges: true,
      considerModelOrder: strategy,
    ),
    children: [
      for (final layer in layers)
        for (final id in layer) ElkNode(id: id, width: 300, height: 44),
    ],
    edges: [
      for (final (index, edge) in edges.indexed)
        ElkEdge(id: 'e$index', sources: [edge.$1], targets: [edge.$2]),
    ],
  );
}

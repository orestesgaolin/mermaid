import 'dart:math';

import 'package:elk/elk.dart';
import 'package:test/test.dart';

/// A graph whose middle layers are wide, like a project with a few hundred
/// tasks per stage.
///
/// Sorting such a layer used to merge the model-order transitive closure on
/// every comparison, which costs O(n² log n × closure size) and took 27 s on a
/// 150-node layer before that bookkeeping was guarded by `useModelOrder`.
void main() {
  test('lays out a graph with wide layers', () {
    final graph = _wideLayerGraph();
    final stopwatch = Stopwatch()..start();
    final result = const ElkLayered().layout(graph);
    stopwatch.stop();

    expect(result.children, hasLength(graph.children.length));
    expect(result.width, greaterThan(0));
    expect(result.height, greaterThan(0));
    // The layout itself takes ~0.1 s; the bound only catches the return of the
    // per-comparison closure bookkeeping, which pushes it past 25 s.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

ElkGraph _wideLayerGraph() {
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
    layoutOptions: const ElkLayoutOptions(
      direction: ElkDirection.right,
      spacingNodeNode: 40,
      spacingNodeNodeBetweenLayers: 100,
      mergeEdges: true,
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

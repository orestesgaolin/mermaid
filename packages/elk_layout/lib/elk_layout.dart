/// Pure-Dart layered graph layout (Sugiyama-style), inspired by the Eclipse
/// Layout Kernel (ELK). The graph model and result mirror the elkjs JSON
/// shape, so this is a recognizable, synchronous, dependency-free alternative.
///
/// ```dart
/// final result = const ElkLayered().layout(ElkGraph(
///   layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
///   children: [ElkNode(id: 'a', width: 80, height: 40), ElkNode(id: 'b', width: 80, height: 40)],
///   edges: [ElkEdge(id: 'e1', sources: ['a'], targets: ['b'])],
/// ));
/// for (final node in result.children) {
///   print('${node.id}: ${node.x}, ${node.y}');
/// }
/// ```
library;

export 'src/api/graph.dart';
export 'src/api/options.dart';
export 'src/api/result.dart';
export 'src/engine/elk_layered.dart';
export 'src/routing/orthogonal_router.dart';

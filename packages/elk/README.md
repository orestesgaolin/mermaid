# elk

`elk` is a pure Dart implementation of layered graph layout. It provides an
elkjs-style graph model and supports compound graphs, ports, configurable
spacing, model-order constraints, and orthogonal edge routing.

The implementation follows the same algorithm family as Eclipse Layout Kernel
and elkjs, but it is not a translation of either project and does not promise
identical coordinates.

## Use

```dart
import 'package:elk/elk.dart';

void main() {
  final result = const ElkLayered().layout(
    ElkGraph(
      layoutOptions: const ElkLayoutOptions(direction: ElkDirection.down),
      children: [
        ElkNode(id: 'a', width: 80, height: 40),
        ElkNode(id: 'b', width: 80, height: 40),
        ElkNode(id: 'c', width: 80, height: 40),
      ],
      edges: [
        ElkEdge(id: 'e1', sources: ['a'], targets: ['b']),
        ElkEdge(id: 'e2', sources: ['a'], targets: ['c']),
      ],
    ),
  );

  for (final node in result.children) {
    print('${node.id}: ${node.x}, ${node.y}');
  }
}
```

Node coordinates are relative to their parent. Use `result.nodesById` for a
flat map with absolute coordinates.

## Options

`ElkLayoutOptions` controls direction, spacing, node placement, fixed
alignment, model-order handling, edge merging, and cycle breaking. For
example:

```dart
const options = ElkLayoutOptions(
  direction: ElkDirection.right,
  spacingBaseValue: 24,
  forceNodeModelOrder: true,
);
```

Edges can refer to a node ID or to an `ElkPort` ID. A node with children is
laid out as a compound node. Existing elkjs graph JSON can be loaded with
`ElkGraph.fromJson`.

## Validation

The comparison tool under `tool/validation` runs the same graph set through
this package and elkjs and writes side-by-side SVG output:

```console
$ cd tool/validation
$ npm install
$ node run_elkjs.mjs
$ cd ../..
$ dart run tool/validation/compare.dart
```

The comparison checks layer assignment, node overlap, ordering, and graph
bounds. Differences in within-layer ordering and exact coordinates are
expected.

## License

MIT. The package contains a vendored derivative of dart_dagre (Apache-2.0).
See `NOTICE` and `lib/src/dagre/LICENSE`.

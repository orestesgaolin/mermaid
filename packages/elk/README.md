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
alignment, hierarchy handling, model-order handling, edge merging, and cycle breaking. For
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

## Hierarchy modes

Set `hierarchyHandling` on root or compound `ElkLayoutOptions`. JSON accepts
`org.eclipse.elk.hierarchyHandling`, `elk.hierarchyHandling`, and
`hierarchyHandling`.

| Mode | Behavior |
| --- | --- |
| `includeChildren` / `INCLUDE_CHILDREN` | Routes edges across included compound boundaries. |
| `separateChildren` / `SEPARATE_CHILDREN` | Lays out groups independently. Edges internal to each group, including links from its own boundary ports to its children, remain routed; edges crossing a separated boundary remain in the result with empty `sections`. |
| `inherit` / `INHERIT` | Uses the enclosing mode; at the root, resolves to `SEPARATE_CHILDREN`. |

Omitting the root mode preserves Dart's existing `INCLUDE_CHILDREN` default.
Omitting a compound override inherits its enclosing mode. An explicit included
child does not reconnect a boundary separated by an ancestor. A direction-only
compound override changes direction without changing the inherited mode; a
hierarchy-only override preserves the inherited direction.

Unlike elkjs 0.9.3, Dart retains cross-boundary edge IDs with empty `sections`
when an included parent contains a separated child, rather than throwing.
Unrouted edges have no positioned labels. Their original label metadata remains
on the input graph. Consumers should draw only the sections that are present.

Dart also retains its existing mixed-direction support under `INCLUDE_CHILDREN`.
elkjs 0.9.3 ignores nested directions in that mode. The broader coordinated
hierarchy optimization remains tracked in
[issue #78](https://github.com/orestesgaolin/mermaid/issues/78); these modes do
not promise identical coordinates or crossing order.

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

The hierarchy tests also read retained elkjs 0.9.3 inputs and outputs from
`test/fixtures/hierarchy_handling_elkjs.json`. After an intentional reference
update, regenerate them from the package root with
`node tool/validation/generate_hierarchy_reference.mjs`. Ordinary tests never
regenerate reference data.

## License

MIT. The package contains a vendored derivative of dart_dagre (Apache-2.0).
See `NOTICE` and `lib/src/dagre/LICENSE`.

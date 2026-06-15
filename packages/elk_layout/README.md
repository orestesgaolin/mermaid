# elk_layout

Pure-Dart **layered graph layout** (Sugiyama-style), inspired by the
[Eclipse Layout Kernel](https://eclipse.dev/elk/) (ELK) and its JavaScript
port [elkjs](https://github.com/kieler/elkjs).

- **Layered algorithm**: cycle breaking → network-simplex layering → crossing
  minimization → Brandes–Köpf coordinate assignment.
- **Orthogonal edge routing** with computed bend points — the characteristic
  ELK look.
- **Compound graphs / clusters**: nodes can contain children; clusters are
  sized and positioned, children returned with parent-relative coordinates.
- **ELK spacing model** (`spacing.baseValue`), **model order** crossing
  constraints, and Brandes–Köpf fixed-alignment options.
- **elkjs-style API**: the input/output mirror the elkjs graph JSON, so it's a
  recognizable, near-drop-in alternative.
- **Synchronous, dependency-free, no I/O** — runs in the VM, AOT, Flutter
  (mobile/desktop/web) and the browser alike.

> Not a transpile of elkjs (which is GWT-compiled Java) — it's a readable Dart
> implementation of the same layered algorithm family, so output is *ELK-like*
> but not byte-identical to elkjs.

## Usage

```dart
import 'package:elk_layout/elk_layout.dart';

void main() {
  final result = const ElkLayered().layout(ElkGraph(
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
  ));

  for (final node in result.children) {
    print('${node.id}: x=${node.x}, y=${node.y}, '
        '${node.width}x${node.height}');
  }
  for (final edge in result.edges) {
    print('${edge.id}: ${edge.sections.first.points}');
  }
}
```

### Compound graphs (clusters)

A node with `children` becomes a cluster whose size and position are computed:

```dart
final result = const ElkLayered().layout(ElkGraph(
  children: [
    ElkNode(id: 'cluster', children: [
      ElkNode(id: 'c1', width: 80, height: 40),
      ElkNode(id: 'c2', width: 80, height: 40),
    ]),
  ],
  edges: [ElkEdge(id: 'e1', sources: ['c1'], targets: ['c2'])],
));
// result.nodesById gives every node with **absolute** coordinates.
```

### Options

`ElkLayoutOptions` mirrors the ELK option keys: `direction`, `spacingBaseValue`,
`nodePlacement`, `fixedAlignment`, `mergeEdges`, `considerModelOrder`,
`forceNodeModelOrder`, `cycleBreaking`, plus explicit spacing overrides.

## License

MIT (see `LICENSE`). Bundles a vendored copy of
[dart_dagre](https://pub.dev/packages/dart_dagre) (Apache-2.0) as the layered
algorithm substrate — see `NOTICE` and `lib/src/dagre/LICENSE`.

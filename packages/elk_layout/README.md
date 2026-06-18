# elk

Pure-Dart **layered graph layout** (Sugiyama-style), inspired by the
[Eclipse Layout Kernel](https://eclipse.dev/elk/) (ELK) and its JavaScript
port [elkjs](https://github.com/kieler/elkjs).

- **Layered algorithm**: cycle breaking → network-simplex layering → crossing
  minimization → Brandes–Köpf coordinate assignment.
- **Orthogonal edge routing** with computed bend points — the characteristic
  ELK look.
- **Compound graphs / clusters**: nodes can contain children; clusters are
  sized and positioned, children returned with parent-relative coordinates.
- **Ports**: edges can attach at fixed points on node borders.
- **ELK spacing model** (`spacing.baseValue`), **model order** crossing
  constraints, and Brandes–Köpf fixed-alignment options.
- **elkjs-style API**, including `ElkGraph.fromJson` for the elkjs graph JSON —
  a recognizable, near-drop-in alternative.
- **Synchronous, dependency-free, no I/O** — runs in the VM, AOT, Flutter
  (mobile/desktop/web) and the browser alike.

> Not a transpile of elkjs (which is GWT-compiled Java) — it's a readable Dart
> implementation of the same layered algorithm family, so output is *ELK-like*
> but not byte-identical to elkjs. See [Validation](#validating-against-elkjs).

## Quick start

```dart
import 'package:elk/elk.dart';

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
    print('${node.id}: x=${node.x}, y=${node.y}, ${node.width}x${node.height}');
  }
  for (final edge in result.edges) {
    print('${edge.id}: ${edge.sections.first.points}'); // start, bends…, end
  }
}
```

Coordinates: a node's `x`/`y` is its top-left **relative to its parent**. Use
`result.nodesById` for a flat map with **absolute** coordinates.

## Configuration

All options live on [`ElkLayoutOptions`]. Defaults match ELK/elkjs for the
`layered` algorithm as configured by mermaid.

| Option | Type / values | Default | Effect |
|---|---|---|---|
| `direction` | `down`, `up`, `right`, `left` | `down` | Primary flow direction (the layering axis). |
| `spacingBaseValue` | `double` | `40` | Base unit; node/edge/layer gaps are derived from it unless set explicitly. |
| `spacingNodeNode` | `double?` | from base | Gap between adjacent nodes in a layer. |
| `spacingEdgeNode` | `double?` | base × 0.5 | Gap between a node and an edge routed past it. |
| `spacingNodeNodeBetweenLayers` | `double?` | from base | Gap between layers. |
| `nodePlacement` | `brandesKoepf`, … | `brandesKoepf` | Coordinate-assignment strategy (others currently fall back to BK). |
| `fixedAlignment` | `none`, `leftUp`, `leftDown`, `rightUp`, `rightDown`, `balanced` | `none` | Brandes–Köpf alignment; `none` balances all four (most stable). |
| `considerModelOrder` | `none`, `nodesAndEdges`, `preferEdges`, `preferNodes` | `none` | Constrain crossing-min to the input order. |
| `forceNodeModelOrder` | `bool` | `false` | Keep siblings strictly in declaration order. |
| `mergeEdges` | `bool` | `false` | Merge parallel edges into a shared trunk. |
| `cycleBreaking` | `greedy`, … | `greedy` | Strategy used to break cycles before layering. |

### Direction

```dart
// Flow left-to-right instead of top-down (e.g. a dependency graph).
const ElkLayoutOptions(direction: ElkDirection.right);
```

### Spacing

```dart
// Tighter than the default 40; or set concrete gaps.
const ElkLayoutOptions(spacingBaseValue: 24);
const ElkLayoutOptions(spacingNodeNode: 60, spacingNodeNodeBetweenLayers: 80);
```

### Model order

Keep sibling nodes in the order you declared them (otherwise crossing
minimization is free to reorder them):

```dart
const ElkLayoutOptions(forceNodeModelOrder: true);
```

### Ports

Give a node `ports` and reference a port id (instead of the node id) in an
edge's `sources`/`targets`. Each port is placed on the node border — its
`side` is explicit or inferred from the flow direction and whether the port is
used as a source (outgoing side) or target (incoming side) — and ports on a
side are ordered to reduce crossings.

```dart
final result = const ElkLayered().layout(ElkGraph(
  layoutOptions: const ElkLayoutOptions(direction: ElkDirection.right),
  children: [
    ElkNode(id: 'hub', width: 80, height: 80, ports: [
      ElkPort(id: 'out1'),
      ElkPort(id: 'out2', side: ElkPortSide.east),
    ]),
    ElkNode(id: 'a', width: 80, height: 40),
    ElkNode(id: 'b', width: 80, height: 40),
  ],
  edges: [
    ElkEdge(id: 'e1', sources: ['out1'], targets: ['a']),
    ElkEdge(id: 'e2', sources: ['out2'], targets: ['b']),
  ],
));
// result.nodesById['hub']!.ports gives each port's position on the border;
// each edge's section starts exactly at its port.
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
```

### Loading elkjs JSON

The graph model mirrors the elkjs JSON, so an existing elkjs graph drops in:

```dart
final graph = ElkGraph.fromJson(jsonDecode(elkjsGraphJsonString));
final result = const ElkLayered().layout(graph);
```

## Validating against elkjs

Exact coordinates will never match elkjs (different implementations), but the
*structure* should. `tool/validation/` runs the same graph set through both
engines and scores agreement:

```sh
cd tool/validation
npm install            # installs real elkjs (once)
node run_elkjs.mjs     # lays the graphs out with elkjs → elkjs_out.json
cd ../.. && dart run tool/validation/compare.dart
```

`compare.dart` prints a structural-agreement table **and** writes a
side-by-side SVG per graph (ours | elkjs) to `tool/validation/output/` for
visual comparison.

On the bundled graph set, `elk` agrees with elkjs **100% on layer
assignment** (which node lands in which layer along the flow axis) and produces
**zero node overlaps**, with comparable bounding-box aspect ratios. Within-layer
ordering differs (different crossing-minimization heuristics; symmetric graphs
are interchangeable either way) — that's the expected, documented divergence.

## License

MIT (see `LICENSE`). Bundles a vendored copy of
[dart_dagre](https://pub.dev/packages/dart_dagre) (Apache-2.0) as the layered
algorithm substrate — see `NOTICE` and `lib/src/dagre/LICENSE`.

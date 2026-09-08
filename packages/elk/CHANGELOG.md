## 0.2.0

- Implement distinct INCLUDE_CHILDREN, SEPARATE_CHILDREN, and INHERIT modes,
  including JSON aliases and independent direction/hierarchy inheritance.
  Separated cross-boundary edges remain in the result without route sections
  or fabricated label positions. Full coordinated hierarchy optimization
  remains outside the supported contract.
- Preserve deep hierarchy endpoints, labels, and orthogonal boundary routes
  across nested directions and compound title bands.
- Correct four-side explicit port placement, outward edge attachment, and
  internal compound-boundary attachment. Preserve self-loop clearance beyond
  nonzero port rectangles and reserve matching layout margins.
- Place edge, node, and port labels; support crossing constraints and hyperedge
  junctions; improve self-loop sizing and edge straightening.
- Honor cycle-breaking, model-order, edge-merging, and Brandes–Köpf alignment
  choices exposed by the public API.
- Parse standard ELK option aliases and spacing keys while retaining legacy
  aliases. Honor explicit asymmetric root padding in all four directions.
- Include ports, labels, routed strokes, and loops in returned layout bounds.

## 0.1.1

- Fixed explicit north/south ports attaching to
  the opposite side of nodes in `ElkDirection.up` layouts.

## 0.1.0

- Initial release.
- **Ports**: `ElkPort.side` / `ElkPortSide`; edges may reference port ids and
  attach at computed border points (`ElkPositionedNode.ports`).
- **elkjs JSON ingestion**: `ElkGraph.fromJson` (and `fromJson` on nodes/edges/
  ports/labels) parse the elkjs graph JSON shape.
- **Validation harness** (`tool/validation/`) comparing structural agreement
  against real elkjs.
- ELK-style **layered** layout: cycle breaking, network-simplex layering,
  crossing minimization, Brandes–Köpf coordinate assignment.
- **Orthogonal edge routing** with computed bend points and parallel-edge
  lanes.
- **Compound graphs / clusters** with parent-relative result coordinates.
- ELK **spacing model** (`spacing.baseValue`), **model order** constraints, and
  Brandes–Köpf fixed-alignment options.
- elkjs-style graph API (`ElkGraph` / `ElkNode` / `ElkEdge` → `ElkResult`).

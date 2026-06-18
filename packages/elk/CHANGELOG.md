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

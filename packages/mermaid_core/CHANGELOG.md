## Unreleased

- Add scene-space node-bound lookup through `RenderScene.nodeBounds` and
  `RenderScene.boundsOf`.
- Add structured flowchart edge metadata and path-distance measurement for
  precise stroke and label interaction.
- Add paint-only flowchart node and link overrides that reuse an existing
  parsed and laid-out scene.
- Document and verify deterministic Dagre, ELK, and hand-drawn flowchart
  geometry, including geometry-preserving style changes.
- Wrap long flowchart labels at spaces, underscores, and hyphens before using
  hard character breaks.
- Place long flowchart edge labels at the midpoint of the routed path and
  adjust them away from node collisions.
- Honor Sankey frontmatter for dimensions, alignment, values, prefixes,
  suffixes, node colors, link colors, and label styles.
- Improve Sankey node ordering and link composition, and keep small node bars
  and gradient lanes visible at a consistent minimum thickness.
- Honor XY chart theme and layout configuration, including horizontal charts,
  data labels, plot spacing, axis typography, and stroke widths.
- Align quadrant dimensions, padding, quoted axis labels, trailing arrows, and
  rotated axes with the configured viewport.
- Improve nested state placement, fills, and routing, including states that
  are referenced before their composite declaration.
- Improve sequence participant sizing, note wrapping, activation alignment,
  side-note clearance, autonumber badges, frame layout, and nested `rect`
  paint order.
- Improve class, flowchart, C4, and requirement graph routing, edge-label
  clearance, relation markers, and dense-node ordering.
- Center titled flowchart subgraphs on their member rows, keep block arrowheads
  outside adjacent nodes, and align Git graph commit labels and tag notches
  with Mermaid.js.
- Correct ER entity spacing, Gantt paint order, Journey label contrast,
  Timeline section spans, Ishikawa label and arrow alignment, and Radar labels.
- Align Venn labels, treemap squarification, spanning block groups, C4
  deployment boundaries, and the default Mermaid color scale with Mermaid.js.
- Include all diagram palettes and specialized color roles in
  `MermaidTheme.copyWith`, equality, and hash-code calculations.
- Preserve hand-drawn edge markers and legacy Font Awesome labels, and add
  gradient strokes and multiply compositing to render scenes and SVG output.

## 0.1.2

- Route flowchart edges into subgraphs with bends that more closely match
  Mermaid.js.
- Prevent command and read-model nodes from overlapping in Event Modeling
  diagrams.
- Align Kanban section titles, card insets, and bottom padding with Mermaid.js.
- Render C4 database cylinders without a white cutout in the top cap.

## 0.1.1

- Prevent late font fallback changes on Flutter web from wrapping flowchart
  labels outside their node boxes.

## 0.1.0

Initial release. Pure Dart port of mermaid.js.

- **28 diagram types**: flowchart, sequence, class, state, ER, pie, gantt,
  quadrant, journey, timeline, xychart, mindmap, requirement, C4, gitGraph,
  sankey, packet, block, radar, treemap, kanban, architecture, cynefin, venn,
  ishikawa, wardley, eventModeling, railroad.
- Diagram detection, hand-written parsers, layout (vendored dagre for
  graph diagrams; `elk` and `tidy-tree` alternate engines), and a
  backend-agnostic **render scene IR**.
- **SVG renderer** (`renderSceneToSvg`) and a **CLI** (`mermaid_dart`) that
  emits SVG, or PNG via an external rasterizer.
- Theme directives: `%%{init}%%` + frontmatter `config.theme`/`themeVariables`;
  named themes default/dark/forest/neutral.
- **Hand-drawn look** (`look: handDrawn`) — a faithful roughjs port.
- **Icons** on flowchart nodes via iconify-style packs (`@{ icon: }`).
- **Math** in labels (`$$...$$`): a TeX subset (super/subscripts, `\frac`,
  `\sqrt`, matrices, `cases`, braces, accents) laid out with scene primitives.
- Validated against 184 upstream demo fixtures.

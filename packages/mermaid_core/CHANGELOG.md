## Unreleased

- Honor quadrant chart dimensions and padding, normalize quoted/trailing-arrow
  axis labels, and keep rotated axes inside the configured viewport.
- Add paint-only flowchart node and link overrides that preserve existing
  scene geometry.
- Add structured flowchart edge metadata and scene-space path distance
  measurement for precise interaction layers.

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

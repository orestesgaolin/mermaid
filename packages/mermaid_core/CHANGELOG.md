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

## 0.3.2

- Keep flowchart nodes inside their subgraph box and sibling subgraph boxes
  apart when many edges cross between subgraphs (#82). A node used in
  several subgraphs now belongs to the first one that lists it, as in
  mermaid.js. Three defects in the vendored dagre are fixed: crossing counts
  were always 0, so edge-crossing reduction did not run; type-2 alignment
  conflicts were not found, so cluster borders drifted away from their
  members; and the initial node order used an unstable sort. Flowchart,
  class, state and requirement layouts can change; they now match
  dagre-d3-es, the dagre build mermaid.js uses.
- Render `<b>`/`<strong>` and `<i>`/`<em>` in flowchart node labels, edge
  labels and subgraph titles as bold and italic text, as mermaid.js does, and
  stop drawing other HTML tags as literal text (#79). Markdown-string labels
  with line breaks also keep their `**bold**` styling now.
- Render `<b>`/`<strong>` and `<i>`/`<em>` as bold and italic text, and
  stop drawing other HTML tags as literal text, in the labels that mermaid.js
  shows as HTML: state descriptions, notes, composite titles and transition
  labels; class labels, notes, relation labels, cardinalities and namespace
  titles (members and methods keep their tags as text, as in mermaid.js);
  ER entity aliases, attribute comments and relationship labels; requirement
  names and field values; block and block edge labels; mindmap nodes; and
  kanban sections, cards and assigned labels. `<br>` now breaks the line in
  ER, requirement and block labels and in multi-line state notes, and a
  quoted requirement name is shown without its quotes.
- Write each line of a styled label to SVG as one `<text>` with a `<tspan>`
  per bold or italic run, so browsers keep normal spaces between runs. The
  new optional `SceneText.run` (`SceneTextRun`) marks the runs of a line.
- Require `elk` 0.2.1.
- Paint state names and composite titles at normal weight, as mermaid.js
  renders them. They were measured at normal weight but painted bold, so the
  last letter wrapped outside the state box.

## 0.3.1

- Render faster: about 9x on a 500-node flowchart (28.4 ms to 3.1 ms, AOT)
  and 7x over the comparison-site samples, with byte-identical output. The
  dagre layout runs on an indexed graph with incremental network simplex;
  directives are parsed once per render; regexes are hoisted or replaced by
  scanners; SVG is written into a reused byte buffer.
- Fix a crash on a class diagram self relation (`C1 --> C1`).
- Fix a crash on flowchart edges to or from an empty subgraph, and draw empty
  subgraphs as mermaid.js does (a zero-height rect with the title below).

## 0.3.0

- Honor active per-diagram layout and style configuration through init directives
  and frontmatter, including nested flow collections. See the configuration
  support notes in `parity/` for backend and upstream limitations.
- Use the effective upstream ER cell padding default of 20 and allow overrides.
- Parse CSS named colors, HSL/HSLA, percentage RGB and alpha forms, with finite
  numeric validation and channel clamping.
- Honor Kanban ticket URLs and all radar margins. Keep Cynefin boundary
  randomness within 32-bit arithmetic on the Dart VM.

- Add registered Kanban task icons, task styles, and interaction directives.
- Apply requirement element styles and interaction directives.
- Correct right-to-left Git graph layout and adjacent class-note placement.
- Require ELK 0.2.0 for corrected compound routes, ports, labels, loops,
  spacing, and layout strategy handling.

## 0.2.1

- Version alignment with `mermaid_flutter` 0.2.1. No code changes.

## 0.2.0

**Behavior changes**

- Scene groups now carry a `SceneGroupRole`. `RenderScene.nodeBounds` and
  node hit-testing include only `SceneGroupRole.node` groups, so cluster,
  frame, namespace, boundary, section, and legend ids are no longer reported
  as nodes.
- `MermaidTheme` equality and `hashCode` now cover every palette field instead
  of the 16 base fields, so two themes that differ only in a palette no longer
  compare equal.
- Default `cScale*`, `cScaleInv*`, and `cScalePeer*` colors now match
  Mermaid.js 11, and `forestTheme` defines an XY chart plot palette.
- Multi-line subgraph titles (`subgraph S["a<br/>b"]`) now sit inside the
  cluster border instead of above it; the cluster reserves the full title band.
- Frontmatter `config:` YAML now strips trailing `# comments`, so
  `width: 800 # note` reads as the number 800 instead of silently falling back
  to the default. As in YAML, an unquoted value that starts with `#` is a
  comment, so quote color literals such as `linkColor: '#ff0000'`.
- Frontmatter config keys may contain hyphens and dots, and values accept
  flow-style maps such as `nodeColors: {Bio-conversion: '#f00'}`.
- `layoutSankey` takes a single `config: SankeyConfig` parameter instead of
  twelve named options. `Mermaid.render` is unaffected.
- `SankeyConfig.useMaxWidth` was removed; it was parsed but never read.
- `XyChart.horizontal`, `showDataLabel`, and `showDataLabelOutsideBar` are now
  getters over `XyChart.config`; the matching constructor parameters were
  removed.

**Changes**

- Add `resolveDiagramConfig` for reading per-diagram configuration from
  directives and frontmatter.
- Honor common layout configuration for sequence, flowchart, state, class,
  Gantt, pie, and gitGraph diagrams through directives and frontmatter.
- Add `SceneShape.copyWith` and `SceneText.copyWith`, and value equality on
  `SceneEdgeMetadata`.
- Compute `RenderScene.nodeBounds` once per scene and reuse the map, and make
  `MermaidTheme` equality short-circuit on identity with a cached hash code.
- Share edge geometry helpers (rect intersection, basis curves, path
  midpoints) and validated config readers across diagram layouts.
- Add scene-space node-bound lookup through `RenderScene.nodeBounds` and
  `RenderScene.boundsOfNode`.
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

**Fixes**

- Header-only diagrams (`flowchart TB`, `classDiagram`, `erDiagram`,
  `requirementDiagram`, `stateDiagram-v2`) render an empty scene instead of
  throwing from `render()`.
- A sequence block with no participants, a transition into an empty composite
  state, and a quadrant chart smaller than its title and axis bands render
  instead of throwing.
- Sankey values too large to scale (such as `1e308`) no longer throw; `NaN`
  and the infinities are reported as a `MermaidParseException` at parse time.
- `look: handDrawn` keeps gradient link colors and multiply blending instead
  of flattening them to a solid color.
- Long flowchart edge labels, flowchart titles, and isolated-direction
  subgraph titles carry explicit line breaks, so SVG output no longer
  overflows its label box.
- Block: a child's span is clamped to its group's column count so a wide span
  no longer paints over siblings, and round shapes are sized from the shorter
  side of their cell.
- C4: boundary descriptions are measured at the width they are drawn at, so a
  long description no longer paints over the elements inside the boundary;
  an empty boundary label reserves no space.
- Class: cross-namespace relations follow `direction`, relation labels use
  the theme's edge-label background, namespace separation repeats until no
  clusters overlap, and notes move with their class.
- Git: the LR commit-tag spear tip is drawn outside the tag body, matching
  upstream.
- Venn: the title band is sized from the measured title so it no longer
  overlaps the circles.
- ER: attribute bands grow with the minimum-height floor so they cover the
  whole entity.
- Requirement: the re-column pass is bounded by each rank's free space, so a
  relation source no longer drags its target past its neighbours.
- XY chart: negative, zero, or non-finite `config.xyChart` dimensions fall
  back to defaults; an all-equal value series maps to the middle of the range
  and a single category is centered, matching d3.
- Sankey: a node with a custom `nodeColors` entry no longer consumes a
  palette slot, and value-less labels are centered on their node.
- Sequence: a `create`d participant's top box is exposed as `actor_<id>`
  again, and message arrowheads stop on the target's activation bar.
- Radar: a body `title` line overrides the frontmatter title, matching every
  other diagram.
- Quadrant: a dangling axis label appends the long arrow with surrounding
  spaces, matching upstream's grammar.
- Journey section labels use the theme's title color; Ishikawa cause labels
  are centered on their box.

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

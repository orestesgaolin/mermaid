# block — parity analysis
**Status:** minor-gaps
**Last analyzed:** (leave as TODO-date)

## How mermaid.js implements it
- Parse/DB: `blockDB.ts` (`typeStr2Type`, `populateBlockDatabase`, `setHierarchy`). Builds a tree under a synthetic `root` composite block; `space` blocks are expanded into N clones (`space:num`).
- Shapes: `renderHelpers.ts:getNodeFromBlock` maps `BlockType` to a flowchart shape string and delegates to the shared `dagre-wrapper/nodes.ts:insertNode`. Supported types: `square`(rect), `round`(rect rx/ry=5), `circle`, `doublecircle`, `ellipse`, `stadium`, `subroutine`, `cylinder`, `diamond`(question), `hexagon`, `block_arrow`, `odd`/`rect_left_inv_arrow`, `lean_right`, `lean_left`, `trapezoid`, `inv_trapezoid`, `group`/`composite`(rect). Node padding default `getConfig().block.padding ?? 0` (composite padding forced to 0).
- Sizing/layout: `layout.ts`. `setBlockSizes` computes a uniform `maxWidth`/`maxHeight` over a block's children (children all normalized to the same cell size), then `width = xSize*(maxWidth+padding)+padding`. `layoutBlocks` positions row-major using `calculateBlockPosition(columns, pos)`; per-row max heights honored; default `padding = config.block.padding ?? 8`. `columns 1` lays out vertically; `columns -1` (auto) = single row.
- Edges: `renderHelpers.ts:insertEdges`. Builds a dagre graph, then draws via shared `dagre-wrapper/edges.ts:insertEdge` with a 3-point path (start, midpoint, end). Markers from `insertMarkers` (`point`, `circle`, `cross`). Edge thickness `thick` from `==`, pattern `dotted` from `.-` (`edge-thickness-*` / `edge-pattern-*` classes). Edge stroke 2.0px (`styles.ts .edgePath .path`). Edge label uses `insertEdgeLabel`/`positionEdgeLabel` at midpoint, rect bg opacity 0.5.
- Styling: `classDef`/`class` (`addStyleClass`, `setCssClass`) AND per-node `style id ...` (`addStyle2Node`). Class `color` is remapped to text fill, `fill`→`bgFill`.
- Cluster/group look: `styles.ts` `.node .cluster` uses `fade(clusterBkg, 0.5)` fill and `fade(clusterBorder, 0.2)` stroke plus a box-shadow; group label color = `titleColor`.
- Renderer `blockRenderer.ts:draw`: viewBox padded by 5 each side; final size adds a `magicFactor` to height.

## How mermaid_dart implements it
- Parse: `block.dart:parseBlock` — hand-written line scanner. `_parseNode` recognizes shapes via bracket prefix: `((`→circle, `([`→stadium, `[(`→cylinder, `(`→rounded, `{`→diamond, else rect; plus `space` and block-arrow `id<["label"]>(dirs)`. Groups via `block:id[:span]` / bare `block` … `end`. `columns N`. Edges via `_parseEdges`.
- Layout: `block.dart:layoutBlock` + `_layoutGrid`. Row-major grid; per-item cell `width/span`; uniform `cellW`/`rowH`; `_cellGap = 8`, `_pad = 14`. Recurses into groups; group height adds 16px for a label band.
- Shapes: `_drawNode` — circle (CircleGeometry), stadium (rect rx=h/2), rounded (rect rx=6), diamond (polygon), cylinder (**rounded rect rx=8 — not a real cylinder**), blockArrow (`_blockArrowPoints` fat-arrow polygon), default rect. Stroke width 1.
- Edges: straight line clipped to rects (`_clip`), single triangular arrowhead (`_arrow`), optional reverse head for `<--`. Stroke width 1.5. Edge label drawn over `edgeLabelBackground` chip at the segment midpoint.
- Styling: only inline `style id k:v,...` parsed into `BlockNode.styles`; `_drawNode` reads `fill`/`stroke`/`color`. No `classDef`/`class`.
- Theme colors: node fill `theme.mainBkg`, border `theme.nodeBorder`; group fill `theme.clusterBkg` (solid), border `theme.clusterBorder` (solid); edges `theme.lineColor`.

## Discrepancies
1. `[open] (high) Missing shapes` — Upstream supports hexagon, subroutine `[[ ]]`, doublecircle `((( )))`, ellipse, lean_left/right, trapezoid/inv_trapezoid, odd/`>]`. We only have rect/rounded/stadium/circle/diamond/cylinder. These tokens fall through to a plain rect.
2. `[open] (high) Cylinder is not a cylinder` — Upstream renders a true database cylinder; we draw a rounded rect (rx=8), so `[( )]` looks wrong.
3. `[open] (high) No classDef/class support` — Upstream supports `classDef name ...` + `class id name`; we only parse inline `style id ...`. Diagrams using classes get no styling.
4. `[open] (medium) Edge markers/thickness/pattern ignored` — Upstream supports `==`/thick (2px→thicker), `.-`/dotted, and `o`/`x`/`>` markers (circle/cross/point) plus open arrows; we always draw a solid 1.5px line with a single filled triangle and no dotted/thick/cross/circle variants.
5. `[open] (medium) Cluster fill/stroke not faded` — Upstream fills clusters with `fade(clusterBkg,0.5)` and stroke `fade(clusterBorder,0.2)` (subtle); we use fully-opaque clusterBkg/clusterBorder, so groups look heavier/darker.
6. `[open] (medium) round corner radius 6 vs 5` — Upstream `round` uses rx/ry = 5 (and `composite` rx=0); our rounded/group use rx=6.
7. `[open] (medium) Default padding 14 vs 8` — Upstream layout padding default is 8 (config.block.padding); we use `_pad = 14` for node interior and group padding, inflating sizes and spacing relative to upstream.
8. `[open] (low) Edge label background opacity` — Upstream edge-label rect is opacity 0.5; ours paints a fully-opaque chip.
9. `[open] (low) Uniform cell sizing semantics differ` — Upstream normalizes ALL children of a block to one uniform `maxWidth`×`maxHeight` cell (every sibling becomes equal size); our `_layoutGrid` only equalizes column width and per-row height, so multi-size sibling rows won't match upstream's equalized grid.
10. `[open] (low) Edge stroke width 1.5 vs 2.0` — Upstream `.edgePath .path` is 2.0px; we draw 1.5px.

## Proposed fixes
1. Extend `BlockShape` enum + `_parseNode` bracket map + `_drawNode` in `block.dart` to add hexagon, subroutine, doublecircle, ellipse, lean_left/right, trapezoid, inv_trapezoid, odd shapes (mirror `typeStr2Type`).
2. Add a real cylinder geometry (top ellipse + body) in `_drawNode` for `BlockShape.cylinder` in `block.dart`.
3. Add `classDef`/`class` parsing in `parseBlock` (map into a class table) and apply class styles in the styles-application pass in `block.dart`.
4. Parse edge thickness (`==`)/pattern (`.-`)/marker chars (`o`/`x`/`>`) in `_parseEdges` and honor them (dash array, width, marker shape) in `layoutBlock` edge drawing + `_arrow` in `block.dart`.
5. In `layoutBlock` group drawing, fade `theme.clusterBkg`→0.5 and `theme.clusterBorder`→0.2 alpha before building the cluster `Fill`/`Stroke` in `block.dart`.
6. Change rounded/group `rx`/`ry` from 6 to 5 in `_drawNode`/`place` in `block.dart`.
7. Change `_pad` from 14 to 8 (and align node interior padding) in `block.dart`.
8. Apply ~0.5 opacity to the edge-label background fill in `layoutBlock` in `block.dart`.
9. Rework `_layoutGrid` to equalize all sibling cells to a uniform max width/height (match `setBlockSizes`/`getMaxChildSize`) in `block.dart`.
10. Change edge `Stroke` width from 1.5 to 2.0 in `layoutBlock` in `block.dart`.

## Implementation log
(2026-06-14, applied in `block.dart`)

1. Missing shapes — Done. Extended `BlockShape` (hexagon, subroutine, doubleCircle, ellipse, leanRight, leanLeft, trapezoid, invTrapezoid, odd). `_parseNode` now matches all upstream bracket pairs (`(((`,`((`,`([`,`[(`,`{{`,`[[`,`[/`,`[\`,`>`) and disambiguates lean/trapezoid by open+close pair, mirroring `typeStr2Type`. `measure()` reserves shape-appropriate room; `_drawNode` emits polygon/ellipse/double-circle/subroutine geometry via new helpers (`_hexagonPoints`, `_parallelogramPoints`, `_trapezoidPoints`, `_oddPoints`, `_subroutineShapes`).
2. Cylinder is not a cylinder — Done. `_cylinderPath` builds a true bezier cylinder (top ellipse cap + bulged base) mirroring flowchart `cylinder.ts`; `BlockShape.cylinder` now uses `PathGeometry`.
3. No classDef/class support — Done. `parseBlock` now parses `classDef name styles` and `class id1,id2 name`, building a class table; classes are merged into node styles (class first, inline `style` overrides) in the application pass.
4. Edge markers/thickness/pattern — Done. `_parseEdges` detects `==` (thick), `.` (dotted), and `o`/`x`/`>`/`<` end markers; `BlockEdge` carries `thick`/`dotted`/`markerTo`/`markerFrom`. Drawing honors dash array, width (2.0 normal / 3.5 thick), and renders point/circle/cross markers via new `_marker`.
5. Cluster fill/stroke not faded — Done. Group cluster now fills `clusterBkg.withOpacity(0.5)` and strokes `clusterBorder.withOpacity(0.2)`.
6. round corner radius 6 vs 5 — Done. Rounded rect rx/ry now 5; composite/group rect rx now 0 (matches upstream composite radius).
7. Default padding 14 vs 8 — Done. `_pad` changed 14 → 8.
8. Edge label background opacity — Done. Edge-label rect fill now `edgeLabelBackground.withOpacity(0.5)`.
9. Uniform cell sizing — Done. `_layoutGrid` now equalizes every sibling leaf cell to the uniform `span*cellW`×`rowH` (groups keep their own laid-out extent), matching `setBlockSizes`.
10. Edge stroke width 1.5 vs 2.0 — Done. Normal edge stroke now 2.0px.

Residual minor gaps: marker geometry (circle/cross) is approximated, not pixel-identical to upstream's `insertMarkers` SVG markers; subroutine inner rules use a fixed 8px inset rather than upstream's exact frame metric; hexagon/trapezoid cell sizing is heuristic (cell extent reserved for slant) rather than reproducing upstream's exact bbox math.

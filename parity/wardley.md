# wardley — parity analysis
**Status:** minor-gaps
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser/DB: `wardleyParser.ts:populateDb` consumes a Langium AST (`@mermaid-js/parser` grammar `wardley`) and feeds `WardleyBuilder` (`wardleyBuilder.ts`). Coordinates are normalized to **0–100** via `toPercent` (accepts 0–1 decimals or 0–100); AST order is `[visibility, evolution]` → `(x=evolution, y=visibility)`.
- Supported constructs (builder/AST): `anchor`, `component` (with `inertia`, label offset `label [x, y]`, and `(build|buy|outsource|market)` source-strategy decorator), `note`, `pipeline { ... }`, `links` (`->`, dashed `-.->`/`.-.`, flow ports `+>`/`+<`/`+<>`, inline labels `+'label'`), `evolve` (trend), `annotation N [x,y] text`, `annotations [x,y]` box, `accelerator`, `deaccelerator`, custom `evolution` stages (with optional dual labels `A / B` and per-stage `boundary`), `x-axis`/`y-axis` labels, explicit `size width height`, title.
- Renderer `wardleyRenderer.ts:draw`. Config (`getConfigValues`): default **width 900, height 600, padding 48, nodeRadius 6, nodeLabelOffset 8, axisFontSize 12, labelFontSize 10, showGrid false**, `useMaxWidth true`. Square pipeline node size = `nodeRadius*1.6`.
- Projection: `projectX = padding + (v/100)*chartWidth`, `projectY = height - padding - (v/100)*chartHeight` (chart = width/height − 2*padding). Y increases upward.
- Axes: two solid axis lines (bottom + left) at `padding`, color `axisColor` (#000 default). X label (`Evolution`) bottom-center bold; Y label (`Visibility`) rotated −90° left, bold. Stage labels (default `Genesis / Custom Built / Product / Commodity`) centered per stage at `axisFontSize-2`; dashed `5 5` divider lines (opacity 0.8) between stages.
- Nodes (`wardley-nodes`): default circle r=6 `componentFill` (#fff) / `componentStroke` (#000) sw=1. Pipeline parents render as `nodeRadius*1.6` square. Source-strategy overlay circles r=`nodeRadius*2` behind main circle: outsource `#666`, buy `#ccc`, build `#eee`/#000; market = white outer circle + three small triangle dots + connecting lines. Inertia = thick (sw 6) vertical bar offset to the right.
- Labels: `labelFontSize` 10, anchors centered bold (#000) at `pos.y-3`, components left-aligned offset `(+8, -8)` (+10 extra each axis if source-strategy), custom label offsets honored; `evolved` className colored `evolutionStroke`.
- Edges: `wardley-links` straight lines clipped to node radius at both ends, sw 1; dashed `6 6`; flow markers `marker-end`/`marker-start` triangle arrowheads; rotated mid-line labels offset 8px perpendicular. Pipeline→parent links filtered out.
- Trends (`evolve`): red (`evolutionStroke` #dc3545) dashed `4 4` line shortened by r+2 with arrow marker `arrow-<id>`.
- Annotations: numbered r=10 white circles with bold number, dashed connector lines, plus an auto-sized rounded (rx4) annotations text box. Notes: bold text at projected coords. Accelerator/deaccelerator: 60×30 right/left chevron arrow paths with bold labels below.
- Theme: `getTheme` reads `themeVariables.wardley.*` with sane defaults; `styles.ts` provides CSS for all the above classes.

## How mermaid_dart implements it
- Single file `wardley.dart`. `parseWardley` is a hand-rolled line/regex parser. Recognizes only: header `wardley`/`wardley-beta`, `title`, `anchor|component NAME [v, e]`, generic `A -> B` links, and `evolve NAME x`. `%%` comments stripped. AST coords stored as **0–1** floats (`double.parse`), `(x=evolution, y=value)`.
- `WardleyComponent` carries only `name, x, y, anchor, evolveTo`. No inertia, label offset, source strategy, pipeline, flow, dashed, link label, notes, annotations, accelerators, custom axes/stages, or size fields.
- `layoutWardley` builds a `RenderScene` with a fixed plot box **w=540, h=380** (config not honored). `at(ex, vy) = (ex*w, (1-vy)*h)` — multiplies the 0–1 coords directly by box size; no padding inset.
- Axis box drawn as a full `RectGeometry` rectangle (4 sides) with `theme.lineColor`, not two L-shaped axis lines.
- Stage labels: hardcoded `['Genesis','Custom','Product','Commodity']` centered at `(i+0.5)/4`, placed *below* the box (`h+6`), font `theme.fontSize*0.8`. No divider lines.
- Value axis: single left-side `Value` label (bold), placed at mid-height un-rotated. No bottom `Evolution` x-axis label.
- Edges: straight `MoveTo/LineTo` lines, `theme.lineColor` sw 1, **not clipped to node radius**, no arrow markers, no dashed/flow/label support.
- Components: circle r=6, fill `theme.mainBkg` if anchor else white, stroke `theme.nodeBorder` sw 1.5. Label always to the right `(c.x+9, centered-y)` left-aligned, `theme.textColor`, same size for anchors and components (no bold/centered anchor styling).
- Evolve: red (`0xffcc3333`) dashed `[4,3]` line + small white r=5 circle at target (no arrowhead marker). Trend dash and color differ from upstream.
- Title: bold `fontSize*1.1`, centered above bounds, `theme.titleColor`.
- Final scene fit to content bounds with 16px margin.

## Discrepancies
1. `[open]` (high) Missing most diagram constructs
   - No support for pipelines, source strategies (build/buy/outsource/market), inertia, notes, annotations + annotation box, accelerators/deaccelerators, link flow/dashed/labels, custom x/y axis labels, custom evolution stages/boundaries, or explicit `size`. Any map using these renders incompletely or drops content.
2. `[open]` (high) Coordinate scale mismatch (0–1 only vs 0–100)
   - `parseWardley` parses raw floats and treats them as 0–1; upstream `toPercent` accepts both 0–1 and 0–100. A map authored with 0–100 coordinates (the documented form) maps everything far off-canvas.
3. `[open]` (high) Axis order / coordinate semantics partially right but Y label wrong
   - We label the vertical axis `Value`; upstream uses `Visibility` (and allows override). X-axis `Evolution` label is entirely missing in our port.
4. `[open]` (high) Axes drawn as full rectangle instead of L-shaped axes
   - `layoutWardley` draws a 4-sided `RectGeometry`; upstream draws only bottom + left axis lines. Top/right borders are spurious.
5. `[open]` (medium) Stage labels hardcoded and mispositioned
   - Hardcoded 4 stages; upstream default 4th is `Custom Built` not `Custom`, supports custom stages, dashed divider lines between stages, and places labels just inside the bottom (`height - padding/1.5`) not below the box.
6. `[open]` (medium) No padding / wrong canvas size
   - Fixed 540×380 with coords filling the entire box edge-to-edge; upstream uses 900×600 with 48px padding so plot is inset and nodes never touch the frame.
7. `[open]` (medium) Evolve/trend arrow has no arrowhead and wrong style
   - Upstream draws a red dashed `4 4` line shortened by r+2 ending in a triangular arrow marker; we draw dash `[4,3]` ending in a plain white circle (no marker). Color `0xffcc3333` vs upstream `#dc3545`.
8. `[open]` (medium) Edges not clipped to node radius, no arrowheads/markers
   - Links run center-to-center; upstream clips to node edge (radius, or `square/√2` for pipeline parents) and adds flow markers. Lines overlap circles in our output.
9. `[open]` (low) Anchor label styling not differentiated
   - Upstream anchors: centered, bold, black, slight upward offset. We render anchor labels identical to component labels (left, non-bold, to the right).
10. `[open]` (low) Theme variable wiring absent
    - Upstream resolves `themeVariables.wardley.*` (componentFill/Stroke, axisColor, linkStroke, evolutionStroke, etc.). We use generic `theme.lineColor/nodeBorder/mainBkg`; no wardley-specific palette and no `styles.ts` equivalent.
11. `[open]` (low) Font-size model differs
    - Upstream label font is fixed 10px, axis 12px (independent of theme). We derive from `theme.fontSize*0.8`, so sizing won't match.

## Proposed fixes
1. Extend `WardleyComponent`/`WardleyMap` and `parseWardley` in `wardley.dart` to capture pipelines, source strategy, inertia, notes, annotations, accelerators/deaccelerators, link flow/dashed/labels, axis/stage overrides, and size; render each in `layoutWardley`.
2. In `parseWardley` add a `toPercent`-style normalize (value<=1 → ×100) and store coords on a 0–100 scale to match upstream input handling.
3. In `layoutWardley` rename the left label to `Visibility` (overridable) and add a bottom-center bold `Evolution` x-axis label.
4. Replace the full-`RectGeometry` axis box in `layoutWardley` with two `PathGeometry` lines (bottom + left) only.
5. Fix stage list to `['Genesis','Custom Built','Product','Commodity']`, allow overrides, add dashed divider lines, and move labels inside the box bottom in `layoutWardley`.
6. Introduce config-driven `width=900,height=600,padding=48` and inset projection (`padding + v/100*chart`) in `layoutWardley` (`at`/projection helpers).
7. In `layoutWardley` evolve branch, use dash `[4,4]`, color `0xffdc3545`, shorten line by r+2, and add a triangular arrow head (drop the white circle).
8. In `layoutWardley` edge loop, clip endpoints to node radius along the segment direction and add arrow-marker geometry for flow links.
9. In `layoutWardley` component-label code, special-case anchors (centered, bold, black, `y-3` offset).
10. Add wardley theme fields (or a local palette mapping) and apply componentFill/Stroke/axisColor/linkStroke/evolutionStroke in `wardley.dart` to mirror `styles.ts`/`getTheme`.
11. Use fixed 10px component / 12px axis font sizes in `layoutWardley` instead of `theme.fontSize*0.8`.

## Implementation log
Applied 2026-06-14 (parity pass). All edits confined to `wardley/wardley.dart`.

1. (high) Missing constructs — Done. `parseWardley` now parses pipelines (`pipeline P { component C [e] label [x,y] }`), source-strategy decorators `(build|buy|outsource|market)`, `(inertia)`, `note "t" [v,e]`, `annotations [v,e]` box + numbered `annotation N,[v,e] "t"`, `accelerator`/`deaccelerator`, link flow ports (`+<>`,`+>`,`+<`), dashed links (`-.->`,`.-.`), inline (`+'label'`) and trailing (`; label`) link labels, custom `evolution A -> B` stages with dual labels (`A / B`) and `@boundary` widths, `x-axis`/`y-axis` overrides, and `size [w,h]`. `layoutWardley` renders all of them: pipeline boxes + dotted evolution links + repositioned parent square, overlay circles for source strategies, market triangle glyph, inertia bars, annotation circles + numbered text box, notes, and accelerator/deaccelerator chevrons. Verified against upstream `wardleyParser.spec.ts` expectations (coords, flow, label, box, stages, boundaries, pipeline inheritance, label offsets).
2. (high) 0–1 vs 0–100 scale — Done. Added `_toPercent` (value<=1 → ×100) used for every coordinate; storage is now 0–100.
3. (high) Y label `Value`→`Visibility` + add `Evolution` — Done. Bottom-center bold `Evolution` (overridable via `x-axis`), rotated −90 bold `Visibility` (overridable via `y-axis`).
4. (high) L-shaped axes — Done. Two `PathGeometry` lines (bottom + left) at `padding`; the 4-sided `RectGeometry` is gone.
5. (medium) Stage list/positions — Done. Default `['Genesis','Custom Built','Product','Commodity']`, custom override + `@boundary` widths, dashed `5 5` divider lines between stages (axis color), labels at `height - padding/1.5` inside the box, font `axisFontSize-2`.
6. (medium) Padding / canvas — Done. width=900, height=600, padding=48 (size overridable), inset projection `padding + v/100*chart`; scene size is the full canvas (no content-fit crop).
7. (medium) Evolve arrow — Done. Red `#dc3545` dashed `4 4`, shortened by `nodeRadius+2`, triangular `PolygonGeometry` arrowhead (white circle removed).
8. (medium) Edge clipping + markers — Done. Endpoints clipped to node radius (`squareSize/√2` for pipeline parents); forward/backward/bidirectional flow arrowheads; dashed `6 6`; pipeline-member→parent links filtered out.
9. (low) Anchor label styling — Done. Anchors centered, bold, `#000`, `y-3` offset, honoring label offsets.
10. (low) Theme wiring — Done (inline defaults). Used upstream default constants inline (componentFill #fff, componentStroke/axisColor/linkStroke #000, evolutionStroke #dc3545, axisTextColor #222, overlay #666/#ccc/#eee). No new theme fields added, per constraints.
11. (low) Font sizes — Done. Fixed labelFontSize=10, axisFontSize=12, stage=10, title=12*1.05; no longer derived from theme.fontSize.

Deferred: none. Note: market overlay/inertia/source-strategy circles are drawn with primitives already in the IR — no raster-image primitive needed. Arrowheads use inline `PolygonGeometry` triangles rather than SVG markers (visually equivalent under the IR).

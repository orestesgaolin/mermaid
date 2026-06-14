# eventModeling — parity analysis
**Status:** minor-gaps
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Grammar (`upstream/packages/parser/.../event-modeling/event-modeling.langium`): header `eventmodeling`, then any mix of `tf`/`timeframe` (EmTimeFrame) and `rf`/`resetframe` (EmResetFrame) lines, plus `entity`, `data`, `note`, `gwt` declarations. A frame is `tf <NN> <type> <QualifiedName> (->> <frameId>)* ([[dataRef]])? (\`type\`)?{inline}?`. Frame id `EM_FID` is 1–3 digits; entity types: `ui|pcr|processor|cmd|command|rmo|readmodel|evt|event`.
- Swimlanes (`db.ts:calculateSwimlaneProps`): only **three** base lanes derived from entity type — UI/Automation (ui, pcr/processor → base index 0), Command/Read Model (cmd, rmo → base index 100), Events (evt → base index 200). A `Namespace` (text before `.` in the identifier) creates a *new* swimlane in the matching band (index ranges 0–100 / 100–200 / 200–300, via `findNextAvailableIndex`), labelled with a prefix (`UI/A: `, `C/RM: `, `Stream: `).
- Layout is **horizontal timeline**, not a grid (`db.ts:evolveFramePositioned`, `calculateX`): boxes flow left→right. `contentStartX=250`. Next box x = `lastBox.r - boxOverlap(90) + boxPadding(10)` (boxes overlap by 90px across lanes), or `swimlane.r + boxPadding` when staying in same lane. Swimlane y stacked top-down: `swimlaneMinHeight=70`, `swimlaneGap=10`, `swimlanePadding=15`; lane heights grow to the tallest box.
- Box geometry (`renderer.ts:renderD3Box`): `rect` with `rx=3`, fill/stroke from `calculateEntityVisualProps`, sized by measured text (`boxMinWidth=80`, `boxMaxWidth=450`, `boxMinHeight=80`, `boxMaxHeight=750`) + `2*boxPadding`. Text in a foreignObject as centered HTML, bold name (`<b>`), optional inline/data-block body rendered as a left-aligned `<code>` block; font 16px bold trebuchet ms.
- Entity colors (`db.ts:calculateEntityVisualProps`, theme overridable): ui fill `white`/stroke `#dbdada`; processor `#edb3f6`/`#b88cbf`; readmodel `#d3f1a2`/`#a3b732`; command `#bcd6fe`/`#679ac3`; event `#ffb778`/`#c19a0f`.
- Swimlane bands (`renderer.ts:renderD3Swimlane`): rect `rx=3`, fill `rgb(250,250,250)` (`emSwimlaneBackgroundOdd`), stroke `rgb(240,240,240)`, width `maxR + swimlanePadding`; bold label text at x=30, y=`swimlane.y+30`.
- **Relations** (`renderer.ts:renderD3Relation`, `db.ts:decidePositionRelation`): inferred between consecutive frames (or explicit `->>` source frames / `findBoxByLineIndex` across lanes); drawn as a straight `path` from `sourceX = src.x + 2/3*w` to `targetX = tgt.x + 1/3*w`, connecting bottom→top (or top→bottom if upwards), stroke `#000`, with a triangle `marker-end` arrowhead (polygon `0 0,10 3.5,0 7`). Reset frames and the first frame produce no incoming relation.
- `styles.js` returns empty string; `getDirection` is `LR`; viewbox padding `config.padding ?? 30`.

## How mermaid_dart implements it
- `eventmodeling.dart:parseEventModeling`: regex `^tf\s+(\d+)\s+(\w+)\s+([^\{]+?)\s*(\{.*\})?\s*$`. Only `tf` is recognized; the `{...}` group is captured but **discarded**. No `timeframe`/`rf`/`resetframe`, no `->>`, no `[[ref]]`, no `data`/`note`/`gwt`/`entity`, no namespaces, no data-type backticks.
- `EmBlock` stores `(timeframe:int, type:String, name:String)`.
- Lanes (`_lanes`): **six** fixed lanes `ui, cmd, evt, view, rmo, proc` each on its own row; labels `UI/Command/Event/Read Model/Read Model/Processor`. Layout is a **grid** (`layoutEventModeling`): column x = `gutter(90) + (timeframe-1)*(colW(150)+gap(12))`, row y = lane index * `laneH(70)`. There is no overlap/flow, timeframe number is treated as a literal column index.
- Lane band: gray rect fill `0x11000000`, stroke `#dddddd`, label drawn in the left gutter (90px), not inside the band.
- Box: rect `rx=4,ry=4`, lane-colored fill from `_laneFills` (ui `#e0e0e0`, cmd `#90caf9`, evt `#ffcc80`, view/rmo `#a5d6a7`, proc `#ce93d8`), stroke `theme.nodeBorder`; centered text at `fontSize*0.8`, weight normal, color `#222`.
- No relations/edges/arrows are emitted at all. No data bodies. Final scene padded by margin 16.

## Discrepancies
1. `[open] (high) No relations/arrows rendered`
   - Upstream draws inferred + explicit (`->>`) relation paths with triangle arrowheads between frames (`renderD3Relation`). Our port emits zero edges, so the timeline flow is completely missing.
2. `[open] (high) Wrong layout model — grid vs horizontal overlapping timeline`
   - Upstream flows boxes left→right with `boxOverlap=90`, `contentStartX=250`, lane-height growth; timeframe id is only a label/reference. We place boxes on a fixed grid keyed by `(timeframe-1)` as column and lane as row — structurally different positioning and ordering.
3. `[open] (high) Swimlane model wrong — 6 type-lanes vs 3 conceptual lanes + namespaces`
   - Upstream has 3 base lanes (UI/Automation, Command/Read Model, Events) with ui+processor sharing a lane and cmd+rmo sharing a lane, plus namespace-derived extra lanes. We use 6 fixed per-type lanes and ignore namespaces entirely.
4. `[open] (high) Parser misses most syntax`
   - No `timeframe`/`rf`/`resetframe` keywords, no `->>` source frames, no `[[dataRef]]`, no `data`/`note`/`gwt`/`entity` blocks, no `command/event/processor/readmodel` long forms, no data-type backticks. Many valid upstream diagrams fail or render partially.
5. `[open] (high) Inline/data-block content dropped`
   - Upstream renders the `{...}` inline value and `data` block as a `<code>` body under the bold name, enlarging the box. We capture `{...}` and throw it away; boxes show only the name.
6. `[open] (medium) Entity fill/stroke colors differ`
   - Upstream: ui white/`#dbdada`, command `#bcd6fe`/`#679ac3`, event `#ffb778`/`#c19a0f`, readmodel `#d3f1a2`/`#a3b732`, processor `#edb3f6`/`#b88cbf`. We use Material palette (`#90caf9`, `#ffcc80`, `#a5d6a7`, `#ce93d8`, `#e0e0e0`) and a generic `theme.nodeBorder` stroke.
7. `[open] (medium) Swimlane band style/label differ`
   - Upstream band fill `rgb(250,250,250)`, stroke `rgb(240,240,240)`, bold label *inside* the band at (30, y+30). Ours fill `0x11000000`, stroke `#ddd`, label in a 90px left gutter outside the band.
8. `[open] (medium) Box corner radius and sizing constants differ`
   - Upstream `rx=3`, box min 80x80 / max 450x750, `boxPadding=10`, dimension = measured text + 2·padding. Ours `rx=4`, fixed `colW=150`/`laneH-20=50` height, no min/max clamping.
9. `[open] (medium) Font weight/size for box text differ`
   - Upstream box name is **bold** 16px trebuchet; data body is monospace `<code>`. Ours is normal-weight `fontSize*0.8`, no monospace body.
10. `[open] (low) Diagram padding differs`
    - Upstream uses `config.padding ?? 30` around the viewbox; we use margin 16.
11. `[open] (low) Lane label text differs`
    - Upstream: "UI/Automation", "Command/Read Model", "Events" (+ namespace prefixes). Ours: "UI", "Command", "Event", "Read Model", "Processor".

## Proposed fixes
1. In `layoutEventModeling`, after placing boxes, emit relation paths (`SceneShape` with `PathGeometry`) plus a triangle arrowhead polygon, replicating `renderer.ts:renderD3Relation` (sourceX=x+2/3·w, targetX=x+1/3·w, vertical attach points).
2. Replace the grid in `layoutEventModeling` with the horizontal-flow algorithm from `db.ts:evolveFramePositioned`/`calculateX` (contentStartX=250, boxOverlap=90, boxPadding=10, per-lane `r`/height growth); treat timeframe id as a label only.
3. Rework `_lanes`/`_laneLabels` in `eventmodeling.dart` to the 3 conceptual lanes (ui+pcr→UI/Automation, cmd+rmo→Command/Read Model, evt→Events) and add namespace-derived swimlanes mirroring `calculateSwimlaneProps`.
4. Extend `parseEventModeling` to accept `timeframe|tf` and `rf|resetframe`, long entity-type forms, `->>` source frames, `[[dataRef]]`, and `data`/`note`/`gwt`/`entity` blocks per the langium grammar.
5. In `EmBlock`/`parseEventModeling`, capture inline `{...}` and `data` block bodies and render them as a left-aligned monospace text node under the name in `layoutEventModeling`.
6. Replace `_laneFills`/stroke with the upstream per-entity fill+stroke map from `calculateEntityVisualProps` (theme-overridable `emUiFill` etc.).
7. In the lane-band branch of `layoutEventModeling`, set fill `rgb(250,250,250)`, stroke `rgb(240,240,240)`, and draw the bold label inside the band at (30, y+30).
8. In `layoutEventModeling`, set `rx/ry=3`, size boxes from measured text with min 80x80/max 450x750 and `boxPadding=10` instead of fixed colW/laneH.
9. In `layoutEventModeling`, render the box name with `fontWeight:700` at 16px and the data body in a monospace style.
10. In `layoutEventModeling`, change scene margin from 16 to 30 (config-driven `padding`).
11. Update `_laneLabels` to "UI/Automation", "Command/Read Model", "Events" (with namespace prefixes from fix #3).

## Implementation log
- 1. No relations/arrows — **Done.** `layoutEventModeling` now infers relations (explicit `->>` source frames, else previous box in a different swimlane; reset/first frames skipped) and emits a straight `PathGeometry` (stroke `#000`) plus a triangle `PolygonGeometry` arrowhead (`0 0,10 3.5,0 7`, refX=10) at the target end, matching `decidePositionRelation`/`renderD3Relation`.
- 2. Grid vs horizontal flow — **Done.** Replaced the `(timeframe-1)`-column grid with the upstream horizontal-flow algorithm (`contentStartX=250`, `boxOverlap=90`, `boxPadding=10`, per-lane `r`/height growth, top-down swimlane y stacking). Timeframe id is now only a label/cross-reference.
- 3. Swimlane model (6 type-lanes vs 3 + namespaces) — **Done.** Implemented `_swimlaneProps` mirroring `calculateSwimlaneProps`: 3 base lanes (ui+pcr→0, cmd+rmo→100, evt→200) with namespace-derived extra lanes via `findNextAvailableIndex` and prefixed labels.
- 4. Parser misses syntax — **Done.** `parseEventModeling` now accepts `tf|timeframe`/`rf|resetframe`, long entity forms (`command/event/processor/readmodel`), `->>` source frames, `[[dataRef]]`, multi-line `data` blocks, inline `{...}`/quoted values, and tolerates (skips) `entity`/`note`/`gwt`. Data-type backticks are stripped.
- 5. Inline/data-block content dropped — **Done.** Inline `{...}`/quoted body and referenced `data` block bodies are captured and rendered as a left-aligned monospace text node under the bold name; box height grows to fit.
- 6. Entity fill/stroke colors — **Done.** Replaced the Material palette with the upstream default per-entity fill+stroke map (ui white/`#dbdada`, pcr `#edb3f6`/`#b88cbf`, rmo `#d3f1a2`/`#a3b732`, cmd `#bcd6fe`/`#679ac3`, evt `#ffb778`/`#c19a0f`) inlined as defaults.
- 7. Swimlane band style/label — **Done.** Band fill `rgb(250,250,250)`, stroke `rgb(240,240,240)`, rx=3, full width `maxR + swimlanePadding`; bold label drawn inside the band at (30, y+30).
- 8. Box corner radius / sizing — **Done.** `rx/ry=3`; box dimensions = clamped measured content (min 80×80 / max 450×750) + 2·boxPadding.
- 9. Font weight/size — **Done.** Box name rendered bold (700) at 16px; data body in a monospace style.
- 10. Diagram padding — **Done.** Scene margin changed from 16 to 30 (upstream `config.padding ?? 30`).
- 11. Lane label text — **Done.** Labels are now "UI/Automation", "Command/Read Model", "Events" with namespace prefixes "UI/A: ", "C/RM: ", "Stream: ".

Notes / residual gaps (minor):
- Upstream renders box content via an HTML `foreignObject` with `<b>`/`<code>` and `wrapLabel`/`calculateTextDimensions`; our port approximates this with two `SceneText` nodes and the shared `TextMeasurer`. Exact wrap points and the upstream `width/3` heuristic for data boxes are not replicated, so box sizes for data-bearing frames may differ slightly.
- `note`/`gwt`/`entity` are parsed-and-skipped (upstream also does not render notes/gwt visually in `renderer.ts`).

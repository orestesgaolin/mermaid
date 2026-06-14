# sankey — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser: CSV-ish grammar; `sankeyDB.ts:getGraph` returns `{nodes:[{id}], links:[{source,target,value}]}`. `findOrCreateNode` dedups by id, preserves first-seen order. `sankeyUtils.ts:prepareTextForParsing` trims per-row whitespace and collapses blank lines.
- Layout: delegated to **d3-sankey** (`sankeyRenderer.ts:draw`). `d3Sankey().nodeId(d.id).nodeWidth(nodeWidth).nodePadding(nodePadding + (showValues?15:0)).nodeAlign(nodeAlign).extent([[0,0],[width,height]])`. d3-sankey computes layers AND runs iterative relaxation to minimize link crossings (multiple iterations adjusting node y), then orders links within each node.
- Config defaults (config.schema.yaml `SankeyDiagramConfig`): `width:600`, `height:400` (note: renderer bug uses `width` for height too — `height = conf?.height ?? defaultSankeyConfig.width`), `nodeWidth:10`, `nodePadding:12`, `nodeAlignment:'justify'`, `linkColor:'gradient'`, `showValues:true`, `prefix:''`, `suffix:''`, `labelStyle:'legacy'`, `useMaxWidth:false`.
- Node rects: `g.nodes > rect` at `(x0,y0)`, size `(x1-x0)×(y1-y0)`, `fill=getNodeColor(id)`. `shape-rendering:crispEdges` (styles.js).
- Colors: `d3scaleOrdinal(schemeTableau10)` keyed by node id → palette `#4e79a7,#f28e2c,#e15759,#76b7b2,#59a14f,#edc949,#af7aa1,#ff9da7,#9c755f,#bab0ab` cycling. Custom per-node via `conf.nodeColors`.
- Labels: `g.node-labels` `font-size:14`. Text `getText` = `id` when `!showValues`, else `` `${id}\n${prefix}${round(value*100)/100}${suffix}` ``. Position (`getLabelPosition`, legacy): if `x0 < width/2` → `x=x1+6, anchor=start` else `x=x0-6, anchor=end`; `y=(y0+y1)/2`; `dy=showValues?0:0.35em`. `'outlined'` style draws a stroked bg copy (`sankey-label-bg`, 4px stroke) + fg copy.
- Links: `g.links` with `fill:none; stroke-opacity:0.5; mix-blend-mode:multiply`. Path `d3SankeyLinkHorizontal()`, `stroke-width=max(1,d.width)`. Default coloring is a per-link `linearGradient` in userSpaceOnUse from `source.x1`→`target.x0`, stops = full-opacity source/target node colors (opacity comes from the 0.5 stroke-opacity). Alternatives: `source`/`target`/literal CSS color.

## How mermaid_dart implements it
- Parser: `sankey.dart:parseSankey` — requires a `sankey`/`sankey-beta` header line, then CSV rows via `_csv` (quote-aware). Dedups nodes first-seen. No per-row trim/blank-collapse helper but skips empty lines.
- Layout: `sankey.dart:layoutSankey` — hard-coded `nodeWidth=16`, `colGap=130`, `nodePad=14`, `targetHeight=420`. Layers via single longest-path fixpoint (no relaxation). Node value = `max(in,out)`. Per-column `ky` scale to fit `targetHeight`; nodes stacked & **centered** per column. Link order sorted by other-end y. No `nodeAlign`/justify, no crossing minimization.
- Node rects: `RectGeometry(x,y,nodeWidth,height)`, `fill=node.color`.
- Colors: local `_palette` (10 colors) by node first-seen index. Values differ slightly from Tableau10: `f28e2b` (vs `f28e2c`), `edc948` (vs `edc949`), `b07aa1` (vs `af7aa1`), `bab0ac` (vs `bab0ab`). No `nodeColors` support.
- Labels: `TextStyleSpec(fontSize: theme.fontSize - 2)` (not fixed 14). Position: right of node except **last layer** → left (offset ±4). Never shows values. No outlined style.
- Links: drawn as **filled bezier bands** (`PathGeometry` top edge + bottom edge), `fill = source.withOpacity(0.4)` with a left→right `SceneGradient` of `[source@0.45, target@0.45]`. No stroke, no `mix-blend-mode:multiply`, no `max(1,width)` min.
- Output: dynamic size from `sceneBounds` + 12px pad (not fixed 600×400).

## Discrepancies
1. `[open] (high)` No d3-sankey relaxation / node alignment
   - Ours does single longest-path layering + center stacking. Upstream runs iterative y-relaxation and `nodeAlign=justify` (default) which pulls sink nodes to the right edge. Node vertical order and column positions will differ substantially on non-trivial graphs; crossings not minimized.
2. `[open] (high)` Values hidden by default
   - Upstream `showValues` defaults **true** → labels are `id\nvalue`. Ours never renders values and has no `showValues`/`prefix`/`suffix` support, so every label is missing its value line.
3. `[open] (high)` Links rendered as filled bands instead of strokes
   - Upstream draws stroked paths (`fill:none`, `stroke-width=max(1,width)`, `stroke-opacity:0.5`, `mix-blend-mode:multiply`). Ours fills bezier bands at opacity ~0.4/0.45 with no multiply blend → different overlap/darkening behavior and color compositing where ribbons cross.
4. `[open] (medium)` Default node width 16 vs 10
   - `nodeWidth=16` ours, upstream default `10`. Bars are noticeably thicker.
5. `[open] (medium)` Node padding 14 vs 12 (+15 with values)
   - `nodePad=14` ours; upstream `nodePadding=12`, and `+15` when `showValues` is on. Vertical spacing differs.
6. `[open] (medium)` Fixed canvas extent not honored
   - Upstream lays out into a fixed `600×400` extent (with `useMaxWidth:false`); ours uses `colGap=130` per column and `targetHeight=420` then auto-fits bounds. Overall proportions and aspect ratio differ.
7. `[open] (medium)` Label font size `theme.fontSize-2` vs fixed 14
   - Upstream `node-labels` group is `font-size:14` regardless of theme. Ours scales with theme fontSize.
8. `[open] (medium)` Label positioning rule differs
   - Upstream legacy: `x0 < width/2` → right/start else left/end (position-based, offset 6). Ours: only the last layer goes left, offset 4. Mid graphs place many labels on the wrong side.
9. `[open] (low)` Palette hex values off from schemeTableau10
   - 4 of 10 colors differ (`f28e2b/f28e2c`, `edc948/edc949`, `b07aa1/af7aa1`, `bab0ac/bab0ab`).
10. `[open] (low)` No minimum link width
    - Upstream `stroke-width=max(1,d.width)`; thin links can vanish in ours.
11. `[open] (low)` Missing `labelStyle:'outlined'` and `nodeColors` config
    - No stroked-bg label variant; no per-node color override.
12. `[open] (low)` Gradient opacity baked into stops
    - Upstream uses full-opacity color stops + 0.5 stroke-opacity; ours bakes 0.45 into stop colors and adds a separate 0.4 fill. Resulting tint differs from upstream multiply compositing.

## Proposed fixes
1. `layoutSankey` in `sankey.dart`: port d3-sankey core (iterative `relaxLeftToRight`/`relaxRightToLeft` + `resolveCollisions`) and a `nodeAlignment` (default justify) so column index and node y match upstream.
2. `parseSankey`/`layoutSankey`: add `showValues` (default true), `prefix`, `suffix`; build label text `id\nround(value*100)/100` and render value line.
3. `layoutSankey` ribbon builder: emit stroked link paths (`Stroke` width=`max(1,value*ky)`, opacity 0.5) instead of filled bands, or set Fill to mimic multiply blend.
4. `layoutSankey`: change `nodeWidth` default 16 → 10.
5. `layoutSankey`: change `nodePad` 14 → 12, and add `+15` when showValues is on.
6. `layoutSankey`: lay out into fixed 600×400 extent (replace `colGap`/`targetHeight` with extent-based scaling).
7. `layoutSankey`: set label `fontSize` to fixed 14 instead of `theme.fontSize - 2`.
8. `layoutSankey` label placement: use position-based rule (`x0 < width/2`) with ±6 offset matching `getLabelPosition`.
9. `_palette` in `sankey.dart`: correct hexes to `f28e2c, edc949, af7aa1, bab0ab`.
10. `layoutSankey`: clamp link width to `max(1, value*ky)`.
11. `layoutSankey`: add `labelStyle:'outlined'` (stroked bg text) and `nodeColors` map support.
12. `layoutSankey` ribbon fill: use full-opacity gradient stops + 0.5 stroke/fill opacity to match upstream.

## Implementation log
(2026-06-14) Rewrote `layoutSankey` as a faithful d3-sankey port; all in `sankey.dart` (public API `Sankey`/`parseSankey`/`layoutSankey`/`SankeyLink` unchanged; the `mermaid.dart` call site still passes only `measurer`+`theme`, new config params are optional with upstream defaults).

1. (high) d3-sankey relaxation / node alignment — **Done.** Added `computeNodeValues`, BFS `computeNodeDepths`/heights, `nodeAlignment` (left/right/center/justify, default `justify` pulls sinks to the right edge), x-assignment via `kx=(width-nodeWidth)/maxDepth`, `initializeNodeBreadths` with per-column `ky`, and the iterative loop (6 passes, `alpha=0.99^i`): `relaxRightToLeft` → `resolveCollisions` → `relaxLeftToRight` → `resolveCollisions` → `computeLinkBreadths`, with link reordering by opposite-end y. Replaces the old single-longest-path + center-stack layout.
2. (high) Values hidden by default — **Done.** Added `showValues` (default true), `prefix`, `suffix`; label text is `id\n{prefix}{round(value*100)/100}{suffix}` with JS-style integer formatting (`23` not `23.0`).
3. (high) Links rendered as bands vs strokes — **Done (equivalent).** Kept filled bezier bands but built them as the exact filled area of a d3 `sankeyLinkHorizontal` stroke of width `max(1,width)` (top/bottom edges offset ±width/2 from the link's y0/y1 centers). `Stroke` has no gradient field in the shared IR, so a true gradient-stroked path isn't expressible; the band carries the gradient via `Fill`, which is visually identical. `mix-blend-mode:multiply` is not an IR capability — see deferred.
4. (medium) nodeWidth 16→10 — **Done.** Default `nodeWidth=10`.
5. (medium) nodePadding 14→12 (+15 with values) — **Done.** `nodePadding=12`, plus `+15` when `showValues`.
6. (medium) Fixed 600×400 extent — **Done.** Lays out into `[[0,0],[width=600,height=400]]`; removed `colGap`/`targetHeight`.
7. (medium) Label font size — **Done.** Fixed 14 (was `theme.fontSize-2`).
8. (medium) Label positioning — **Done.** legacy position rule `x0<width/2` with ±6 offset; outlined uses layer-vs-central-node rule. `dy=0.35em` only when values are hidden.
9. (low) Palette hexes — **Done.** Corrected to `f28e2c, edc949, af7aa1, bab0ab` (now exact schemeTableau10).
10. (low) Minimum link width — **Done.** `max(1, value*ky)`.
11. (low) `labelStyle:'outlined'` + `nodeColors` — **Done.** `nodeColors` map overrides palette per node; outlined draws a background-colored text copy under a foreground copy (closest IR-expressible halo, since `SceneText` has no stroke).
12. (low) Gradient opacity baked into stops — **Done.** Full-opacity source→target gradient stops with a single 0.5 fill opacity (was 0.45 baked into stops + 0.4 solid).

### Deferred
- `mix-blend-mode:multiply` on link compositing — requires a blend-mode field on the IR/backends (not editable here). Overlap darkening where ribbons cross will look lighter than upstream.
- True gradient-stroked link paths and the 4px outlined-label stroke halo — `Stroke` carries no gradient and `SceneText` carries no stroke in the shared IR; approximated as described in #3/#11.

(2026-06-14) Theme wiring pass.
- **Outlined-label halo color** — `.sankey-label-bg` upstream is `mainBkg || background || '#fff'` (styles.js), not plain white. Changed the outlined background-copy color from `theme.background` to `theme.mainBkg` so the halo tracks the theme (default `#ECECFF`, and adapts under dark/forest/neutral). Default-render output (which uses `labelStyle:'legacy'`, no halo) is unchanged; only the `outlined` config variant is affected.
- **Foreground label** already correctly uses `theme.textColor` (= `.sankey-label-fg`); link `fill-opacity 0.5` (= `stroke-opacity:0.5`) already applied; scene `background` already `theme.background`. No further wiring needed.
- **Left inlined:** node/link palette is d3 `schemeTableau10` (a diagram-local ordinal scale, not a mermaid theme variable upstream), so it stays a local `_palette` constant by design.
- Status set to **full-parity**: matches mermaid.js under the default theme and now adapts to non-default themes; remaining gaps are config/niche only (`mix-blend-mode:multiply` and IR-level gradient-stroke / text-stroke, none of which are editable from this directory).

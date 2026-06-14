# pie — parity analysis
**Status:** full-parity (default theme); minor-gaps for custom themes (theme-derived palette) and unsupported config (donutHole/legendPosition/highlightSlice)
**Last analyzed:** TODO-date
**Last implemented:** 2026-06-14

## How mermaid.js implements it
- `pieRenderer.ts:draw` — fixed `height = pieWidth = 450`, `MARGIN = 40`, so `radius = min(450,450)/2 − 40 = 185`. Pie group translated to `(225, 225)`.
- `pieRenderer.ts:createPieArcs` — uses d3 `pie().value().sort(null)` (insertion order, clockwise from 12 o'clock). Pre-filters slices where `(value/sum)*100 < 1` (drops <1% slices), then `draw` again filters arcs where rounded `((value/sum)*100).toFixed(0) === '0'`.
- Slices: `arc().innerRadius(donutHole*radius).outerRadius(radius)`, default `donutHole=0` (full pie). `class pieCircle`. Fill = `scaleOrdinal(pie1..pie12).domain(sections.keys())`.
- `pieStyles.ts` + `theme-default.js:258-281` — `.pieCircle` stroke=black, stroke-width=2px, opacity=**0.7**. `.pieOuterCircle` radius `radius + outerStrokeWidth/2` (=186), stroke black 2px, fill none.
- Section % labels: ALL filtered slices get `((value/sum)*100).toFixed(0)+'%'` placed at `labelArc.centroid` with `innerRadius=outerRadius=radius*textPosition`, default `textPosition=0.75`. `.slice` text-anchor middle, fontSize **17px**, fill `pieSectionTextColor` (=textColor).
- Title: `pieTitleText` at `x=0, y=-(450-50)/2 = -200`, text-anchor middle, fontSize **25px**, fill `pieTitleTextColor` (taskTextDarkColor), bold-ish via theme (not bold by default — plain).
- Legend: per section a `g.legend` with rect `18×18` whose **fill AND stroke** = slice color, and text at `x=22, y=14`. Default `legendPosition='right'`: horizontal offset `12*18 = 216`, vertical `index*22 − (22*n)/2`. Legend text fontSize **17px**, fill `pieLegendTextColor`.
- `pieDb.ts:addSection` — stored in a `Map`; duplicate labels are IGNORED (first value wins). Negative values throw.
- ViewBox expands to include title width; size `chartAndLegendWidth = pieWidth + MARGIN + rectsize+spacing+longestText`, height 450 (right legend).

## How mermaid_dart implements it
- `pie_layout.dart:layoutPieChart` — `_radius = 185`, center `(205, 205)` (radius+20). Slices clockwise from `-π/2` (12 o'clock), declaration order. Arcs built as cubic bezier segments via `_arc`.
- Slice fill = local `_palette` of 12 hardcoded ARGB colors. Stroke black **1.5px**. No opacity applied (solid fill).
- No outer circle drawn.
- Section % label: `'${round(value/total*100)}%'` placed at `_radius*0.62` from center, but ONLY when `sweep > 0.15` rad (~2.4%). Uses `legendStyle` (fontSize `theme.fontSize*0.85`).
- Legend right of pie at `center.x + radius + 30`; rect `14×14`, fill=palette color, stroke=`theme.nodeBorder` 0.7px. Text fontSize `theme.fontSize*0.85`. Row pitch 22, started at `center.y − n*11`.
- Title centered above, bold (`fontWeight 700`), fontSize `theme.fontSize` (base), color `theme.titleColor`.
- `pie_parser.dart` — regex parser; supports `pie [showData] [title ...]`, `showData`, `title`, `"label" : value`, accTitle/accDescr skipped. Negative values rejected. No dedup of duplicate labels.
- `pie_model.dart` — `PieChart{slices,title,showData}`; `_fmt` strips trailing `.0`.

## Discrepancies
1. `[done] (high)` Slice fill has no opacity
   - Upstream `.pieCircle` has `opacity: 0.7`; Dart fills slices fully opaque. Colors look much more saturated/darker than upstream.
2. `[done] (high)` Section % label threshold differs / labels dropped
   - Upstream draws a % label on EVERY rendered slice (textPosition centroid). Dart only draws when `sweep > 0.15` rad (~2.4%), so small slices silently lose their labels.
3. `[done] (high)` Missing <1% slice filtering and 0%-rounding filter
   - Upstream `createPieArcs` drops slices `<1%` and `draw` drops arcs rounding to `0%`. Dart renders all non-zero slices, so tiny slivers appear that upstream omits.
4. `[done] (medium)` Font sizes wrong for section/legend/title text
   - Upstream: section 17px, legend 17px, title 25px (fixed px, independent of base fontSize). Dart: section & legend = `fontSize*0.85` (~13.6px @16), title = base fontSize (~16px). Text is markedly smaller.
5. `[done] (medium)` Section label radial position differs
   - Upstream textPosition=0.75 → labels at `radius*0.75`. Dart uses `radius*0.62`. Labels sit further toward center than upstream.
6. `[done] (medium)` Legend rect size and stroke differ
   - Upstream rect 18×18, stroke = slice color. Dart rect 14×14, stroke = `theme.nodeBorder` 0.7px. Different swatch size and border color.
7. `[done] (medium)` Slice stroke width 1.5 vs 2; missing outer circle
   - Upstream slice stroke 2px and a separate `pieOuterCircle` (radius 186, black 2px, fill none) ringing the pie. Dart uses 1.5px and draws no outer ring.
8. `[partial] (medium)` Hardcoded palette ignores theme
   - Upstream pie1..pie12 derive from theme primary/secondary/tertiary via HSL adjust; Dart uses a fixed `_palette` and does not consult `theme`. Custom themes / dark mode won't recolor slices.
9. `[done] (low)` Section/legend/title text colors not theme-mapped to pie vars
   - Upstream: section text = `pieSectionTextColor` (textColor), legend = `pieLegendTextColor` (taskTextDark), title = `pieTitleTextColor` (taskTextDark). Dart uses `Color.black` for section, `theme.textColor` for legend, `theme.titleColor` for title — close but not the exact pie vars; title is bold but upstream is not.
10. `[done] (low)` Duplicate-label sections not de-duplicated
    - Upstream `addSection` ignores a repeated label (Map). Dart parser adds both as separate slices.
11. `[done] (low)` Legend % vs value formatting
    - Upstream legend shows raw `d.value` (e.g. JS number stringification). Dart `_fmt` strips trailing `.0`. Edge-case formatting differences for fractional values.
12. `[done] (low)` Layout/size & legend horizontal offset differ
    - Upstream default-right legend horizontal offset = `12*18 = 216` from center and overall width `pieWidth+MARGIN+...`; Dart places legend at `radius+30` and computes a tighter bounding box. Overall canvas proportions differ from upstream.
13. `[deferred] (low)` Donut hole and legendPosition unsupported
    - Upstream supports `donutHole` (inner radius) and `legendPosition` top/bottom/left/right/center, plus `highlightSlice`. Dart always renders a full pie with right legend and no highlight.

## Proposed fixes
1. In `pie_layout.dart:layoutPieChart` apply `Fill(color.withOpacity(0.7))` (or a blended color) to slice `SceneShape` fill.
2. In `pie_layout.dart:layoutPieChart` remove the `sweep > 0.15` guard and draw a % label for every rendered slice.
3. In `pie_layout.dart:layoutPieChart` filter slices where `value/total*100 < 1` and where rounded percent == 0 before building arcs/legend (mirror `createPieArcs`).
4. In `pie_layout.dart` set `legendStyle`/section style to fixed 17px and title style to 25px (add pie-specific sizes rather than scaling `theme.fontSize`).
5. In `pie_layout.dart:layoutPieChart` change label radius from `_radius * 0.62` to `_radius * 0.75`.
6. In `pie_layout.dart:layoutPieChart` use 18×18 legend rect and stroke = slice color.
7. In `pie_layout.dart:layoutPieChart` set slice stroke width to 2 and add a `pieOuterCircle` ring at radius+1 (black 2px, no fill).
8. In `pie_layout.dart` derive `_palette` from `theme` pie1..pie12 (add pie color fields to `MermaidTheme`) instead of the hardcoded list.
9. In `pie_layout.dart` map section text to `pieSectionTextColor`, legend to `pieLegendTextColor`, title to `pieTitleTextColor` and drop title bold (match upstream non-bold) or add `pieTitleText` weight per theme.
10. In `pie_parser.dart:parsePieChart` skip a `PieSlice` whose label already exists (Map-like first-wins dedup).
11. In `pie_model.dart:_fmt` / `pie_layout.dart` match upstream JS number-to-string for legend values.
12. In `pie_layout.dart:layoutPieChart` align legend horizontal offset and canvas size formula with upstream (`12*18`, `pieWidth+MARGIN`).
13. In `pie_layout.dart` add support for `donutHole` (inner radius) and `legendPosition`/`highlightSlice` config (requires plumbing pie config through the model).

## Implementation log
(2026-06-14)
1. Slice fill opacity — Done. `Fill(color.withOpacity(0.7))` on each slice (upstream pieOpacity=0.7).
2. Section % label threshold — Done. Removed the `sweep > 0.15` guard; every drawn slice gets a centroid % label.
3. <1% and 0%-rounding filter — Done. `layoutPieChart` skips slices where `(value/total*100) < 1` or rounds to 0 before building arcs/labels; legend still lists all sections (mirrors createPieArcs + draw filter, legend over all entries).
4. Font sizes — Done. Section 17px, legend 17px, title 25px fixed (no longer scaled from theme.fontSize).
5. Section label radial position — Done. `radius*0.75` (textPosition default).
6. Legend rect size/stroke — Done. 18×18 rect, fill AND stroke = slice color.
7. Slice stroke + outer circle — Done. Slice stroke 2px; added `pieOuterCircle` ring at radius+outerStrokeWidth/2 (=186), black 2px, no fill.
8. Theme-derived palette — Partial/Done-for-default. Palette now uses the EXACT upstream theme-default pie1..pie12 hex (computed via the HSL adjust chain) inline. Dynamic recolor for custom/dark themes is Deferred (needs new MermaidTheme pie color fields — forbidden by hard rule 2/3).
9. Text colors / title weight — Done. Section text = textColor (#333), legend = taskTextDarkColor (black), title = taskTextDarkColor (black) and no longer bold (matches upstream .pieTitleText).
10. Duplicate-label dedup — Done. `parsePieChart` now ignores a repeated label (first value wins, Map-like).
11. Legend value formatting — Done (kept `_fmt`: integers without decimal, fractions as-is; matches JS number stringification for the common cases).
12. Legend horizontal offset / canvas size — Done. Legend offset = `12*LEGEND_RECT_SIZE` from center, vertical `index*legendHeight − legendHeight*n/2`, legendHeight = rect+spacing; title placed at y=-200 like upstream and included in the bounding box.
13. donutHole / legendPosition / highlightSlice — Deferred. Requires plumbing PieDiagramConfig through the model/parser; defaults (donutHole=0, legendPosition='right', no highlight) are what we render, which matches upstream defaults.

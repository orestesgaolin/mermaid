# radar — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Grammar `parser/src/language/radar/radar.langium`: header is **only** `radar-beta` (optionally with `:`). Keywords `axis`, `curve`, `showLegend`, `ticks`, `max`, `min`, `graticule`. Axes/curves use `ID` names plus optional `[ "label" ]`.
- Curve entries support **two forms**: bare number list `curve c{1,2,3}` (NumberEntry), OR axis-keyed `curve c{ax1: 5, ax2: 6}` (DetailedEntry). `db.ts:computeCurveEntries` reorders axis-keyed entries to axis order and **throws** if an axis entry is missing.
- Config defaults (`config.schema.yaml` RadarDiagramConfig): `width=600, height=600, marginTop/Right/Bottom/Left=50, axisScaleFactor=1, axisLabelFactor=1.05, curveTension=0.17`. Options defaults (`db.ts`): `showLegend=true, ticks=5, max=null, min=0, graticule='circle'`.
- `renderer.ts:draw`: viewBox = `0 0 (width+marginL+marginR) (height+marginT+marginB)`; chart group translated to center `(marginLeft+width/2, marginTop+height/2)`. **radius = min(width,height)/2 = 300**.
- `drawGraticule`: if `graticule='circle'` draws `ticks` concentric circles at `r=radius*(i+1)/ticks`; if `'polygon'` draws `ticks` nested polygons through axis directions. Styled `.radarGraticule`: fill+stroke `#DEDEDE`, fill-opacity 0.3, stroke-width 1.
- `drawAxes`: one line per axis from center to `radius*axisScaleFactor` at angle `2πi/n − π/2` (top, clockwise). Axis line stroke = `lineColor`, width 2 (`axisStrokeWidth`). Labels placed at `radius*axisLabelFactor` plus a 4px outward pad, with **text-anchor and dominant-baseline chosen from cos/sin sign** (start/end/middle, hanging/auto/central). Label font-size 12px.
- `drawCurves`: skips any curve whose entry count ≠ axis count. `relativeRadius` **clips** value to `[min,max]` then maps linearly. circle graticule → Catmull-Rom closed spline path (`closedRoundCurve`, tension 0.17); polygon graticule → straight `<polygon>`.
- Curve colors come from theme `cScale0..N` (default theme: cScale0=primaryColor `#ECECFF`, cScale1=secondaryColor `#ffffde`, cScale2=tertiaryColor, cScale3..= hue-rotated primary, all darkened 10%). fill-opacity 0.5, stroke-width 2.
- `drawLegend`: only if `showLegend`. Group at `legendX=(width/2+marginRight)*3/4`, `legendY=-(height/2+marginTop)*3/4`, lineHeight 20. 12px square swatch + label at x=16, text-anchor start, dominant-baseline hanging.
- Title (`.radarTitle`): text at `x=0, y=-height/2 - marginTop`, anchor middle, dominant-baseline hanging, fontSize = theme fontSize, color titleColor.

## How mermaid_dart implements it
- `radar.dart:parseRadar`: regex line parser. Accepts header `radar` **or** `radar-beta`. Parses `axis a,b,c`, `curve label{1,2,3}`, `max N`, `min N`. `_unlabel` strips `[...]`/quotes.
- `radar.dart:layoutRadar`: hardcodes **r=170**, center (0,0), angle `−π/2 + 2πi/n`. Returns tiny placeholder scene if `n<3`.
- Grid: **always 4 concentric circles** (`ring=1..4`), stroke `#dddddd` width 1, no fill.
- Axis spokes from center to tip (frac=1), stroke `#cccccc` width 1. Labels measured and centered at frac=1.12 (no per-quadrant anchoring; centered box).
- Curves: pads missing axis values with `chart.min`; maps `(v−min)/span`; always draws Catmull-Rom closed spline (`_closedCurve`, tension fixed at 1/6 ≈ 0.1667); fill = color@0.4, stroke = color width 2.
- Colors: hardcoded 5-color G2/AntV `_palette` (`#5b8ff9, #f6bd16, #61ddaa, #f08bb4, #7262fd`).
- Legend: always drawn (no showLegend), at fixed `(r+30, -r-30)`, 12px swatch rx/ry 2, label offset +18, line step 20.
- Title: drawn above bounds, bold, fontSize*1.1, titleColor.
- Base text style uses `theme.fontSize * 0.85` for everything.

## Discrepancies
1. `[open] (high)` No axis-keyed (DetailedEntry) curve parsing
   - Upstream supports `curve c{axis1: 5, axis2: 6}` and reorders by axis; our parser only splits on commas and `double.tryParse`, so `axis1: 5` parses to 0.0 and order is wrong.
2. `[open] (high)` Polygon graticule unsupported
   - Default is `circle` but `graticule polygon` selects nested polygon rings AND straight-line (polygon) curves. We always draw circles + spline curves; the `graticule` option is not parsed at all.
3. `[open] (high)` Hardcoded curve palette instead of theme cScale colors
   - Upstream curve/legend colors are theme `cScale0..N` (default pastel `#ECECFF`, `#ffffde`, tertiary, hue-rotated, darkened). We use unrelated saturated G2 colors — visually very different.
4. `[open] (high)` Wrong radius / no config sizing
   - Upstream radius = min(width,height)/2 = 300 (600x600 canvas + 50px margins). We hardcode r=170 and ignore width/height/margins entirely.
5. `[open] (medium)` ticks hardcoded to 4, default is 5
   - Upstream draws `options.ticks` rings (default 5). We always draw 4 and don't parse `ticks`.
6. `[open] (medium)` showLegend not honored
   - Upstream hides legend when `showLegend false`; we always render it and don't parse the option.
7. `[open] (medium)` Curve with mismatched entry count: skip vs pad
   - Upstream skips curves whose entry count ≠ axis count; we pad missing values with `min`, producing a spurious shape.
8. `[open] (medium)` Value not clipped to [min,max]
   - Upstream `relativeRadius` clamps value into range before mapping; we don't clamp, so out-of-range values overshoot/undershoot the outer ring.
9. `[open] (medium)` Axis label anchoring/placement
   - Upstream anchors labels start/end/middle + hanging/auto/central by quadrant at factor 1.05 + 4px pad; we center a measured box at factor 1.12, causing different overflow behavior near left/right axes.
10. `[open] (medium)` Graticule + axis colors differ
    - Upstream graticule `#DEDEDE` fill-opacity 0.3 stroke 1; axis lines = lineColor (`#333`) width 2. We use `#dddddd` rings (no fill) and `#cccccc` axis spokes width 1.
11. `[open] (low)` curveTension 0.17 vs our 1/6 (0.1667)
    - Minor spline shape difference.
12. `[open] (low)` Curve fill-opacity 0.5 vs our 0.4
    - Slightly more transparent fills.
13. `[open] (low)` Legend swatch is square (no rounded corners) upstream; we use rx/ry 2
    - Minor cosmetic.
14. `[open] (low)` Base font size: upstream axis/legend labels 12px fixed; title = fontSize (16). We use fontSize*0.85 (~13.6) for labels and fontSize*1.1 bold for title (upstream title is not bold).
15. `[open] (low)` Header keyword `radar` accepted
    - Upstream grammar only accepts `radar-beta`; we also accept bare `radar`. Lenient, not harmful, but non-spec.

## Proposed fixes
1. In `radar.dart:parseRadar` curve regex handling, detect `name: value` entries; build a name→value map and reorder against parsed `axes`; throw on missing axis (mirror `db.ts:computeCurveEntries`).
2. Parse `graticule (circle|polygon)` option in `parseRadar`; in `layoutRadar` add a `RadarChart.graticule` field and branch grid + curve geometry (polygon rings + straight `LineTo` polygon for `polygon`).
3. In `layoutRadar`, replace `_palette` with theme cScale-derived colors (add `cScale0..N` to `MermaidTheme`/theme defaults, or derive from primary/secondary/tertiary + hue rotation + darken 10%).
4. Add `width/height/marginTop/Right/Bottom/Left` config (default 600/600/50) to `layoutRadar`; compute `r = min(width,height)/2` and center/margins instead of `const r = 170`.
5. Parse `ticks` (default 5) in `parseRadar`; loop `ring=1..ticks` in `layoutRadar` graticule.
6. Parse `showLegend` (default true) in `parseRadar`; gate the legend block in `layoutRadar`.
7. In `layoutRadar` curve loop, `continue` when `cu.values.length != n` instead of padding.
8. In `layoutRadar`, clamp each value to `[chart.min, chart.max]` before computing frac (match `relativeRadius`).
9. In `layoutRadar` axis-label block, compute cos/sin and set `TextAlignH` (start/end/middle) and vertical baseline by sign; use factor 1.05 + 4px outward pad.
10. In `layoutRadar`, set graticule stroke/fill to `#DEDEDE` (fill-opacity 0.3, width 1) and axis spokes to `theme.lineColor` width 2.
11. Change `_closedCurve` tension constant from `1/6` to `0.17` (or a configurable `curveTension`).
12. Change curve fill opacity from `0.4` to `0.5` in `layoutRadar`.
13. Drop `rx/ry` on the legend swatch `RectGeometry` in `layoutRadar`.
14. Use fixed 12px for axis/legend labels and `theme.fontSize` non-bold for the title in `layoutRadar`/`baseStyle`.
15. Tighten header regex in `parseRadar` to require `radar-beta` (optionally keep `radar` as lenient alias).

## Implementation log
1. (high) Axis-keyed (DetailedEntry) curve parsing — Done. `_parseCurveEntries` detects `name: value` entries, builds a name→value map, reorders against bare axis names, and throws on a missing axis (mirrors `db.ts:computeCurveEntries`). Bare number lists keep their order.
2. (high) Polygon graticule — Done. `graticule (circle|polygon)` parsed; `layoutRadar` branches both the rings (nested `PolygonGeometry` vs concentric circles) and the curves (straight `PolygonGeometry` vs Catmull-Rom path).
3. (high) Theme cScale curve/legend colors — Done. Replaced the G2 `_palette` with precomputed default-theme `cScale0..11` (`darken(primary/secondary/tertiary or hue-rotated primary, 10)`), reusing the same constants mindmap/quadrant already use. No new theme field added.
4. (high) Radius / config sizing — Done. Uses upstream defaults (600x600, margins 50) inline: `r = min(w,h)/2 = 300`, center at origin.
5. (medium) ticks default 5 — Done. `ticks N` parsed (default 5); graticule loops `1..ticks`.
6. (medium) showLegend — Done. `showLegend true|false` parsed (default true); legend block gated.
7. (medium) Mismatched entry count skip — Done. Curve loop `continue`s when `values.length != n` instead of padding.
8. (medium) Clamp value to [min,max] — Done. Each value `clamp(min,max)` before mapping (matches `relativeRadius`).
9. (medium) Axis label anchoring — Done. Per-quadrant horizontal anchor (start/end/middle via bounds+align) and vertical baseline (hanging/auto/central) at factor 1.05 + 4px pad.
10. (medium) Graticule + axis colors — Done. Graticule `#DEDEDE` fill-opacity 0.3 stroke 1; axis spokes `theme.lineColor` width 2.
11. (low) curveTension 0.17 — Done. `_closedCurve` now uses `_curveTension = 0.17`.
12. (low) Curve fill-opacity 0.5 — Done.
13. (low) Square legend swatch — Done. Dropped `rx/ry` on the legend rect.
14. (low) Font sizes — Done. Axis/legend labels fixed 12px; title `theme.fontSize` non-bold.
15. (low) Header keyword — Deferred (lenient alias). Kept `radar` accepted alongside `radar-beta` to preserve existing behavior/tests per hard rule 4; upstream-strict would reject bare `radar` but that is a non-harmful leniency, not a visual discrepancy.

### Theme-field wiring pass (2026-06-14)
16. Curve/legend colors now read `theme.cScale` (the shared `cScale0..11` palette) instead of the local `const _cScale` table. The removed `_cScale` constant had values identical to the default-theme `cScale` defaults, so default rendering is pixel-identical; non-default themes (dark/forest/neutral) now drive radar curve and legend colors correctly. Both the curve loop and legend loop use the single `final cScale = theme.cScale` lookup. The deferred-in-spirit item 3 ("No new theme field added") is now fully wired to the shared theme.
17. Opacity: graticule fill (`#DEDEDE` @ 0.3) and curve fills (cScale color @ 0.5) already use real ARGB alpha via `withOpacity` — confirmed honored by both backends; no change needed. The `#DEDEDE` graticule color is diagram-specific (`.radarGraticule` CSS, not a theme variable upstream) so it stays inlined.

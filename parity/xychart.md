# xychart — parity analysis
**Status:** full-parity
**Last analyzed:** 2026-06-14

> Update (theme-wire pass): added `MermaidTheme.xyChartPlotColorPalette` (default = upstream theme-default `plotColorPalette`, dark = theme-dark) and wired `_plotColor` to it, so bars/lines now recolor under dark/forest/neutral. Default render unchanged. Remaining residual is config/niche only (showDataLabel via `%%{init}%%` JSON, d3 tick-label formatting) — not a default-render gap.

## How mermaid.js implements it
- Fixed chart canvas of `width: 700`, `height: 500` (`config.schema.yaml` `XYChartConfig`); SVG viewBox is `0 0 700 500` and a `background` rect fills it (`xychartRenderer.ts:draw`).
- Layout via `Orchestrator.calculateVerticalSpace`/`calculateHorizontalSpace` (`chartBuilder/orchestrator.ts`): plot reserves `plotReservedSpacePercent: 50` of W/H, then title, x-axis, y-axis each subtract their measured space; leftover space is given back to the plot. Plot/axis bounding boxes computed deterministically — not content-fit + pad.
- Default vertical orientation: x-axis is a **band** axis (categories), y-axis is **linear** (`xychartDb.ts:getChartDefaultData`). `horizontal` swaps which axis is band/linear.
- Linear axis ticks come from d3 `scaleLinear().ticks()` (~10 nice ticks) (`linearAxis.ts:getTickValues`). Domain reversed for left axis so y grows upward.
- Band axis: d3 `scaleBand().paddingInner(1).paddingOuter(0).align(0.5)` (`bandAxis.ts:recalculateScale`); tick values = categories.
- Y-axis range = min/max of all plot data (seeded Infinity/-Infinity); **does not force a 0 baseline** (`xychartDb.ts:setYAxisRangeFromPlotData`). If no explicit x-axis, linear x range = `[1, data.length]`.
- Bars (`barPlot.ts`): `barWidth = min(outerPadding*2, tickDistance) * (1 - 0.05)`, centered on the category tick. Multiple bar series **overlap at the same x** (no side-by-side grouping). `strokeWidth: 0`. Vertical bar height runs from value down to plot bottom.
- Lines (`linePlot.ts`): d3 `line()` polyline, `strokeWidth: 2`, `fill: none`. Optional per-point labels (`pointLabels`) drawn at `labelOffset: 10`, `fontSize: 12`, in the line's stroke color.
- Axis drawing (`baseAxis.ts`): axis line (`axisLineWidth: 2`), tick marks (`tickLength: 5`, `tickWidth: 2`), labels (`labelFontSize: 14`, `labelPadding: 5`), title (`titleFontSize: 16`, `titlePadding: 5`, rotated 270° for left axis). All four sub-elements drawn separately; **no full-plot grid lines**.
- Chart title (`chartTitle.ts`): `titleFontSize: 20`, `titlePadding: 10`, centered above plot.
- `showDataLabel` / `showDataLabelOutsideBar` render value text in/above bars with adaptive font sizing (`xychartRenderer.ts`).
- Colors from theme (`theme-default.js`): `backgroundColor` = `#f4f4f4` (light) / inverted for dark; all axis/title/label colors = `primaryTextColor`; `plotColorPalette = #ECECFF,#8493A6,#FFC3A0,#DCDDE1,#B8E994,#D1A36F,#C3CDE6,#FFB6C1,#496078,#F8F3E3`. Plot color indexed by **plot declaration order** (`getPlotColorFromPalette`).

## How mermaid_dart implements it
- Single file `diagrams/xychart/xychart.dart`: `parseXyChart` (regex line parser) + `layoutXyChart`.
- Fixed plot box `plotW = 560`, `plotH = 320`; final scene size = content bounds + `pad = 12` (`layoutXyChart`) — not the upstream 700×500 canvas.
- Y range: data min/max, then **forces `if (minV > 0) minV = 0`** (line 194) and `maxV = minV + 1` fallback.
- Value ticks: own "nice step" of `(max-min)/5` rounded to 1/2/5×10ⁿ (lines 224–227) — ~5 ticks, not d3's ~10.
- Draws full-width/height **grid lines** at each value tick (`Color(0xffdddddd)`, width 1) plus a single L-shaped axis path (`theme.lineColor`, width 1.2). No tick marks.
- Bars: grouped **side-by-side** within `band*0.7`, each `barW = groupW/barSeries.length`, with a 2px inset (lines 255–271).
- Lines: polyline, stroke width 2, color from `_plotPalette`.
- Palette `_plotPalette` (lines 160–167): `#ECECFF, #848484, #FFFFDE, #2CA02C, #D62728, #9467BD` — only first entry matches upstream.
- Axis/category labels use `baseStyle` = `fontSize * 0.8` (~12.8). Axis titles use `baseStyle.copyWith(fontWeight: 700)`. Chart title uses `fontSize * 1.15` (~18.4), weight 700, `theme.titleColor`.
- Category-label thinning when labels would collide (lines 308–315).
- No `showDataLabel`, no per-point line labels.

## Discrepancies
1. `[open] (high)` Multiple bar series overlap upstream, grouped side-by-side here
   - Upstream draws every bar series centered on the same category tick (later series overdraw earlier); our port splits the band into `barW = groupW/barSeries.length` slots. Multi-bar charts look structurally different.
2. `[open] (high)` Plot color palette wrong from index 1 onward
   - Upstream `#ECECFF,#8493A6,#FFC3A0,#DCDDE1,#B8E994,#D1A36F,#C3CDE6,#FFB6C1,#496078,#F8F3E3` (10 entries); ours `_plotPalette` is a 6-entry list with `#848484/#FFFFDE/#2CA02C/#D62728/#9467BD` — every 2nd+ series is the wrong color.
3. `[open] (high)` Missing `showDataLabel` / `showDataLabelOutsideBar`
   - Bar value labels (with adaptive font sizing) are not implemented.
4. `[open] (high)` Missing per-point line labels (`pointLabels`)
   - Parser only captures `label` per series and bare numbers; quoted per-point labels after values (`linePlot.ts` `pointLabels`) are unsupported, so labeled-point line charts drop the labels.
5. `[open] (medium)` Y-axis baseline forced to 0
   - Our port sets `minV = 0` when all data > 0; upstream keeps the data minimum (no forced zero), changing axis range and bar heights.
6. `[open] (medium)` Tick count / values differ
   - Upstream uses d3 `scale.ticks()` (~10 nice ticks); ours uses `(max-min)/5` (~5 ticks), so grid density and labels differ.
7. `[open] (medium)` Grid lines vs tick marks
   - We draw full-plot grey grid lines and no tick marks; upstream draws short tick marks (`tickLength 5`, `tickWidth 2`) and an axis line, with **no** grid lines across the plot.
8. `[open] (medium)` Fixed 700×500 canvas vs content-fit
   - Upstream always emits a 700×500 viewBox with a background rect; ours emits a content-bounds + 12px pad scene (~584-wide). Overall proportions and whitespace differ.
9. `[open] (medium)` Font sizes off
   - Axis labels should be 14 (we use ~12.8), axis titles 16 (we use base weight-700), chart title 20 (we use ~18.4). titlePadding 10, axis titlePadding/labelPadding 5 not honored.
10. `[open] (low)` Bar width formula differs
    - Upstream `min(outerPadding*2, tickDistance)*0.95`; ours `band*0.7` (with extra 2px inset). Single-series bar widths differ slightly.
11. `[open] (low)` Background color default
    - Upstream xychart default background is `#f4f4f4`; our port uses `theme.background`. Verify the Dart default theme matches `#f4f4f4`, else the canvas tint differs.
12. `[open] (low)` Axis line styling
    - Upstream axis line width 2 in `primaryTextColor`; ours 1.2 in `theme.lineColor`.

## Proposed fixes
1. In `layoutXyChart` bar loop (xychart.dart ~255-271), draw all bar series centered on the same `catPix(i)` with shared `barWidth`, removing the `b*barW` side-by-side offset.
2. Replace `_plotPalette` (xychart.dart:160) with the upstream 10-color list `#ECECFF,#8493A6,#FFC3A0,#DCDDE1,#B8E994,#D1A36F,#C3CDE6,#FFB6C1,#496078,#F8F3E3`.
3. Add `showDataLabel`/`showDataLabelOutsideBar` support: parse the config and emit `SceneText` over/in bars in `layoutXyChart`.
4. Extend `parseXyChart` line/number parsing to capture per-point quoted labels and add `pointLabels` to `XySeries`; render them in the line block of `layoutXyChart`.
5. In `layoutXyChart` (xychart.dart:194), drop the `if (minV > 0) minV = 0;` forced-zero baseline to match `setYAxisRangeFromPlotData`.
6. Replace the `(max-min)/5` step logic (xychart.dart:224-227) with a d3-`ticks()`-style ~10-tick "nice" algorithm.
7. In `layoutXyChart`, replace full-plot grid `SceneShape`s with short tick-mark paths (`tickLength 5`, `tickWidth 2`) at each tick.
8. Make `layoutXyChart` emit a fixed 700×500 canvas (background rect + viewBox) and position components via reserved-space layout instead of content-fit + pad.
9. In `layoutXyChart`, use `fontSize 14` for axis labels, `16` for axis titles, `20` for chart title (`baseStyle`/title `TextStyleSpec`).
10. Update bar-width calc in `layoutXyChart` to `min(outerPadding*2, tickDistance)*0.95` and remove the 2px inset.
11. Confirm/set the xychart default background to `#f4f4f4` in the theme used by `layoutXyChart`.
12. Set axis-line stroke to width 2 / `theme.textColor` (primaryTextColor) in `layoutXyChart`.

## Implementation log

### Theme-wiring pass (palette fields)
Reviewed every color in `xychart.dart` against the shared `MermaidTheme`
palette. The semantically-themed colors were already wired and are confirmed
correct:
- axis lines / ticks / labels / titles / data-labels → `theme.primaryTextColor`
  (upstream `xyChart.{x,y}Axis*Color`/`dataLabelColor` all default to
  `primaryTextColor`).
- canvas background → `theme.background` (upstream `xyChart.backgroundColor`
  defaults to `background`).
- chart title → `theme.titleColor`.

No hardcoded color in this file maps to any of the newly-added palette fields
(cScale*/pie*/git*/sequence/journey/quadrant/ER/venn/requirement), so there was
nothing to re-point — default rendering is unchanged.

No opacity/alpha deferral existed in this doc (bars/lines/axes are all fully
opaque upstream — `barPlot`/`linePlot`/`baseAxis` use solid fills/strokes), so
no `withOpacity` fix applies here.

**Residual (needs a theme field):** the 10-entry plot palette `_plotPalette`
stays inlined. Upstream sources it from `xyChart.plotColorPalette`, which
differs between the default (`#ECECFF,#8493A6,…`) and dark
(`#3498db,#2ecc71,…`) themes. The shared `MermaidTheme` does not yet expose an
xychart palette field, and theme.dart is out of scope for this pass, so the
palette cannot adapt to non-default themes without editing the shared theme.
Under the **default** theme the inlined list equals upstream exactly, so default
rendering is pixel-identical; only non-default-theme plot colors differ.

### Original port

Rewrote `layoutXyChart` as a faithful port of upstream's `Orchestrator` +
`BaseAxis`/`LinearAxis`/`BandAxis` + plot/title components. Extended
`parseXyChart` for per-point labels and frontmatter `showDataLabel(/OutsideBar)`.
All 21 upstream corpus fixtures now parse + layout to a 700x500 canvas without
errors; the existing `xychart_mindmap_req_c4_test.dart` xychart tests pass.

1. (high) Multiple bar series overlap — **Done.** Bars now centered on the same
   category tick with a shared `barWidth = min(outerPadding*2, tickDistance)*0.95`;
   removed the side-by-side `groupW/barSeries.length` split.
2. (high) Plot color palette — **Done.** Replaced `_plotPalette` with the exact
   upstream 10-color list; color indexed by plot declaration order
   (`_plotColor`, matching `getPlotColorFromPalette`).
3. (high) `showDataLabel`/`showDataLabelOutsideBar` — **Done.** Added config
   fields (read from YAML frontmatter `xyChart:` block in `parseXyChart`) and
   `_addDataLabels`, porting the adaptive font-size + in/outside-bar placement
   from `xychartRenderer.ts` for both orientations.
4. (high) Per-point line labels (`pointLabels`) — **Done.** `dataPoints` now
   captures a quoted label per datum; `XySeries.pointLabels` carries them (line
   plots only); rendered at `labelOffset 10`, `fontSize 12` in the stroke color.
5. (medium) Forced-zero y baseline — **Done.** Dropped `if (minV > 0) minV = 0`;
   value range is now pure data min/max (`setYAxisRangeFromPlotData`).
6. (medium) Tick count/values — **Done.** Replaced `(max-min)/5` with a d3
   `scaleLinear().ticks()` port (`_d3Ticks`/`_tickIncrement`, ~10 nice ticks).
7. (medium) Grid lines vs tick marks — **Done.** Removed full-plot grid lines;
   `_drawAxis` emits short tick marks (`tickLength 5`, `tickWidth 2`) plus the
   axis line, no plot-spanning grid.
8. (medium) Fixed 700x500 canvas — **Done.** Ported the reserved-space layout
   (`calculateVerticalSpace`/`calculateHorizontalSpace`); scene is always
   700x500. Background fill is carried on `RenderScene.background` (our IR's
   dedicated field) rather than an explicit rect node — same visual result, and
   avoids inventing a node the existing test counts against.
9. (medium) Font sizes — **Done.** Axis labels 14, axis titles 16, chart title
   20; `titlePadding 10`, axis `labelPadding`/`titlePadding 5` all honored.
10. (low) Bar-width formula — **Done.** Now `min(outerPadding*2, tickDistance)*0.95`,
    no 2px inset.
11. (low) Background color — **Done.** Uses `theme.background` (our default
    theme's background equals upstream `#f4f4f4`).
12. (low) Axis line styling — **Done.** Axis line width 2 in `primaryTextColor`
    (all axis/title/label/data-label colors use `primaryTextColor` per upstream
    theme defaults).

Notes / residual minor gaps:
- `showDataLabel` is read from YAML frontmatter only (matching the config-driven
  upstream path); there is no `%%{init}%%` JSON config parser in this port, so
  charts configured via `%%{init}%%` won't pick it up.
- Text dimension measurement uses our `TextMeasurer` rather than d3/SVG metrics,
  so reserved-space sizes (and thus exact plot box) can differ by a few px from
  upstream's browser measurements.
- d3 numeric tick label formatting is approximated (`_formatTick`); matches for
  the common integer/short-decimal cases in the corpus.

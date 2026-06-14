# quadrant — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Config/layout in `quadrant-chart/quadrantBuilder.ts:QuadrantBuilder`. Defaults: `chartWidth=chartHeight=500`, `quadrantPadding=5`, `titleFontSize=20`, `titlePadding=10`, `quadrantLabelFontSize=16`, `xAxisLabelFontSize=16`, `yAxisLabelFontSize=16`, `pointLabelFontSize=12`, `pointRadius=5`, `pointTextPadding=5`, `quadrantTextTopPadding=5`, internal border width 1, external border width 2.
- `calculateSpace()` reserves space for axis labels, title, and `quadrantPadding`, then computes the inner quadrant rect (`quadrantLeft/Top/Width/Height`).
- `getQuadrants()` builds 4 region rects in order q1=top-right, q2=top-left, q3=bottom-left, q4=bottom-right. Quadrant label is centered (`horizontalPos='middle'`) when there are **no** points, but moved to the **top** of the region (`quadrantTextTopPadding`, `horizontalPos='top'`) when points exist.
- `getQuadrantPoints()` uses d3 `scaleLinear` to map x∈[0,1]→[left,left+width] and y∈[0,1]→[top+height,top] (y inverted). Point fill = `quadrantPointFill`, radius default 5, label placed `pointTextPadding` below the dot (anchor center, baseline hanging).
- `getAxisLabels()`: x-axis labels default to **top** (`xAxisPosition='top'`) but `build()` forces **bottom** when points exist. When `xAxisRightText` is set, both x labels are centered in their half; otherwise left-aligned at the quadrant edge. Y-axis labels rotated −90°, similar left/middle logic when `yAxisTopText` present.
- `getBorders()` draws 6 lines: 4 external (width 2, `quadrantExternalBorderStrokeFill`) and 2 internal divider lines — vertical and horizontal mid-lines (width 1, `quadrantInternalBorderStrokeFill`).
- `getTitle()`: centered at `chartWidth/2`, y=`titlePadding`, fontSize 20, `quadrantTitleFill`.
- Theme (`themes/theme-default.js:314+`): `quadrant1Fill=primaryColor=#ECECFF`; q2=+5/+5/+5 → `#F1F1FF`; q3=+10 → `#F6F6FF`; q4=+15 → `#FBFBFF`. Text fills = `primaryTextColor`=invert(#ECECFF) (near-black) with −5/−10/−15 nudges. `quadrantPointFill`=darken(#ECECFF) (light fill ⇒ darken). Border fills = `primaryBorderColor`.
- Renderer `quadrantRenderer.ts:draw` paints groups: quadrants(rect+text), border(lines), data-points(circle+text), labels, title. SVG viewBox `0 0 500 500`.
- DB (`quadrantDb.ts`) + grammar (`parser/quadrant.jison`) support `classDef`, per-point `:::className`, and inline point styles `radius:N`, `color:#hex`, `stroke-color:#hex`, `stroke-width:Npx` (validated in `utils.ts`).

## How mermaid_dart implements it
- Single file `diagrams/quadrant/quadrant.dart`. `parseQuadrantChart()` is a regex line parser: header, `title`, `x-axis a --> b`, `y-axis a --> b`, `quadrant-1..4`, and `label: [x, y]` points (clamped 0..1).
- `layoutQuadrantChart()` hardcodes `plot=440`, `left/top=10`. Regions ordered q1 top-right…q4 bottom-right (matches upstream order).
- Quadrant fills hardcoded `_quadrantFills = [#e5e5fb, #d6d6f5, #e5e5fb, #f0f0ff]`. Quadrant labels always drawn at region top (+8), never centered.
- Outer plot rect drawn once with `theme.nodeBorder` stroke; no internal divider lines.
- Points: filled circle radius 4 with `theme.textColor`, label placed +6 below.
- Axis labels: x-left centered at `left+plot/4`, x-right centered at `right-plot/4` (always centered, always bottom). Y labels rotated −90° left of plot at quarter heights. All axis/quadrant/point text uses `baseStyle` = `fontSize*0.85`, axis labels bold (700).
- Title fontSize `fontSize*1.15` bold, `theme.titleColor`, above the plot.
- Final scene padded by 10.

## Discrepancies
1. `[open] (high) Internal divider lines missing` — upstream draws vertical + horizontal mid divider lines (width 1) plus a 4-side external border (width 2); we draw only a single outer rect stroke, so the four quadrants are not separated by lines.
2. `[open] (high) Quadrant fill colors wrong` — upstream fills are `#ECECFF/#F1F1FF/#F6F6FF/#FBFBFF` (nearly identical pale lavender, monotonic lighten); our `_quadrantFills` are saturated, out-of-order, and include a duplicate, producing a visibly different checker pattern.
3. `[open] (high) classDef / per-point styling unsupported` — upstream parses `classDef`, `point:::class`, and inline `radius/color/stroke-color/stroke-width`; our parser only accepts `label: [x,y]` and throws on style syntax.
4. `[open] (medium) Point fill & radius wrong` — upstream uses `quadrantPointFill` (darkened lavender) and radius 5; we use `theme.textColor` (near-black) and radius 4.
5. `[open] (medium) Quadrant label placement ignores point count` — upstream centers the quadrant label when there are no points and only moves it to the top when points exist; we always place it at the top.
6. `[open] (medium) Font sizes do not match` — upstream uses absolute sizes (title 20, axis 16, quadrant 16, point 12); we use a single `fontSize*0.85` (~13.6) for axis/quadrant/point text and `fontSize*1.15` for title, so relative scale is off (quadrant/axis text too small, point text too large relative to them).
7. `[open] (medium) X-axis label alignment/position logic missing` — upstream left-aligns x labels at the quadrant edge when no `xAxisRight` is given (and supports xAxisPosition top when no points); we always center both halves at the bottom.
8. `[open] (low) Plot size hardcoded 440 vs 500` — upstream chart is 500×500 with padding 5; we use plot 440 with padding 10, changing absolute coordinates and aspect/space allocation.
9. `[open] (low) Border / text colors from wrong theme tokens` — borders should use `primaryBorderColor` (external+internal); quadrant text fills should derive from `primaryTextColor` with per-quadrant nudges. We use `theme.nodeBorder` for the rect and `theme.textColor` for all labels.
10. `[open] (low) pointTextPadding 5 vs our +6` — minor label offset difference below the dot.

## Proposed fixes
1. In `quadrant.dart:layoutQuadrantChart`, emit 4 external border line `SceneShape`s (width 2) + 2 internal divider lines (width 1) instead of the single outer rect.
2. In `quadrant.dart`, replace `_quadrantFills` with theme-derived `[primary, lighten+5, +10, +15]` (add quadrant fill tokens to `theme/theme.dart`).
3. In `quadrant.dart:parseQuadrantChart`, add grammar for `classDef name ...`, `point:::class`, and inline `radius/color/stroke-color/stroke-width`; store on `QuadrantPoint` and apply in layout.
4. In `quadrant.dart:layoutQuadrantChart` point loop, use a `quadrantPointFill` theme token and radius 5 (configurable per-point).
5. In `quadrant.dart:layoutQuadrantChart`, branch quadrant-label placement on `chart.points.isEmpty` (center vs top), mirroring `getQuadrants()`.
6. In `quadrant.dart:layoutQuadrantChart`, set explicit font sizes (title 20, axis 16, quadrant 16, point 12) instead of `fontSize*0.85`/`*1.15`.
7. In `quadrant.dart:layoutQuadrantChart` axis-label section, left-align x labels at quadrant edge when `xAxisRight==null`, and implement xAxisPosition top-when-no-points.
8. In `quadrant.dart:layoutQuadrantChart`, change `plot` to 500 and `quadrantPadding` to 5 (or derive from config) to match upstream coordinate space.
9. In `quadrant.dart`, source border color from a `primaryBorderColor`-equivalent theme token and quadrant text fills from `primaryTextColor` nudges.
10. In `quadrant.dart` point label, use offset 5 to match `pointTextPadding`.

## Implementation log
Rewrote `quadrant.dart` to mirror `QuadrantBuilder` (500×500 space, padding 5,
calculateSpace, scaleLinear point mapping, anchor/baseline-aware text placement).

1. Internal divider lines missing — Done. Emit 4 external border segments
   (width 2) + 2 internal divider segments (width 1) as 2-point
   `PolygonGeometry` shapes (stroke only → SVG `fill="none"`), with the same
   half-external-width insets as upstream `getBorders()`. Replaced the single
   outer rect stroke.
2. Quadrant fill colors wrong — Done. Inlined exact upstream defaults
   `#ECECFF/#F1F1FF/#F6F6FF/#FBFBFF` (primaryColor + per-channel +5/+10/+15).
3. classDef / per-point styling — Done. Parser now accepts `classDef name ...`,
   `label:::class : [x,y]`, and inline `radius/color/stroke-color/stroke-width`
   with the same validation as `utils.ts`; styles stored on `QuadrantPoint`
   /`QuadrantChart.classes` and applied in layout (inline overrides class).
4. Point fill & radius — Done. Default fill `#B9B9FF` (darken(primary)),
   radius 5; stroke drawn only when stroke-width > 0.
5. Quadrant label placement by point count — Done. Centered (middle baseline)
   when no points; anchored at region top + `quadrantTextTopPadding` (5) when
   points exist.
6. Font sizes — Done. title 20 (bold), axis 16, quadrant 16, point 12 absolute.
7. X-axis alignment/position — Done. Left-anchored at quadrant edge when no
   `xAxisRight` (center in half otherwise); x-axis at top when no points, bottom
   when points exist; y-axis left/middle logic mirrored.
8. Plot size 440 vs 500 — Done. Full 500×500 coordinate space with
   quadrantPadding 5 and calculateSpace-derived inner rect.
9. Border / text colors — Done. Borders use `theme.primaryBorderColor`; quadrant
   text fills use inlined `primaryTextColor` (invert #ECECFF = #131300) with
   −5/−10/−15 nudges; axis/point/title text use `theme.primaryTextColor`.
10. pointTextPadding — Done. Label offset now 5 below the dot.

Deferred: none. Note: bare-trailing `x-axis a -->` (no right text) does not
append the upstream `⟶` glyph to the left label — pre-existing behavior, not a
listed discrepancy.

### Theme wiring pass (MermaidTheme palette)
Replaced all inlined quadrant color constants with the shared `MermaidTheme`
palette fields so the diagram now adapts to dark/forest/neutral themes while
keeping default-theme output identical (the field defaults equal the old
inlined constants):
- Quadrant region fills `_quadrant1Fill.._quadrant4Fill` → `theme.quadrant1Fill
  ..quadrant4Fill` (deleted the four `const` declarations).
- Quadrant label text fills `_quadrant1TextFill.._quadrant4TextFill` →
  `theme.quadrant1TextFill..quadrant4TextFill` (deleted the four constants).
- Point default fill / stroke `_quadrantPointFill` → `theme.quadrantPointFill`
  (deleted the constant; inline `color`/`stroke-color` still override).
- Point label color `theme.primaryTextColor` → `theme.quadrantPointTextFill`.
- X-axis label color → `theme.quadrantXAxisTextFill`; Y-axis label color →
  `theme.quadrantYAxisTextFill`; title color → `theme.quadrantTitleFill`.
- Borders: external/internal stroke `theme.primaryBorderColor` →
  `theme.quadrantExternalBorderStrokeFill` / `quadrantInternalBorderStrokeFill`.
  Default-render correction: upstream resolves these via
  `mkBorder(primaryColor) = adjust(#ECECFF, {s:-40, l:-10}) = #c7c7f1`, which is
  what `theme-default.js` overrides them to — NOT the raw `primaryBorderColor`
  (`#9370db`) the old code used. So the default border color changes from
  `#9370db` to the correct `#c7c7f1`, closing discrepancy #9 properly.
No opacity items were deferred for this diagram (all fills are opaque upstream).

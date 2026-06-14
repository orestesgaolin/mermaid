# timeline — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser: `parser/timeline.jison` — header `timeline | timeline LR | timeline TD`, `title <text>`, `section <text>`, period lines (`period` token = `[^#:\n]+`), and event lines (`event` token = `: <text>`). `timelineDb.js:addTask/addEvent/addSection` build `tasks[]` each with `{section, task, score, events[]}`. Periods are tasks; subsequent `:` lines append to the last task's `events[]`.
- Renderer `timelineRenderer.ts:draw` (this is the active path; `svgDraw.drawTask`/`drawFace` are journey leftovers and are NOT called for timeline):
  - Constants: `LEFT_MARGIN = 50`, `masterX = 50 + LEFT_MARGIN = 100`, `masterY/sectionBeginY = 50`. Node base `width:150`, `padding:20` (final node width `150 + 2*20 = 190`). Section width = `200*max(tasks,1) - 50`.
  - Two-pass height measurement via `svgDraw.getVirtualNodeHeight`: `height = bbox.height + fontSize*1.1*0.5 + padding`, clamped to `maxHeight`. `maxSectionHeight`/`maxTaskHeight` get `+20`, `+50` spacing.
  - Layout is VERTICAL/columnar: each section is a header box at top (`drawNode` at `translate(masterX, sectionBeginY)`), tasks drawn below at `masterY = sectionBeginY + maxSectionHeight + 50`, and each task's events stacked vertically BELOW the task (`drawEvents`: `masterY += 100` then each event `+10+height`). Columns advance `masterX += 200` per task.
  - Per task with events: a dashed vertical connector line (`stroke-width:2`, `stroke-dasharray:5,5`, `marker-end arrowhead`) from task bottom down through all events.
  - Bottom horizontal "activity line": `lineWrapper line` at `y=depthY`, `x1=LEFT_MARGIN`, `x2=box.width+3*LEFT_MARGIN`, `stroke-width:4`, black, `marker-end arrowhead`.
- `svgDraw.drawNode` + `defaultBkg`: rounded-rect path with corner radius `r=5` (`rd=5`), PLUS a separate bottom `<line>` (`node-line-<section>`) under each node. Text is wrapped (`wrap`) to node width, centered, vertically middle.
- Title: `timelineRenderer.ts:draw` appends `<text>` `font-size:4ex`, `font-weight:bold`, `y=20`, x ≈ `box.width/2 - LEFT_MARGIN` (classic look).
- Colors `styles.js:genSections`: section/task/event rects fill `cScale<i>` (default theme = `darken(primaryColor/secondaryColor/tertiaryColor/..., 10)` → `#ECECFF`, `#ffffde`, etc., each darkened ~10%). Text fill `cScaleLabel<i>`. `.section-<i> line` stroke `cScaleInv<i>`, width 3. `.eventWrapper { filter: brightness(120%) }`. Section index used is `section-${i-1}` (offset by -1). Without sections, multicolor cycles per task unless `disableMulticolor`.
- Arrowhead marker `svgDraw.initGraphics`: `markerWidth 6`, `markerHeight 4`, path `M0,0 V4 L6,2 Z`.

## How mermaid_dart implements it
- `timeline.dart:parseTimeline` — line-based regex parser. Handles `timeline` header, `title`, `section`, `accTitle/accDescr` (skipped), period lines split on `:`, and `:`-prefixed continuation events. Inline `a : b : c` splits a period plus multiple events on one line. Does NOT recognize `timeline LR`/`timeline TD` direction. Frontmatter title supported.
- `timeline.dart:layoutTimeline` — HORIZONTAL/compact layout, fixed geometry: `colWidth=140`, `colGap=10`, `sectionH=26`, `periodH=30`, with one shared `axisY` and `eventsTop`. Section header box drawn above the period row; period boxes in a single horizontal row; events stacked below each period.
- Section fill palette hardcoded `_sectionFills` = `[#ececff,#ffffde,#d5e5cf,#e5d0cf,#cfd6e5,#e5cfe0]` (NOT darkened, and order/values differ from theme cScale). All shapes in a section share one fill; event rects use `fill.withOpacity(0.55)`.
- Connectors: per-period dashed vertical drop (`width:0.8`, dash `[3,3]`) from period box through axis to events, plus short dashed stubs above each event box. One shared horizontal arrow axis (`width:1.5`) with a hand-drawn arrowhead triangle at the right.
- Text: `baseStyle` = `fontSize * 0.85`, period/section labels `fontWeight:700`, events normal weight. Title `fontSize*1.2`, weight 700, centered above bounds.
- Rounded rects rx/ry 3–4; strokes `theme.nodeBorder` width 0.7–1.0.

## Discrepancies
1. `[open] (high) Layout orientation differs (horizontal vs vertical columns)`
   - Upstream lays sections as header boxes with tasks/events stacked VERTICALLY in 200px columns (`masterX += 200`, events below each task). Ours is a single horizontal row of 140px period boxes sharing one axis. The overall shape/topology is materially different.
2. `[open] (high) Section/task fill colors not derived from theme cScale (and not darkened)`
   - Upstream fills come from `cScale<i> = darken(primary/secondary/..., 10)`; ours uses a hardcoded non-darkened palette in a different order. Colors visibly differ for every section.
3. `[open] (medium) Event rects use brightness-120% sibling color upstream, opacity 0.55 here`
   - Upstream `.eventWrapper{filter:brightness(120%)}` lightens the section color; we instead drop fill to 55% opacity, producing a washed-out look rather than a brighter one.
4. `[open] (medium) Missing per-node bottom underline (node-line)`
   - `defaultBkg` adds a `<line>` under every section/task/event node (stroke `cScaleInv`, width 3); we render no such underline.
5. `[open] (medium) Node sizing constants differ`
   - Upstream node width 190 (150+2*20), section width `200*tasks-50`, task height `bbox+fontSize*0.55+padding` clamped to maxHeight; ours uses colWidth 140, periodH 30, eventH0 24. Box dimensions/spacing differ throughout.
6. `[open] (medium) Corner radius mismatch`
   - Upstream node rect radius r=5 (rd=5); ours uses rx/ry 3 (sections/events) and 4 (periods).
7. `[open] (low) `timeline LR`/`timeline TD` direction not parsed`
   - Upstream grammar accepts direction tokens and `setDirection`. Our parser only matches bare `^timeline\b`; a `timeline LR` header line still passes (rest ignored) but direction is dropped; `timeline TD` (vertical) is the upstream default-ish path we already resemble but don't honor.
8. `[open] (low) Title position/size differ`
   - Upstream title `font-size:4ex` (~bold, large) placed near top-left/area `box.width/2 - LEFT_MARGIN`, y=20. Ours is `fontSize*1.2`, centered over the diagram bounds above the content.
9. `[open] (low) Bottom activity-line weight differs`
   - Upstream main axis `stroke-width:4` black extending `box.width + 3*LEFT_MARGIN`; ours is width 1.5 in `theme.lineColor` sized to content. Connector dashed line widths also differ (upstream 2 / dash 5,5 vs ours 0.8 / dash 3,3).
10. `[open] (low) No multicolor-per-task when sections are absent`
    - Upstream cycles section color per task when there are no sections (`isWithoutSections && !disableMulticolor`); ours puts all sectionless periods in one empty-named section with a single fill.

## Proposed fixes
1. Rework `timeline.dart:layoutTimeline` to a vertical columnar layout: section header row, task row below (`+maxSectionHeight+gap`), events stacked vertically per task in ~200px columns.
2. Replace `_sectionFills` in `timeline.dart` with theme-derived `cScale` colors (darken primary/secondary/tertiary/hue-adjusted by 10%) indexed per section.
3. In `layoutTimeline` event drawing, use a brightness-120% variant of the section fill instead of `fill.withOpacity(0.55)`.
4. In `layoutTimeline` add a bottom underline `SceneShape(PathGeometry line)` under each section/period/event box (stroke `cScaleInv`/lineColor, width ~3).
5. Align node constants in `layoutTimeline`: width 190, section width `200*periods-50`, height = textHeight + fontSize*0.55 + padding clamped to a section max.
6. Set period/section/event `RectGeometry` corner radius to 5 in `layoutTimeline`.
7. In `parseTimeline` capture `timeline (LR|TD)` and store/honor direction in `TimelineDiagram`.
8. In `layoutTimeline` title block, raise font to ~`fontSize*2` bold and match upstream x/y placement.
9. In `layoutTimeline` set the activity axis stroke width to 4 and connector dashed lines to width 2, dash `[5,5]`.
10. In `layoutTimeline` cycle fill color per period when the single section name is empty (sectionless multicolor).

## Implementation log
- 1 (high) Layout orientation — **Done.** `layoutTimeline` rewritten to upstream's vertical columnar layout: section header boxes at `sectionBeginY=50`, task row below at `+maxSectionHeight+50`, events stacked vertically per task (+200 from task top, spaced +10), columns advance 200px (`masterX += 200*max(tasks,1)` per section). Section width `200*max(tasks,1)-50`.
- 2 (high) Theme cScale fills — **Done.** Replaced hardcoded `_sectionFills` with `_cScale` = exact default-theme `darken(adjust(primary,{h}),10)` hexes (computed against khroma's HSL algorithm; cScale0 `#b9b9ff` matches the repo's existing `darken(#ECECFF)` reference). Indexed `section % 12` (THEME_COLOR_LIMIT).
- 3 (medium) Event brightness vs opacity — **Done.** Events now use `_brightness(fill, 1.2)` (CSS `filter: brightness(120%)` = ×1.2 per channel, clamped) instead of `fill.withOpacity(0.55)`.
- 4 (medium) Per-node bottom underline — **Done.** Every section/task/event node draws a bottom `<line>` (PathGeometry) stroked with `cScaleInv<i>`, width 3, matching `defaultBkg`.
- 5 (medium) Node sizing constants — **Done.** Node width 190 (150+2·20), section width `200·tasks-50`, virtual height `textHeight + fontSize·1.1·0.5 + 20` clamped via `maxSectionHeight`/`maxTaskHeight` (+20 each), events clamp to height 50.
- 6 (medium) Corner radius — **Done.** All node rects use radius 5 (`_nodeRadius`).
- 7 (low) `timeline LR`/`timeline TD` direction — **Done.** Parser captures the trailing token into `TimelineDiagram.direction` (`TimelineDirection.{td,lr}`). Carried for fidelity; upstream renders columnar regardless of direction so layout is unchanged.
- 8 (low) Title position/size — **Done.** Title now `fontSize*2` bold, left-anchored near top (`x = box.width/2 - LEFT_MARGIN`, `y≈20`), matching the classic look.
- 9 (low) Activity-line / connector weights — **Done.** Bottom axis is black width 4 extending `box.width + 3·LEFT_MARGIN` with an arrowhead; per-task connector is black width 2, dash `[5,5]`.
- 10 (low) Sectionless multicolor — **Done.** When no named sections exist, the per-task color index increments (multicolor), cycling cScale per task.

Notes:
- Title `font-size:4ex` approximated as `fontSize*2` (4ex ≈ 2em for typical fonts) — no `ex` unit support in the IR; close enough visually.
- Arrowhead markers are drawn as explicit path triangles (no shared SVG marker primitive in the IR), matching upstream's `M0,0 V4 L6,2 Z` shape.

### Theme wiring (palette pass)
- Replaced the inlined `_cScale` and `_cScaleInv` constant arrays with the shared
  `theme.cScale` / `theme.cScaleInv` palette getters in `drawNode`. The default-theme
  values of those theme fields are byte-identical to the old inlined hexes (verified
  against theme.dart lines 25-48), so default rendering is pixel-identical, while
  dark/forest/neutral now drive correct section/task/event fills and bottom-underline
  strokes. Section/event index is still `colorIndex % 12` (THEME_COLOR_LIMIT).
- Opacity check: upstream timeline `styles.js` has no `fill-opacity`/transparency —
  only `.eventWrapper { filter: brightness(120%) }`, which we already implement via
  `_brightness(fill, 1.2)`. No opacity fix needed.
- No remaining default-render gap; status raised to full-parity. Residual items are
  config/niche only (parsed-but-unused `timeline LR/TD` direction — upstream renders
  columnar regardless — and the `4ex` title-size unit approximation).

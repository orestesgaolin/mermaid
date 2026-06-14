# gantt — parity analysis
**Status:** full-parity
**Last analyzed:** 2026-06-14

## How mermaid.js implements it
- `ganttRenderer.js:draw` — width is responsive: `w = parentElement.offsetWidth` (or `conf.useWidth`, fallback 1200). Height `h = 2*topPadding + nTasks*(barHeight+barGap)`. Bars are time-scaled by a d3 `scaleTime` whose range is `[0, w - leftPadding - rightPadding]`.
- Config defaults (`config.schema.yaml` GanttDiagramConfig): `barHeight=20`, `barGap=4` (row stride 24), `topPadding=50`, `leftPadding=75`, `rightPadding=75`, `gridLineStartPadding=35`, `fontSize=11`, `sectionFontSize=11`, `titleTopMargin=25`, `numberSectionStyles=4`, `axisFormat='%Y-%m-%d'`.
- `drawRects` — section background rects span full width `w - rightPadding/2`, `y = order*gap + topPadding - 2`, height = `gap` (one stride per row). Class `section{i % 4}`.
- Task bars: `rx=ry=3`, `x=timeScale(start)+leftPadding`, width `timeScale(renderEndTime||endTime) - timeScale(start)`. Milestone: square of side `barHeight` rotated 45° scaled 0.8 (`styles.js .milestone`), centered on `(start+end)/2`. `vert` markers: thin full-height vertical bars (a tag we don't support).
- Task label placement (`drawRects` text `x`): if `textWidth > barWidth`, place outside-right (`endX+leftPadding+5`) unless it would overflow `w`, then outside-left (`startX-5`); else centered. Label `y = order*gap + barHeight/2 + (fontSize/2 - 2) + topPadding`.
- `makeGrid` — `axisBottom` at `translate(leftPadding, h-50)`, full-height tick lines (`tickSize = -(h-topPadding-gridLineStartPadding)`), tick `font-size=10`, fill `#000`. d3 chooses tick count/format automatically; `tickInterval`/`weekday`/`topAxis` configurable. Axis default `%Y-%m-%d`, or `%d` when `dateFormat==='D'`.
- `drawExcludeDays` — coalesces contiguous excluded days into range rects (`.exclude-range`, fill `excludeBkgColor=#eeeeee`) from `gridLineStartPadding` to bottom; only drawn if excludes/includes present and span ≤ 5 years.
- `drawToday` — vertical line at `timeScale(now)+leftPadding` from `titleTopMargin` to `h-titleTopMargin`; color `todayLineColor=red`, width 2px; suppressed when `todayMarker off`; custom style string allowed.
- Title: `text` at `(w/2, titleTopMargin)`, class `titleText` (font-size 18, anchor middle).
- Theme colors (`theme-default.js`): `taskBkgColor=#8a90dd`, `taskBorderColor=#534fbc`, `activeTaskBkgColor=#bfc7ff`, `activeTaskBorderColor=#534fbc`, `doneTaskBkgColor=lightgrey`, `doneTaskBorderColor=grey`, **`critBkgColor=red`** (#ff0000), **`critBorderColor=#ff8888`**, `todayLineColor=red`, `sectionBkgColor=rgba(102,102,255,0.49)`, `altSectionBkgColor=white`, `sectionBkgColor2=#fff400`. `.section` opacity 0.2.
- Section bands (`styles.js`): only 4 styles — `section0`=sectionBkgColor, `section1/3`=altSectionBkgColor (white), `section2`=sectionBkgColor2 (yellow). Task fill follows `task{secNum}` = `taskBkgColor` for all sections (NOT tinted per section).
- Task text fill: `.taskText{n}` = `taskTextColor`; outside text = `taskTextOutsideColor` (black); active/done/crit text use `taskTextDarkColor` (black) — crit text is **not** forced white.
- `ganttDb.js` resolves task metadata: tags `active|done|crit|milestone|vert`, optional id, `start`/`end`/duration/`after`/`until`, `inclusiveEndDates`, `fixTaskDates` for excludes (`renderEndTime` frozen at original end). Supports `click`/`href`/`call` links and accTitle/accDescr.

## How mermaid_dart implements it
- `gantt_layout.dart:layoutGanttChart` — fixed `_chartWidth=800` plot area, `_barHeight=22`, `_rowGap=10` (stride 32), `_diagramPadding=12`, `chartTop=8`. Left gutter is measured from section-name width (not a fixed 75). Bars `rx=ry=3`, milestone = diamond polygon radius 11.
- Colors are hardcoded constants: `_taskFill=#8a90dd`, `_taskBorder=#534fbc`, `_activeFill=#bfc7ff`, `_doneFill=#d3d3d3`, `_doneBorder=#808080`, `_critFill=#ff8888`, `_critBorder=#ff0000`. Section bands use a custom 4-color tint palette `_sectionBands` (lavender/yellow/green/pink), not the theme scheme.
- Crit/active text forced white inside bar (`insideColor`). Label fits inside if `width < (x2-x1)-8`, else placed to the right of the bar (no left-fallback logic).
- Section band rect spans `gutter + _chartWidth + 20`, height = `tasks*stride`. Section title drawn bold at x=4, vertically centered in band.
- `_ticks` — hand-rolled step buckets (hour/6h/day/2day/week/month/quarter) with collision-based label thinning; grid lines per tick. Axis labels below chart.
- Excluded days drawn per-day (not coalesced) as `#33999999` translucent rects; today marker red width 2.
- `gantt_parser.dart` — hand parser: tags, id, dates, durations, `after`, excludes (weekends/weekday/dates), includes, todayMarker. `fixTaskDates` ported with frozen `renderEnd`. `inclusiveEndDates`, `vert`, `until`, `topAxis`, `weekday`, `tickInterval`, `displayMode`/`compact`, `click`/`link`/`call` parsed-and-ignored.
- `gantt_dates.dart` — strftime-lite formatter (`%Y %m %d %e %b %a %H %M`) and dayjs-token date parser (YYYY/MM/DD/HH/mm/ss).
- Font size `theme.fontSize * 0.85`; title `fontSize * 1.2` bold.

## Discrepancies
1. `[open] (high)` Critical-task colors swapped vs theme
   - Upstream `critBkgColor=red (#ff0000)` with `critBorderColor=#ff8888`. Ours uses fill `#ff8888` + border `#ff0000` — exactly inverted, so crit bars look pink-with-red-border instead of red-with-pink-border.
2. `[open] (medium)` Section band palette differs from theme scheme
   - Upstream cycles only 4 styles where odd sections (1,3) are white (`altSectionBkgColor`), section2 is yellow `#fff400`, section0 is `rgba(102,102,255,0.49)` at 0.2 opacity. Ours uses a custom lavender/yellow/green/pink palette, so band colors won't match for any chart with ≥2 sections.
3. `[open] (medium)` Bar/row metrics differ from config defaults
   - Upstream `barHeight=20`, stride `barHeight+barGap=24`. Ours `_barHeight=22`, stride 32 (`_rowGap=10`). Rows are ~33% taller, changing overall proportions and density.
4. `[open] (medium)` Milestone shape geometry
   - Upstream is a `barHeight`-sized square (side 20) rotated 45° scaled 0.8 → diagonal ~22.6, half-diag ~11.3 with the same task fill/border. Ours is a fixed radius-11 diamond. Close but slightly different size and not tied to barHeight.
5. `[open] (medium)` Crit/active task text should not be white
   - Upstream paints active/done/crit task text with `taskTextDarkColor` (black) via `.activeText/.doneText/.activeCritText`; there is no white override for crit. Ours forces white for crit-not-done inside the bar.
6. `[open] (low)` Fixed plot width vs responsive width
   - Upstream scales bars to container width (`offsetWidth`/`useWidth`/1200) minus left+right padding; ours uses a constant 800px plot. Acceptable for an intrinsically-sized render but absolute pixel positions and tick density will differ.
7. `[open] (low)` Left gutter measured, not fixed leftPadding=75
   - Upstream reserves a fixed `leftPadding=75` and bars start there; ours derives the gutter from the widest section name (min 10). Layout origin differs and bars shift left when section names are short.
8. `[open] (low)` Excluded days not coalesced; tint color differs
   - Upstream merges contiguous excluded days into one `.exclude-range` rect filled `excludeBkgColor=#eeeeee`; ours draws one `#33999999` rect per day. Visually grey vs light-grey and seam lines between adjacent days.
9. `[open] (low)` Outside label has no left-overflow fallback
   - Upstream places an overflowing label to the left of the bar (`startX-5`, `text-anchor:end`) when right placement would exceed width `w`; ours always places it to the right, which can run off the right edge for late tasks.
10. `[open] (low)` Missing `vert` vertical-marker tag
   - Upstream supports `vert` tasks rendered as full-height thin vertical bars with a bottom label; our parser ignores the tag entirely (the task is dropped from `tags` matching and treated as a normal bar or skipped).
11. `[open] (low)` `inclusiveEndDates` and `dateFormat D` ignored
   - Upstream adjusts end dates (+1 day inclusive) and uses axis `%d` when `dateFormat==='D'`; ours parses-and-ignores `inclusiveEndDates` and has no `D` axis special-case.
12. `[open] (low)` Title position and font size
   - Upstream title font-size 18 at fixed `(w/2, titleTopMargin=25)` from the top; ours uses `fontSize*1.2` placed above the chart relative to measured bounds. Minor size/position drift.

## Proposed fixes
1. In `gantt_layout.dart` swap `_critFill`/`_critBorder` to `_critFill = Color(0xffff0000)` (red) and `_critBorder = Color(0xffff8888)`.
2. In `gantt_layout.dart` replace `_sectionBands` with the theme scheme: index0 = `rgba(102,102,255,0.49)`-at-0.2, index1/3 = white, index2 = `#fff400`-at-0.2 (cycle length 4 via `numberSectionStyles`).
3. In `gantt_layout.dart` set `_barHeight = 20` and use a `barGap = 4` so `rowStride = barHeight + barGap = 24` (rename `_rowGap`).
4. In `gantt_layout.dart` milestone branch, derive diamond half-diagonal from `_barHeight` (`r = _barHeight*0.8/√2 ≈ 0.566*barHeight`) instead of the constant 11.
5. In `gantt_layout.dart` drop the `insideColor` white override — use `theme.textColor` (black) for crit/active inside-bar text.
6. In `gantt_layout.dart:layoutGanttChart` plumb a configurable plot width (default 1200 minus paddings) instead of the hardcoded `_chartWidth = 800`.
7. In `gantt_layout.dart` use a fixed left padding (75) as the bar origin and place section names within it, instead of `gutter` from measured names.
8. In `gantt_layout.dart` exclude-day loop, coalesce contiguous excluded days into single rects and fill with `#eeeeee` (theme `excludeBkgColor`).
9. In `gantt_layout.dart` task-label branch, add the left-overflow fallback: when `x2 + labelWidth` exceeds plot right edge, place label left of the bar with right alignment.
10. In `gantt_parser.dart` and `gantt_model.dart`/`gantt_layout.dart` add `vert` tag support: parse it and render a full-height thin vertical bar with a bottom-anchored label.
11. In `gantt_parser.dart` implement `inclusiveEndDates` (+1 day on end) and in `gantt_layout.dart:_defaultAxisFormat` emit `%d` when `dateFormat == 'D'`.
12. In `gantt_layout.dart` title block, use fixed font-size 18 and position the title at the top margin (`titleTopMargin`) centered on the plot width.

## Implementation log
(2026-06-14)
1. Done — `_critFill` = red (#ff0000), `_critBorder` = #ff8888 in gantt_layout.dart.
2. Done — `_sectionBands` replaced with theme scheme (section0=rgba(102,102,255,0.49)@0.2, section1/3=white@0.2, section2=#fff400@0.2), opacity baked into alpha.
3. Done — `_barHeight=20`, `_barGap=4`, `rowStride=24`.
4. Done — milestone half-diagonal derived from `_barHeight*0.8/sqrt2`; centered on (start+end)/2.
5. Done — dropped white inside override; normal inside text = white (taskTextColor), active/done/crit inside = black (taskTextDarkColor), outside text = black.
6. Done(partial) — fixed plot width set to upstream fallback 1050 (=1200-75-75) for correct proportions/density. True container-responsive width deferred (intrinsic render has no container; acceptable).
7. Done — fixed `leftPadding=75` bar origin (`gutter`), section names placed within it.
8. Done — excluded days coalesced into single range rects, filled excludeBkgColor (#eeeeee).
9. Done — outside-label left-overflow fallback (right-aligned at `x1-6-w` when right placement exceeds plot right).
10. Done — `vert` tag parsed (model + parser) and rendered as full-height thin vertical bar (width 0.08*barHeight) with bottom-anchored centered label; does not occupy rows.
11. Done — `inclusiveEndDates` (+1 day on manual end) in parser; axis `%d` when `dateFormat=='D'` (dateFormat plumbed through model).
12. Done — title font-size fixed 18, centered on full chart width (gutter+chartWidth+leftPadding)/2.

Note: today-marker color corrected to red (#ff0000, todayLineColor); section title color uses titleColor. The single-Fill-color IR cannot represent CSS opacity layering exactly, so band alphas are pre-multiplied approximations.

(2026-06-14 — theme wiring + opacity pass)
- THEME WIRING: the shared MermaidTheme palette additions do NOT include any
  gantt-specific fields (no taskBkgColor / sectionBkgColor / critBkgColor /
  excludeBkgColor / gridColor / todayLineColor). The generic fields gantt does
  use (background, textColor, titleColor, fontFamily, fontSize) were already
  wired via the `theme` parameter. All remaining gantt color constants are
  diagram-specific with no corresponding theme variable available to wire to,
  so they stay inlined (default-theme values, pixel-identical). No theme.dart
  edits possible/permitted; nothing further to wire.
- OPACITY FIX: grid tick stroke now bakes the upstream `.grid .tick`
  opacity 0.2->0.8 into the alpha channel — `_gridColor` 0xffd3d3d3 -> 0xccd3d3d3
  (gridColor=lightgrey @ opacity 0.8). Section-band alphas were already
  pre-multiplied (0.2 / sectionBkgColor 0.49) and are correct.
- DEFAULT-RENDER FIX: task/crit/active/done bars and milestone now use
  stroke-width 2 (was 1 for rects, 1.5 for milestone) to match upstream
  styles.js `.task`/`.crit`/`.done` { stroke-width: 2 } and milestone's
  inherited `.task` width.
- Default rendering is otherwise unchanged. Remaining deltas are config/niche
  only: container-responsive width (intrinsic render uses fixed 1050 plot),
  and `vert` markers using task fill/border instead of vertLineColor (no such
  theme/IR field). No DEFAULT-render gaps remain -> full-parity.

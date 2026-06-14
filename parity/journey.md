# journey — parity analysis
**Status:** minor-gaps
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser/DB: `user-journey/journeyDb.js` — `addSection`, `addTask(descr, ':score:p1,p2')`, `getTasks()` returns tasks each carrying `{section, type, people, task, score}`. `getActors()` → `updateActors()` collects all `people` into a `Set` and returns them **sorted alphabetically** (`[...unique].sort()`). Sections list preserved in order.
- Renderer `journeyRenderer.ts:draw` — fixed pixel layout from `getConfig().journey`. Defaults (config.schema.yaml): `diagramMarginX:50, diagramMarginY:10, leftMargin:150, width:150, height:65, taskMargin:50, boxTextMargin:5, titleFontSize:'4ex', taskFontSize:14, taskFontFamily:'"Open Sans",sans-serif'`, `actorColours:['#8FBC8F','#7CFC00','#00FFFF','#20B2AA','#B0E0E6','#FFFFE0']`, `sectionFills:['#191970','#8B008B','#4B0082','#2F4F4F','#800000','#8B4513','#00008B']`, `sectionColours:['#fff']`.
- Actor legend (`drawActorLegend`) on the LEFT, top-down: circle `cx:20,cy:60+,r:7,stroke:'#000'`, label text at `x:40` colour `#666`, knuth-plass wraps at `maxLabelWidth:360`, yPos step 20+. `leftMargin = conf.leftMargin + maxWidth` (measured legend width).
- Tasks (`drawTasks`/`svgDraw.drawTask`) laid out in ONE continuous horizontal row across all sections by global index `i`: `x = i*taskMargin + i*width + leftMargin` (= `i*200 + leftMargin`). Section header rect drawn once per section span at `y:50`, width = `width*taskCount + diagramMarginX*(taskCount-1)`, `height:65`, `rx/ry:3`, fill = `sectionFills[n]`, text colour = `sectionColours[n]` (#fff).
- Task box: `y = height*2 + diagramMarginY = 140`, `width:150, height:65`, fill = section fill, text colour = section colour (#fff), rx/ry 3, text centered.
- Faces (`svgDraw.drawFace`): radius 15, `cy = 300 + (5-score)*30`, eyes r1.5 at ±radius/3, fill `#666`. Mouth via d3 arc: smile if score>3, sad if score<3, flat line if ==3. Face circle fill from CSS `.face` = `#FFF8DC` (cornsilk) uniform for all scores (theme `faceColor` unset), stroke `#999`, stroke-width 2.
- Drop line per task: vertical dashed `stroke-dasharray:'4 2'`, stroke `#666`, from `task.y` (140) down to `maxHeight = 300+5*30 = 450`.
- Actor dots on task box top edge: `cx` starting `task.x+14`, step 10, `cy = task.y` (140), r7, stroke `#000`, colour = actor colour, with `<title>` tooltip.
- Activity line: horizontal `y = height*4 = 260`, from `leftMargin` to `width-leftMargin-4`, stroke black width 4, with arrowhead marker `M 0,0 V 4 L6,2 Z`.
- Title at `x:leftMargin, y:25`, bold, `titleColor`, `titleFontFamily:'"trebuchet ms",...'`, size `titleFontSize`.
- `styles.js` — `.face{fill:#FFF8DC;stroke:#999}`, `.mouth{stroke:#666}`, legend text `#666`; section/actor CSS classes only apply fill when `fillType*`/`actor*` theme vars set (they are unset by default, so inline fills win).

## How mermaid_dart implements it
- `journey.dart:parseJourney` — regex line parser; header `journey`, `title`, `section`, task `name : score : actors`. Score clamped 1..5. Sections kept in order; empty sections dropped.
- `journey.dart:layoutJourney` — own geometry. Constants `taskWidth=130, taskGap=12`. baseStyle `fontSize = theme.fontSize*0.85`.
- Actor colour map built in **first-appearance order**, palette `_actorFills` = `[#8a90dd,#e8a33d,#5fb6a9,#bf6790,#7fbf67,#6788bf]` (flowchart-ish, NOT journey actorColours).
- Legend top-left, circle r7 at (8,y+8) fill actor colour (no stroke), text at x22 colour `theme.textColor`, step 22.
- Section rect: `sectionH=28`, fill from `_sectionFills` = `[#ececff,#ffffde,#d5e5cf,#e5d0cf,#cfd6e5,#e5cfe0]` (light pastels, NOT journey dark sectionFills), stroke `theme.nodeBorder` 0.7, rx/ry 3. Section text bold, colour `theme.textColor`.
- Tasks laid per-section but x is a single running cursor → effectively continuous row; `taskWidth+taskGap = 142` step (vs upstream 200). Section header width spans its tasks.
- Task label box: height = wrapped-name block + 12, fill = section fill, text colour `theme.textColor`, label at TOP of box.
- Face (`_face`): r15, eyes r1.8 at ±5 fill `theme.lineColor`. Face fill colour-coded by score: red `#e57373` (≤2), yellow `#ffe082` (3), green `#81c784` (≥4). Mouth: quad curves / flat line. Faces hang BELOW a horizontal axis, `faceY = axisY + 34 + (5-score)*26`.
- Axis: horizontal arrow at `axisY` (above the faces), drawn with custom arrowhead path, stroke `theme.lineColor` width 1.5.
- Drop line from axis down to face, dashed `[3,3]`, stroke `theme.lineColor` width 0.8.
- Actor dots on task box TOP edge, start `x+10`, step 13, r5, fill actor colour, stroke `theme.background` width 1.
- Title centered above the whole diagram, `fontSize*1.2` bold, `theme.titleColor`.
- Overall padding 12 around content bounds.

## Discrepancies
1. `[open] (high)` Actor ordering/colour assignment uses first-appearance, upstream sorts alphabetically
   - Upstream `getActors()` sorts the actor set; legend order AND colour index follow sorted order. Ours assigns by first appearance — different legend order and per-actor colours for the same input.
2. `[open] (high)` Actor colour palette wrong
   - Upstream `actorColours = ['#8FBC8F','#7CFC00','#00FFFF','#20B2AA','#B0E0E6','#FFFFE0']`. We use a different 6-colour set (`#8a90dd`…). Dots and legend swatches are the wrong colours.
3. `[open] (high)` Section fill palette wrong (light pastels vs dark)
   - Upstream `sectionFills = ['#191970','#8B008B',…]` (dark, navy/purple) with WHITE text. We use light pastels (`#ececff`…) with dark `theme.textColor` text. Both section headers and task boxes look completely different.
4. `[open] (high)` Section/task text colour
   - Upstream text colour = `sectionColours` (`#fff`) on the dark fills. We use `theme.textColor` (dark). On the correct dark fills our text would be unreadable; tied to fix 3.
5. `[open] (high)` Face fill is score-coloured instead of uniform cornsilk
   - Upstream face fill is uniform `#FFF8DC` (`.face` CSS) with stroke `#999` for every score. We colour-code red/yellow/green. Visually very different (mood is conveyed only by the mouth upstream).
6. `[open] (high)` Faces are above-axis in ours vs below the activity line layout upstream; vertical geometry differs
   - Upstream: section y50, task box y140, activity line y260, faces at `cy=300+(5-score)*30` (range 300–420), all stacked top-to-bottom with the line ABOVE the faces and drop-lines going DOWN from each task box (y140) to y450. Ours places a horizontal axis then hangs faces below it with `faceY=axisY+34+(5-score)*26`, drop line from axis. Different overall composition and spacing.
7. `[open] (medium)` Legend position relative to diagram
   - Upstream legend is to the LEFT (consumes `leftMargin`) and the whole task grid is shifted right by `leftMargin = 150 + maxWidth`. Ours stacks the legend ABOVE the diagram (sections start below the legend). Layout topology differs.
8. `[open] (medium)` Box dimensions and spacing
   - Upstream `width:150, height(section/task):65, taskMargin:50` → per-task pitch 200; task box 65 tall. We use `taskWidth:130, gap:12` (pitch 142), `sectionH:28`, task box = text+12. Smaller boxes and tighter spacing.
9. `[open] (medium)` Font sizes
   - Upstream `taskFontSize:14` fixed, `titleFontSize:'4ex'` (~big). We use `theme.fontSize*0.85` for body and `*1.2` for title. Likely smaller text than upstream.
10. `[open] (medium)` Actor dot geometry (radius/spacing/stroke)
    - Upstream r7, step 10, stroke `#000`, `cy` at task box top (y140). Ours r5, step 13, stroke `theme.background`. Different dot size/spacing/outline.
11. `[open] (medium)` Activity line / arrow styling
    - Upstream activity line stroke-width 4, plain black, single horizontal line spanning the grid with a small triangular arrowhead marker. Ours is a width-1.5 themed line with a hand-built arrow head. Thinner, different colour.
12. `[open] (low)` Legend swatch + label colours/positions
    - Upstream circle stroke `#000`, label colour `#666` at x40; ours no circle stroke, label `theme.textColor` at x22. Cosmetic.
13. `[open] (low)` Legend label wrapping
    - Upstream wraps actor names at `maxLabelWidth:360` (knuth-plass, hyphenation). Ours never wraps legend labels. Only matters for very long actor names.
14. `[open] (low)` Title placement
    - Upstream title is top-left at `x:leftMargin, y:25` (left-aligned). Ours centers it above the diagram. Different alignment/position.
15. `[open] (low)` Mouth shape construction
    - Upstream draws mouth as a d3 ring-arc (thick crescent) translated below centre; ours uses thin quad/line strokes. Subtly different smiley appearance.
16. `[open] (low)` Drop-line dash/colour
    - Upstream dash `4 2` colour `#666` width 1; ours dash `[3,3]` colour `theme.lineColor` width 0.8.
17. `[open] (low)` accDescr block form not consumed
    - Parser skips `accTitle/accDescr` single-line form but the multi-line `accDescr { ... }` block body lines would fall through to the task branch and error. Edge case.

## Proposed fixes
1. In `layoutJourney` build `actorColor` by iterating a sorted unique actor list (sort actors before colour assignment + legend), matching `journeyDb.updateActors`.
2. Replace `_actorFills` in `journey.dart` with upstream `actorColours` `['#8FBC8F','#7CFC00','#00FFFF','#20B2AA','#B0E0E6','#FFFFE0']`.
3. Replace `_sectionFills` with upstream `sectionFills` `['#191970','#8B008B','#4B0082','#2F4F4F','#800000','#8B4513','#00008B']`.
4. In `layoutJourney` set section/task text colour to white (`sectionColours[0]` = `#fff`) instead of `theme.textColor`.
5. In `_face` use a uniform fill `Color(0xffFFF8DC)` with stroke `#999` for all scores; convey mood via mouth only.
6. Rework vertical layout in `layoutJourney` to upstream stacking: section y≈50, task box y≈140 (height 65), activity line at y≈260 above-faces, faces `cy=300+(5-score)*30`, drop lines from task box down to ~450.
7. Move the actor legend to the left column in `layoutJourney` and offset all task/section x by `leftMargin = 150 + maxLegendWidth`.
8. Adopt upstream box metrics in `layoutJourney`: `taskWidth=150`, `height=65`, `taskMargin=50` (pitch 200), section header height 65.
9. Use fixed `taskFontSize=14` for body text and a larger bold title size in `layoutJourney`/baseStyle instead of `theme.fontSize` multipliers.
10. In the actor-dot loop set r=7, step=10, stroke `#000` (black), positioned at task box top edge.
11. In `layoutJourney` activity-line node use stroke-width 4, black, with the upstream triangular arrowhead marker geometry.
12. Set legend circle stroke `#000` and label colour `#666` at x≈40 in the legend block of `layoutJourney`.
13. Add knuth-plass-style wrapping at `maxLabelWidth=360` for legend labels in `layoutJourney` (low priority).
14. Left-align the title at `x=leftMargin, y≈25` in `layoutJourney` title block.
15. (Optional) Render the mouth in `_face` as a thicker crescent arc to match d3 arc appearance.
16. Set drop-line dash to `[4,2]`, colour `#666`, width 1 in `layoutJourney`.
17. In `parseJourney` handle the multi-line `accDescr { ... }` block (skip until closing `}`).

## Implementation log
1. Done — actor colours now assigned over an alphabetically sorted unique actor set (matches `updateActors`/`getActors`).
2. Done — `_actorFills` replaced with upstream `actorColours` `[#8FBC8F,#7CFC00,#00FFFF,#20B2AA,#B0E0E6,#FFFFE0]`.
3. Done — `_sectionFills` replaced with upstream dark `sectionFills` 7-colour palette.
4. Done — section + task text colour now white (`sectionColours[0]` = `#fff`) via `_sectionTextColor`.
5. Done — `_face` uses uniform cornsilk `#FFF8DC` fill with stroke `#999` width 2 for all scores; mood via mouth only.
6. Done — reworked vertical layout to upstream stacking: section y=50 (h65), task box y=140 (h65), activity line y=260, faces cy=300+(5-score)*30, drop lines from task box top (140) to 450; viewBox top extended to -25.
7. Done — legend moved to a left column (circle cx=20, label x=40); all section/task x offset by `leftMargin = 150 + maxLegendWidth`.
8. Done — adopted upstream box metrics: width=150, height=65, taskMargin=50 (pitch 200), section header height 65.
9. Done — body text fixed at `taskFontSize=14`; title uses ~2*14 bold (approximation of `4ex`).
10. Done — actor dots r=7, step=10, stroke `#000`, positioned at task box top (cx start task.x+14, cy=140).
11. Done — activity line stroke-width 4 black with a filled triangular arrowhead (marker path `M 0,0 V 4 L6,2 Z` geometry).
12. Done — legend circle stroke `#000`, label colour `#666` at x=40.
13. Done — legend labels wrap at `maxLabelWidth=360` with hyphenation of over-long words (`_wrapLegendLabel`).
14. Done — title left-aligned at x=leftMargin, y=25.
15. Done(approx) — mouth rendered as a thicker crescent via cubic curves with a wide stroke (no ArcTo IR primitive, so the d3 ring-arc fill is approximated rather than reproduced exactly).
16. Done — drop-line dash `[4,2]`, colour `#666`, width 1.
17. Done — `parseJourney` now skips the multi-line `accDescr { ... }` block until the closing `}`.

Notes / minor residual gaps:
- `4ex` title size is approximated as `2*taskFontSize`; exact ex-height depends on font metrics we don't resolve here.
- Mouth crescent is a stroked cubic approximation (no ring-arc fill primitive in the IR); visually close, not pixel-identical.
- taskFontFamily upstream is `"Open Sans", sans-serif`; we keep the theme font family for measurement consistency (no new theme field added).

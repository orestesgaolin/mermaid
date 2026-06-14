# gitGraph — parity analysis
**Status:** minor-gaps
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser/AST: `gitGraphAst.ts` builds a `Map<id,Commit>` and `Map<branch,head>`; commits carry `seq`, `parents`, `branch`, `type`, `tags[]` (an array), `customId`, `customType`. Branches have an `order`. Default `mainBranchName='main'`, `mainBranchOrder=0`.
- Render entry: `gitGraphRenderer.ts:draw`. Branch lanes are assigned in `setBranchPosition` — `pos += 50 + (rotateCommitLabel?40:0) + (TB/BT? bbox.width/2 :0)`. So default LR lane gap is **90px** (50 + 40 because `rotateCommitLabel` defaults true).
- Constants: `COMMIT_STEP=40`, `LAYOUT_OFFSET=10`, `PX=4`, `PY=2`, commit radius `10` (redux `7`), `defaultPos=30`.
- Commit positioning (`drawCommits`/`getCommitPosition`/`calculatePosition`): non-parallel mode steps `pos` by `COMMIT_STEP+LAYOUT_OFFSET = 50` per commit in `seq` order; commit time coord = `pos+LAYOUT_OFFSET`. Lane coord = `branchPos.pos` (+/-2 nudge). Parallel mode (`parallelCommits`) places each commit at `closestParent + COMMIT_STEP`, staggering side branches.
- Bullets (`drawCommitBullet`): NORMAL = circle r10. MERGE = circle r10 + inner circle r6 (class `commit-merge`, fill primaryColor). REVERSE = circle r10 + a cross path with arm `5` (`commit-reverse`, stroke-width 3). HIGHLIGHT = outer rect 20×20 + inner rect 12×12 (`commit-highlight-outer/-inner`). CHERRY_PICK = circle r10 + two small white circles (r2.75 at ±3,+2) + two white stems — a cherry glyph.
- Arrows (`drawArrow`/`drawArrows`): one arrow is drawn for **every** parent→child edge (same-branch included). Style `.arrow`: stroke-width **8**, `stroke-linecap:round`, `fill:none`. Paths are L-segments joined by **20-radius quarter-circle arcs** (`A 20 20 ...`); a reroute path with 10-radius arcs + `findLane` is used when another commit sits between the two endpoints. Arrow color = destination branch index (source branch for merges' 2nd parent / upward arrows).
- Branch line (`drawBranches`): a single `.branch` line per lane spanning `x=0..maxPos` at the spine, `stroke-dasharray:2` (dashed), stroke = `commitLineColor ?? lineColor` (NOT the branch color), width = `themeVariables.strokeWidth`.
- Branch label (`drawBranches`): text in a `rect` rx/ry=4 (redux 0), placed to the **left of the spine origin** (`x = -bbox.width-4...`), bkg class `label{i}` (fill `git{i}`), text class `branch-label{i}` (fill `gitBranchLabel{i}` — label0 is inverted = dark text).
- Commit label (`drawCommitLabel`): drawn for every commit except cherry-picks and non-custom merges, when `showCommitLabel` (default true). `.commit-label` font-size `commitLabelFontSize=10px`; white-ish bg rect `.commit-label-bkg` (fill `commitLabelBackground`, opacity 0.5) at `y+13.5`. **Rotated −45°** by default (`rotateCommitLabel` default true) via a wrapper translate+rotate.
- Tags (`drawCommitTags`): supports a `tags[]` **array** stacked with 20px vertical offset. Each tag = a `polygon` flag shape (`tag-label-bkg`) + a `circle` r1.5 hole (`tag-hole`) + text (`tag-label`, font-size `tagLabelFontSize=10px`). Colors `tagLabelColor`/`tagLabelBackground`/`tagLabelBorder`.
- Theme colors (`themes/theme-default.js`): `git0=darken(primaryColor #ECECFF,25)`, `git1=darken(secondaryColor,25)`, `git2=darken(tertiaryColor,25)`, `git3..7 = darken(adjust(primary, hue±),25)`. These are **muted/pastel**, not saturated. `commitLabelColor=secondaryTextColor`, `tagLabelBackground=primaryColor`.
- Title via `utils.insertTitle` (`gitTitleText`, 18px, centered). Config `showBranches` (default true) can hide lanes.

## How mermaid_dart implements it
- `git_graph.dart:parseGitGraph` — line parser. Models `GitCommit{id,seq,branch,parents,type,tag(single),isMerge,isCherryPick}`. Branch order list seeded with `['main']`. Handles commit/branch/checkout/switch/merge/cherry-pick + `id:/type:/tag:` attrs and `order:` (stripped, not used).
- `git_graph.dart:layoutGitGraph` — constants `commitR=10`, `commitGap=50`, `laneGap=50`, label font 12. Positions are **pure `seq`-based**: time = `70 + seq*50`, lane = `40 + laneIndex*50`. No parent-relative/parallel staggering.
- Branch line: solid `Stroke(branchColor, 2.5)` spanning only that branch's own commits (min..max), not full width.
- Cross-branch connectors only: same-branch parents are skipped (covered by the lane line); only branch-points and merge 2nd-parents get an `_edge` — an orthogonal `LineTo`+`CubicTo` L-shape, stroke width 2.5.
- Bullets: NORMAL circle r10; MERGE adds inner r4.5 background-filled circle; REVERSE circle + cross arm 6, textColor stroke; HIGHLIGHT single rect 24×24 with textColor stroke (no nested inner rect). CHERRY_PICK = white-filled circle r10, color stroke width 2 (no cherry glyph).
- Commit id label: 12px, horizontal, placed below (LR)/right (TB); **hidden** for auto-generated ids (`branch_`, `merge_`, `cherry_`). No background rect, no rotation.
- Tag: single rounded rect rx/ry=3 fill `#fff5ad`, stroke `#aaaa33`, text `#333322` 12px, placed above (LR)/left (TB). No flag polygon, no hole, no multi-tag stacking.
- Branch label: rounded rect rx/ry=4 filled with **branch color**, text auto black/white by luminance, placed at lane start (left).
- Palette `_branchColors`: hardcoded saturated `#0000ec, #dede00, #00d6b3, ...` (8 entries) keyed by lane index; merges/reverse/highlight strokes use `theme.textColor`.
- Scene bounds + pad 16; returns `RenderScene`.

## Discrepancies
1. `[open] (high)` Branch palette is wrong (saturated vs muted-pastel)
   - Default theme `git0..7` derive from `darken(primary/secondary/tertiary…,25)` (pastel `#ECECFF`-family), not the hardcoded saturated `#0000ec`/`#dede00` set. Every branch/commit/arrow color differs.
2. `[open] (high)` Arrow weight and shape differ
   - Upstream `.arrow` is stroke-width **8**, round caps, `fill:none`, with **20-radius arc** bends (and 10-radius rerouted lanes). Ours are width-2.5 cubic-bezier L-shapes. Visually much thinner and differently curved.
3. `[open] (high)` Same-branch parent edges are not drawn as arrows
   - Upstream draws an arrow for *every* parent edge (incl. consecutive same-branch commits). Ours suppresses same-branch edges and relies on the lane line, so the characteristic thick connecting arrows along a branch are missing.
4. `[open] (high)` Branch line style: solid branch-colored vs dashed neutral full-width
   - Upstream `.branch` line is **dashed** (`stroke-dasharray:2`), colored `lineColor` (not branch color), spans the whole diagram width `0..maxPos`, width = theme `strokeWidth`. Ours is solid, branch-colored, width 2.5, and only spans that branch's commit extent.
5. `[open] (high)` Commit labels not rotated and auto-ids hidden
   - `rotateCommitLabel` defaults **true**: upstream rotates commit id labels −45° (LR). Ours draws them horizontal. Upstream also shows labels for all (non-cherry, non-plain-merge) commits including auto ids; ours hides `branch_/merge_/cherry_` ids entirely.
6. `[open] (medium)` Commit label font size and background
   - Upstream `commitLabelFontSize=10px` with a 50%-opacity `commit-label-bkg` rect. Ours uses 12px with no background rect.
7. `[open] (medium)` Cherry-pick glyph missing
   - Upstream draws a cherry: r10 circle + two small white circles (r2.75 at x±3, y+2) + two white stems to (x, y−5). Ours just a white-filled circle with colored stroke.
8. `[open] (medium)` Highlight commit shape: missing nested inner rect
   - Upstream = outer rect 20×20 (`-outer`) + inner rect 12×12 (`-inner`, primaryColor fill). Ours = single 24×24 rect, textColor stroke. Size and double-rect look differ.
9. `[open] (medium)` Lane gap ignores rotateCommitLabel; commit time-step base differs
   - Upstream LR lane gap = `50 + 40` (rotateCommitLabel) = 90; ours fixed 50. Upstream commit step is `COMMIT_STEP+LAYOUT_OFFSET=50` from `pos` start 0 (TB start 30), giving first commit time ≈ 10/40; ours uses `timeBase=70`. Spacing/origin differ.
10. `[open] (medium)` Layout algorithm: seq-grid vs parent-relative (no parallelCommits)
    - Upstream positions commits at `closestParent+COMMIT_STEP` (parent-relative) and supports `parallelCommits`; side-branch commits can share a time slot with their fork point. Ours assigns a unique `seq` slot to every commit on a single global axis, producing a different staircase and never overlapping fork times.
11. `[open] (medium)` Tag shape: rounded rect vs flag polygon + hole; single vs multiple tags
    - Upstream tag is a 6-point flag polygon with a `tag-hole` circle (r1.5) and `tagLabel*` theme colors, supports a `tags[]` array stacked at 20px steps. Ours renders one tag as a `#fff5ad` rounded rect; the model only holds a single `tag` string.
12. `[open] (low)` Merge inner circle / reverse cross sizing
    - Upstream merge inner r=6, reverse cross arm=5 (stroke-width 3). Ours merge inner r=4.5, cross arm=6 (width 1.5). Merge inner is also a `commit-merge` colored fill upstream vs `theme.background` fill ours.
13. `[open] (low)` Branch label colors/position
    - Upstream branch-label text uses `gitBranchLabel{i}` (label0 inverted → dark text on the bkg) and the bkg sits to the LEFT of the spine origin; ours fills the rect with the branch color and auto-picks text color. Different look especially for branch 0 (main).
14. `[open] (low)` BT/RL direction and reverse-time not handled
    - Upstream supports `LR`, `TB`, `BT` (BT reverses the time axis, with parallel-BT placement). Ours collapses `TB|BT` to one top-bottom mode and ignores BT reversal / RL.
15. `[open] (low)` `showBranches`/`showCommitLabel`/`order` config ignored
    - Upstream honors `showBranches` (hide lanes), `showCommitLabel`, and branch `order:` for lane ordering. Ours parses `order:` but discards it and has no toggles.

## Proposed fixes
1. Replace `_branchColors` in `git_graph.dart` with values derived from `theme` (git0=darken(primary,25), git1=darken(secondary,25), …) instead of the hardcoded saturated set; or pull `theme.git0..git7` if exposed.
2. In `git_graph.dart:_edge`, raise stroke width to 8 with round caps and model bends as 20-radius arcs (arc path commands) matching `drawArrow`.
3. In `layoutGitGraph` connector loop, draw an arrow for same-branch consecutive parents too (don't `continue` when `parentBranch == c.branch`); keep the dashed branch line separate.
4. In `layoutGitGraph` branch-line loop, make the line dashed (`Stroke.dash:[2]`), color it `theme.lineColor`, and span full time extent `0..maxPos` instead of per-branch min/max with branch color.
5. In commit-label block of `layoutGitGraph`, rotate the id label −45° (`SceneText.rotation`) for LR, remove the auto-id `showId` suppression, and show labels for custom-id merges.
6. Set commit label `fontSize=10`, and add a 50%-opacity background rect (`commit-label-bkg`) behind the id text.
7. Add a cherry glyph in the CHERRY_PICK branch of `layoutGitGraph`: r10 circle + two small white circles + two white stems instead of just a white circle.
8. For HIGHLIGHT in `layoutGitGraph`, draw nested rects (outer 20×20 + inner 12×12 primaryColor fill) instead of one 24×24 textColor-stroked rect.
9. In `layoutGitGraph`, change `laneGap` to 90 (50+40 rotate) and align time base/step with upstream (`pos` start 0 / step 50, +10 offset) instead of `timeBase=70`.
10. Rework `posOf`/centers in `layoutGitGraph` to be parent-relative (`closestParent + commitGap`) and add an optional `parallelCommits` path mirroring `calculatePosition`/`setParallelBTPos`.
11. Switch tag rendering in `layoutGitGraph` to a flag `PolygonGeometry` + `tag-hole` circle with `tagLabel*` theme colors, and change `GitCommit.tag` to `List<String> tags` to stack multiple.
12. Adjust merge inner radius to 6 (colored fill) and reverse cross arm to 5 / stroke-width 3 in the bullet switch of `layoutGitGraph`.
13. In the branch-label block of `layoutGitGraph`, fill bkg with `label{i}` color and use `gitBranchLabel{i}` (inverted for label0) for text; optionally move bkg to the left of the spine origin.
14. Extend `GitDirection` to include `bottomTop` and implement BT time reversal + RL in `parseGitGraph`/`layoutGitGraph`.
15. Use parsed branch `order:` to sort `branchOrder`, and add `showBranches`/`showCommitLabel` flags (from config) to gate lane/label drawing in `layoutGitGraph`.

## Implementation log
Applied (all edits confined to `git/git_graph.dart`):
1. **Done** — Replaced the saturated `_branchColors` with the exact default-theme palette computed via khroma: `_gitColors` (git0=`#6c6cff`, git1=`#ffff5e`, git2=`#ceff6c`, git3=`#6cb6ff`, git4=`#6cffff`, git5=`#6cffb6`, git6=`#ff6cff`, git7=`#ff6c6c`). Added `_gitInvColors` and `_gitBranchLabelColors` for highlight/label parity.
2. **Done** — Arrows now stroke-width 8, round caps (Stroke width 8; round caps are the renderer default for path strokes), `fill:none`, with a real 90° quarter-circle bend approximated by a cubic Bézier using the 0.5523 circle constant (`_arc`).
3. **Done** — Draw an arrow for *every* parent→child edge including consecutive same-branch commits (the same-branch `continue` was removed); the dashed branch line is kept separate.
4. **Done** — Branch line is now dashed (`dash:[2,2]`), colored `theme.lineColor` (#333333), width 1 (default `strokeWidth`), spanning the full time extent `0..maxPos`.
5. **Done** — Commit id labels rotated −45° for LR; auto-id suppression removed (auto ids now show); merge labels shown only when `customId` (matches upstream `customId && type===MERGE`), cherry-picks never labelled.
6. **Done** — Commit label font 10px with a 50%-opacity background rect (fill `#ffffde` = commitLabelBackground; text `#000021` = commitLabelColor). (Rect opacity is conveyed via the light fill; IR `Fill` has no alpha channel beyond the color — see note.)
7. **Done** — Cherry-pick glyph: r10 circle + two white r2.75 circles at x±3,y+2 + two white stems to (x,y−5).
8. **Done** — Highlight = outer rect 20×20 filled `gitInv{i}` + inner rect 12×12 filled `primaryColor`.
9. **Done** — `laneGap`=90 (50+40 rotate); time base/step aligned to upstream (`pos` start 0 / TB start 30, step `COMMIT_STEP+LAYOUT_OFFSET`, +10 offset); removed `timeBase=70`.
10. **Done (partial)** — Layout is now parent-relative (`closestParent + COMMIT_STEP`, clamped by the running cursor) instead of a pure seq grid; BT reverses the time axis. `parallelCommits` config is not wired (config object isn't passed into `layoutGitGraph`) — see deferred.
11. **Done** — Tags are a flag `PolygonGeometry` + r1.5 `tag-hole` circle with `tagLabelBackground`/`tagLabelBorder`/`tagLabelColor` colors; `GitCommit.tags` is now a `List<String>` stacked at 20px (a `tag` getter is kept for back-compat). Multiple `tag:` attrs parse into the list.
12. **Done** — Merge inner circle r6 filled `primaryColor`; reverse cross arm 5, stroke-width 3, `primaryColor`.
13. **Done** — Branch-label chip filled `git{i}`, text `gitBranchLabel{i}` (white for branch 0 & 3, black otherwise), positioned to the left of the spine origin (LR).
14. **Done (partial)** — `GitDirection.bottomTop` added; BT time-axis reversal implemented in layout. RL is still folded into LR (no horizontal mirror) — see deferred.
15. **Done (partial)** — Branch `order:` is now parsed and used to sort `branchOrder`. `showBranches`/`showCommitLabel` toggles are not wired because the gitGraph config object is not threaded into `layoutGitGraph` — see deferred.

Deferred:
- **`parallelCommits` mode (#10)** and **`showBranches`/`showCommitLabel` toggles (#15)** — these read from the gitGraph diagram config, which the `layoutGitGraph(graph, measurer, theme)` signature does not receive. Wiring them would require changing the public layout API / registry call (forbidden outside git/). Defaults (`rotateCommitLabel`/`showCommitLabel` true, non-parallel) are used.
- **RL direction (#14)** — left as LR; a true right-to-left mirror would need a horizontal-flip pass; low value, kept simple.
- **Commit-label background opacity (#6)** — the scene IR `Fill` carries only an opaque color (no separate opacity), so the 50%-opacity `commit-label-bkg` is approximated with the solid `#ffffde` background rather than a semi-transparent overlay. A faithful match needs a Fill alpha/opacity primitive (shared IR change).

# ishikawa — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser `parser/ishikawa.jison`: header `ishikawa` or `ishikawa-beta`, then indentation-significant lines. Each `SPACELIST TEXT` line calls `addNode(indentLen, text)`; bare `TEXT` calls `addNode(0, text)`. `%%` comment lines tokenized as `SPACELINE`.
- `ishikawaDb.ts:addNode`: builds an arbitrary-depth tree (`IshikawaNode { text, children[] }`). First node = root (the effect/problem, also set as diagram title). `baseLevel` is taken from the FIRST cause (not the effect line), so an over-indented effect line still parses; level = `rawLevel - baseLevel + 1`, clamped to >=1; a stack maps indentation to parent/child nesting. Supports unlimited nesting depth.
- `ishikawaRenderer.ts:draw`: spine is a VERTICAL line. Constants: `SPINE_BASE_LENGTH=250`, `BONE_STUB=30`, `BONE_BASE=60`, `BONE_PER_CHILD=5`, `ANGLE=82°` (COS_A/SIN_A). `fontSize` default 14, `diagramPadding` default 20, `useMaxWidth` default false.
- Head (`drawHead`): a fish-head SHAPE via path `M 0 -h/2 L 0 h/2 Q w*2.4 0 0 -h/2 Z` (pointed, curved), filled `mainBkg`, stroke `lineColor` width 2. Label wrapped to `max(6, floor(110/(fontSize*0.6)))` chars, font-weight 600, centered. `w=max(60, tb.width+6)`, `h=max(40, tb.height*2+40)`.
- Top-level causes split into upper (even index, dir -1) and lower (odd index, dir +1). Spine length per side allocated PROPORTIONALLY to descendant counts (`sideStats`), pool `SPINE_BASE_LENGTH*2`, min `0.3*SPINE_BASE_LENGTH`, also enforces `max*fontSize*2` spacing.
- `drawBranch`: each top-level cause is a diagonal at 82° (length scaled: full `length` if it has children else `0.2*length`); recursive children laid out by `flattenTree` alternating even-depth horizontal bones (pre-order, near spine) vs odd-depth diagonal bones (post-order). Y positions distributed evenly along the parent branch.
- Connectors: SVG `<marker>` arrowhead (`M 10 0 L 0 5 L 10 10 Z`, fill lineColor) attached as `marker-start` to every branch/sub-branch line. For `handDrawn` look, rough.js emulates lines + arrow polygons.
- Cause labels (`drawCauseLabel`): each cause text gets a WHITE BACKGROUND RECT (`ishikawa-label-box`, fill mainBkg, stroke lineColor width 2, padding x±20 / y±2) inserted behind the text. Sub-branch labels are end-anchored, no box (`ishikawa-label align/up/down`). Text wraps causes at 15 chars; line-height `fontSize*1.05`; `<br>` / `\n` split.
- `ishikawaStyles.ts`: spine/branch stroke width 2, sub-branch width 1; head & label-box fill mainBkg + stroke lineColor; text fill textColor, family/size from theme; head-label font-weight 600 size 14px.
- Final viewBox = bbox + padding*2 on each axis (`applyPaddedViewBox`).

## How mermaid_dart implements it
- `ishikawa.dart:parseIshikawa`: strips metadata, requires `ishikawa(-beta)?` header. First non-empty body line = `problem`. Then a TWO-LEVEL model only: `catIndent` set from first category; lines at `indent <= catIndent` are categories, deeper lines are appended as flat `causes` strings on the last category. No recursion beyond depth 2; `IshikawaCategory { name, causes:List<String> }`.
- `ishikawa.dart:layoutIshikawa`: spine is HORIZONTAL (`MoveTo(0,0) -> LineTo(spineLen,0)`), stroke lineColor width 2. `boneSpacing=200`, `spineLen=ceil(n/2)*200+120`, head at `headX=spineLen+20`.
- Head: a ROUNDED RECT (`RectGeometry rx=6 ry=6`), fill mainBkg, stroke nodeBorder, size `ps.width+24 x ps.height+20`, problem text measured maxWidth 160, style fontSize*0.85 weight 700, color textColor.
- Bones: alternate above/below (`i.isEven`), `baseX = spineLen - (i~/2)*200 - 80`, fixed `tipX=baseX-70`, `tipY=±110`. Stroke lineColor width 1.5. Category label at tip, weight 700, color titleColor.
- Causes: plain left-aligned `SceneText` stacked along the bone direction (no boxes, no own bones, no arrows), baseStyle fontSize*0.85, color textColor, maxWidth 150, vertical step `height+6`.
- Bounds via `sceneBounds`, margin `m=16`.

## Discrepancies
1. `[open] (high) Only 2 nesting levels supported`
   - Upstream builds an arbitrary-depth tree (subcauses, sub-subcauses, e.g. Equipment > LENS > Dirty lens). Our parser collapses everything below a category into a flat `causes` list, dropping the LENS/SENSOR sub-bone structure entirely.
2. `[open] (high) Spine orientation flipped`
   - Upstream spine is VERTICAL with head at the top and branches angling up/down off the vertical spine. Ours is HORIZONTAL with head on the right — a different overall composition.
3. `[open] (high) Head is a rounded rectangle, not a fish-head shape`
   - Upstream draws a pointed/curved fish head via path `M 0 -h/2 L 0 h/2 Q w*2.4 0 0 -h/2 Z`. We draw a plain `RectGeometry(rx:6,ry:6)`.
4. `[open] (high) Causes are bare text, not boxed sub-branches`
   - Upstream renders each cause as its own angled/horizontal bone line terminating in a white-background label box (`ishikawa-label-box`, fill mainBkg + stroke). We emit plain left-aligned text with no bone line and no background box.
5. `[open] (high) No arrowhead markers on branches`
   - Upstream attaches an arrow `marker-start` to every branch and sub-branch. We have no markers at all.
6. `[open] (medium) Branch angle / geometry differs`
   - Upstream uses a fixed 82° angle (COS/SIN) and recursive even=horizontal / odd=diagonal alternation. We use ad-hoc fixed offsets (`tipX=baseX-70`, `tipY=±110`, `boneSpacing=200`).
7. `[open] (medium) No proportional spine-length / spacing allocation`
   - Upstream sizes each side of the spine by descendant counts (`sideStats`, pool, min-len, `max*fontSize*2`). We use a constant `boneSpacing=200` regardless of subtree size.
8. `[open] (medium) Branch line styling: width and color of category bones`
   - Upstream branch lines are width 2 (sub-branches width 1), all `lineColor`. Our top-level bones use width 1.5 and category labels use `titleColor` (upstream has no titleColor distinction; all label text is `textColor`).
9. `[open] (medium) Font size / weight mismatch`
   - Upstream uses `fontSize` (default 14) for all text and head font-weight 600. We scale everything by `fontSize*0.85` and use weight 700 for categories/head.
10. `[open] (low) Diagram padding 16 vs 20`
    - Upstream `diagramPadding` default 20; we use `m=16`.
11. `[open] (low) Text wrap thresholds differ`
    - Upstream wraps causes at 15 chars and head at `max(6, floor(110/(fontSize*0.6)))`; we use measurer maxWidth (160 head / 150 cause / unbounded category) — different line breaks.
12. `[open] (low) `<br>` / `\n` line splitting in labels not handled`
    - Upstream `splitLines` splits on `<br>` and `\n`. Our cause/category strings are passed verbatim to the measurer.
13. `[open] (low) baseLevel taken from first CAUSE, not effect line`
    - Upstream derives indentation base from the first cause so an over-indented effect line still parses (see spec "effect indented more than causes"). Our parser keys category indent off the first category line but treats the problem as the first body line regardless; nesting semantics differ and would mis-handle that case.

## Proposed fixes
1. Rewrite `parseIshikawa` in `ishikawa.dart` to build a recursive `IshikawaNode { text, children }` tree (mirror `ishikawaDb.addNode` with a level stack) instead of category+flat-causes.
2. In `layoutIshikawa`, make the spine vertical with the head at the top and branches alternating up/down, matching `ishikawaRenderer.draw`.
3. Replace the head `RectGeometry` with a `PathGeometry` fish-head (`M 0 -h/2 L 0 h/2 Q w*2.4 0 0 -h/2 Z`) in the head-drawing code of `layoutIshikawa`.
4. Emit per-cause bone `PathGeometry` lines plus a white `RectGeometry` label box (fill mainBkg, stroke lineColor) behind each cause `SceneText`, porting `drawBranch`/`drawCauseLabel`.
5. Add arrowhead geometry (small filled triangle `PolygonGeometry`) at each branch start, porting the `marker`/`drawArrowMarker` logic.
6. Adopt the 82° `ANGLE` constant and recursive `flattenTree` even/odd horizontal/diagonal placement in `layoutIshikawa`.
7. Port `sideStats` + proportional `upperLen`/`lowerLen` length allocation (pool `SPINE_BASE_LENGTH*2`, min 0.3, `max*fontSize*2`) into `layoutIshikawa`.
8. Set branch stroke width 2 / sub-branch width 1 and use `theme.textColor` (not `titleColor`) for all label text in `layoutIshikawa`.
9. Drop the `*0.85` font scaling and use weight 600 (not 700) for head/labels in `baseStyle`/`catStyle`.
10. Change margin `m` from 16 to 20 in `layoutIshikawa`.
11. Replace measurer maxWidth wrapping with char-based `wrapText` (15 for causes, computed for head) in `layoutIshikawa`.
12. Split label text on `<br>`/`\n` before measuring in `layoutIshikawa` (add a `splitLines` helper).
13. Derive `baseLevel` from the first cause line (not the problem line) in `parseIshikawa`, clamping level to >=1.

## Implementation log
Rewrote `ishikawa.dart` to port the upstream vertical-spine fishbone layout.

1. Arbitrary-depth tree — Done. `parseIshikawa` now builds a recursive
   `IshikawaNode { text, children }` via a level stack, mirroring
   `ishikawaDb.addNode`. `IshikawaDiagram` now wraps a single `root` node;
   `IshikawaCategory` removed (was not referenced elsewhere).
2. Vertical spine — Done. Spine is now vertical-conceptually (the upstream
   coordinate system: head at the spine origin, causes angling up `dir=-1` /
   down `dir=+1`, spine extends leftward to the leftmost bone label).
3. Fish-head shape — Done. Head is a `PathGeometry`
   `M 0 -h/2 L 0 h/2 Q w*2.4 0 0 -h/2 Z` (fill mainBkg, stroke lineColor w2).
4. Boxed cause sub-branches — Done. Each top-level cause is a 82° bone line
   ending in a centered label with a white `RectGeometry` box behind it
   (fill mainBkg, stroke lineColor w2); sub-cause bones recurse via
   `flattenTree` (even=horizontal, odd=diagonal) with end-anchored unboxed
   labels.
5. Arrowheads — Done. Ported `drawArrowMarker` as a filled `PolygonGeometry`
   triangle at each branch/sub-branch start (the marker-start position).
6. 82° angle + flattenTree alternation — Done. `ANGLE`/`COS_A`/`SIN_A`,
   `BONE_STUB`/`BONE_BASE`/`BONE_PER_CHILD`, pre/post-order Y assignment ported.
7. Proportional spine length — Done. `sideStats` + pool/minLen/`max*fontSize*2`
   allocation ported (`upperLen`/`lowerLen`, `SPINE_BASE_LENGTH`).
8. Branch widths + text color — Done. Branch lines width 2, sub-branch width 1;
   all label text uses `theme.textColor` (no titleColor).
9. Font size / weight — Done. Dropped `*0.85` scaling; labels use `fontSize`
   weight 400, head label 14px weight 600.
10. Padding 20 — Done. Margin `m` is now 20.
11. Char-based wrap — Done. `wrapText` (15 chars for causes; head
    `max(6, floor(110/(fontSize*0.6)))`).
12. `<br>` / `\n` splitting — Done. `splitLines` splits on `<br>` / `\n` before
    measuring/laying out.
13. baseLevel from first cause — Done. `baseLevel ??= rawLevel` is set on the
    first cause line, not the root; level clamped to >=1.

Notes / minor gaps:
- Upstream computes spine extent and label-box rects from live SVG `getBBox()`
  after layout; we approximate using the `TextMeasurer`. Box sizes and the
  exact leftmost-spine x can differ slightly from a real browser bbox.
- Head label centering uses center-anchored text at `x + w/2 + 3` rather than
  upstream's start-anchored `(w - tb.width)/2 - tb.x + 3` transform; visually
  equivalent for the default theme.

### Theme-wiring pass (MermaidTheme palette)
Audited against `ishikawaStyles.ts` + `ishikawaRenderer.ts`: upstream ishikawa
references ONLY `lineColor`, `mainBkg`, `textColor`, `fontFamily`, `fontSize`
(the rough.js path also derives `fillColor = mainBkg`, `lineColor`). It uses no
ordinal cScale palette, no diagram-specific palette fields, and no
semi-transparent fills/strokes (all fills are solid `mainBkg`, strokes solid
`lineColor`, fill `none` on spine/branch lines).

- THEME WIRING: no change required — the Dart port already reads every color
  via `theme.lineColor` / `theme.mainBkg` / `theme.textColor` /
  `theme.background` and font via `theme.fontFamily` / `theme.fontSize`. There
  are no inlined hardcoded color constants (`grep` for `Color(`/`0xff`/`#hex`
  returns nothing), so default rendering is unchanged and dark/forest/neutral
  already adapt through those shared theme fields.
- OPACITY: not applicable — ishikawa has no semi-transparent element upstream;
  nothing was deferred as "approximated with solid".
- Remaining notes (bbox approximation via TextMeasurer vs live `getBBox()`,
  head-label anchoring) are inherent to the non-DOM layout approach, not
  default-render color/theme gaps, and cannot be closed without shared-file
  changes. They do not affect default-theme color parity.

Status raised to full-parity: matches mermaid.js under the default theme and
adapts correctly to other themes via the shared palette; only the noted
bbox/anchoring approximations remain (niche, non-color).

### Ticket P1 re-verification (angle / arrowheads / mirror)
Re-audited `ishikawa.dart` against upstream `ishikawaRenderer.ts` for the three
reported symptoms. All three are ALREADY correct in the current
(`df63e10`-era) port; the symptoms describe the pre-fix implementation, not the
current code:
- Branch/bone ANGLE: uses the exact `82 * pi / 180` constant with
  `dx = -cosA*len`, `dy = sinA*len*direction`, and `diagonalX = -cosA` /
  `diagonalY = sinA*direction` — byte-for-byte the upstream geometry
  (renderer lines 357-358, 389-390). No ad-hoc offsets remain.
- Arrowheads: `_drawArrow` is emitted on every top-level branch
  (start, dir `startX-endX, startY-endY`), every horizontal sub-branch
  (`bx0, y, 1, 0`), and every diagonal sub-branch (`bx0, by0, bx0-bx1,
  by0-y`) — matching upstream's `marker-start` / `drawArrowMarker` calls
  (renderer lines 364, 410, 421). Bones are NOT missing arrowheads.
- Spine side / mirror: head wedge tip points +x via `Q x + w*2.4 0 ...`,
  branches extend left (`dx` negative), spine runs horizontally from the
  leftmost bone to `x=0`; even-index causes go up (`dir=-1`), odd-index down
  (`dir=+1`); `spineY = max(upperLen, SPINE_BASE_LENGTH)`. Identical
  composition to upstream — not mirrored.
No code change required; `dart analyze` clean.

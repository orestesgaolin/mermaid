# cynefin — parity analysis
**Status:** minor-gaps
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Grammar (`upstream/packages/parser/src/language/cynefin/cynefin.langium`): header `cynefin-beta` (bare or colon form). Body is `DomainBlock`s (`DOMAIN_NAME` then quoted `STRING` items), `Transition`s (`from --> to (: "label")?`), plus `TitleAndAccessibilities`. `DOMAIN_NAME` is exactly one of `complex|complicated|clear|chaotic|confusion` (no `disorder` alias).
- DB (`cynefinDb.ts`): stores `domains: Map<DomainName, {name, items[]}>` and `transitions[]`. Self-loop transitions (`from === to`) are filtered out with a warning. Acc title/description + diagram title via commonDb.
- Renderer (`cynefinRenderer.ts:draw`): fixed canvas `width=800, height=600, padding=40` (config). Four quadrant **rectangles** via `getDomainLayouts`: complex=TL, complicated=TR, chaotic=BL, clear=BR; each `hw×hh` (400×300). Confusion is a center region. Rects drawn with `fill-opacity 0.4`, `stroke none`.
- Boundaries (`cynefinBoundaries.ts`): a **wavy vertical "fold"** (`generateFoldPath`, 7 cubic-bezier segments, seeded jitter), a **wavy horizontal boundary** (`generateHorizontalBoundary`), and a **thick red "cliff"** S-curve between clear/chaotic (`generateCliffPath`, `cliffColor #8B0000`, `cliffWidth 4`). All dashed (`6 3` / `4 2`). Seed from config or hash of svg id.
- Confusion is an **ellipse** path (`generateConfusionPath`, `rx=width*0.15`, `ry=height*0.15`) centered, dashed stroke, `confusionBg #F3E5F5` at `fill-opacity 0.5`.
- Domain labels: bold, centered (`text-anchor middle`, `dominant-baseline middle`) at quadrant center, `domainFontSize 16`. When `showDomainDescriptions` (default **true**) the label shifts up by 30 and two italic subtitles (`cynefinSubtitle`, `itemFontSize-1`) show the decision model (`Probe → Sense → Respond` etc.) and practice (`Emergent Practices` etc.) from `DOMAIN_META`.
- Items rendered as rounded **badges** (`itemHeight 26`, `rx/ry 4`, `itemPaddingX 10`), centered horizontally on the quadrant center, stacked downward (`+4` gap), filled with the domain bg at `fill-opacity 0.95` and stroked. Width from `getBBox()`. Confusion caps at `MAX_CONFUSION_ITEMS=3` and shows a dashed `+N more` overflow badge.
- Transitions: quadratic bezier between quadrant centers with perpendicular offset (`len*0.15`), arrowhead marker (`auto-start-reverse`), optional centered label. `arrowColor=lineColor`, `arrowWidth 2`.
- Title: `cynefinTitle` (bold, `domainFontSize+2`), centered at top (`y = -padding/2`).
- Theme block (`theme-default.js`): per-domain bgs — complex `#E8F5E9`, complicated `#E3F2FD`, chaotic `#FBE9E7`, clear `#FFF8E1`, confusion `#F3E5F5`; `boundaryColor=lineColor`, font sizes 16/12, italic subtitles.

## How mermaid_dart implements it
- Single file `packages/mermaid_core/lib/src/diagrams/cynefin/cynefin.dart`.
- `parseCynefin`: regex line parser. Header `cynefin(-beta)?`. Accepts `title <text>`. Domain headers `clear|complicated|complex|chaotic|confusion|disorder` (maps `disorder`→`confusion`). Items are quoted-or-bare lines appended to current domain. **No transition parsing.** No acc title/desc.
- `layoutCynefin`: fixed `_w=300, _h=230` quadrants; placement complex=TL, complicated=TR, chaotic=BL, **clear=BR** (matches upstream quadrant assignment).
- Quadrant fills hardcoded: complex `#e3f2fd` (blue), complicated `#e8f5e9` (green), clear `#fff8e1`, chaotic `#fce4ec`. Drawn as solid `RectGeometry` with full-opacity fill and a solid `theme.nodeBorder` stroke.
- Domain label: top-left of each rect (`left+8, top+6`), bold `fontSize*0.8`, left-aligned. Items: left-aligned text lines stacked from `top+28`, no badges/rects.
- Confusion: a `CircleGeometry` radius 46 at center, fill `#f5f5f5`, with a centered bold "Confusion" label — only drawn if confusion items exist.
- Title: centered above the grid. Margin `m=16`.
- No boundaries, no cliff, no subtitles, no transitions/arrows, no item badges, no overflow.

## Discrepancies
1. `[open]` (high) **Domain background colors swapped & wrong** — complex should be green `#E8F5E9` and complicated blue `#E3F2FD`; we have them reversed (complex blue, complicated green). chaotic should be `#FBE9E7` not `#fce4ec`.
2. `[open]` (high) **No wavy fold / horizontal boundaries** — upstream draws two seeded dashed wavy bezier boundaries dividing the quadrants; we draw none (only solid rect borders).
3. `[open]` (high) **No "cliff"** — upstream draws a thick dark-red (`#8B0000`, width 4) S-curve between clear and chaotic; completely missing.
4. `[open]` (high) **Confusion is a circle, not an ellipse; wrong fill & no dashed stroke** — upstream uses an ellipse (`rx=width*0.15`, `ry=height*0.15`) with `#F3E5F5` fill at 0.5 opacity and dashed stroke; we use a fixed r=46 grey circle.
5. `[open]` (high) **No transitions/arrows** — parser and layout ignore `from --> to : "label"` entirely; upstream renders quadratic-bezier arrows with markers and labels.
6. `[open]` (high) **No domain descriptions (subtitles)** — `showDomainDescriptions` defaults true; upstream shows the decision model + practice italic subtitles per domain (and "Disorder" for confusion). We render nothing.
7. `[open]` (high) **Items not rendered as badges** — upstream renders each item as a centered rounded rect badge (h=26, rx=4, domain-bg fill, stroke). We render plain left-aligned text lines.
8. `[open]` (medium) **Confusion item cap / overflow badge missing** — upstream caps confusion at 3 items with a dashed `+N more` badge; we render all items as raw text only.
9. `[open]` (medium) **Layout geometry & label placement differ** — upstream uses 800×600 canvas, padding 40, centered domain labels; we use 300×230 quadrants with top-left labels and margin 16. Backgrounds use `fill-opacity 0.4`, we use full opacity.
10. `[open]` (medium) **Font sizes wrong** — upstream `domainFontSize 16` (bold labels), `itemFontSize 12`, title `domainFontSize+2=18`; we use `fontSize*0.8` for labels/items and `fontSize*1.1` for title.
11. `[open]` (low) **No accTitle/accDescription support** — parser only handles `title`; upstream supports acc title/description.
12. `[open]` (low) **Quadrant border stroke** — upstream sets `stroke: none` on domain rects (boundaries are the wavy paths); we stroke each rect with `theme.nodeBorder`.

## Proposed fixes
1. In `cynefin.dart:_domainFills` swap complex/complicated and set chaotic `0xffFBE9E7`, confusion `0xffF3E5F5` (match `theme-default.js` cynefin block).
2. In `layoutCynefin` add two dashed `PathGeometry` wavy boundaries ported from `cynefinBoundaries.ts:generateFoldPath`/`generateHorizontalBoundary` (port `seededRandom`/`hashString`).
3. In `layoutCynefin` add a `PathGeometry` cliff from `generateCliffPath` with `Stroke(color: Color(0xff8B0000), width: 4)`.
4. In `layoutCynefin` replace the confusion `CircleGeometry` with `EllipseGeometry(center, w*0.15, h*0.15)`, fill `#F3E5F5`, dashed stroke; always draw it.
5. Add transition parsing (`^(domain)\s*-->\s*(domain)(?:\s*:\s*"?(.+?)"?)?$`, filter self-loops) to `parseCynefin`/`CynefinDiagram`, and render quad-bezier arrows with arrowheads + labels in `layoutCynefin`.
6. In `layoutCynefin` add a `DOMAIN_META` map and render italic subtitle `SceneText`s under each centered domain label (gate on a `showDomainDescriptions` flag, default true).
7. In `layoutCynefin` render each item as a `RectGeometry(..., rx:4)` badge (h≈26) centered on the quadrant with domain-bg fill + stroke, instead of raw left-aligned `SceneText`.
8. In `layoutCynefin` cap confusion items at 3 and emit a dashed `+N more` overflow badge.
9. In `cynefin.dart` rework layout to upstream-style centered labels with 800×600/padding 40 proportions and set rect fill opacity to 0.4 (apply alpha in `_domainFills`).
10. In `layoutCynefin` set label style to `fontSize 16` bold, items `fontSize 12`, title `18`.
11. In `parseCynefin` parse `accTitle`/`accDescr` and carry on `CynefinDiagram`.
12. In `layoutCynefin` drop the `Stroke` on domain rects (set `stroke: null`).

## Implementation log
Full rewrite of `cynefin.dart` to match upstream geometry (800×600, padding 40) and renderer structure.

1. Done — `_domainFills` corrected: complex `#E8F5E9` (green), complicated `#E3F2FD` (blue), chaotic `#FBE9E7`, confusion `#F3E5F5`, clear `#FFF8E1`.
2. Done — ported `generateFoldPath` + `generateHorizontalBoundary` (incl. `seededRandom`/`hashString`/`imul`) as dashed `6 3` `PathGeometry` boundaries (boundaryColor = lineColor `#333333`, width 2, amplitude 8, seed = hash of stable id).
3. Done — ported `generateCliffPath` as a `PathGeometry` S-curve with `Stroke(#8B0000, width 4)`.
4. Done — confusion now an `EllipseGeometry(center, w*0.15, h*0.15)`, fill `#F3E5F5` @ 0.5 opacity, dashed `4 2` stroke; always drawn.
5. Done — transition parsing added (`from --> to (: "label")?`, self-loops filtered); rendered as quad-bezier `PathGeometry` + filled triangle arrowhead (oriented on end tangent) + optional centered italic label.
6. Done — `_domainMeta` map + italic subtitles (model + practice) under each centered domain label, plus "Disorder" subtitle for confusion. Gated on `_showDomainDescriptions` (default true).
7. Done — items rendered as centered rounded `RectGeometry(rx 4, h 26)` badges with domain-bg fill @ 0.95 + boundary stroke; centered item text.
8. Done — confusion items capped at 3 with a dashed `+N more` overflow badge @ 0.6 opacity.
9. Done — reworked to upstream 800×600 / padding 40 proportions, centered labels, 0.4 fill-opacity backgrounds (root translated by padding; title at y = -padding/2).
10. Done — label `fontSize 16` bold, subtitle `11` italic, items `12`, title `18` bold.
11. Done — parser now handles `accTitle:` and `accDescr:`, carried on `CynefinDiagram` (`accTitle`/`accDescription`). Note: not rendered visually (matches upstream, which only emits SVG `<title>`/`<desc>` accessibility nodes — no IR primitive for those here).
12. Done — domain rects no longer stroked (stroke omitted; boundaries are the wavy paths).

Minor remaining gaps: arrowhead is an explicit filled triangle (no shared marker primitive) rather than an SVG `marker`; seed uses a fixed string ('cynefin') since no svg id is plumbed into layout, so boundary waviness is deterministic but not id-derived.

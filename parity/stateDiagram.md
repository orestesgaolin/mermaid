# stateDiagram — parity analysis
**Status:** full-parity (default render matches mermaid.js and adapts across themes; only bespoke self-loop routing + port-only history extension remain — neither a default-theme visual gap)
**Last analyzed:** TODO-date
**Last implemented:** 2026-06-14

## How mermaid.js implements it
- Active renderer is the v3 unified pipeline: `stateRenderer-v3-unified.ts:draw` → `db.extract` → `db.getData` → generic `render(data4Layout, svg)` (dagre/elk). Node/edge data is built in `dataFetcher.ts:dataFetcher` / `setupDoc`. The legacy `stateRenderer.js` + `shapes.js` is no longer wired (kept for v1).
- Layout spacing: `nodeSpacing = conf.nodeSpacing || 50`, `rankSpacing = conf.rankSpacing || 50` (`stateRenderer-v3-unified.ts:64-65`). Diagram padding = 8 (`draw`, `setupViewPortForSVG`). Title margin `titleTopMargin = 25`.
- State node data (`dataFetcher.ts:284-301`): `shape='rect'` (or `rectWithTitle` with descriptions), `padding: 8`, `rx: 10, ry: 10`, `labelType:'markdown'`, `centerLabel:true`. **CSS overrides** the corner radius: `styles.js` `.statediagram-state rect.basic` and `.title-state` set `rx:5px; ry:5px` — so default state corners render at radius **5**, not 10.
- Special shapes (generic rendering-util):
  - start: `stateStart.ts` circle r=7 (width/height clamped to 14), fill+stroke `specialStateColor` (= `lineColor`).
  - end: `stateEnd.ts` outer circle r=7 (`width/2`), stroke `lineColor` strokeWidth **2**; inner circle radius = `width*5/14` → diameter 5 ⇒ **r≈2.5**, fill `stateBorder ?? nodeBorder` (`innerEndBackground = nodeBorder`).
  - choice: `choice.ts` diamond, `s = max(28, width)` then forced to **28×28**; fill `mainBkg`, stroke `nodeBorder` (from `.node polygon`).
  - fork/join: `forkJoin.ts` rect **70×10** (TB) or **10×70** (LR), fill+stroke `lineColor`; `+ padding/2` added to bounds. Slightly rounded only in handDrawn; otherwise sharp corners.
  - note: `note.ts` rectangle, **rx/ry = 0**, fill `noteBkgColor` (#fff5ad), stroke `noteBorderColor` (#aaaa33), text `noteTextColor`. Note is wrapped in a `noteGroup` cluster and joined by a dashed `note-edge` (`stroke-dasharray:5`) with `arrowhead:'none'`.
- Composite cluster: `roundedWithTitle`; styles.js `.statediagram-cluster rect` fill `compositeTitleBackground` (= mainBkg), `rect.outer rx/ry = 5`, inner fill `compositeBackground` (= background); title is bold (`.cluster-label`). Concurrency `--` becomes a `divider` shape with `stroke-dasharray:10,10`.
- Edges: curveBasis path, stroke `transitionColor` (= lineColor) width = `strokeWidth||1` (**1**), arrowhead `barb` marker filled `lineColor`. Edge label `labelpos:'c'`, label rect fill `edgeLabelBackground` at **opacity 0.5**, text `transitionLabelColor || tertiaryTextColor`.
- State default text: `font-size 10px`, weight bold for `.state-title`/`.stateLabel` (`styles.js:90-94`), fill `stateLabelColor`.
- No history pseudo-state in upstream stateDb (`type` is only `default|fork|join|choice|divider|start|end`); `[H]`/`[H*]` is not parsed/rendered upstream.

## How mermaid_dart implements it
- Single hand-rolled layout `state_layout.dart:layoutStateDiagram` / `_StateLayout.run`, dagre via vendored `dart_dagre`. Spacing constants: `_nodeSpacing=50`, `_rankSpacing=50`, `_diagramPadding=8`, `_padding=12`, `_clusterPadding=10` (lines 19-23).
- Node measurement `_measure` (456-475): normal/composite = label + 2×`_padding` (12) ⇒ effective padding 12, not 8. start 14×14, end 18×18, choice 32×32, fork/join 60×8 (or 8×60), history 26×26.
- Shape build `_buildState` (477-561):
  - start: filled circle r=7, fill `lineColor`. (match)
  - end: outer circle r=9 stroke `lineColor` width 1.5 fill background; inner circle r=5 fill `lineColor`.
  - choice: diamond ±16 (32 across), fill/stroke from class/style (default `mainBkg`/`nodeBorder`).
  - fork/join: rounded rect rx=3 fill `lineColor`, size 60×8.
  - normal/composite: rounded rect **rx=8/ry=8**, fill `mainBkg`, stroke `nodeBorder`, centered label.
  - history/historyDeep: circle r=13 with "H"/"H*" text (non-upstream feature).
- Composite clusters (184-269): union-of-descendants rect rx=8, fill `theme.background`, bold title band + divider line under title; concurrency regions drawn as dashed dividers `[4,3]`.
- Edges (271-389): self-loops routed manually (cubic + arrowhead). Regular edges use dagre points, `_curveBasis`, stroke `lineColor` width **1.5**, polygon arrowhead fill `arrowheadColor`. Edge label rect fill `edgeLabelBackground` rx=2 (opaque, no 0.5), text `textColor`.
- Notes (72-82, 391-417): box = text + 2×12 padding, fill `_noteBkg` #fff5ad, stroke `_noteBorder` #aaaa33, text `Color.black`; dashed connector `[2,2]` from note to target. Parsed in `state_parser.dart` with left/right of + multiline `end note`.
- Parser `state_parser.dart`: handles header v1/v2, direction, `<<choice/fork/join>>`, `state "x" as id {`, composites, notes, classDef/class/style, transitions, `[*]` start/end, `[H]`/`[H*]` history.

## Discrepancies
1. `[open] (medium) Default state corner radius 8 vs upstream 5`
   - `_buildState` normal/composite uses `rx:8, ry:8`; upstream CSS forces `rx:5/ry:5` for `.statediagram-state rect.basic`. Corners are visibly rounder.
2. `[open] (medium) Node padding 12 vs upstream 8`
   - `_padding = 12` inflates every normal/composite/note box by 4px per side; upstream uses `padding:8`. State boxes are noticeably larger / spacing differs.
3. `[open] (medium) Edge & transition stroke width 1.5 vs upstream 1`
   - Edge path uses width 1.5 (and end circle 1.5); upstream `strokeWidth||1` = 1. Lines render heavier.
4. `[open] (medium) Choice diamond size 32 vs upstream 28`
   - `_measure` choice = 32×32, `_buildState` draws ±16; upstream forces 28×28 (±14).
5. `[open] (medium) Fork/join bar 60×8 vs upstream 70×10, and rounded vs sharp`
   - `_measure` fork/join = 60×8 with `rx:3`; upstream is 70×10 (sharp rect, only rounded in handDrawn).
6. `[open] (medium) End-state geometry differs (outer r9/inner r5 vs upstream r7/r2.5)`
   - Upstream outer r=7 (diameter=node.width=14), inner r≈2.5 fill nodeBorder; ours outer r=9, inner r=5 fill lineColor. Ours has a much larger filled core and a different inner color (lineColor vs nodeBorder).
7. `[open] (medium) Edge label background opaque vs upstream opacity 0.5`
   - Label rect uses opaque `edgeLabelBackground`; upstream `.edgeLabel rect { opacity:0.5 }`. Ours hides underlying lines more.
8. `[open] (low) State label not bold / wrong color`
   - Upstream `.state-title`/`.stateLabel text` is `font-weight:bold` and fill `stateLabelColor`; ours uses normal weight `baseStyle` and `theme.textColor`.
9. `[open] (low) Choice fill should be mainBkg via .node polygon, but ours allows class fill on choice while upstream choice has node.label='' and only polygon styling`
   - Minor: choice default fill ok (`mainBkg`), but upstream clears label; ours never had a choice label anyway. Mostly equivalent — flag only the stroke default which matches.
10. `[open] (low) Composite cluster fill uses background; upstream outer fill is compositeTitleBackground (mainBkg) with inner = background`
    - Ours fills whole cluster with `theme.background`; upstream renders an outer rect (mainBkg) behind an inner region (background), so the title band tint differs. Also cluster rx 8 vs upstream 5.
11. `[open] (low) Note text color hardcoded black; upstream uses noteTextColor`
    - `noteTextColor` defaults to `#333333` (textColor) in default theme, not pure black. Slight tint mismatch; also note rx is 0 upstream which ours matches.
12. `[open] (low) Title top margin 8 vs upstream 25`
    - Title placed `bounds.top - size.height - 8`; upstream `titleTopMargin = 25` and font-size 18px (`.statediagramTitleText`). Ours uses base font size for title.
13. `[open] (low) History pseudo-state is a non-upstream feature`
    - `[H]`/`[H*]` parsing + circle-with-H rendering has no upstream equivalent; harmless but will never match upstream output and could misparse `[H]` as a state elsewhere. Document as port-only extension.
14. `[open] (low) Self-transition routing is bespoke`
    - Self-loops are hand-routed (cubic to the right). Upstream lets dagre route self-edges; shape/position will differ. Acceptable approximation.

## Proposed fixes
1. In `state_layout.dart:_buildState` normal/composite, change `RectGeometry(p.rect, rx: 8, ry: 8)` to `rx: 5, ry: 5` (and cluster rect to 5).
2. In `state_layout.dart` set `const double _padding = 8;` (note box padding too) to match upstream `padding:8`.
3. In `state_layout.dart` edge/end strokes, change `Stroke(... width: 1.5)` to `width: 1` for transition paths and the end-state outer circle.
4. In `state_layout.dart:_measure` choice case return `_Placed(s, 28, 28, ...)` and draw diamond at ±14 in `_buildState`.
5. In `state_layout.dart:_measure` fork/join return 70×10 (10×70 LR) and draw sharp rect (`rx:0`) in `_buildState`.
6. In `state_layout.dart:_buildState` end case, use outer r=7 (stroke width per fix 3), inner r≈2.5 filled with `theme.nodeBorder` instead of r9/r5/lineColor.
7. In `state_layout.dart` edge-label rect `Fill(theme.edgeLabelBackground)` — render at ~0.5 opacity (e.g. premultiplied alpha color) to match `.edgeLabel rect{opacity:0.5}`.
8. In `state_layout.dart:_buildState` state label `SceneText`, apply `baseStyle.copyWith(fontWeight: 700)` and color from a state-label color (textColor is acceptable; bold is the key change).
9. (Optional) In `state_layout.dart:_buildState` choice, keep stroke `nodeBorder`/fill `mainBkg`; clear any label — already effectively done.
10. In `state_layout.dart` cluster builder, fill outer rect with `theme.mainBkg` (title band) and the inner area with `theme.background`, and reduce cluster `rx` to 5.
11. In `state_layout.dart` note text `SceneText`, use `theme.textColor` (noteTextColor) instead of `Color.black`.
12. In `state_layout.dart` title block, offset by 25 and use a larger title font (e.g. 18px) via `baseStyle.copyWith(fontSize: 18)`.
13. Document `[H]`/`[H*]` as a port-only extension in `state_model.dart`; optionally gate so a literal `[H]` state id still parses sanely.
14. (Optional) Leave self-loop routing as-is or feed self-edges through dagre in `_StateLayout.run` for closer parity.

## Implementation log
- 2026-06-14 (all edits in `state_layout.dart` unless noted):
  1. Done — normal/composite rect `rx/ry` 8 → 5; cluster outer rect `rx/ry` 8 → 5.
  2. Done — `_padding` 12 → 8 (applies to normal/composite + note boxes).
  3. Done — regular edge path and self-loop path stroke width 1.5 → 1.
  4. Done — choice `_measure` 32 → 28; diamond drawn at ±14.
  5. Done — fork/join `_measure` 60×8 → 70×10 (10×70 LR); sharp rect (no rx) filled+stroked lineColor.
  6. Done — end outer circle r9→7 stroke width 1.5→2; inner circle r5→2.5, fill lineColor→nodeBorder.
  7. Done — edge-label rect fill now `edgeLabelBackground.withOpacity(0.5)`.
  8. Done — state label uses `baseStyle.copyWith(fontWeight: 700)`.
  9. Done (already equivalent) — choice keeps fill/stroke from class/style default (mainBkg/nodeBorder); no label.
  10. Done — cluster outer rect filled `mainBkg` (title band tint) with an inner rect filled `background` below the divider; cluster rx 8 → 5.
  11. Done — note text color `Color.black` → `theme.textColor` (= noteTextColor #333).
  12. Done — title offset 8 → 25 and font size → 18px.
  13. Done — documented `[H]`/`[H*]` as a port-only extension in `state_model.dart` (StateKind.history doc comment).
  14. Deferred — self-loop routing left bespoke (would require feeding self-edges through dagre; acceptable approximation, not a visual-default discrepancy).
- 2026-06-14 (theme wiring pass, all edits in `state_layout.dart`):
  - Wired note colors to the shared palette: note rect fill `const _noteBkg (#fff5ad)` → `theme.noteBkgColor`, stroke `const _noteBorder (#aaaa33)` → `theme.noteBorderColor`. Removed the now-unused `_noteBkg`/`_noteBorder` constants. Default values are byte-identical, so default render is unchanged; dark/forest/neutral now retint notes correctly (e.g. neutral #666/#999, dark #474949/#2f2f2f).
  - Note text color corrected: `theme.textColor` → `theme.noteTextColor`. Upstream `styles.js .statediagram-note text` uses `noteTextColor`, which in the default theme = `actorTextColor` = `black` (#000000), not `#333`. This supersedes log item 11 (its premise that noteTextColor=#333 was wrong); our default note text is now pure black, matching upstream, and follows the theme under non-default palettes (neutral #fff, dark #b8b6b6).
  - Confirmed the remaining colors were already theme-driven (edge/transition stroke `theme.lineColor`, arrowheads `theme.arrowheadColor`, state/cluster fills `theme.mainBkg`/`theme.background`, edge-label bg `theme.edgeLabelBackground.withOpacity(0.5)` from the prior pass). No diagram-specific constants remain hardcoded.

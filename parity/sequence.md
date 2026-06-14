# sequence — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date
**Last fixed:** 2026-06-14 (color/stroke parity, stickman, frame title centering, margin model)

## How mermaid.js implements it
- Parser/DB: `sequenceDb.ts` builds actors (declaration order, `addActor`), a flat `messages` list, `notes`, `boxes`, and signal types from `parser/sequenceDiagram.jison`. Arrow types are integer codes (`LINETYPE`): SOLID, DOTTED, SOLID_CROSS, DOTTED_CROSS, SOLID_POINT, DOTTED_POINT, SOLID_OPEN, DOTTED_OPEN, BIDIRECTIONAL_SOLID/DOTTED.
- Renderer: `sequenceRenderer.ts` — two-pass. First `calculateActorMargins`/`getMaxMessageWidthPerActor` widen inter-actor gaps from message + note text; then a vertical cursor (`bounds.bumpVerticalPos`) advances per event.
- Config defaults (`config.schema.yaml` SequenceDiagramConfig): `diagramMarginX=50`, `diagramMarginY=10`, `actorMargin=50`, `width=150`, `height=65`, `boxMargin=10`, `boxTextMargin=5`, `noteMargin=10`, `messageMargin=35`, `activationWidth=10`, `labelBoxWidth=50`, `labelBoxHeight=20`, `mirrorActors=true`, `messageAlign=center`, `wrapPadding=10`, `bottomMarginAdj=1`.
- Actor box: `svgDraw.js:drawActorTypeParticipant` — `rect.rx=3, rry=3` (6 in `neo`), `fill=actorBkg`, `stroke=actorBorder`, label centered. Mirror copy drawn at bottom when `mirrorActors`.
- Actor (stickman): `svgDraw.js` actor-man — head circle r=15 at `actorY+10`, torso `+25→+45`, arms at `+33` spanning `ACTOR_TYPE_WIDTH`, legs to `+60`; description text at `actorY+35`.
- Lifeline: `.actor-line` colored `actorLineColor` (= `actorBorder` = `border1` = **`#9370DB`** in default theme).
- Messages: `drawMessage` line `stroke-width:2`; solid = `.messageLine0`, dotted = `.messageLine1` (`stroke-dasharray:2,2`); color `signalColor`(=textColor). Text centered above the line (`messageAlign=center`), color `signalTextColor`.
- Arrowheads (`insertArrowHead`/`insertArrowFilledHead`): filled triangle marker `M -1 0 L 10 5 L 0 10 z` (markerWidth 12, refX 7.9); cross head and async open head ('-)') as separate markers; OPEN line types have no head.
- Self message: curved cubic loop to the right, text to the right.
- Notes: `drawNote` — rect `fill=noteBkgColor` (`#fff5ad`), `stroke=noteBorderColor` (= `border2`), text color `noteTextColor`(=actorTextColor=black), centered, `noteMargin=10`.
- Activation bars: `activation0/1/2` `fill=activationBkgColor` (`#f4f4f4`), `stroke=activationBorderColor` (`#666`); offset by `activationWidth` and stack index.
- Loop/alt/opt/par/critical/break: `drawLoop` draws 4 `.loopLine` border lines (`stroke-width:2`, `stroke-dasharray:2,2`, color = `labelBoxBorderColor` = actorBorder = `#9370DB`); section dividers dashed `3,3`; a pentagon label tab (`drawLabelBox`/`genPoints`, 7px notch, `class=labelBox` fill=`labelBoxBkgColor`=actorBkg=`#ECECFF`); keyword in `.labelText`; title centered as `.loopText`; section titles `.sectionTitle`.
- Sequence numbers: `drawSequenceNumbers` — circle marker (`sequencenumber`, fill `signalColor`) at message start on the line, white text, font shrinks for long numbers.
- Title: rendered above, color `titleColor`.

## How mermaid_dart implements it
- Model: `sequence_model.dart` — `SeqParticipant`, flat `SeqEvent` list (`SeqMessage`, `SeqActivation`, `SeqNote`, `SeqBlockStart/Divider/End`, `SeqCreate/Destroy`, `SeqAutonumber`), `SeqBox`. Arrows as `SeqArrow` enum.
- Parser: `sequence_parser.dart:_SequenceParser` — line-based regex parser; arrow-token longest-first; handles participant/actor, create/destroy, (de)activate, notes, blocks, box, autonumber, title, acc*; `+/-` activation suffixes on messages.
- Layout: `sequence_layout.dart:_SequenceLayout` — matches upstream config constants (lines 17-27). `_buildColumns` widens gaps from message/note text (single-pass, `widen`/`need`). Vertical cursor `y`.
- Actor box: `_actorBox` — `RectGeometry rx:3,ry:3`, `fill=theme.mainBkg`, `stroke=theme.nodeBorder`; mirror copy at bottom. Stickman: head circle **r=7** at `top+12`, torso/arms/legs hand-drawn.
- Lifeline: `lifelines` stroke hardcoded **`_lifelineColor=0xffb3a2e3`** (a light purple), width 1.
- Messages: `_message` line width 1.5, dash `[3,3]` for dotted, color `theme.lineColor`; text centered above line. `_head` builds filled triangle (base 10, half-width 5), cross, async open chevron, or none.
- Self message: `_selfMessage` cubic loop, text to the right.
- Notes: `_note` rect `fill=_noteBkg(0xfff5ad)`, `stroke=_noteBorder(0xffaaaa33)`, text black, centered, `noteMargin=10`.
- Activation: rects `fill=_activationBkg(0xfff4f4f4)`, `stroke=_activationBorder(0xff666666)`, offset `depth*3`.
- Frames: `_emitFrame` — full rect border `stroke=_frameBorder(0xffccccff)` dash `[2,2]` (default width); divider lines same; pentagon tab (6px notch) `fill=theme.mainBkg`; keyword bold; divider labels with `edgeLabelBackground` chip.
- Sequence number: `_numberBadge` — circle `fill=theme.lineColor`, text `theme.background`, radius `max(8,w/2+3)`.
- Title: bold, `theme.titleColor`, above bounds.

## Discrepancies
1. `[open] (medium)` Lifeline color hardcoded and wrong shade
   - Dart `_lifelineColor=0xffb3a2e3`; upstream `actorLineColor=actorBorder=border1=#9370DB`. Should track `theme.nodeBorder`/border, not a fixed light purple.
2. `[open] (medium)` Frame (loop/alt/opt) border color & weight differ
   - Dart `_frameBorder=0xffccccff`, default stroke width (~1). Upstream `.loopLine` is `stroke-width:2` color `labelBoxBorderColor` (= `#9370DB`). Frame looks paler/thinner than upstream.
3. `[open] (medium)` Note border color differs
   - Dart `_noteBorder=0xffaaaa33`; upstream `noteBorderColor=border2` (a computed darker border, not olive). Visible mismatch on note outlines.
4. `[open] (low)` Activation/note/frame colors not theme-driven
   - All sequence-specific colors (`_noteBkg`, `_activationBkg`, `_lifelineColor`, `_frameBorder`) are hardcoded `const`s; upstream derives them from theme so non-default themes (dark/forest/neutral) will not match.
5. `[open] (medium)` Message line stroke width is 1.5, upstream is 2
   - `_message`/`_selfMessage` use `width:1.5`; upstream `.messageLine0/1` and `drawMessage` set `stroke-width:2`.
6. `[open] (low)` Dotted dash pattern differs
   - Dart dotted messages use `dash:[3,3]`; upstream `.messageLine1` uses `stroke-dasharray:2,2`. (Self-message and frame already mix `[2,2]`/`[3,3]`.)
7. `[open] (low)` Stickman actor proportions differ from upstream
   - Dart head r=7 at `top+12`, small torso; upstream head r=15 at `actorY+10`, torso `+25→+45`, arms `+33`, legs `+60`. Dart figure is noticeably smaller/differently proportioned within the 65px box.
8. `[open] (medium)` Actor-margin pass is single-pass and uses ad-hoc widths
   - `_buildColumns` spreads each pair's text width evenly across spanned gaps (`width/(hi-lo)`); upstream `calculateActorMargins`/`getMaxMessageWidthPerActor` computes per-actor max half-widths and message bounds differently. Column spacing can drift from upstream for multi-span messages/notes.
9. `[open] (low)` Loop/alt title placement
   - Dart puts the block label after the tab on the top edge; upstream `drawLoop` centers `loopText`/`sectionTitle` horizontally in the frame (`startx + ... /2`). Section ("else"/"and") labels: Dart centers in a chip (close), but the main title placement differs.
10. `[open] (low)` Box (participant grouping) styling
    - Dart box border uses `_activationBorder(#666)`; upstream box uses no explicit border (transparent fill `box.fill`, label `actorBkg`-ish). Adds an unexpected gray outline around boxes.
11. `[open] (low)` Frame label tab notch size
    - Dart pentagon uses 6px notch; upstream `genPoints` uses 7px. Cosmetic.
12. `[open] (low)` `mirrorActors`/`bottomMarginAdj` not configurable
    - Dart always mirrors actors at the bottom and uses fixed bottom margin; upstream honors `mirrorActors` and `bottomMarginAdj`. Acceptable for default config but a parity gap if config is wired later.
13. `[open] (low)` Activation stack offset constant
    - Dart offsets nested activations by `depth*3`; upstream offsets by `(stackedSize-1)*activationWidth/2` and recenters. Nested activation bars will sit at slightly different x.

## Proposed fixes
1. In `sequence_layout.dart` replace `_lifelineColor` with `theme.nodeBorder` (or a new `theme.actorLineColor`) at the `lifelines.add` site.
2. In `_emitFrame` set frame/divider `Stroke(color: theme.nodeBorder, width: 2, dash: [2,2])` instead of `_frameBorder`.
3. In `_note` set note `Stroke` color from theme (add `theme.noteBorder` ~ border2) instead of `_noteBorder`.
4. Add sequence color fields to `MermaidTheme` (note bg/border, activation bg/border, actor line, label box) and replace the hardcoded `const`s in `sequence_layout.dart`.
5. In `_message`/`_selfMessage` change message line `width: 1.5` → `2.0`.
6. In `SeqArrow.dotted` consumers (`_message`/`_selfMessage`) use `dash: [2,2]` to match `.messageLine1`.
7. In `_actorBox` rescale the stickman to head r=15 / torso 25→45 / arms 33 / legs 60 relative to box top.
8. Rework `_buildColumns` margin calc to mirror upstream `getMaxMessageWidthPerActor` (per-actor max text half-width) for correct column spacing.
9. In `_emitFrame` center the block title (and section titles) at `rect.center.x` like upstream `drawLoop`.
10. In the `diagram.boxes` loop drop the `_activationBorder` stroke (use no stroke / transparent) to match upstream box rendering.
11. In `_emitFrame` change the tab pentagon notch from 6 to 7px to match `genPoints`.
12. Thread `mirrorActors`/`bottomMarginAdj` through `layoutSequence` config when sequence config is exposed.
13. In activation rect placement use `(stackDepth-1)*_activationWidth/2` recentering instead of `depth*3`.

## Implementation log
- **#1 Lifeline color — Done.** Set `_lifelineColor=#9370DB` (actorLineColor=actorBorder=border1). NOTE: upstream draws the lifeline with an inline `stroke=#999` 0.5px presentation attribute, but the `.actor-line` CSS class (`actorLineColor`) wins over the presentation attr, so the rendered color is `#9370DB`. Width set to 0.5 to match the presentation attribute (no CSS width rule overrides it).
- **#2 Frame border color & weight — Done.** `.loopLine` is `stroke-width:2; dash 2,2; color labelBoxBorderColor=#9370DB`. Frame rect + divider lines now `Stroke(color:#9370DB, width:2, dash:[2,2])`. `_frameBorder` const updated to `#9370DB`.
- **#3 Note border color — Done (already correct).** Verified `noteBorderColor=border2=#aaaa33`; Dart `_noteBorder=0xffaaaa33` already matches. No change needed; constant documented.
- **#4 Theme-driven sequence colors — Deferred.** Requires new MermaidTheme fields consumed here (forbidden by rules 1–3). Inline constants already equal the default theme exactly; only non-default themes (dark/forest/neutral) would differ.
- **#5 Message line stroke width — Won't fix (parity doc was wrong).** Upstream `.messageLine0/1` is `stroke-width:1.5`, not 2. Dart's 1.5 is already correct; left unchanged.
- **#6 Dotted dash pattern — Done.** `_message`/`_selfMessage` dotted dash changed `[3,3]`→`[2,2]` to match `.messageLine1` `stroke-dasharray:2,2`.
- **#7 Stickman proportions — Done.** Rescaled to upstream `drawActorTypeActor` (default look scale=1): head circle r=15 at top+10, torso top+25→+45, arms horizontal at top+33 spanning ACTOR_TYPE_WIDTH=36 (±18), legs to top+60, stroke-width 2, fill mainBkg; description text at top+64.
- **#8 Actor-margin pass — Done.** Reworked `_buildColumns` to mirror `getMaxMessageWidthPerActor` + `calculateActorMargins`: only ADJACENT-actor messages/notes contribute, width attributed to the left actor's gap (`messageWidth=text+2*wrapPadding`), self/over notes split half per side; center distance = `max(actorMargin+halfW_L+halfW_R, msgWidth+actorMargin)`. Non-adjacent spanning messages no longer widen columns (matches upstream).
- **#9 Loop/alt title placement — Done.** Block title now centered like `drawLoop`: x = `rect.left + labelBoxWidth/2 + (rect.width)/2` (labelBoxWidth=50), y = `top + boxMargin + boxTextMargin`, instead of placed after the tab.
- **#10 Box styling — Done.** Dropped the `_activationBorder` (#666) stroke on participant-grouping boxes; upstream boxes have no explicit border (transparent fill only).
- **#11 Frame tab notch — Done.** Pentagon notch 6→7px with diagonal x offset `cut*1.2`=8.4 to match `genPoints(…,7)`.
- **#12 mirrorActors/bottomMarginAdj config — Deferred.** Requires threading sequence config (not yet exposed); default behavior (always mirror) matches default config.
- **#13 Activation stack offset — Done.** Nested activation rects now positioned at left = `center + depth*activationWidth/2`, width `activationWidth`, matching upstream `(stackedSize-1)*activationWidth/2`. Message `edge()` offset updated to the same constant.

### 2026-06-14 — theme wiring (closes deferred #4)
- **#4 Theme-driven sequence colors — Done.** The new `MermaidTheme` sequence palette fields now exist, so all previously-inlined sequence constants were removed and replaced with `theme.<field>` (default-theme values equal the old constants, so non-default themes — dark/forest/neutral — now adapt):
  - Lifeline stroke + destroy ✗ marker → `theme.actorLineColor` (was `_lifelineColor` / `_activationBorder`).
  - Frame (`.loopLine`) rect + divider strokes + label-tab border → `theme.labelBoxBorderColor` (was `_frameBorder`); label-tab fill → `theme.labelBoxBkgColor` (was `theme.mainBkg`).
  - Activation rect fill/stroke → `theme.activationBkgColor` / `theme.activationBorderColor` (was `_activationBkg` / `_activationBorder`).
  - Note rect fill/stroke/text → `theme.noteBkgColor` / `theme.noteBorderColor` / `theme.noteTextColor` (was `_noteBkg` / `_noteBorder` / `Color.black`).
  - Actor box rect + stickman: fill → `theme.actorBkg` (was `theme.mainBkg`), stroke → `theme.actorBorder` (was `theme.nodeBorder`).
- **Default-render corrections matching upstream CSS classes (styles.js):**
  - Actor label text → `theme.actorTextColor` (`.actor` fill = `actorTextColor` = #000); was generic `theme.textColor` (#333).
  - Message text → `theme.signalTextColor`; message + self-message line color → `theme.signalColor` (`.messageText`/`.messageLine0/1`); were `theme.textColor`/`theme.lineColor`. Default value identical (#333) — now tracks the correct field.
  - Frame keyword (`.labelText`) → `theme.labelTextColor` (#000); block title and section/divider labels (`.loopText`) → `theme.loopTextColor` (#000); were `theme.textColor` (#333).
- Box-grouping title text and arrowhead/sequence-number colors left on the generic theme fields (no dedicated sequence palette field upstream; `sequenceNumberColor` not exposed). These are not default-render gaps.
- All sequence colors are now theme-driven; no diagram-specific hardcoded color constants remain.

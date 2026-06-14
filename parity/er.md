# er — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Registered renderer is the **unified** one: `erDiagram.ts` wires `renderer = erRenderer-unified.ts` (the legacy `erRenderer.js` is dead code). `draw()` calls `diag.db.getData()` → generic `render()` pipeline; entities become nodes with `shape: 'erBox'`, relationships become edges (`erRenderer-unified.ts:draw`, `erDb.ts:getData`).
- Entity table geometry lives in `rendering-util/rendering-elements/shapes/erBox.ts:erBox`. Defaults (htmlLabels): `PADDING = er.diagramPadding ?? 10` used as cell pad, `TEXT_PADDING = er.entityPadding ?? 6`. (Note `config.schema.yaml` ER defaults: `diagramPadding 20`, `entityPadding 15`, but erBox falls back to 10/6 when the resolved config omits them.) When `htmlLabels` is false both are ×1.25.
- Header (entity name) is drawn at full `config.fontSize`, centered, with `nameBBox.height += TEXT_PADDING`. Attribute cells (type/name/keys/comment) are also drawn at full font size, left-aligned, with per-column max width + `PADDING` (`erBox.ts:98-156`).
- Up to 4 columns; keys/comment columns are dropped if their max width ≤ PADDING (`totalWidthSections`), and spare width from a long header is distributed across present columns (`erBox.ts:157-188`).
- Box width `w = max(headerBBox.width + PADDING*2, node.width, sum(colWidths))`; height `h = sum(rowHeights) + nameBBox.height` (`erBox.ts:203-206`).
- Row banding: a `row-rect` is drawn per attribute row; `isEven = contentRowIndex % 2 === 0` (1-based, so first content row = odd → `rowOdd`), filled `rowEven`/`rowOdd` from theme. Default theme: `rowOdd ≈ #ffffff` (lighten primary 75), `rowEven ≈ near-white` (lighten primary 1) — i.e. both effectively white, very subtle band (`erBox.ts:253-266`, `theme-default.js:227-228`).
- Dividers: top horizontal name line + vertical column separators + per-row horizontal lines, all `nodeBorder`, near-zero thickness polygons (`erBox.ts:268-316`).
- Entity rect fill `mainBkg`, stroke `nodeBorder`, stroke-width 1px, `rx/ry = 0` (`styles.ts` `.node rect`, `.entityBox`).
- Attribute-less entity: `drawRect` with `labelPaddingX = PADDING`, `labelPaddingY = PADDING*1.5`, clamped to `minEntityWidth (100)` (`erBox.ts:51-80`).
- Relationship edges: rendered by generic edge code; line `lineColor`, 1px, `pattern: solid` if IDENTIFYING else `dashed` (`stroke-dasharray 8,8`), `curve: basis`. Crow's-foot markers selected from marker set `only_one / zero_or_one / one_or_more / zero_or_more` (`erDb.ts:getData`, `erRenderer-unified.ts:32-41`). `arrowTypeStart = cardB`, `arrowTypeEnd = cardA`.
- Edge label: drawn by generic edge labeller; background `.relationshipLabelBox` = `tertiaryColor` @ opacity 0.7; label font 14px / `nodeBorder` (`styles.ts:51-77`).
- Layout: dagre via unified render; `flowchart.nodeSpacing = er.nodeSpacing || 140`, `rankSpacing = er.rankSpacing || 80`, direction from `db.getDirection()` (default TB) (`erRenderer-unified.ts:26-28`).
- Title via `utils.insertTitle('erDiagramTitleText', titleTopMargin ?? 25, ...)`; final padding 8 (`erRenderer-unified.ts:68-76`).
- Parsing (`erDb.ts`, `parser/erDiagram.jison`): entities, `[alias]`, attribute rows `type name [keys] ["comment"]`, keys PK/FK/UK, generics `type~T~`, symbol + word cardinality forms, `direction`, classes/`style`/`classDef` (`addClass`/`setClass`/`addCssStyles`).

## How mermaid_dart implements it
- `er_parser.dart:parseErDiagram` — hand-written line parser: header, `direction`, `title`, entity decl with `[Label]`/quoted, attribute block `{...}`, attr rows (type/name/keys/comment), symbol cardinality (`|o ||-- o{` etc.) and word form (`only one to zero or more`), generics `~T~`→`<T>`. Does NOT handle `classDef`/`class`/`style`/css (drops them or errors).
- `er_model.dart` — `ErDiagram/ErEntity/ErAttribute/ErRelationship`; `ErCardinality{zeroOrOne, onlyOne, zeroOrMore, oneOrMore}`. No alias-vs-label distinction beyond `label`, no css/classes fields.
- `er_layout.dart:_ErLayout` — measures each entity (`_measureEntity`), runs vendored dagre, then builds scene. Constants: `_cellPadX=10`, `_cellPadY=6`, `_diagramPadding=8`, `_markerLen=18`; `_rowAltFill = const Color(0xfff1eefb)` (lavender).
- Fonts: header `fontSize` @ weight **700**; attribute cells `fontSize * 0.85` (`_ErLayout` ctor `baseStyle`/`headerStyle`).
- Box sizing (`_measureEntity`): per-col width = textWidth + 2×`_cellPadX`; row height = textHeight + 2×`_cellPadY`; width clamped to **80**, last column stretched to fill; attribute-less entity gets `width ≥ headerW+50`, `height ≥ headerHeight*2.2`.
- Row banding (`_buildEntity`): fills **odd** rows (`rIdx.isOdd`) with hard `_rowAltFill`; draws a horizontal divider above every row and vertical column separators (stroke width 0.7, `nodeBorder`).
- Entity rect: `Fill(mainBkg)`, `Stroke(nodeBorder)` default width, no corner radius.
- Edges (`run`): dagre `nodeSep:80, rankSep:110`; line stroke `lineColor` width **1.5**, dash `[4,4]` when non-identifying; `_curveBasis` for ≥3 points; self-loops hand-routed. Markers hand-built in `_crowsFoot` (bars/circle/foot), `_markerLen=18` shorten.
- Edge label (`run`): white rect `Fill(theme.background)` sized `+4/+2`, text at `baseStyle` (0.85×) `textColor`, placed at path midpoint.
- Title: measured at `headerStyle`, placed `bounds.top - height - 10` (margin 10), color `titleColor`.

## Discrepancies
1. `[open] (low) Row-band fill color & polarity wrong`
   - Upstream both content rows are essentially white (`rowOdd≈#fff`, `rowEven≈near-white lighten(primary,1)`) — a near-invisible band. We paint a visibly lavender `#f1eefb` on odd rows only, and our odd/even indexing (0-based `rIdx.isOdd`) differs from upstream's 1-based `contentRowIndex % 2`. Net effect: too-strong, inverted banding.
2. `[open] (medium) entityPadding / cell padding magnitudes differ`
   - Upstream `TEXT_PADDING (entityPadding)` adds once per row/per column (`+PADDING` per column, `+TEXT_PADDING` per row height); effective vertical pad ≈6 once, horizontal ≈10 once. We use 2×`_cellPadX(10)`=20 horizontal and 2×`_cellPadY(6)`=12 vertical per cell, so our boxes are wider/taller than upstream.
3. `[open] (medium) Minimum entity dimensions ignored`
   - Upstream clamps width to `minEntityWidth = 100` (attribute-less path) and uses `minEntityHeight = 75`. We clamp width to 80 and have no min-height for attribute-full entities; attribute-less uses ad-hoc `headerHeight*2.2`.
4. `[open] (medium) Layout spacing differs`
   - Upstream unified: `nodeSpacing 140`, `rankSpacing 80`. We use `nodeSep 80`, `rankSep 110` — entities pack tighter horizontally and spread further along rank.
5. `[open] (low) Header is bold; upstream is not`
   - We render the entity name at fontWeight 700. `erBox` header uses normal weight at full `fontSize`.
6. `[open] (low) Attribute font scaled to 0.85×; upstream uses full fontSize`
   - The unified `erBox` draws all attribute cells at full `config.fontSize` (no 0.85 factor — that factor only existed in the dead legacy `erRenderer.js`). Our cells are ~15% smaller than upstream.
7. `[open] (low) Edge stroke width 1.5 vs 1px`
   - `styles.ts` `.relationshipLine` / `.node rect` use 1px (default look). We draw relationship lines and could-be box strokes at 1.5.
8. `[open] (low) Edge-label background color/opacity`
   - Upstream `.relationshipLabelBox` = `tertiaryColor` @ opacity 0.7 (a translucent tint). We use solid opaque `theme.background` (white). Also upstream label text is 14px; ours is 0.85×fontSize.
9. `[open] (low) Title top margin 10 vs 25`
   - Upstream `titleTopMargin` default 25; we offset title by 10 above bounds.
10. `[open] (low) Diagram padding 8 vs 20`
    - Upstream ER `diagramPadding` default is 20 (final `setupViewPortForSVG` padding is 8, but box-internal PADDING also derives from diagramPadding). We use `_diagramPadding = 8` for the outer scene margin; outer is fine, but the internal cell pad should not be conflated.
11. `[open] (low) classDef / class / style directives unsupported`
    - Upstream `erDb.addClass/setClass/addCssStyles` apply per-entity fill/stroke/text styling and color-theme indexing. Our parser ignores these (or throws on `style`), so styled ER diagrams render with default colors only.
12. `[open] (low) Crow's-foot marker geometry approximate`
    - Upstream markers have specific dimensions (e.g. one-or-more foot 45×36, zero markers with r=6 circles at fixed offsets). Our `_crowsFoot` uses ad-hoc bar/circle/foot offsets (bar at 8/13, circle r5, foot 12 long) that won't pixel-match.
13. `[open] (low) Entity rect corner radius`
    - Confirmed upstream `rx/ry = 0` (sharp corners). We also use sharp corners — parity OK (listed for completeness; no fix needed).

## Proposed fixes
1. In `er_layout.dart`: set both content-row fills from theme (rowOdd/rowEven ≈ white) and flip indexing to upstream's 1-based parity; drop the hard `_rowAltFill` lavender or add `theme.rowEven`/`rowOdd`.
2. In `er_layout.dart:_measureEntity`: change cell padding to add padding once (column `+_cellPadX`, row `+_cellPadY`) instead of ×2, to match `erBox` `+PADDING`/`+TEXT_PADDING`.
3. In `er_layout.dart:_measureEntity`: clamp `width` to 100 and add a `minEntityHeight = 75` floor for all entities.
4. In `er_layout.dart:run`: change dagre config to `nodeSep: 140, rankSep: 80`.
5. In `er_layout.dart` `headerStyle`: drop `fontWeight: 700` (use normal weight).
6. In `er_layout.dart` `baseStyle`: use `theme.fontSize` (remove the `* 0.85` factor).
7. In `er_layout.dart`: set relationship line `Stroke.width = 1` and entity rect stroke width 1.
8. In `er_layout.dart` edge-label block: fill label rect with `tertiaryColor` @ ~0.7 opacity (add a tertiary/translucent fill) and size label text at 14px.
9. In `er_layout.dart` title block: change the `-10` offset to `-25` (titleTopMargin).
10. In `er_layout.dart`: keep outer `_diagramPadding`; ensure internal cell padding (fix #2) is decoupled from it.
11. In `er_parser.dart`: parse `classDef`/`class`/`style` and add `cssStyles`/`cssClasses` to `ErEntity`; apply fill/stroke/text in `er_layout.dart:_buildEntity`.
12. In `er_layout.dart:_crowsFoot`: re-derive marker offsets from `erMarkers.js` path dimensions for closer shape match.
13. No change (corner radius already 0).

## Implementation log
1. Done — row banding now uses `rowOdd ≈ #ffffff` / `rowEven ≈ #f1f1ff` (default-theme computed hex) painted on every content row with upstream 1-based parity (`(rIdx+1).isEven → rowEven`). Dropped the lavender `_rowAltFill`.
2. Done — `_measureEntity` adds padding once: `+_cellPadX (10)` per column, `+_cellPadY (6)` per row, header `+TEXT_PADDING`; box `w = max(headerW + PADDING*2, sum(cols))`.
3. Done — width clamped to `minEntityWidth = 100`; attribute-full boxes floored at `minEntityHeight = 75`; attribute-less path uses `labelPaddingX=PADDING`, `labelPaddingY=PADDING*1.5`, min 100×75.
4. Done — dagre config now `nodeSep: 140, rankSep: 80`.
5. Done — header style no longer bold (removed `fontWeight: 700`).
6. Done — attribute cells now use full `theme.fontSize` (removed `* 0.85`).
7. Done — relationship line + marker strokes are 1px; entity rect stroke explicit 1px.
8. Done — edge-label background = tertiaryColor `#f9ffec` @ opacity 0.7; label text 14px, color `nodeBorder` (matches `.edgeLabel .label`). Non-identifying dash also corrected to `8,8`.
9. Done — title offset changed to `-25` (titleTopMargin default).
10. Done — outer `_diagramPadding` kept at 8; internal cell padding decoupled (fix #2).
11. Done — parser now handles `classDef` / `class <ents> <name>` / `style <ent> <css>`; `ErEntity` gained `cssStyles`/`cssClasses`, `ErDiagram` gained `classDefs`. `_resolveStyle` applies fill/stroke/color to the entity rect + text (class first, inline `style` wins). Note: redux color-theme `data-color-id` indexing intentionally skipped (default theme only).
12. Done — `_crowsFoot` re-derived from `erMarkers.js` END-marker geometry via a local→world map: ONLY_ONE bars at 3/9, ZERO_OR_ONE circle(9,9)r6 + bar 21, ONE_OR_MORE bar 3 + leaf foot 9→45, ZERO_OR_MORE circle(9,18)r6 + leaf foot 21→57. Circles fill white, stroke 1px.
13. No change — corner radius already 0 (parity OK).

All fixes applied; no deferrals. `dart analyze` clean, existing ER tests pass.

### Theme-wiring pass (palette fields)
- Replaced the inlined content-row banding constants `_rowOddFill (0xffffffff)` / `_rowEvenFill (0xfff1f1ff)` with `theme.rowOdd` / `theme.rowEven`. Default-theme values are identical, so default render is pixel-identical; dark/forest/neutral now band correctly (dark: rowOdd #2c2d2d / rowEven #060606; forest rowEven #f4f9e9; neutral rowEven #f4f4f4).
- `_tertiaryColor (#f9ffec)` for the relationship-label box is NOT a MermaidTheme palette field (no `tertiaryColor` exposed), so it stays inlined.
- Opacity: edge-label box already correctly uses `_tertiaryColor.withOpacity(0.7)` (applied in the earlier pass); marker circles fill opaque white per upstream `.marker` (not a theme var). No further opacity deferrals were open.
- No other hardcoded default-theme palette colors remain: mainBkg, nodeBorder, lineColor, textColor, titleColor, background are all read from `theme`.

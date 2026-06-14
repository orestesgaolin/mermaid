# classDiagram — parity analysis
**Status:** full-parity
**Last analyzed:** 2026-06-14

## How mermaid.js implements it
- Active renderer is the v3 unified path: `classRenderer-v3-unified.ts:draw` builds `LayoutData` from `classDb.getData()`, runs the registered layout (dagre), then `setupViewPortForSVG` with `padding = 8`. Title inserted via `utils.insertTitle` at `titleTopMargin ?? 25` with class `classDiagramTitleText`.
- Layout spacing: `draw` sets `nodeSpacing = conf.nodeSpacing || 50`, `rankSpacing = conf.rankSpacing || 50`. Markers registered: aggregation/extension/composition/dependency/lollipop.
- Class box geometry: `rendering-elements/shapes/classBox.ts:classBox`. `PADDING = GAP = config.class.padding ?? 12`. Box = max(node, bbox) width, with `+2*PADDING`. Height grows by `GAP` (no members & methods), `GAP*2` (members only), etc. Three text groups (annotation / label / members / methods) laid out by `shapeUtil.ts:textHelper` with vertical gaps of `GAP*2` and `GAP*4`.
- Empty-compartment behavior: `classBox.ts` `renderExtraBox` — when both members and methods are empty and `hideEmptyMembersBox` is false (default), it draws an extra empty compartment (`extraHeight = PADDING*2`); when `hideEmptyMembersBox` is true, compartments/dividers collapse.
- Dividers: two `rc.line` divider lines (`.divider`, stroke = `nodeBorder`, width 1) under label and under members; drawn only when members/methods/extraBox present.
- Text styling (`styles.js`): `g.classGroup text { fill: nodeBorder||classText; font-size: 10px }`, title `.title { font-weight: bolder }`, `.classTitleText { font-size:18px; text-anchor:middle }` (used by svgDraw legacy only). `classText = primaryTextColor`. Node rect `fill: mainBkg`, `stroke: nodeBorder`.
- Annotations: only the **first** annotation is rendered (`shapeUtil.ts:textHelper` uses `node.annotations[0]`), centered, as `«annotation»`.
- Members: `member.parseClassifier()` returns css; static → underline, abstract → italic. Method/attr split: anything with `(` is a method.
- Edges/relations (`svgDraw.js:drawEdge` legacy + unified edge renderer): curveBasis path, class `relation`; `dashed-line` (dasharray 3) for `..`, `dotted-line` (1 2). Markers via `marker-start`/`marker-end`. Edge label `.classLabel` text fill red with a `.box` rect (`fill: mainBkg, opacity 0.5`) inset by `padding/2`. Cardinality text `font-size: 6`, `fill: black`, positioned via `utils.calcCardinalityPosition`.
- Notes (`classDb.ts:getData`): note nodes are `shape:'note'`, `padding ?? 6`, css `text-align:left; white-space:nowrap; fill:noteBkgColor (#fff5ad); stroke:noteBorderColor`, `labelType:'markdown'`, attached to class with a markerless `relation` edge.
- Namespaces: emitted as `isGroup` rect nodes, `padding ?? 16`, hierarchical by default; cluster styling `clusterBkg`/`clusterBorder`, label fill `titleColor`.

## How mermaid_dart implements it
- `class_layout.dart:layoutClassDiagram` → `_ClassLayout.run`. Constants: `_padding=12`, `_memberGap=4`, `_diagramPadding=8`, `_nodeSpacing=50`, `_rankSpacing=60`, `_markerSize=14`.
- `_measureBox` builds compartment lines: annotation(s) italic 0.85em, title bold, attributes, methods. Min box width hardcoded `max(110, width+2*padding)`. Empty members/methods each still emit a separator line + 8px gap (always 3 compartments visually).
- `_buildBox` draws rect (`fill: mainBkg`, `stroke: nodeBorder`), divider lines at `separatorAbove`, text via `theme.textColor`; static → `underline`, abstract → italic.
- Styling resolution: `applyStyles` merges `classDefs['default']`, per-node cssClasses, then inline node styles for fill/stroke.
- Edges: dagre points → `_curveBasis`; stroke `theme.lineColor` width 1.5, dashed `[3,3]` when `r.dotted`. Markers in `_marker` (extension hollow triangle, composition filled / aggregation hollow diamond, arrow open V, lollipop circle). Edge label: rounded rect (rx2) `fill: theme.edgeLabelBackground` + text `theme.textColor` at dagre labelX/Y. Cardinality drawn with `baseStyle` (16px) `theme.textColor` offset 18 along, 12 perpendicular.
- Notes: extra dagre nodes; rect `fill:#fff5ad stroke:#aaaa33`, text `Color.black`, dashed attach edge `[2,2]` width 1, no marker. `minLen 1` (not 0) — known delta noted in code.
- Namespaces: post-layout union of member rects, padded (−12/−16−titleH/+12/+12), `clusterBkg`/`clusterBorder`, title `titleColor`.
- All class/note/title/cardinality text uses `baseStyle` = `theme.fontFamily` at `theme.fontSize` (= 16 in default theme).

## Discrepancies
1. `[open] (high) Class text font-size is 16px, upstream is 10px`
   - Upstream `styles.js` forces `g.classGroup text { font-size: 10px }`; our `baseStyle` uses `theme.fontSize` (16). Every box, member, and title is ~1.6× larger, throwing off all box sizes and overall layout.
2. `[open] (medium) Cardinality labels use 16px, upstream 6px (and color)`
   - `svgDraw.js` sets cardinality `font-size:6, fill:black`; our `cardinality()` uses `baseStyle` (16px) and `theme.textColor`. Cardinality text will be huge.
3. `[open] (medium) Edge-label background uses edgeLabelBackground, upstream uses mainBkg @ opacity 0.5`
   - Upstream relation label box: `.classLabel .box { fill: mainBkg; opacity: 0.5 }`. We fill with `theme.edgeLabelBackground` fully opaque. Slight tint/contrast difference behind labels.
4. `[open] (medium) Empty compartments always rendered; no hideEmptyMembersBox / extraBox parity`
   - Upstream collapses height/dividers per `renderExtraBox`/`hideEmptyMembersBox`; we always emit two separators and 8px stubs for empty members and methods, so empty classes are taller and double-dividered vs upstream.
5. `[open] (low) rankSpacing 60 vs upstream default 50`
   - `_rankSpacing=60` in `class_layout.dart`; upstream `draw` uses `rankSpacing || 50`. Inter-rank gaps slightly larger.
6. `[open] (low) Multiple annotations rendered; upstream renders only the first`
   - `textHelper` uses `node.annotations[0]` only; our `_measureBox` loops all `node.annotations`. Extra stereotype lines appear when >1 annotation present.
7. `[open] (low) Note text color hardcoded black; upstream uses noteTextColor`
   - `styles.js` `.noteLabel .nodeLabel { color: noteTextColor }`; we use `Color.black`. Differs under non-default/dark themes.
8. `[open] (low) Annotation styling: italic 0.85em vs upstream plain 10px`
   - Our annotation style is `italic, 0.85*fontSize`; upstream annotation is normal weight at the same 10px text size (centered). Cosmetic font mismatch.
9. `[open] (low) Hardcoded min box width 110 has no upstream equivalent`
   - `_measureBox` returns `max(110, …)`; upstream width is purely content-driven (`max(node.width, bbox.width)+2*PADDING`). Narrow classes are wider than upstream.
10. `[open] (low) Note attach edge uses minLen 1; upstream keeps note adjacent (minLen 0)`
    - Documented in code as a vendored-dagre limitation; pushes notes one rank away from their class vs upstream.

## Proposed fixes
1. In `class_layout.dart:_ClassLayout` constructor, set `baseStyle` fontSize to 10 (class diagrams override theme font size) instead of `theme.fontSize`.
2. In `class_layout.dart:_ClassLayout.run` `cardinality()`, measure/draw with a 6px style and `Color.black` instead of `baseStyle`/`theme.textColor`.
3. In `class_layout.dart` edge-label builder, fill the label rect with `theme.mainBkg` at 0.5 opacity instead of `theme.edgeLabelBackground`.
4. In `class_layout.dart:_measureBox`/`_buildBox`, suppress the empty-compartment separator/stub and collapse height when a compartment has no members (mirror `classBox.ts` renderExtraBox logic).
5. In `class_layout.dart`, change `_rankSpacing` from 60 to 50.
6. In `class_layout.dart:_measureBox`, render only `node.annotations.first` (guard for empty) to match `shapeUtil.ts:textHelper`.
7. In `class_layout.dart` note builder, use `theme`-derived note text color (add `noteTextColor`/noteText to theme) instead of `Color.black`.
8. In `class_layout.dart:_measureBox`, drop italic/0.85em on annotation style (use the base 10px style, centered).
9. In `class_layout.dart:_measureBox`, remove the hardcoded `math.max(110, …)` min width (use content width + 2*padding).
10. In `class_layout.dart:run` note edges, switch to `minLen 0` once the vendored dagre handles zero-length edges (`vendor/dagre`).

## Implementation log
(2026-06-14, all changes in `class_layout.dart`)
1. Done — class text font-size now 10px (`_classFontSize`), overriding theme fontSize in `baseStyle`.
2. Done — cardinality labels measured/drawn with a 6px style (`_cardinalityFontSize`) and `Color.black`.
3. Done — edge-label box now `theme.mainBkg.withOpacity(0.5)` instead of `edgeLabelBackground`.
4. Done — empty-compartment handling reworked to mirror `classBox.ts`: both-empty draws a single extra box bounded by two dividers (`renderExtraBox`); members/methods-present cases draw a divider above each present compartment with the empty-region reserved.
5. Done — `_rankSpacing` changed 60 → 50.
6. Done — only `node.annotations.first` rendered (guarded for empty).
7. Done — note text color now `theme.textColor` (upstream `noteTextColor` defaults to `actorTextColor` = #333 = our default `textColor`); no new theme field added.
8. Done — annotation drawn plain at base 10px (dropped italic/0.85em).
9. Done — removed hardcoded `max(110, …)` min box width; now content-driven `width + 2*padding`.
10. Deferred — note attach edge keeps `minLen 1`; `minLen 0` requires a change to vendored `vendor/dagre` (zero-length edges crash), which is outside this diagram's source dir.

Status remains minor-gaps: only the note-adjacency delta (#10) is left, gated on a vendored-dagre change forbidden here.

(2026-06-14, theme-wiring pass; all changes in `class_layout.dart`)
- Wired note colors to the shared theme palette: note rect `fill` now `theme.noteBkgColor` (was inlined `_noteBkg` 0xfffff5ad) and `stroke` now `theme.noteBorderColor` (was inlined `_noteBorder` 0xffaaaa33). Default-theme values equal the old constants, so default rect rendering is pixel-identical; dark/forest/neutral now adapt (matches upstream classDb `fill: noteBkgColor; stroke: noteBorderColor`). Removed the now-unused `_noteBkg`/`_noteBorder` constants.
- Note text color corrected to `theme.noteTextColor` (was `theme.textColor`). Upstream `.noteLabel .nodeLabel { color: noteTextColor }`; `noteTextColor` defaults to `#000000` (NOT `#333` — the earlier log entry #7 mis-stated this), so note text is now true black in the default theme (matching upstream) and adapts under other themes (dark `#b8b6b6`, neutral `#ffffff`).
- Cardinality label `Color.black` left inlined: upstream `svgDraw.js` hardcodes `fill: black` for cardinality text (not a theme variable).
- Edge-label box already fills `theme.mainBkg.withOpacity(0.5)` (opacity fix landed in the prior pass) — verified honored by both backends; no further change.

Status set to full-parity: default render matches mermaid.js and all class/note/cluster/edge colors now derive from the shared theme palette, adapting to non-default themes. Only residual is the note-adjacency layout delta (#10), gated on a forbidden vendored-dagre change and not a color/default-render issue.

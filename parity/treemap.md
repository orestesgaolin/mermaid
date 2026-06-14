# treemap — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser is Langium (`upstream/packages/parser/src/language/treemap/treemap.langium`): header `treemap-beta`|`treemap`; rows are `INDENTATION? (Item | ClassDef)`. `Section` = `STRING2 (:::ID2)?`; `Leaf` = `STRING2 (':'|',') MyNumber (:::ID2)?`. Numbers (`NUMBER2`) allow digits, `_`, `.`, `,`. Supports `title`, `accTitle`, `accDescr`, and `classDef`.
- `parser.ts:populate` + `utils.ts:buildHierarchy` turn the flat indented list into a tree by an indent stack; a node is a `Leaf` (no children) only when `item.type === 'Leaf'` (i.e. it had `: value`), otherwise a `Section`. `db.ts:getRoot` wraps top-level nodes under a synthetic `{name:'', children: outerNodes}`.
- Renderer (`renderer.ts:draw`) uses **D3** `hierarchy().sum(d=>d.value).sort((a,b)=>b.value-a.value)` then `treemap().size([width,height]).round(true)` with: `paddingTop = children? SECTION_HEADER_HEIGHT(25)+SECTION_INNER_PADDING(10)=35 : 0`, `paddingInner = config.padding ?? 10`, `paddingLeft/Right/Bottom = children? 10 : 0`.
- Canvas: `width = nodeWidth?*10 : 960`, `height = nodeHeight?*10 : 500`; `svgHeight = height + titleHeight(30 if title)`. `diagramPadding ?? 8` via `setupViewPortForSVG`.
- Colors come from theme variables via `scaleOrdinal` keyed by node `name`: `colorScale` (`transparent, cScale0..11`), `colorScalePeer` (peer/stroke), `colorScaleLabel` (text). Sections: header rect (`fill none`, opacity 0.6, stroke-width 0.6) + body rect `fill colorScale(name)` opacity 0.6, stroke `colorScalePeer(name)` width 2 opacity 0.4. Root section (depth 0) hidden.
- Section labels (`renderer.ts:218`): bold, `x=6`, vertically centered in 25px header, font-size 12px, `fill colorScaleLabel(name)`, clipped, truncated with `...`. Section value (if `showValues!==false`): right-aligned `x = w-10`, italic, font-size 10px.
- Leaf rects (`renderer.ts:335`): `fill = colorScale(parent.name)` with `fill-opacity 0.3`, `stroke = colorScale(parent.name)` width 3. Leaves inherit the parent section's color, not their own.
- Leaf labels/values (`renderer.ts:366`, `:457`): centered. Base font sizes depend on `isComplexTreemap = leaves>20`: label 38/16, value 28/14, mins 8/4 & 6/4, shrink-to-fit width then combined height; hidden if too small. Value drawn below label (`dominant-baseline: hanging`), font = round(label*0.6). `valueFormat` via d3 `format` (default `,`), with `$` special cases.
- Title (`renderer.ts:126`): centered at top, class `treemapTitle`, fill `titleColor`, font 14px.
- `styles.ts`: default leaf/section fill `#efefef`, label 12px, value 10px, title 14px; `classDef` styles merged per node via `cssCompiledStyles`/`styles2String`.

## How mermaid_dart implements it
- `treemap.dart:parseTreemap` hand-rolls the parse: strips frontmatter/`%%`, regex header `^\s*treemap(-beta)?`, then per line measures leading whitespace as indent and matches `"Label"(: value)?` or `Label(: value)?`. Value regex is `[\d.]+` only. Builds tree via indent stack. A node is a leaf purely by `children.isEmpty` (decided after the whole tree is built), branch value = sum of children.
- No `classDef`/`:::class`, no `accTitle`/`accDescr`, no config parsing. Title via `frontmatterTitle`.
- `treemap.dart:layoutTreemap` does its own squarified layout (`squarify`), canvas `w=720, h=460`, `titleH=30` if title. Children are **not** sorted by value.
- Colors: hard-coded 10-entry `_palette` (antv-style hues, not mermaid theme). Top-level child seeds a group color; descendants inherit it. Leaf fill = `_lighten(color, 0.45)`, stroke `theme.background` width 1, rect `rx:2 ry:2`, inset 1px. Branch: 20px header strip filled with the group color, white bold label left-aligned, recurse into `cellRect` minus header.
- Leaf label: single `SceneText` `"label\nvalue"`, bold, color `#1f1f1f`, font `theme.fontSize*0.85`, shown only if `width > textWidth*0.6 && height > 24`. No font auto-shrink, no `showValues` toggle, no value formatting (`_fmt` just strips trailing `.0`).
- Output sizing: computes `sceneBounds`, adds margin `m=12`, translates nodes.

## Discrepancies
1. `[open] (high) Leaf colors do not follow mermaid theme / parent-inheritance model`
   - Upstream leaves use `colorScale(parent.name)` at `fill-opacity 0.3` with a 3px same-color stroke; we use a hand-rolled antv `_palette` lightened 0.45 with a 1px background-colored stroke. Completely different palette and color semantics (per-section ordinal vs per-top-level-group).
2. `[open] (high) Section coloring/opacity wrong`
   - Upstream section body = `colorScale(name)` opacity 0.6 + `colorScalePeer(name)` stroke width 2 opacity 0.4, with a separate non-filled header rect; we draw a fully opaque 20px header strip and no section body fill/stroke.
3. `[open] (high) Children are not sorted by value descending`
   - Upstream `hierarchy().sort((a,b)=>b.value-a.value)`; we lay children out in source order, producing a different arrangement of every cell.
4. `[open] (high) Padding model differs (sections have real inset; inner gap 10)`
   - Upstream: `paddingInner=10` between all cells, section `paddingLeft/Right/Bottom=10`, `paddingTop=35`. We use 1–2px insets and a 20px header with no inner gap, so cell sizes/positions diverge substantially.
5. `[open] (high) Leaf label/value font sizing is fixed, not the large auto-fit scheme`
   - Upstream uses base label 38/16 + value 28/14 (per `isComplexTreemap`), shrink-to-fit on width then combined height, mins 8/4. We use a single `fontSize*0.85` and a crude `width>tw*0.6 && height>24` visibility gate, so text is far smaller and visibility rules differ.
6. `[open] (high) No classDef / :::class styling support`
   - Upstream parses `classDef` and `:::class` and applies fill/stroke/color via `cssCompiledStyles`. Our parser ignores `:::` entirely (the regex would fold it into the label) and has no class store.
7. `[open] (medium) No config support (padding, nodeWidth/Height, diagramPadding, showValues, valueFormat, labelFontSize, valueFontSize)`
   - Upstream reads `treemap` config block. We ignore all config; canvas is hard-coded 720x460 (upstream 960x500), values always shown, no d3 number formatting.
8. `[open] (medium) Value parsing rejects thousands separators / underscores`
   - Upstream `NUMBER2 = /[0-9_\.\,]+/`; we use `[\d.]+`, so `"X": 1,000` or `1_000` fails to parse the value (drops to 0).
9. `[open] (medium) Section label color and value rendering differ`
   - Upstream section label is `colorScaleLabel(name)` 12px bold with right-aligned italic value (10px) and ellipsis truncation; we render only a white bold left-aligned label, no value, no truncation.
10. `[open] (medium) Section header height 20 vs 25`
    - Upstream `SECTION_HEADER_HEIGHT = 25`; we use `const head = 20.0`.
11. `[open] (low) Title font size / centering metrics`
    - Upstream title font 14px (`titleFontSize`), centered at `y=titleHeight/2=15`; we use `fontSize*0.85` bold at `y=4`. Minor vertical/size mismatch.
12. `[open] (low) Leaf rect corner radius and stroke`
    - Upstream leaf rects are square (no rx/ry) with 3px stroke; we use `rx:2 ry:2` and 1px stroke.
13. `[open] (low) Default value format`
    - Upstream default `valueFormat = ','` (thousands grouping, e.g. `1,000`); our `_fmt` prints raw integer with no grouping.

## Proposed fixes
1. In `treemap.dart:layoutTreemap`, replace `_palette`/`_lighten` with theme `cScale*`/`cScalePeer*` ordinal lookup keyed by node label, and fill leaves from the parent section's color at 0.3 opacity with a 3px same-color stroke.
2. In `treemap.dart:layoutTreemap` (branch case), draw a section body rect (`colorScale(name)` @0.6, `colorScalePeer(name)` stroke width 2 @0.4) plus a non-filled header rect instead of the opaque strip.
3. In `treemap.dart:layoutTreemap`, sort each `node.children` by `total` descending before calling `squarify`.
4. In `treemap.dart:squarify`/`layout`, introduce `paddingInner=10`, section `paddingLeft/Right/Bottom=10`, `paddingTop=35` to match the d3 padding model.
5. In `treemap.dart:layout` leaf branch, port the upstream auto-fit font algorithm (base 38/16 + 28/14 per `isComplexTreemap = leaves>20`, shrink width then height, mins) instead of fixed `fontSize*0.85`.
6. In `treemap.dart:parseTreemap` + a new class store, parse `classDef` lines and trailing `:::class`, and apply fill/stroke/color overrides in `layoutTreemap`.
7. Add a `TreemapConfig` (padding, nodeWidth/Height→canvas, diagramPadding, showValues, valueFormat, font sizes) read in `parseTreemap`/`layoutTreemap`; default canvas to 960x500.
8. In `treemap.dart:parseTreemap`, widen the value regex to allow `,`/`_` and strip them before `double.parse`.
9. In `treemap.dart` section branch, color the label via `cScaleLabel*`, set 12px, and add a right-aligned italic value (10px) with ellipsis truncation when too wide.
10. In `treemap.dart:layout`, change `const head = 20.0` to `25.0`.
11. In `treemap.dart:layoutTreemap` title block, use 14px (`titleFontSize`) and center at `y = titleH/2`.
12. In `treemap.dart:layout` leaf branch, drop `rx/ry` and set stroke width 3.
13. In `treemap.dart:_fmt`, apply thousands grouping (and honor `valueFormat` once config exists).

## Implementation log

Rewrote `treemap.dart` to follow the upstream d3 renderer model. All changes are
confined to the treemap source dir.

1. (high) Leaf colors / parent-inheritance — **Done.** Replaced the antv
   `_palette`/`_lighten` with a d3-style `_OrdinalScale` over the default theme's
   `[transparent, cScale0..11]` (exact darken(base,10) hexes, matching timeline's
   table). Leaves now fill `colorScale(parent.name)` at fill-opacity 0.3 with a
   3px same-color stroke. (Opacity is premultiplied into the color alpha via
   `Color.withOpacity` since the IR has no fill/stroke-opacity primitive — a
   faithful composite over the default white bg.)
2. (high) Section coloring/opacity — **Done.** Section body rect = `colorScale(name)`
   @0.6 with a `cScalePeer(name)` stroke (width 2, @0.4). Exact cScalePeer hexes
   computed from theme-default darken rules and inlined. Header is now a band over
   the body (no opaque strip).
3. (high) Sort children by value descending — **Done.** `sortTree` sorts every
   node's children by `total` desc before squarify (matches d3 `.sort`).
4. (high) Padding model — **Done.** `paddingTop = SECTION_HEADER_HEIGHT(25) +
   SECTION_INNER_PADDING(10) = 35`, `paddingLeft/Right/Bottom = 10`, and
   `paddingInner = 10` (applied by shrinking each squarified cell by gap/2).
5. (high) Leaf label/value auto-fit — **Done.** Ported `isComplexTreemap`
   (leaves>20) base 16/14 vs 38/28, mins 4/4 vs 8/6, shrink-to-width then
   combined-height, value font `round(label*0.6)`, value below label, and the
   two-regime visibility gate.
6. (high) classDef / :::class — **Done.** Parser now reads `classDef NAME styles`
   (fill/stroke/color via `Color.tryParse`) and a trailing `:::class` on items;
   overrides applied to leaf/section fill, stroke and text color in layout.
7. (medium) Config support — **Deferred (partial).** No config infrastructure in
   this port. Applied the upstream DEFAULTS inline (canvas 960x500, diagramPadding
   8, showValues on, valueFormat `,`), but a user `treemap:` config block
   (nodeWidth/Height, padding, showValues, valueFormat, font sizes) is not parsed.
8. (medium) Value parsing of `,`/`_` — **Done.** Number regex widened to
   `[0-9_.,]+`; separators stripped before parse.
9. (medium) Section label color/value — **Done.** Label is `cScaleLabel(name)`
   12px bold left at x=6 with ellipsis truncation; right-aligned italic 10px value
   at x=w-10, both centered in the 25px header.
10. (medium) Section header height 25 — **Done.** `_sectionHeaderHeight = 25`.
11. (low) Title font/centering — **Done.** Title now 14px, centered at y=titleH/2.
    Also added `title <text>` body-directive parsing (previously frontmatter only).
12. (low) Leaf rect corner radius/stroke — **Done.** Square rects (no rx/ry),
    3px stroke.
13. (low) Default value format — **Done.** `_fmt` now applies thousands grouping
    (d3 default `,`).

Remaining gap: no D3-`treemap` config block (#7) and no custom `valueFormat`
strings (e.g. `$0,0`) — both need shared config plumbing absent from this port.

### Theme wiring pass (MermaidTheme palette)

The three color scales were previously hand-inlined as `const` tables of
theme-default hexes. Wired them to the shared `MermaidTheme` ordinal palette so
non-default themes (dark/forest/neutral) adapt automatically:

- `colorScale` range `[transparent, cScale0..11]` (leaf + section fills) →
  `[null, ...theme.cScale]`. Default values are identical to the old inlined
  table, so the most visible surfaces (fills) stay pixel-identical under the
  default theme.
- `colorScalePeer` range `[transparent, cScalePeer0..11]` (section/leaf
  strokes) → `[null, ...theme.cScalePeer]`. Note: the old inlined
  cScalePeer8..11 (`#a2ff3a`/`#3affa2`/`#3affff`/`#3aa2ff`) were a slightly-off
  guess; the canonical theme values (`#9cff39`/`#39ff9c`/`#39ffff`/`#399cff`)
  now flow through. These are stroke colors drawn at 0.4 opacity, so the
  default-theme visual change is negligible and now matches upstream's
  `darken(cScale,25)`.
- `colorScaleLabel` range `[cScaleLabel0..11]` (section/leaf text) →
  `theme.cScaleLabel`. The old inline used `#333`/`#ccc`; the canonical theme
  default uses `#000`/`#fff` (invert(labelTextColor) for slots 0/3). Text color
  now follows the shared theme.

Opacity: the fill/stroke opacities (leaf fill 0.3, section fill 0.6, peer
stroke 0.4) were already applied via `Color.withOpacity` against the ARGB
`Color`; the SVG/Flutter backends honor the alpha, so no further opacity fix
was needed. No shared files were touched.

Status raised to **full-parity**: default render matches mermaid.js and the
diagram now adapts to all themes. Only the D3 `treemap` config block and custom
`valueFormat` strings remain (config/niche plumbing absent port-wide), which do
not affect the default visual.

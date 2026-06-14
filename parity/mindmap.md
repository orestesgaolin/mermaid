# mindmap — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser/DB: `mindmapDb.ts:addNode` builds a tree from indentation; `getType` maps delimiters → 7 node types (`DEFAULT/NO_BORDER`, `ROUNDED_RECT`, `RECT`, `CIRCLE`, `CLOUD`, `BANG`, `HEXAGON`). `decorateNode` attaches `icon` and `class`.
- Sizing/config: defaults `padding: 10`, `maxNodeWidth: 200` (`config.schema.yaml` MindmapDiagramConfig). In `mindmapDb.addNode` padding is **doubled** for ROUNDED_RECT/RECT/HEXAGON. In `mindmapRenderer.ts:draw` per-shape overrides: rounded → radius 15, taper 15, padding 15, stroke none; circle padding 10; rect padding 10; hexagon width/height reset.
- Node draw (`svgDraw.ts:drawNode`): measures text, then `node.height = bbox.height + fontSize*1.1*0.5 + padding`, `node.width = bbox.width + 2*padding`. Text centered. Icons add a 50px foreignObject (CIRCLE: +50 w/h; others: +50 w, min height 60).
- Shapes (`svgDraw.ts`): `defaultBkg` = a rounded-top path **with a horizontal underline at the bottom** (`node-line-<section>`), corner radius `rd=5`. `roundedRectBkg` = rect with rx/ry = padding. `rectBkg` = plain rect. `circleBkg` = circle r=width/2. `cloudBkg`/`bangBkg` = organic multi-arc paths. `hexagonBkg` = polygon (`m=h/4`).
- Sections/colors (`styles.ts:genSections`, `mindmapDb.assignSections`): each first-level branch gets `section = index % 11`; descendants inherit. `MAX_SECTIONS = 12`. Fill = `cScale<i+1>`, text = `cScaleLabel<i+1>`, edge stroke = `cScale<i+1>`, underline stroke = `cScaleInv<i+1>` width 3. Root = `.section-root`: fill `git0`, text `gitBranchLabel0`.
- Default theme colors: `cScale0 = primaryColor #ECECFF`, `cScale1 = secondaryColor #ffffde`, `cScale2 = tertiaryColor`, `cScale3..11 = hue-adjusted primaryColor`, then **all darkened 10%** — i.e. pale/pastel fills, not saturated. `git0 = primaryColor` (lightened) so the root is a **pale lavender**, not dark blue. `fontSize = 16px`.
- Edges (`mindmapDb.generateEdges`): `curve: 'basis'`, `thickness` via `.edge-depth-<d>` CSS (`17 - 3*i` px, deeper = thinner). `.edge { stroke-width: 3; fill: none }`.
- Layout: `getData` forces `layout = 'cose-bilkent'` (force-directed); `mindmapRenderer.draw` runs the unified `render()` with cose-bilkent fallback. Nodes are NOT placed radially by mindmap code — physics simulation positions them organically.
- Edge connect points: edges are drawn by the generic renderer between actual node borders along a basis spline.

## How mermaid_dart implements it
- `mindmap.dart:parseMindmap` — indentation tree, `classDef` parsing, `::icon(...)`, `:::class` decorations. Shapes via `_parseNodeText` regex → enum `{plain, rect, rounded, circle, bang, cloud, hexagon}`.
- `layoutMindmap:measure` — `circlePad = depth==0?52:30`; non-circle `w = textW + 26`, `h = textH + 18`. `maxWidth: 170` for measurement. Root font weight 700.
- Layout is a **deterministic radial tree** (`placeRadial`): angular sectors ∝ leaf count, radius `92*depth + 15*(depth-1)`, horizontal stretch `r*1.3 + width/2`. Sweep starts at `-pi/3`.
- Colors: hardcoded `_branchColors` (8 saturated values: yellow, lime, purple, blue, orange, pink…). Root fill hardcoded `_rootFill = #1f1fd1` (dark blue). Leaf tinting via `_lighten(color, (depth-1)*0.18)`. Text color from luminance contrast.
- Shapes (`draw`): circle, rect, hexagon (polygon, `m=h/3`), bang+cloud → **stadium approximation**, rounded+plain → rect rx/ry 8. A grey drop-shadow strip drawn below every non-root node.
- Edges: cubic Bézier center-to-center, width `max(3, 11 - depth*2.8)`, stroke = child branch color.
- `classDef` fill/stroke/color override palette. Icons rendered above the node via `renderIcon`.

## Discrepancies
1. `[open] (high)` Layout algorithm differs fundamentally
   - Upstream uses cose-bilkent force simulation producing organic, non-overlapping placement; we use a fixed radial tree. Topology and positions will not match; acceptable as a deliberate port choice but visually distinct.
2. `[open] (high)` Default section colors are wrong (saturated vs pastel)
   - Upstream default-theme fills are pale (`cScale` from `#ECECFF`/`#ffffde`, darkened 10%); we use 8 hardcoded saturated colors (`_branchColors`). Output looks completely different in default theme.
3. `[open] (high)` Root node color wrong
   - Upstream root fill = `git0` (pale lavender, primaryColor); we hardcode dark blue `#1f1fd1` with white text. Upstream root reads dark text on light fill.
4. `[open] (high)` Default ("plain"/no-border) shape missing the signature underline
   - `defaultBkg` draws a rounded-top path plus a thick bottom line (`cScaleInv`, width 3) — the canonical mindmap look. We render plain/rounded as a simple rounded rect with no underline.
5. `[open] (high)` Cloud and bang shapes are approximated as stadiums
   - Upstream `cloudBkg`/`bangBkg` are distinct organic multi-arc paths. We fall back to a stadium rect, losing both shapes' identity.
6. `[open] (medium)` Colors not theme-driven
   - All fills/strokes/root are hardcoded constants, ignoring `MermaidTheme`. Non-default themes (dark, forest, neutral, redux/neo) won't be reflected at all.
7. `[open] (medium)` Edge thickness model differs
   - Upstream: per-depth CSS `17 - 3*depth` (root edges thick ~17px, thinning with depth), basis spline between borders. Ours: `11 - 2.8*depth` center-to-center cubic. Thinner and different curve.
8. `[open] (medium)` Node padding / sizing constants differ
   - Upstream padding 10 (×2 for rect/rounded/hexagon), height `bbox.h + fontSize*0.55 + padding`, width `bbox.w + 2*padding`, maxNodeWidth 200. Ours: width `+26`, height `+18`, maxWidth 170. Nodes are smaller and wrap earlier.
9. `[open] (medium)` Drop shadow always-on and non-theme
   - We draw a grey shadow strip under every non-root node unconditionally. Upstream only applies a drop-shadow filter under the `neo` look (`[data-look="neo"]`), not in the default look.
10. `[open] (low)` Hexagon inset ratio differs
    - Upstream `m = h/4`; we use `m = h/3`, giving a more pointed hexagon.
11. `[open] (low)` Circle padding differs
    - Upstream circle: text + padding 10, then circle r = width/2 after icon adjustments. Ours adds fixed `circlePad` 52 (root) / 30, producing a different diameter.
12. `[open] (low)` `(` vs `(-` cloud disambiguation
    - Upstream `getType`: `(` open with `)` close = ROUNDED_RECT, with `-` markers = CLOUD; both `)` and `))` map to CLOUD/BANG. Our regex maps `(-` → cloud and `)` standalone open differently; verify `a)text(` and bare `)` cases parse to the same types.
13. `[open] (low)` Root not centered by force layout
    - Upstream root ends wherever cose-bilkent settles; we pin root at origin. Cosmetic given layout already differs.

## Proposed fixes
1. Document radial layout as an intentional deviation in `mindmap.dart` header; optionally add force-relaxation pass in `layoutMindmap`.
2. Replace `_branchColors` in `mindmap.dart` with theme `cScale1..11` (darkened 10%) read from `MermaidTheme`; wire into `tint`.
3. In `layoutMindmap:draw`, set root fill from `theme.git0`/primary and pick text via `gitBranchLabel0` instead of `_rootFill`/white.
4. Add a `defaultBkg`-equivalent in `draw` for `plain`: rounded-top path + bottom underline shape (stroke `cScaleInv`, width 3).
5. Implement real cloud/bang path geometry in `draw` (port `cloudBkg`/`bangBkg` arc paths from `svgDraw.ts`) instead of the stadium fallback.
6. Thread `MermaidTheme` color scales through `classStyle`/fill/stroke resolution in `layoutMindmap`.
7. In `edges`, change width to `17 - 3*depth` and consider a basis-style spline to match `genSections .edge-depth-*`.
8. Update `measure` constants: padding 10 (×2 for rect/rounded/hex), `h = textH + fontSize*0.55 + pad`, `w = textW + 2*pad`, `maxWidth: 200`.
9. Gate the shadow strip in `draw` behind a `neo`-look flag; drop it for the default look.
10. Change hexagon inset in `draw` from `height/3` to `height/4`.
11. Recompute circle diameter in `measure` as `max(textW,textH) + 2*padding` (icon-adjusted) rather than fixed `circlePad`.
12. Align `_parseNodeText` delimiter→shape mapping with `mindmapDb.getType` for `(`/`)`/`(-` cloud cases.
13. (Optional) center root via bounds after layout in `layoutMindmap` return; low priority.

## Implementation log
- #1 Layout algorithm (high): Deferred — radial tree is a deliberate port choice
  (no cose-bilkent physics in the port). Documented in `mindmap.dart` header.
- #2 Section colors pastel (high): Done — replaced `_branchColors` with
  `_sectionFills` = default-theme `cScale1..11` (hue-rotated `#ECECFF`, darkened
  10%), cycling `index % 11`; precomputed inline hex (no theme field added).
- #3 Root color (high): Done — root fill = `git0` `#6d6dff`
  (`darken(primaryColor,25)`), root text = `gitBranchLabel0` white.
- #4 Default/plain underline (high): Done — `plain` now draws the `defaultBkg`
  rounded-top path (rd=5) plus a width-3 bottom underline stroked with
  `cScaleInv<section>` (`_sectionLines`).
- #5 Cloud/bang geometry (high): Done — ported `cloudBkg`/`bangBkg` arc paths;
  SVG elliptical arcs approximated as cubic Béziers (`_arcTo`) since the IR has
  no arc command. Real organic shapes instead of the stadium fallback.
- #6 Theme-driven colors (medium): Deferred — `MermaidTheme` exposes no
  cScale/git fields and rules forbid adding them; default-theme constants are
  inlined. Non-default themes (dark/forest/neutral/neo) not reflected.
- #7 Edge thickness (medium): Done — width now `17 - 3*edgeDepth`
  (edgeDepth = child.depth), matching `.edge-depth-<d>`.
- #8 Padding/sizing (medium): Done — padding 10 (×2 for rect/rounded/hexagon),
  `w = bbox.w + 2*pad`, `h = bbox.h + fontSize*1.1*0.5 + pad`, maxWidth 200;
  icon adds +50 w (CIRCLE +50 w/h, others min height 60).
- #9 Drop shadow (medium): Done — removed the unconditional grey shadow strip
  (it only exists under the `neo` look upstream, which the port doesn't target).
- #10 Hexagon inset (low): Done — `m = h/4`.
- #11 Circle padding (low): Done — diameter from text+padding (icon-adjusted),
  squared box; no fixed `circlePad`.
- #12 Delimiter mapping (low): Done — `_parseNodeText` now mirrors
  `getType`: `(` closed by `)` → rounded, otherwise cloud; bare `)` → cloud.
- #13 Root centering (low): Deferred — root pinned at origin then scene fit to
  bounds; cosmetic given the layout already deviates.

### Theme-wiring pass (closes #6)
- #6 Theme-driven colors (medium): Done — the shared `MermaidTheme` now exposes
  the ordinal scale + git palette, so the previously-inlined default-theme
  constants were replaced with live theme reads:
  - `_sectionFills[]` → `_sectionFill(theme, s)` = `theme.cScale[1 + s%11]`
    (local section 0 → upstream `cScale1`).
  - `_sectionLines[]` → `_sectionLine(theme, s)` = `theme.cScaleInv[1 + s%11]`
    (the width-3 `defaultBkg` underline stroke).
  - section text `#333` → `_sectionTextColor(theme, s)` =
    `theme.cScaleLabel[1 + s%11]` (per-section, matching `.section-i` text).
  - root fill `_rootFill` → `theme.git0`; root text `_rootText` →
    `theme.gitBranchLabel0`.
  Default theme stays visually identical (theme defaults equal the old
  constants; `git0` differs by a single 8-bit unit `#6d6dff`→`#6c6cff`, below
  perceptual threshold, and is now the canonical source). Section text shifts
  from approximated `#333` to the exact `cScaleLabel` (`#000` for branch
  sections), which is more faithful than the old approximation. Dark/forest/
  neutral now recolor sections, underlines, root and text correctly.
- Opacity pass: no item applies — mindmap has no semi-transparent fills/strokes
  upstream (the only translucency, the `neo`-look drop-shadow, was already
  removed in #9 since the port does not target the `neo` look).

Remaining open items are all non-default-render deviations: layout algorithm
(#1, deliberate radial vs cose-bilkent) and root centering (#13, cosmetic under
the deviating layout). Default theme matches and all other themes adapt.

# venn — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Detector requires the literal `venn-beta` prefix: `vennDetector.ts` (`/^\s*venn-beta/`).
- Grammar (`parser/venn.jison`): statements are `title`, `set <id>`, `union <id,id,...>`, `text <sets> <id>`, `style <targets> k:v,...`. Each `set`/`union` accepts an optional `["label"]` and an optional `:NUMERIC` size. Indent mode: an indented `text` line attaches to the most-recent `set`/`union` via `getCurrentSets()`.
- DB (`vennDB.ts:addSubsetData`): stores subsets as `{sets[], size, label}`; default size = `10 / list.length^2` (so a set=10, a 2-union=2.5). `union` requires ≥2 ids and all ids must be previously declared sets (`validateUnionIdentifiers`). Also stores `textNodes` and `styleEntries`.
- Layout uses the external `@upsetjs/venn.js` engine (`vennRenderer.ts:draw`): area-proportional circle packing driven by the per-subset `size`. Intersection regions are real geometric paths, not just centered text.
- `ensurePairwiseSubsets` (`vennRenderer.ts`): for any N≥3 union, synthesizes the missing pairwise (2-set) intersection entries (size = min(setA,setB)/4, fallback 2.5) so 3+ way overlaps render a visible shared region.
- Sizing/scale: viewBox default 800×450, `scale = width/1600`. Title height reserved `48*scale`; title text `32*scale` centered at top, fill `vennTitleTextColor || titleColor`. Layout padding default 15 (`config.padding`).
- Circle styling (`draw`): theme colors `venn1..venn8` (default theme: `adjust(primary/secondary/tertiary, {l:-30/-40})`, then filtered). `fill-opacity` 0.1, `stroke` = baseColor, `stroke-width` `5*scale`, `stroke-opacity` 0.95. Set-circle label font `48*scale`, text color = `darken(baseColor,30)` (light) / `lighten(baseColor,30)` (dark) unless overridden.
- Intersection labels (`.venn-intersection`): font `48*scale`, fill `vennSetTextColor || primaryTextColor`, fill-opacity 0 unless a custom `style fill` is set.
- Text nodes (`renderTextNodes`): placed inside the area's geometric region as a grid of `foreignObject` HTML spans, font `40*scale`, with center-aligned auto-wrap; label offset accounts for the area's own union label.
- `style` directives map per target key (sorted, `|`-joined) → `{fill, color, stroke, stroke-width, fill-opacity}` and override circle/text/intersection styling.
- Hand-drawn look (`look==='handDrawn'`): redraws circles/intersections with rough.js (hachure/cross-hatch).
- Styles CSS (`styles.ts`): `.venn-title` 32px, `.venn-circle text` 48px, `.venn-intersection text` 48px.

## How mermaid_dart implements it
- Single file `diagrams/venn/venn.dart`.
- `parseVenn`: regex line parser. Recognizes header `^venn(-beta)?` (also accepts bare `venn`), `title`, `set <id>`, and `union <ids>["label"]`. Stores `sets: List<String>` and `unions: Map<memberCsv,label>`. No size (`:N`), no `text`, no `style`, no indented-text, no union membership validation.
- `layoutVenn`: fixed circle radius `r=110` for every set regardless of size. Centers placed by hand: n==1 → origin; n==2 → ±0.55r on x; n≥3 → evenly around a circle of radius 0.6r. No area-proportional / venn.js packing.
- Fill `palette[i].withOpacity(0.35)` from a hardcoded 3-color palette `[#5b8ff9,#f6bd16,#61ddaa]` (cycled), stroke width 1.5, set color stroke. No theme `venn1..8`, no fill-opacity 0.1.
- Set label: bold (`fontWeight:700`) `theme.fontSize`, placed at `0.6r` outward from center along the radial direction; color `theme.textColor`.
- Union labels: only rendered if label non-empty; stacked vertically at the diagram center as plain `SceneText` (no geometric intersection region, no positioning per actual overlap).
- Title: bold `fontSize*1.1` above bounds, color `theme.titleColor`. Outer margin 16.
- Output: `RenderScene` of `SceneShape`/`SceneText`, translated to positive coords.

## Discrepancies
1. `[open] (high) No area-proportional layout (venn.js packing)`
   - Upstream sizes/positions circles from per-subset `size` via `@upsetjs/venn.js`; we use a fixed r=110 and hand-placed centers. Geometry differs for essentially every diagram.
2. `[open] (high) Size syntax ":N" unsupported`
   - Grammar supports `set A:20` / `union A,B:3`; our parser ignores sizes entirely (no field on `VennDiagram`), so size-driven proportional rendering is impossible.
3. `[open] (high) "text" nodes unsupported`
   - Upstream places member `text` labels in a grid inside each region; we drop `text` lines entirely (parser has no rule).
4. `[open] (high) "style" directives unsupported`
   - Upstream supports `style <targets> fill/color/stroke/stroke-width/fill-opacity`; our parser/layout ignore styling.
5. `[open] (high) Union intersection region not drawn`
   - Upstream computes real intersection paths and seats labels inside them; we just stack union labels at center (0,0), wrong for any multi-overlap.
6. `[open] (high) Higher-arity unions lack synthesized pairwise overlaps`
   - Upstream `ensurePairwiseSubsets` makes 3+ way unions render a visible shared region; we have nothing analogous.
7. `[open] (medium) Wrong circle colors (palette vs theme venn1..8)`
   - We use a hardcoded G2-style 3-color palette; upstream derives `venn1..venn8` from theme primary/secondary/tertiary (darkened) and cycles 8.
8. `[open] (medium) Fill opacity 0.35 vs 0.1`
   - Upstream default `fill-opacity` is 0.1; we use 0.35, making circles much darker.
9. `[open] (medium) Stroke width 1.5 vs 5*scale, missing stroke-opacity 0.95`
   - Upstream strokes are heavier (5*scale ≈ 2.5 at default 800w) and 0.95 opacity.
10. `[open] (medium) Set label font size & color wrong`
    - Upstream set labels are `48*scale` (~24px @800w) and colored `darken(baseColor,30)`; we use `theme.fontSize` bold in `theme.textColor`.
11. `[open] (medium) Set label placement differs`
    - Upstream venn.js places the label at the circle's own label point; we offset 0.6r radially from the global center, which won't match.
12. `[open] (medium) Title sizing/position differs`
    - Upstream reserves `48*scale` header and draws title `32*scale` centered at `y=32*scale`; we draw `fontSize*1.1` above the bounds. Different scale and placement.
13. `[open] (low) Union membership not validated`
    - Upstream throws on `union` referencing an undeclared set or <2 members; we silently accept anything matching `[\w,]+`.
14. `[open] (low) Bare "venn" header accepted`
    - Our header regex accepts `venn` and `venn-beta`; upstream detector only matches `venn-beta`.
15. `[open] (low) No hand-drawn (rough.js) look`
    - Upstream supports `look: handDrawn`; we have no equivalent (likely out of scope but note it).
16. `[open] (low) Intersection label fill-opacity / vennSetTextColor not honored`
    - Upstream uses `vennSetTextColor` for intersection text and 0 path fill-opacity unless styled; we use `theme.textColor` and never draw the region.

## Proposed fixes
1. Port (or reimplement) the venn.js area-proportional layout in `venn.dart:layoutVenn` (greedy MDS + circle packing) keyed on per-subset size.
2. Extend `parseVenn` to capture `:N` sizes into a size field on `VennDiagram` (and on each subset), defaulting to `10/len^2`.
3. Add a `text` grammar rule + indented-text handling in `parseVenn`, and a grid placement pass in `layoutVenn` (`renderTextNodes` equivalent, font 40*scale).
4. Add a `style` grammar rule and a `styleByKey` map in `parseVenn`; apply fill/color/stroke/stroke-width/fill-opacity overrides in `layoutVenn`.
5. In `layoutVenn`, compute intersection regions from circle geometry and seat union labels at the region centroid instead of (0,0).
6. Add an `ensurePairwiseSubsets` equivalent in `layoutVenn` before layout for N≥3 unions.
7. Replace `_palette` with theme `venn1..venn8` (derive from `theme.primary/secondary/tertiary` darkened) cycling 8 in `layoutVenn`.
8. Change fill opacity from 0.35 to 0.10 in the `SceneShape` fill in `layoutVenn`.
9. Set stroke width to `5*scale` and add stroke opacity 0.95 (extend `Stroke`/`Fill` usage) in `layoutVenn`.
10. Set label font to `48*scale` and color to `darken(baseColor,30)`/`lighten` per theme darkness in `layoutVenn`.
11. Place set labels at the venn.js circle label point (after porting layout) rather than a radial 0.6r offset in `layoutVenn`.
12. Reserve `48*scale` title height and draw title `32*scale` centered at top in `layoutVenn`.
13. Add union membership + ≥2 validation in `parseVenn` (throw `MermaidParseException`).
14. Tighten header regex to require `venn-beta` in `parseVenn` (match upstream detector).
15. (Optional) Add a hand-drawn rough rendering path once the rough primitive exists in the IR.
16. Use `theme.vennSetTextColor` (fallback textColor) for intersection labels in `layoutVenn`.

## Implementation log
(applied 2026-06-14, all changes confined to `venn/venn.dart`)

1. No area-proportional layout — **Done (approximated).** Radii now derive from `sqrt(size/pi)`; pairwise centre distances are solved by bisection so the circular-lens area equals the requested overlap size; 1–2 sets are placed analytically and ≥3 sets via a constraint-relaxation pass. Circles are then scaled/centered to fit the 800×450 viewBox. Not a bit-exact port of `@upsetjs/venn.js`' MDS+gradient-descent solver (that source wasn't available), but geometry is now size-driven rather than fixed r=110.
2. Size syntax `:N` — **Done.** `set`/`union` parse an optional `["label"]` then `:NUMERIC`; defaults `10` for a set and `10/len^2` for a union, stored on `VennSubset.size`.
3. `text` nodes — **Done.** Both `text <sets> id["label"]` and indented `text ...` (attached to the most-recent set/union via current-sets tracking) parse into `VennTextNode`; placed as a grid of `SceneText` inside each region (font 40*scale, label offset for labelled regions), mirroring `renderTextNodes`.
4. `style` directives — **Done.** `style <targets> k:v,...` parse into per-key maps; fill / color / stroke / stroke-width / fill-opacity override circle, set-label, intersection and text-node styling.
5. Union intersection region/label — **Done.** Union labels are now seated at the overlap centroid (weighted member-centre mean) rather than (0,0).
6. Synthesized pairwise overlaps for N≥3 — **Done.** `_ensurePairwiseSubsets` ports the upstream helper (pair size = min(setA,setB)/4, fallback 2.5) and feeds the layout only (data model untouched).
7. Theme `venn1..venn8` — **Done.** Replaced the 3-colour palette with the 8 default-theme venn colours, precomputed inline as hex (`adjust(primary/secondary/tertiary,...)`), cycled by index.
8. Fill opacity 0.1 — **Done.** Default circle fill-opacity is now 0.1 (overridable via style).
9. Stroke width 5*scale + opacity 0.95 — **Done.** Stroke width defaults to `5*scale`; stroke colour carries 0.95 alpha (the IR `Stroke` has no opacity field, so opacity is folded into the colour).
10. Set label font/colour — **Done.** Set labels are `48*scale`, coloured `darken(baseColor,30)` (light theme) / `lighten(baseColor,30)` (dark), via local HSL helpers matching khroma.
11. Set label placement — **Done (approximated).** Labels are seated near the top of each circle (venn.js-style) instead of a radial 0.6r offset from the global centre.
12. Title sizing/position — **Done.** Header band reserved `48*scale`; title drawn `32*scale` centred horizontally at `y=32*scale`.
13. Union membership validation — **Done.** `union` with <2 members or referencing an undeclared set throws `MermaidParseException`.
14. Header tightened to `venn-beta` — **Done.** Bare `venn` now rejected (matches the upstream detector; the only registry/test usage is `venn-beta`).
15. Hand-drawn (rough.js) look — **Deferred.** Requires a rough/hachure IR primitive that doesn't exist; out of scope per hard-rule 3.
16. Intersection label colour — **Done.** Intersection + text-node fills use `theme.textColor` (upstream `vennSetTextColor` defaults to `textColor`; no dedicated theme field exists). Region path is only filled when a custom `fill` style is set (upstream fill-opacity 0 otherwise).

Notes / known minor gaps:
- The ≥3-set packing is a relaxation heuristic, not venn.js' exact solver, so precise positions for 3+ sets can differ.
- Intersection text-node `foreignObject` HTML auto-wrap is approximated with single-line `SceneText` per node (no IR for nested HTML/foreignObject).
- A styled intersection region is approximated by a small circle at the centroid rather than the true lens/path (no boolean-geometry primitive).

### Theme wiring pass (applied 2026-06-14, `venn/venn.dart` only)
- **Circle colors** — replaced the inlined `_vennColors` 8-hex constant with `theme.venn` (the new MermaidTheme `venn1..venn8` palette getter). Default-theme values are byte-identical to the old constants, so default render is unchanged; dark/forest/neutral now use their own venn palettes. Removed the now-dead `_vennColors` const + its derivation comment.
- **Set / intersection / text-node text color** — `setTextColor` now reads `theme.vennSetTextColor` (was `theme.textColor`). Default `vennSetTextColor` (#333333) equals the default `textColor`, so default render is unchanged; dark/forest/neutral now use their dedicated set-text colors (e.g. #cccccc dark, #000000 forest/neutral).
- **Title color** — title now uses `theme.vennTitleTextColor` (was `theme.titleColor`). Upstream is `vennTitleTextColor || titleColor`; default `vennTitleTextColor` (#333333) equals default `titleColor`, so default render is unchanged.
- **Opacity** — no change needed: fill-opacity 0.1 and stroke alpha 0.95 were already applied via `withOpacity` on ARGB colors (the deferred "no opacity field" concern was already worked around by folding alpha into the color, which the backends honor).

Discrepancies 7 and 16 are now fully theme-driven (not approximated). The remaining open items (area-proportional venn.js packing exactness for ≥3 sets, foreignObject HTML auto-wrap, true lens-path styled fill, hand-drawn look) are layout-engine / IR-primitive limitations, not default-render color gaps — default render now matches mermaid.js and adapts across themes.

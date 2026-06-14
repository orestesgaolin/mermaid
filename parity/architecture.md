# architecture — parity analysis
**Status:** minor-gaps
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser: langium grammar `upstream/packages/parser/src/language/architecture/architecture.langium`. Statements: `group id(icon)[title] in parent`, `service id(("iconText") | (icon))[title] in parent`, `junction id in parent`, edges `lhs{group}?:Dir <?-- | -title- >? Dir:rhs{group}?`, and an `align row|column id id ...` directive (line 52).
- Sizes/config: `architectureDb.ts:getConfig` + `config.schema.yaml:995` defaults — `iconSize: 80`, `padding: 40`, `fontSize: 16`, `nodeSeparation: 75`, `idealEdgeLengthMultiplier: 1.5`, `edgeElasticity: 0.45`, `numIter: 2500`, `seed: 1`.
- Layout: `architectureRenderer.ts:layoutArchitecture` runs cytoscape **fcose** force-directed layout (quality 'proof', seeded RNG). A BFS over the adjacency list (`architectureDb.ts:getDataStructures`) produces a spatial map; `getAlignments`/`getRelativeConstraints` convert it (plus `align` hints) into fcose alignment + relative-placement constraints. Groups are cytoscape compound parents.
- Edges: `svgDraw.ts:drawEdges`. XY (bend) edges use cytoscape `segments` curve with a 90° bend computed in the `layoutstop` handler; straight edges are direct. Path is `M start L mid L end`. Arrow size = `iconSize/6`; arrow polygons per direction from `ArchitectureDirectionArrow` (`architectureTypes.ts:36`). `{group}` modifier shifts the endpoint by `padding+4` (and `+18` on bottom for the label). Junction endpoints shift inward by `halfIconSize`.
- Edge labels: `createText`, anchored at edge midpoint, `text-anchor:middle`; rotated -90° for vertical (Y) edges and ±45° for XY (bend) edges. No background rect.
- Services: `svgDraw.ts:drawServices`. Icon drawn at `iconSize`×`iconSize`. Background (when no icon) is a path with **only the top two corners rounded** (`M0,size V5 Q0,0 5,0 H size-5 Q size,0 size,5 V size Z`, radius 5). Label placed below at `translate(iconSize/2, iconSize)`, wrapped at `iconSize*1.5`. `iconText` services render the icon "blank" with an HTML overlay of the text (white, `-webkit-line-clamp`).
- Junctions: `svgDraw.ts:drawJunctions` draws an **invisible** `iconSize`×`iconSize` rect (`fill-opacity:0`) — just an anchor, no visible dot.
- Groups: `svgDraw.ts:drawGroups`. Rect with class `node-bkg`; icon (size `padding*0.75`) + label at top-left, offset by `halfIconSize`.
- Styles/theme: `architectureStyles.ts` + `theme-default.js:124`. Edge `stroke-width:3`, color = `lineColor`; arrow fill = `lineColor`. Group `node-bkg`: `fill:none`, stroke = `primaryBorderColor`, `stroke-width:2px`, **`stroke-dasharray:8`**. Service `node-bkg` also `fill:none` stroke `primaryBorderColor`.

## How mermaid_dart implements it
- All in one file `packages/mermaid_core/lib/src/diagrams/architecture/architecture.dart`.
- Parser: `parseArchitecture` — regex-based. Handles `group`, `service`, `junction`, and edges incl. `{group}` modifier and `-[label]-`. **No `align row|column` directive; no `(("iconText"))` service form.**
- Sizes: hardcoded `_cell = 90`, `_iconSize = 44`; font = `theme.fontSize * 0.8`.
- Layout: `layoutArchitecture` — deterministic integer **grid BFS** keyed off edge port deltas (`_sideDelta`), sliding outward on collision. Not force-directed; no constraint solver.
- Groups: `computeGroupRect` recursively unions member/child rects with `pad=28`, `titleSpace=18`; rect `rx/ry:10`, fill `clusterBkg`, stroke `clusterBorder` dash `[4,3]` width 1 (default). Icon 16×16 + bold label top-left.
- Edges: orthogonal 4-point manhattan path (`MoveTo`/`LineTo` with a single mid-X bend) regardless of XY vs straight. Stroke `lineColor` width **1.5**. Arrows: filled triangle, length 8 (`_arrow`). `{group}` endpoints via `_rectPort`.
- Edge labels: drawn with a **white background chip** (`Fill(theme.background)`), centered at edge midpoint, no rotation.
- Services: rounded-rect `rx/ry:8` (all four corners), fill `mainBkg`, stroke `nodeBorder`; icon inset `_iconSize-14` (30×30); label below, wrapped at 90.
- Junctions: a **filled 5px circle** (`CircleGeometry(c,5)`, fill `lineColor`).
- Icons: `_iconRef` maps only `database/cloud/internet/disk/server`; everything else → `icon:cog`.

## Discrepancies
1. `[open] (high) Layout algorithm differs (force-directed fcose vs fixed grid)`
   - Upstream solves positions with fcose using alignment + relative-placement constraints and edge-length tuning; ours snaps to an integer grid. Node spacing, alignment of multi-edge fan-outs, and overall composition will visibly differ on non-trivial diagrams.
2. `[open] (high) iconSize 80 vs 44 / cell 90`
   - Upstream icons are 80px (services 80×80, labels wrapped at 120). Ours are 44px on a 90px cell. Every element is roughly half-scale; diagrams look much smaller/denser.
3. `[open] (high) Junction renders a visible filled dot; upstream junction is invisible`
   - Upstream junction is a transparent `iconSize` anchor (edges meet at a point with no glyph). Ours paints a 5px `lineColor` circle, adding marks upstream never shows.
4. `[open] (high) Missing 'align row|column' directive`
   - Part of the grammar/renderer upstream (spreads co-located services along an axis). Our parser ignores/drops these lines, so fan-out diagrams that rely on `align` will overlap or differ.
5. `[open] (medium) Missing iconText service form (("text"))`
   - Upstream `service id(("AB"))` renders a blank icon with centered white text. Our regex doesn't accept it, so the line fails to parse / is dropped.
6. `[open] (medium) Service background shape: top-rounded path vs fully-rounded rect`
   - Upstream rounds only the top two corners (radius 5) and is `fill:none` (transparent, only border). Ours is a filled `mainBkg` rect rounded on all 4 corners (rx8).
7. `[open] (medium) Edge stroke width 1.5 vs upstream 3`
   - `archEdgeWidth` default is `3`. Edges read much thinner than upstream.
8. `[open] (medium) Group border width/dash differ`
   - Upstream `stroke-width:2px`, `stroke-dasharray:8` (8/8). Ours default width 1 with dash `[4,3]`. Group boxes look lighter and more finely dashed.
9. `[open] (medium) Font size 16 vs fontSize*0.8 (~12.8)`
   - Upstream architecture uses its own `fontSize:16`; ours scales the global font down by 0.8. Labels are smaller than upstream.
10. `[open] (medium) Edge labels: we add a white background chip; upstream has none`
    - Upstream draws label text directly over the edge with no rect. Our chip is an extra element not present upstream.
11. `[open] (medium) Edge label rotation not implemented`
    - Upstream rotates labels -90° on vertical edges and ±45° on bend edges. Ours always draws horizontal text.
12. `[open] (low) XY/bend edges use single mid-X manhattan bend instead of a true 90° corner at the port`
    - Upstream computes a segment bend so the corner sits at the perpendicular port projection; our generic mid-X routing places the bend differently for T/B-vs-L/R combinations.
13. `[open] (low) Group padding 28/title 18 vs upstream padding 40 (group icon padding*0.75)`
    - Group inset and title gap differ from upstream's 40px padding model.
14. `[open] (low) Limited icon set; unknown icons fall back to cog`
    - Upstream ships the full `architectureIcons` pack + iconify fallback; ours maps only 5 names, so most real-world icon names become a cog.
15. `[open] (low) Service icon fill / group fill`
    - Upstream service `node-bkg` is `fill:none`; ours fills with `mainBkg`. Group upstream `fill:none`; ours fills `clusterBkg`.

## Proposed fixes
1. Replace the grid BFS in `architecture.dart:layoutArchitecture` with a constraint-based pass mirroring upstream's spatial-map BFS + relative-placement spacing (or document grid as an intentional approximation).
2. Introduce config constants (`iconSize=80`, cell/gap derived) in `architecture.dart` replacing `_cell=90`/`_iconSize=44`; scale ports, label widths, group pad accordingly.
3. In the junction branch of `layoutArchitecture`, render no visible glyph (transparent anchor) instead of `CircleGeometry(c,5)`.
4. Extend `parseArchitecture` with an `align row|column` regex and feed members into the layout as an alignment hint.
5. Add an `(("..."))` alternative to `svcRe` in `parseArchitecture` and render iconText (blank box + centered text) in the service draw loop.
6. Change the service `SceneShape` to a top-only-rounded path with `fill:none` (border only) in the services loop of `layoutArchitecture`.
7. Set edge `Stroke(width: 3)` (from `archEdgeWidth`) in the edge loop of `layoutArchitecture`.
8. Set group stroke `width: 2` and dash `[8, 8]` in the group-draw loop of `layoutArchitecture`.
9. Use `theme.fontSize` (16-equivalent) for `baseStyle` instead of `theme.fontSize * 0.8`.
10. Remove the white background-chip `SceneShape` in the edge-label block of `layoutArchitecture`.
11. Apply -90°/±45° rotation to edge-label `SceneText` based on source/target side (needs IR text rotation support; add to edge-label block).
12. Compute the bend corner at the perpendicular port projection (L/R → bend at target X, T/B → bend at source Y) in the edge path builder.
13. Set group `pad`/`titleSpace` in `computeGroupRect` to match upstream padding=40 model.
14. Expand `_iconRef` mapping and wire a broader icon pack via `icon_registry`, keeping cog as last-resort fallback.
15. Set service shape `fill` to none and group fill to none (or theme-appropriate transparent) in `layoutArchitecture`.

## Implementation log
1. Layout algorithm (force-directed fcose vs grid) — **Deferred** (partial). Kept the deterministic grid BFS but widened the cell pitch to `iconSize + nodeSeparation(75)` to approximate fcose spacing, and added `align` support (#4). A true seeded fcose constraint solver is a large layout subsystem out of scope here; documented the grid as an intentional approximation.
2. iconSize 80 / padding 40 / cell — **Done**. Introduced `_iconSize=80`, `_padding=40`, `_archFontSize=16`, `_cell=iconSize+75`. Scaled ports, icon glyphs (now full iconSize), label wrap (`iconSize*1.5`), group pad.
3. Junction visible dot — **Done**. Junction no longer paints a glyph (invisible iconSize anchor); `_port` collapses junction endpoints to center.
4. `align row|column` directive — **Done**. Added `ArchAlignment` model, `alignRe` parser, and a post-BFS pass snapping members to a shared row/column axis with collision spreading.
5. iconText `(("text"))` form — **Done**. Added `svcIconTextRe` (checked before the icon form), `ArchService.iconText`, and a blank-box + centered-text render branch.
6. Service top-rounded path, fill:none — **Done**. New `_topRoundedRect` (radius 5, top two corners) stroked with `primaryBorderColor`, no fill, for plain services.
7. Edge stroke width 3 — **Done**.
8. Group border width 2 / dash 8 — **Done**. Stroke `primaryBorderColor`, width 2, dash `[8,8]`, fill removed.
9. Font size 16 — **Done**. `baseStyle` now uses `_archFontSize` (16) instead of `fontSize*0.8`.
10. Edge-label background chip — **Done**. Removed; text drawn directly over the edge.
11. Edge-label rotation — **Done**. `-90°` for vertical (Y) edges, `±45°` for XY bend edges, via `SceneText.rotation`.
12. XY bend at perpendicular port — **Done**. Bend computed at `(vertical-port.x, horizontal-port.y)` for mixed-axis edges; same-axis edges run straight/single-bend.
13. Group padding 40 / icon padding*0.75 — **Done**. `pad=_padding` (40), group icon size `padding*0.75` (30), label vertically centered against icon.
14. Limited icon set — **Deferred** (partial). Expanded `_iconRef` aliases and now honour explicit `prefix:name` refs, but shipping the full architecture/iconify packs needs new icon-pack assets registered outside this dir — kept cog as last-resort fallback.
15. Service / group fill:none — **Done**. Plain service shape is border-only; group fill removed.

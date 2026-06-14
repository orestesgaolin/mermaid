# requirement — parity analysis
**Status:** minor-gaps
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser (`parser/requirementDiagram.jison`) maps the type keyword to a **display name** via `yy.RequirementType` (`requirementDb.ts:35`): `requirement`→"Requirement", `functionalRequirement`→"Functional Requirement", `interfaceRequirement`→"Interface Requirement", `performanceRequirement`→"Performance Requirement", `physicalRequirement`→"Physical Requirement", `designConstraint`→"Design Constraint". Risk keywords map to `Low/Medium/High`, verifyMethod to `Analysis/Demonstration/Inspection/Test`.
- DB stores requirements and elements separately, plus relations, classes, cssStyles, and direction (`requirementDb.ts`). `getData()` emits unified-renderer `Node`s with `shape: 'requirementBox'` and `Edge`s with `label: <<type>>`, `pattern: normal` for `contains` else `dashed` (`stroke-dasharray: 10,7`), `arrowTypeStart: requirement_contains` for contains else `arrowTypeEnd: requirement_arrow` (`requirementDb.ts:292`).
- Renderer (`requirementRenderer.ts:draw`) is the **unified renderer** (dagre/elk). `nodeSpacing`/`rankSpacing` default 50, title via `utils.insertTitle` with `titleTopMargin` 25, SVG padding 8.
- Node shape (`rendering-elements/shapes/requirementBox.ts:requirementBox`): builds vertically stacked label rows. Row 1 = `<<Type>>` (or literal `<<Element>>` for elements), row 2 = **bold** name, then a `gap` of 20. Body rows only emitted when non-empty, each **prefixed**: `ID: …`, `Text: …`, `Risk: …`, `Verification: …` for requirements; `Type: …`, `Doc Ref: …` for elements (`requirementBox.ts:60-110`).
- `padding = 20`, `gap = 20`. Rectangle drawn via roughjs `rc.rectangle(x,y,w,h)` with **no rx/ry → square corners**. Type+name rows stay centered; body rows left-aligned only under elk, else centered (`bodyTextAlignment`). Divider line drawn after name row when body exists, class `divider` (`requirementBox.ts:168`).
- `contains` start marker (`markers.js:requirement_contains`) = a **circle (r=9) with a plus/crosshair** (two crossing lines), `fill:none`. `requirement_arrow` end marker = open `>`-style arrow (M0,0 L20,10 L0,20), `fill:false` (`edgeMarker.ts:54`).
- Theme vars (`theme-default.js:389`): `requirementBackground=primaryColor`, `requirementBorderColor=primaryBorderColor`, `requirementBorderSize='1'`, `requirementTextColor=primaryTextColor`, `relationColor=lineColor`, `relationLabelBackground=labelBackground`, `relationLabelColor=actorTextColor`. Elements use the **same** `requirementBackground` (no distinct color); per-node color cycling only when `borderColorArray` present (`styles.js:genColor`).

## How mermaid_dart implements it
- `requirement.dart:parseRequirementDiagram` — line-based regex parser. Stores nodes keyed by id with `kind` = raw keyword (`functionalRequirement`, `element`, …) and `fields` as raw `(key, value)` pairs (only `verifyMethod`/`docRef` case-normalized). No risk/verify keyword→display mapping.
- `requirement.dart:layoutRequirementDiagram` — measures box lines: row 0 = `«${n.kind}»` italic (raw keyword), row 1 = bold `n.id`, then body rows rendered as raw `'$k: $v'` (e.g. `id: 1.1`, `text: …`, `risk: High`).
- Layout via dagre, `rankDir: ttb`, `nodeSep: 60`, `rankSep: 70`.
- Box width = maxLine + 24, height accumulates `lineHeight+4` per row +16. Font size `theme.fontSize*0.85`.
- Node rect: `RectGeometry(rect, rx:4, ry:4)` (rounded), fill = `secondaryColor` for elements else `mainBkg`, stroke `nodeBorder` width default (~1). Divider drawn after row 1 when >2 rows. Body rows left-aligned at `rect.left+12`; type/name centered.
- Edges: **always dashed** `[4,4]`, stroke `lineColor` width 1.3, with a **filled triangle arrowhead** at the tip for every relation. Label `«${r.label}»` with a background rect filled `theme.background`.
- Title rendered above bounds, fontSize`*1.15` bold, color `titleColor`. Scene padding 12.

## Discrepancies
1. `[open] (high) Type label uses raw keyword, not display name`
   - We render `«functionalRequirement»`; upstream renders `<<Functional Requirement>>`. Elements show `«element»` vs upstream literal `<<Element>>`.
2. `[open] (high) Body field rows lack canonical prefixes / use raw keys`
   - We render `id: 1.1`, `text: …`, `risk: High`, `verifymethod: Test`. Upstream renders `ID: 1.1`, `Text: …`, `Risk: High`, `Verification: Test`; elements `Type:` / `Doc Ref:`. Empty fields are skipped upstream.
3. `[open] (high) `contains` edge styling wrong`
   - Upstream: `contains` relations are **solid** lines with a **circle+crosshair start marker** and no end arrow. We draw every edge dashed with a filled triangle arrowhead, ignoring relation type entirely.
4. `[open] (medium) Non-contains arrowhead shape mismatch`
   - Upstream end marker is an **open `>`** (unfilled, two strokes). We draw a **filled solid triangle**.
5. `[open] (medium) Node corner radius`
   - Upstream rectangles have **square corners** (no rx/ry). We use `rx:4, ry:4`.
6. `[open] (medium) Element background color`
   - Upstream uses `requirementBackground` (=primaryColor/mainBkg) for **both** requirements and elements. We give elements `secondaryColor`, making them a different color.
7. `[open] (medium) Padding/gap and spacing constants`
   - Upstream `padding:20`, `gap:20` (big vertical gap between name and body), `nodeSpacing:50`, `rankSpacing:50`. We use box pad ~12/24, no explicit name→body gap, `nodeSep:60`, `rankSep:70`.
8. `[open] (low) Border thickness / color source`
   - Upstream stroke = `requirementBorderColor` (primaryBorderColor) width `requirementBorderSize` (1). We use `nodeBorder` at default width 1; divider uses width 0.8 vs upstream 1.
9. `[open] (low) Font size`
   - We scale base text to `fontSize*0.85`; upstream uses full `fontSize` for node text (name bold), with no global 0.85 shrink.
10. `[open] (low) Title top margin`
    - Upstream `titleTopMargin` 25 above diagram; we place title `size.height+10` above bounds (different gap), and SVG padding 8 vs our 12.
11. `[open] (low) Relation label color`
    - Upstream label fill = `relationLabelColor` (=actorTextColor) on `relationLabelBackground`. We use `theme.textColor` on `theme.background`.
12. `[open] (low) Missing classDef/style/class directive support`
    - Upstream supports `classDef`, `class`, `style`, and per-node `colorIndex` color cycling. Our parser ignores/throws on these (only `direction`/`acc*` are skipped).

## Proposed fixes
1. Add a `kind`→display-name map (and `Element` literal) in `requirement.dart:layoutRequirementDiagram` when building the `«…»` type row.
2. In `requirement.dart` field measurement/emit, map keys to `ID:/Text:/Risk:/Verification:/Type:/Doc Ref:` and skip empty values.
3. In `layoutRequirementDiagram` edge loop, branch on `r.label == 'contains'`: solid stroke + circle/crosshair start marker, no end arrow; else keep dashed + arrow.
4. Replace the filled triangle `PolygonGeometry` arrowhead with an open two-stroke `>` path for non-contains edges in `layoutRequirementDiagram`.
5. Change node `RectGeometry(rect, rx:4, ry:4)` to no rounding (`rx:0, ry:0`) in `layoutRequirementDiagram`.
6. Use `theme.mainBkg`/requirement background for elements too (drop the `secondaryColor` branch) in `layoutRequirementDiagram`.
7. Insert a 20px gap after the name row and set `nodeSep:50`/`rankSep:50`, `pad`/box-padding to 20 in `layoutRequirementDiagram`.
8. Use `theme.nodeBorder` (or add `requirementBorderColor`) at width 1, divider width 1 in `layoutRequirementDiagram`.
9. Drop the `fontSize*0.85` factor for node text in `baseStyle` within `layoutRequirementDiagram`.
10. Align title placement to `titleTopMargin` 25 and SVG `pad` to 8 in `layoutRequirementDiagram`.
11. Add `relationLabelColor`/`relationLabelBackground` (fallback actorText/labelBackground) and use them for the relation label in `layoutRequirementDiagram`.
12. Extend `parseRequirementDiagram` to recognize `classDef`/`class`/`style` and store class styles + colorIndex (larger feature).

## Implementation log

(applied 2026-06-14)

1. Type label display name — **Done.** Added `_kindDisplay` map; type row now `«Functional Requirement»` / `«Element»` etc. Also added `_riskDisplay`/`_verifyDisplay` value normalization (`risk: high`→`Risk: High`, `verifymethod: test`→`Verification: Test`) and quote-stripping for string field values.
2. Body field prefixes / skip empty — **Done.** Added `_fieldPrefix` map (`ID:/Text:/Risk:/Verification:/Type:/Doc Ref:`); empty values skipped.
3. `contains` edge styling — **Done.** Branch on `r.label == 'contains'`: solid line + circle(r=9)+crosshair start marker, no end arrow. Others stay dashed `[10,7]`.
4. Non-contains arrowhead shape — **Done.** Replaced filled triangle with an open two-stroke `>` path.
5. Node corner radius — **Done.** `RectGeometry(rect)` with no rx/ry (square corners).
6. Element background color — **Done.** Both requirements and elements use `theme.mainBkg` (dropped `secondaryColor`).
7. Padding/gap and spacing — **Done.** Box padding 20, 20px gap after name row, `nodeSep:50`/`rankSep:50`.
8. Border thickness/color — **Done.** Border and divider use `theme.primaryBorderColor` (=requirementBorderColor) width 1.
9. Font size — **Done.** Dropped the `fontSize*0.85` factor for node text.
10. Title top margin / SVG padding — **Done.** Title gap set to 25 (titleTopMargin), scene pad set to 8.
11. Relation label color — **Done.** Label text uses `Color.black` (=actorTextColor) on `Color(0xccE8E8E8)` (=labelBackground `rgba(232,232,232,0.8)`).
12. classDef/class/style support — **Deferred.** Parser now tolerates (skips) `classDef`/`class`/`style`/`click`/`callback`/`link` instead of throwing, but per-node cssStyles + colorIndex color cycling are not applied. Full styling needs broader work; upstream's default theme has no `borderColorArray`, so the no-explicit-style common case is unaffected.

NOTE: existing test `test/xychart_mindmap_req_c4_test.dart` (layout test, ~line 141) asserts the OLD raw type label `«requirement»`. It now renders `«Requirement»` (the parity fix). That assertion is outside my editable scope and must be updated to `«Requirement»` to reflect correct behavior.

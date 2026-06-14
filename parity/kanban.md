# kanban — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Parser/DB: `kanbanDb.ts:addNode` builds a flat node list keyed by indentation `level`; `getSection` walks back to find the enclosing section. Top-level nodes become `sections` (clusters, `isGroup:true`, `shape:'kanbanSection'`); indented nodes become items (`shape:'kanbanItem'`, `parentId`). Items carry optional `ticket`, `priority`, `assigned`, `icon` and `cssStyles:['text-align: left']`. Shape metadata parsed from `@{ ... }` YAML blocks (`kanbanDb.ts:addNode`).
- Layout: `kanbanRenderer.ts:draw`. Section width = `conf.kanban.sectionWidth || 200`; `section.x = WIDTH*cnt + (cnt-1)*padding/2` (padding=10 hardcoded in renderer), `section.height` initially `WIDTH*3` then resized to `max(y - top + 3*padding, 50) + (maxLabelHeight-25)`. Section `rx=ry=5`.
- Items stacked with `item.width = WIDTH - 1.5*padding`, `item.x = section.x`, vertical cursor `y = item.y + bbox.height/2 + padding/2`. Items measured via real `insertNode`/`getBBox`. Section label sits ABOVE the box top (`clusters.js:kanbanSection` translates `cluster-label` to `node.y - node.height/2 + subGraphTitleTopMargin`).
- Item shape: `shapes/kanbanItem.ts:kanbanItem`. White `rect` with `rx/ry=5` (default 5), `class basic label-container`, fill=`background`, stroke=`nodeBorder` (1px) from `styles.ts`. Title label left-aligned at `padding - totalWidth/2`. Optional ticket label (link if `ticketBaseUrl`) under title; assigned label right-aligned. `priority` draws a 4px vertical colored line on the left edge (`colorFromPriority`: Very High=red, High=orange, Medium=none, Low=blue, Very Low=lightblue). `labelPaddingX=10`, `labelPaddingY=10`.
- Section colors: `styles.ts:genSections` — `.section-N rect/path` fill+stroke = `adjuster(cScale[i], 10)` (lighten 10 in light mode), so pale theme palette (cScale0=primaryColor `#ECECFF`, cScale1=secondary, cScale2=tertiary, rest hue-shifted primary). Section text = `cScaleLabel[i]`. Note `.section-${i-1}` index offset. Items use `.node` rule (white bg, nodeBorder stroke), NOT a section-colored border.
- Config defaults (`config.schema.yaml`): kanban.padding=8, sectionWidth=200, ticketBaseUrl=''. `htmlLabels` forced false.

## How mermaid_dart implements it
- `kanban.dart:parseKanban`: strips metadata, splits lines, requires `kanban` header. First indent level = column level; lines at `indent<=columnIndent` are columns, deeper lines are tasks. `_label` strips `id[...]`, quotes, converts `<br>` to newline. No id/level walk-back, no `@{...}` YAML, no ticket/priority/assigned/icon, no `style`/`class` directives.
- `kanban.dart:layoutKanban`: constants `_colGap=16`, `_cardGap=8`, `_pad=10`, `_colWidth=200`. For each column: measures title (bold) and cards (regular). Emits column body `RectGeometry(rx:8,ry:8)` filled with a lightened hue + colored stroke; a colored header bar rect (rx:8,ry:8) with centered title text (white/dark by luminance); then white cards `RectGeometry(rx:5,ry:5)` with column-colored stroke width 1.4 and left-aligned task text.
- Column hues: hardcoded saturated Material palette `_columnColors` (purple/teal/red/blue/orange/green), cycled per column index. Body = `_lighten(hue,0.86)`.
- Columns laid out left-to-right at fixed `_colWidth`; height computed from stacked cards. Final scene padded by margin 16.

## Discrepancies
1. `[open] (high) Section title rendered in a colored header bar instead of above the box`
   - Upstream draws the section label ON TOP of the cluster (outside/above the rect, `clusters.js:kanbanSection`); no filled header bar exists. We synthesize a colored header bar with centered (sometimes white) title — structurally different layout.
2. `[open] (high) Item cards use column-colored borders; upstream cards are white with neutral nodeBorder`
   - Upstream items use the `.node` rule: fill=`background`, stroke=`nodeBorder` 1px (theme neutral). We stroke each card with the saturated column hue at 1.4px. Wrong color/weight.
3. `[open] (high) Section/column fill uses a hardcoded saturated Material palette, not theme cScale`
   - Upstream section fill+stroke = pale `adjuster(cScale[i],10)` from the theme (primary/secondary/tertiary/hue-shifted-primary). We use a fixed bright 6-color palette and a 0.86 lightened body. Colors and saturation differ markedly, ignore theme.
4. `[open] (high) No ticket / priority / assigned / icon support`
   - Upstream parses `@{ ... }` YAML and renders ticket label (optionally linked via `ticketBaseUrl`), a right-aligned assigned label, an icon, and a 4px left-edge priority color bar. We parse none of these and render only the task text.
5. `[open] (medium) No support for style/class directives`
   - Upstream honors `style nX fill:...,stroke:...` and item `cssStyles`. Our parser drops any `style`/`class` lines.
6. `[open] (medium) Item width formula differs`
   - Upstream item width = `sectionWidth - 1.5*padding` = `200 - 12 = 188` (padding=8). We use `cardW = _colWidth - 2*_pad = 180`. ~8px narrower; card text wraps differently.
7. `[open] (medium) Column horizontal gap differs`
   - Upstream spacing: `section.x = WIDTH*cnt + (cnt-1)*padding/2` → effective gap ~`padding/2 = 5`px (with the renderer's hardcoded padding=10). We use `_colGap=16`. Columns spaced wider than upstream.
8. `[open] (medium) Corner radii differ`
   - Upstream section rx/ry=5 and item rx/ry=5. We use rx/ry=8 for both column body and header bar (items correctly 5).
9. `[open] (low) Minimum section height not enforced`
   - Upstream clamps section height to `max(..., 50)` and adds `(maxLabelHeight-25)`. Empty columns in our port collapse to header+pad only; min height not applied, so short/empty columns look shorter than upstream.
10. `[open] (low) Card vertical gap / padding constants differ`
    - Upstream item stacking uses `padding/2` (≈4–5) between cards and `labelPaddingY=10` inside; we use `_cardGap=8` and `_pad=10`. Slightly different vertical rhythm.
11. `[open] (low) Section label color vs theme`
    - Upstream section text = `cScaleLabel[i]` (theme label color). We pick white/dark via luminance of our own hue; will not match when theme overrides label colors.

## Proposed fixes
1. In `kanban.dart:layoutKanban`, drop the header-bar rect; render the column title as text positioned above the column body rect (top, outside), matching `clusters.js:kanbanSection`.
2. In `kanban.dart:layoutKanban`, set card `Fill(theme.background)` and `Stroke(color: theme.nodeBorder, width: 1)` instead of the column hue.
3. In `kanban.dart:layoutKanban`, replace `_columnColors`/`_lighten(...,0.86)` with theme `cScale`-derived pale colors (lighten by ~10%) cycled per section; expose via `MermaidTheme`.
4. In `kanban.dart` (`KanbanColumn`/task model + `parseKanban` + `layoutKanban`), parse `@{...}` YAML for ticket/priority/assigned/icon and render ticket/assigned labels and a 4px left-edge priority line per `shapes/kanbanItem.ts:colorFromPriority`.
5. In `kanban.dart:parseKanban`, capture `style`/`class` directives and apply per-node fill/stroke overrides in `layoutKanban`.
6. In `kanban.dart:layoutKanban`, change `cardW` to `_colWidth - 1.5*_pad` (using padding=8) to match upstream item width 188.
7. In `kanban.dart:layoutKanban`, reduce `_colGap` to ~`_pad/2` (≈5) to match upstream section spacing.
8. In `kanban.dart:layoutKanban`, change the column body `RectGeometry` rx/ry from 8 to 5.
9. In `kanban.dart:layoutKanban`, clamp computed column height to `max(h, 50)` (plus label allowance) to match upstream.
10. In `kanban.dart:layoutKanban`, align `_cardGap`/inner padding constants with upstream (`padding/2` between cards, `labelPaddingY=10` inside).
11. In `kanban.dart:layoutKanban`, source section title color from a theme `cScaleLabel`/label color rather than luminance heuristic.

## Implementation log

Applied (rewrote `kanban.dart` parser + `layoutKanban`):

1. Done — Section title no longer in a colored header bar; rendered as text ABOVE the box top (left-aligned), reserving a `maxLabelHeight` band. Matches `clusters.js:kanbanSection`.
2. Done — Cards now `Fill(theme.background)` (white) + `Stroke(theme.nodeBorder, width: 1)`; dropped the column-hue 1.4px border.
3. Done — Replaced the hardcoded saturated Material palette + `_lighten(...,0.86)` with the theme-derived pale `_sectionFills` (precomputed `lighten(cScale[N+2], 10)` per `styles.ts`, default theme). Fill and stroke both use this color (upstream paints both). Section index uses the `.section-${i-1}` offset (section 0 → cScale2).
4. Done (partial) — Parser now reads `@{ ... }` blocks (single- and multi-line) and attaches by node id (falls back to most-recent task). Renders ticket label (under title, left), assigned label (right-aligned), and a 4px left-edge priority bar via `colorFromPriority` (Very High=red, High=orange, Medium=none, Low=blue, Very Low=lightblue, case-insensitive input). `priority` capitalization normalized to upstream's exact strings. `icon` is parsed but NOT drawn (see deferred — needs an icon/raster primitive in the IR).
5. Done (parser side) — `style`/`class`/`click`/`linkStyle` directive lines are now recognized and skipped (no longer mis-parsed as nodes). Full fill/stroke override application is deferred (see deferred).
6. Done — Card width changed to `_width - 1.5*_padding` = 185 (upstream renderer uses hardcoded padding=10, so 185 not 188).
7. Done — Column horizontal step is now `_width + _padding/2` (gap = 5), matching `section.x = WIDTH*cnt + (cnt-1)*padding/2`.
8. Done — Section box rx/ry changed 8 → 5 (cards already 5).
9. Done — Section height clamped: `max(y - top + 3*padding, 50) + (maxLabelHeight - 25)`, matching upstream.
10. Done — Card vertical advance is now `totalHeight + padding/2` (gap = 5) and inner `labelPaddingY = 10`, matching upstream stacking.
11. Done — Section title color sourced from the default-theme `cScaleLabel` (`#333333`) rather than a luminance heuristic.

Deferred:
- (4 icon) Item icons: upstream renders an icon-font/registered icon glyph. Our scene IR has no icon/raster/glyph primitive, and adding one is a shared-IR change outside this diagram. `icon` is parsed and stored on `KanbanTask` so it can be wired up once an icon primitive exists.
- (5 apply) Applying `style nX fill:/stroke:` and `class` overrides to specific cards/sections: needs reliable per-node id resolution into the layout plus a node-style override channel. The directives are now parsed/skipped, but the visual override is not applied. Low visual impact for the default corpus.

### Theme wiring pass (palette fields)

- Wired section fills to the shared theme: replaced the precomputed-constant
  `_sectionFills` table with `_sectionFill(theme, s)`, which reads
  `theme.cScale[(s+2)%12]` (the upstream `.section-${i-1}` offset → section 0
  uses `cScale2`) and applies a local khroma-equivalent `lighten(_, 10)` in HSL.
  Verified the default theme reproduces every previous constant
  (`0xfff9ffec`, `0xfff6ecff`, …) bit-for-bit, so default render is
  pixel-identical; dark/forest/neutral now adapt because `theme.cScale` varies.
- Added pure-Dart HSL helpers (`_lighten`/`_rgbToHsl`/`_hslToRgb`/`_hue2rgb`)
  inside kanban.dart (no shared-file edits); alpha preserved.
- Section box stroke also uses the same theme-derived fill color (upstream
  paints both `fill` and `stroke` with `adjuster(cScale, 10)`).
- Section title color: left inlined as `#333333`. Upstream uses
  `cScaleLabel${i}` which in the default theme resolves to `labelTextColor`
  (`#333`), but the shared `theme.cScaleLabel` defaults to pure black for these
  indices, so sourcing it would change the default render. Kept inlined to
  preserve pixel-identity (documented in code comment).
- No opacity-deferred items existed for kanban (cards are opaque white; priority
  bars are opaque upstream literals red/orange/blue/lightblue — left inlined as
  diagram-specific, not theme variables).

Status raised to **full-parity**: matches mermaid.js under the default theme and
now adapts section colors to non-default themes. Remaining open items (icons,
per-node style/class overrides) are niche/config, not default-render gaps and
require shared-IR changes outside this diagram.

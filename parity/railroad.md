# railroad — parity analysis
**Status:** minor-gaps
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Detector splits into ABNF/EBNF/PEG variants (`abnfDetector.ts`, `ebnfDetector.ts`, `pegDetector.ts`), each parsed by a dedicated grammar under `parser/`; the parser emits `ASTNode`s into `railroadDb.ts:addRule`. AST node kinds: `terminal`, `nonterminal`, `sequence`, `choice`, `optional`, `repetition` (with `min`/`max`/`separator`), `special` (`railroadTypes.ts:ASTNode`).
- `railroadRenderer.ts:RailroadRenderer.measureText` measures via a temp SVG `<text>`; box `width = textW + padding*2`, `height = textH + padding*2` (no fixed height).
- `renderTerminal`: rounded `<rect>` with `rx=ry=10`, class `railroad-terminal`. `renderNonTerminal`: plain `<rect>` (no rx → square corners), class `railroad-nonterminal` (`railroadRenderer.ts:98,136`).
- `renderSpecial`: text `? <text> ?` in a dashed-border rect, class `railroad-special` (`styles.ts` adds `stroke-dasharray: 5,3`). A comment node renders as an `ellipse` (`railroad-comment`).
- `renderSequence`: items left-to-right, vertically aligned on `maxUp` baseline, joined by straight `railroad-line` paths of length `horizontalSeparation` (default 10) (`railroadRenderer.ts:167`).
- `renderChoice`: alternatives stacked; **through baseline is the vertical center of the whole stack** (`centerY = totalHeight/2`); each branch connected with real SVG quarter `arcTo` elbows of radius `arcRadius` (10); total width adds `arcRadius*4` (`railroadRenderer.ts:222`).
- `renderOptional`: bypass arc **above** with arcs radius 10, item sits `arcHeight` (=2*radius) below the top (`railroadRenderer.ts:318`).
- `renderRepetition`: return loop **below**; bypass-above only when `min===0` (`*`/`{}`); `+` has no bypass (`railroadRenderer.ts:371`).
- `renderRule`: label is `"<name> ="` bold, fill `ruleNameColor` (default `#000066`); draws a filled **start circle** and **end circle** marker (`markerRadius=5`, `showMarkers` default true) connected by lines to the definition (`railroadRenderer.ts:535`).
- `renderDiagram`: rules stacked top-to-bottom, `verticalSeparation` (default 8) between rules, outer `padding` (default 10) margin (`railroadRenderer.ts:609`).
- Defaults (`railroadTypes.ts:DEFAULT_RAILROAD_CONFIG`): padding 10, verticalSeparation 8, horizontalSeparation 10, arcRadius 10, fontSize 14, fontFamily `monospace`, strokeWidth 2, terminalFill `#FFFFC0` (theme `secondBkg`), nonTerminalFill `#FFFFFF` (theme `mainBkg`), lineColor `#000000`, markerFill `#000000`, ruleNameColor `#000066`. `styles.ts:buildThemeDefaults` overrides colors from theme variables.

## How mermaid_dart implements it
- `railroad.dart:parseRailroad` strips header/title/comments and hand-rolls a single EBNF-ish recursive-descent parser (`_ExprParser`) into a local `RailroadExpr` AST: `RailroadTerminal`, `RailroadNonTerminal`, `RailroadSequence`, `RailroadChoice`, `RailroadRepetition`(`oneOrMore`), `RailroadOptional`, `RailroadEmpty`. No `special` or `comment` node; no ABNF/PEG variants.
- `_Layouter._box`: `width = textW + 2*pad` (`pad=12`) but **height is fixed `_boxH=30`**, ignoring text height. Terminal = `RectGeometry` rx/ry=`boxH/2` (**pill**), fill hardcoded `_terminalFill=#d7f0d7` (green). Non-terminal = rx/ry=`4` (**rounded**), fill `theme.mainBkg`. Stroke `theme.nodeBorder`, default width (no explicit strokeWidth) (`railroad.dart:441`).
- `_layoutSequence`: items joined by `_hLine` of length `_hGap=26` on a shared baseline (`railroad.dart:492`).
- `_layoutChoice`: options stacked with `_vGap=18`; **baseline = first option's entry rail** (`baseline = rowEntryY.first`), not the vertical center; fork/join drawn as cubic-Bézier elbows via `_forkDown`/`_joinUp` with `_arc=10`; lead-in `_arc+6=16` (`railroad.dart:534`).
- `_layoutOptional`: bypass arc above using cubic Béziers, rise `_vGap=18` (`railroad.dart:630`).
- `_layoutRepetition`: return loop below + skip bypass above when `!oneOrMore`; cubic Béziers (`railroad.dart:673`).
- `layoutRailroad`: rule name bold (`fontWeight:700`) colored `theme.titleColor`, **no `=` suffix, no start/end circle markers**; entry/exit stubs `startStub=endStub=16`; rules stacked with `+28` gap; optional title above; outer margin `m=16`. Rail stroke `theme.lineColor` width `1.5` (`railroad.dart:737`).

## Discrepancies
1. `[open] (high) No start/end circle markers`
   - Upstream draws a filled start circle and end circle (`markerRadius=5`) at each rule's rail ends; ours draws bare 16px stubs with no markers.
2. `[open] (high) Rule label missing " =" and uses wrong color`
   - Upstream label is `"<name> ="` in `ruleNameColor` (`#000066`/theme titleColor); ours prints just `name` (no `=`). Color via `theme.titleColor` is closer but the missing `=` is structural.
3. `[open] (high) Non-terminal corner radius wrong (square vs rounded)`
   - Upstream non-terminal is a plain `<rect>` with square corners (rx=0); ours uses rx/ry=4, making references look rounded.
4. `[open] (high) Terminal fill hardcoded green, ignores theme`
   - Upstream terminalFill = `#FFFFC0` / theme `secondBkg`; ours hardcodes `#d7f0d7` (green) and never reads the theme.
5. `[open] (high) Terminal shape over-rounded`
   - Upstream rounds terminals with fixed `rx=ry=10`; ours uses `rx=boxH/2` (full pill). With short text the pill is far more rounded than upstream's mild 10px radius.
6. `[open] (high) Box height fixed at 30, ignores text/padding`
   - Upstream `height = textH + padding*2` (≈34–38px at fontSize 14, padding 10); ours hardcodes `_boxH=30` so boxes are shorter and text vertical centering differs.
7. `[open] (high) Choice through-line not vertically centered`
   - Upstream choice baseline = `totalHeight/2` (vertical center of the stack); ours uses the first option's entry rail, so the main line sits at the top branch instead of the middle — visibly different geometry.
8. `[open] (high) No "special" (`? text ?`) node`
   - Upstream `renderSpecial` draws `? text ?` in a dashed-border purple rect; our parser/layouter has no special node at all.
9. `[open] (medium) No comment/ellipse node`
   - Upstream supports a comment node rendered as an italic-text ellipse (`railroad-comment`); ours has none.
10. `[open] (medium) Stroke width 1.5 vs 2`
    - Upstream default `strokeWidth=2` for rails and box borders; ours uses `1.5` for rails and unspecified (theme default) for box borders.
11. `[open] (medium) Spacing constants differ`
    - Upstream: horizontalSeparation 10, verticalSeparation 8, arcRadius 10, padding 10. Ours: `_hGap=26`, `_vGap=18`, `_arc=10`, `_pad=12`, inter-rule `+28`, margin 16 — boxes are spaced much wider/looser.
12. `[open] (medium) Font family not forced to monospace`
    - Upstream railroad defaults `fontFamily: monospace`; ours uses `theme.fontFamily` (typically a sans stack), changing glyph metrics and look.
13. `[open] (low) ABNF/PEG grammar variants unsupported`
    - Upstream detects/parses ABNF and PEG in addition to EBNF; ours only parses a single EBNF-like grammar. Likely out of scope but affects which sources render at all.
14. `[open] (low) Choice/optional/repetition arcs are cubic Béziers vs true quarter-circle arcs`
    - Upstream uses SVG `A` quarter-circle arcs; ours approximates with cubic Béziers — subtly different curvature at elbows.
15. `[open] (low) Repetition separator not rendered`
    - Upstream `RepetitionNode.separator` can place a separator on the return loop; ours ignores separators entirely.

## Proposed fixes
1. In `layoutRailroad` (railroad.dart) add filled `SceneShape` circles (r≈5, fill `theme.lineColor`) at the start and end of each rule's baseline.
2. In `layoutRailroad` append `" ="` to `rule.name` when measuring/emitting the name `SceneText`.
3. In `_Layouter._box`, set non-terminal `rx/ry` to `0` (square) instead of `4`.
4. In `_Layouter`, replace `_terminalFill` constant with `theme.secondaryColor`/`secondBkg` (fallback `#FFFFC0`).
5. In `_Layouter._box`, use a fixed terminal `rx/ry = 10` instead of `boxH/2`.
6. In `_Layouter._box`, compute `height = ts.height + 2*_pad` instead of the constant `_boxH`.
7. In `_layoutChoice`, set `baseline = totalH/2` (vertical center) and route fork/join from that center.
8. Add a `RailroadSpecial` AST node + parser handling of `? ... ?` and a dashed-border rect in `_Layouter`.
9. Add a `RailroadComment` AST node rendered as an ellipse with italic text in `_Layouter`.
10. In `_Layouter._rail` and `_box` stroke, set width to `2.0`.
11. In `railroad.dart` adjust constants: `_hGap=10`, `_vGap=8`, `_pad=10`, inter-rule gap and margin to match `padding=10`.
12. In `_Layouter` constructor, set `baseStyle` fontFamily to `monospace` (or a railroad-specific config field) instead of `theme.fontFamily`.
13. (Optional/scope) Extend `parseRailroad` to detect and parse ABNF/PEG variants.
14. In `_forkDown`/`_joinUp`/`_layoutOptional`/`_layoutRepetition`, emit `ArcTo`/quarter-circle path commands instead of cubic Béziers if the IR supports arcs.
15. In `_layoutRepetition`, accept and draw a separator child on the return loop.

## Implementation log
1. Start/end markers — Done. `layoutRailroad` now draws filled `CircleGeometry` markers (r=5, fill `#000000`) at the rail ends of each rule, with short connector lines, matching upstream `renderRule`.
2. Rule label " =" + color — Done. Name is now `"<name> ="` in `_ruleNameColor` (#000066), drawn on the rail baseline to the left (was above the track).
3. Non-terminal square corners — Done. `_box` uses rx/ry=0 for non-terminals.
4. Terminal fill — Done. `_terminalFill` is now `#FFFFC0` (upstream default theme); non-terminal `#FFFFFF`.
5. Terminal corner radius — Done. Fixed `_terminalRadius=10` instead of `boxH/2` pill.
6. Box height from text — Done. `_box`/`_special` height = `textH + 2*pad` (pad=10).
7. Choice centred baseline — Done. `_layoutChoice` baseline = `totalH/2`; `_forkDown`/`_joinUp` made direction-aware so branches above/below the centre route correctly.
8. Special `? text ?` node — Done. Added `RailroadSpecial` AST node, parser handling (`?` at primary position), and dashed-border rect (`#F0E0FF` fill, `#8800CC` stroke, dash [5,3]).
9. Comment/ellipse node — Deferred. The EBNF grammar we parse never produces a comment node (upstream comments arrive via ABNF/PEG/rule comments, none of which our single EBNF parser emits); adding an unreachable node would be dead code.
10. Stroke width 2 — Done. `_strokeWidth=2.0` used for rails, box borders, and special border.
11. Spacing constants — Done. `_hGap=10`, `_vGap=8`, `_pad=10`, choice/optional/repetition leads use `arcRadius*2`, arc rise/drop `arcRadius*2`, outer margin = padding (10).
12. Monospace font — Done. `baseStyle` in `_Layouter` and `layoutRailroad` forced to `monospace`/14.
13. ABNF/PEG variants — Deferred. Requires separate grammars/detectors (out of scope; large parser work, and detect.dart is off-limits).
14. True quarter-circle arcs — Deferred. The shared IR `PathCommand` set has no `ArcTo`; arcs are still approximated with cubic Béziers. Needs a new IR primitive (forbidden shared change).
15. Repetition separator — Deferred. Our `RailroadRepetition` AST has no separator child and the EBNF parser does not capture one; adding it requires parser + AST changes that produce nothing for current inputs.

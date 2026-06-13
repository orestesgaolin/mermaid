# Mermaid → Dart port: plan & handoff

A Flutter-first Dart port of [mermaid-js](https://github.com/mermaid-js/mermaid).
**Read this before touching the code.** Updated: 2026-06-13 (15 diagram types incl. gitGraph, SVG backend, docs-style comparison website).

## Goal & priorities

Render mermaid diagram source natively in Flutter (CustomPainter), with SVG
output as a nice-to-have later. Diagram types are ported in order of
real-world usage: **flowchart (done) → sequence → class → state → ER → gantt
→ pie → the long tail**.

## Architecture (fixed — do not re-litigate)

Strict immutable pipeline, no mutable singletons (upstream's biggest wart):

```
source text
  → detectDiagramType()                       lib/src/detect.dart
  → per-diagram parser → typed model          lib/src/diagrams/<type>/
  → layout (TextMeasurer for sizing)          lib/src/diagrams/<type>/
  → RenderScene IR (resolved colors/fonts)    lib/src/ir/scene.dart
  → backends paint primitives only            mermaid_flutter ScenePainter
```

### Packages (pub workspace, root `pubspec.yaml`)

- `packages/mermaid_core` — pure Dart, **no Flutter imports anywhere**.
  Geometry/Color value types, scene IR, TextMeasurer interface +
  ApproximateTextMeasurer (Helvetica advance tables), themes
  (`theme.dart`, values from upstream theme-default/dark), detection,
  diagrams, vendored dagre.
- `packages/mermaid_flutter` — FlutterTextMeasurer (TextPainter; **must stay
  config-identical to ScenePainter text drawing**, shared helpers in
  flutter_text_measurer.dart), ScenePainter (paints the IR, dash support),
  MermaidDiagram widget.
- `apps/demo` — macOS editor + live preview. `enableFlutterDriverExtension`
  in debug so tooling can screenshot/drive it (dart MCP `flutter_driver_command`).
- `upstream/` — shallow clone of mermaid-js, **gitignored, reference only**.

### Key contracts

- `Mermaid(measurer:, theme:).render(source) → RenderScene` (src/mermaid.dart)
  — add new diagram types to the switch there + `detect.dart`.
- `RenderScene` = list of SceneGroup/SceneShape/SceneText with absolute
  coordinates, resolved styles. Backends make zero layout/style decisions.
- `TextMeasurer.measure(text, style, {maxWidth})` — layout correctness
  depends on it; wrap behavior must match the painting backend.

## What is done (flowchart, complete vertical slice)

- Parser: hand-written scanner/recursive-descent (`flow_parser.dart`),
  covering the full upstream grammar incl. all 15 shapes, full edge matrix
  (`destructEndLink` semantics ported exactly), subgraphs (nested,
  `direction`), classDef/class/style/linkStyle(+default)/click, `:::`,
  v11 `@{ shape:, label: }` (aliases mapped in `_v11Shapes`; valid-but-
  unported shapes → rect), frontmatter title, directives, comments.
- Layout (`flow_layout.dart`): vendored dagre; upstream shape sizing math;
  d3 curveBasis ported exactly; boundary clipping via intersect ports;
  arrowheads (point/circle/cross, bidirectional); edge labels with dagre
  label positions; compound clusters; **recursive fragment layout** for
  subgraphs whose `direction` differs (they become fixed-size nodes in the
  parent dagre run; cross-boundary edges clip to the cluster rect);
  self-loops as compact right-side cubics (skip dagre).
- Vendored dagre (`lib/src/vendor/dagre/`, from pub `dart_dagre 1.0.0`,
  Apache-2.0, de-Fluttered): **8 porting bugs fixed vs dagre.js** — grep
  `// Vendored fix:` before debugging layout issues; the bug is often here.
  Reference sources: raw.githubusercontent.com/dagrejs/dagre/master/lib/.

## Fidelity workflow (comparing against official mermaid.js)

Render references with mermaid-cli and build side-by-side pairs:
`npx -y @mermaid-js/mermaid-cli -i x.mmd -o ref.png -b white -s 2`, ours via
the offscreen render test, then `magick montage` (see /tmp/fidelity in the
2026-06-10 session, script in git history). A full pass over all samples was
done 2026-06-10; per-type fixes landed for sequence (badges, frame style,
label z-order), class (`name() : ret`), ER (lavender stripes), pie (palette,
black strokes), journey (axis + score-height faces), timeline (arrow axis,
dashed drops), gantt (section tints, axis density), quadrant (label
placement). Remaining known deltas: no text rotation in the IR (quadrant
y-labels horizontal), class note placement, state self-loop label overlap.

## Validation workflow (use it for every change)

1. `cd packages/mermaid_core && dart test` — 143+ tests. Parser tests are
   ported from upstream `flow-*.spec.js`; keep doing this for new diagrams
   (upstream spec files are the executable spec).
2. `dart run tool/validate_corpus.dart [-v]` — runs parse+layout over
   `test/fixtures/upstream_flowcharts/*.mmd` (60 files extracted from
   upstream demos/*.html `<pre class="mermaid">` blocks — extraction snippet
   lives in git history, commit 37eeaf1). **Must stay 60/60.**
   When adding a diagram type, extract its fixtures the same way
   (upstream/demos/sequence.html, classchart.html, ...) into sibling dirs.
3. `cd apps/demo && flutter test test/render_samples_test.dart` — offscreen
   PNG renders of every demo sample to `build/sample_renders/` (loads real
   Trebuchet MS from /System/Library/Fonts/Supplemental). Eyeball them.
4. `flutter analyze` everywhere; zero issues is the bar.
5. Visual: `cd apps/demo && flutter run -d macos`, then connect via dart MCP
   (`dtd listDtdUris` → connect → `flutter_driver_command screenshot`).

## Recipe for porting a new diagram type

1. Read upstream grammar (`packages/mermaid/src/diagrams/<type>/parser/*.jison`
   or langium in `packages/parser`) and the `*Db.ts` + `*Renderer.ts`.
2. Create `lib/src/diagrams/<type>/<type>_model.dart` — immutable model of
   the facts the db captures (skip presentation state).
3. `<type>_parser.dart` — hand-written, line/scanner based;
   `MermaidParseException` with line numbers; port spec cases from upstream
   `*.spec.js` as the test suite.
4. `<type>_layout.dart` — emits RenderScene. Bespoke layouts (sequence,
   gantt, pie) compute positions directly; graph-like ones reuse the
   vendored dagre + the shape/intersect/curveBasis helpers in flow_layout
   (extract shared helpers rather than duplicating).
5. Wire into `detect.dart` (regex, priority order matters — see upstream
   diagram-orchestration.ts) and the `Mermaid.render` switch.
6. Fixtures from upstream demos + validator dir; demo app sample; offscreen
   render test entry.

## Status / next steps (in order)

- [x] Flowchart slice — 60/60 corpus, incl. v11 `@{shape}`, self-loops,
  per-subgraph direction (recursive fragments), edge→subgraph-id endpoints
  (representative member + clip at cluster rect).
- [x] Demo auto-fit scaling (FittedBox toggle vs InteractiveViewer).
- [x] **Sequence diagram** (`diagrams/sequence/`) — 9/9 corpus, 61 tests.
  Participants/actors, full arrow matrix, +/- and explicit activations
  (nested bars), notes, loop/alt/opt/par/critical/break/rect with nesting,
  autonumber badges, self-messages, mirrored actor boxes. Gaps: `box`
  participant grouping parsed-but-ignored, create/destroy lifecycle,
  message-x not offset by activation bar width, par_over.
- [x] **Class diagram** (`diagrams/class_diagram/`) — 16/16 corpus, 51
  tests. Members (visibility/static/abstract/generics incl. nesting), full
  relation marker matrix, cardinalities, namespaces (nested, labeled),
  notes, classDef/style. Gaps: static underline (IR has no underline),
  lollipop is plain circle, interaction/links ignored.
- [x] Shared scene helpers in `ir/scene_utils.dart` (bounds/translate) —
  use them for new diagrams; flow_layout still has private copies.
- [x] **State diagram** (`diagrams/state/`) — 8/8 corpus, 29 tests.
  States/transitions, scoped `[*]` start/end, composites (nested, cluster
  rect from descendant bounds — dagre's own cluster position is unreliable
  with boundary-crossing edges), choice/fork/join, notes, self-transitions
  on composites. Gaps: concurrency `--` regions laid out together (not
  split), `:::` on states, history states.
- [x] Demo polish: live editing keeps the last good scene with an error
  chip overlay (MermaidDiagram.keepLastGoodSceneOnError); style editor
  drawer (MermaidTheme.copyWith + ==) with per-color hex fields and font
  size, applied live.
- [x] **ER diagram** (`diagrams/er/`) — 6/6 corpus. Entity tables
  (type/name/keys/comment columns, row striping), crow's foot markers,
  symbol + word-form cardinalities, identifying/non-identifying lines.
- [x] **Pie chart** (`diagrams/pie/`) — slices via bezier arcs, in-slice
  percentages, legend with showData. Palette approximates theme pie1..12.
- [x] **Gantt** (`diagrams/gantt/`) — 9/9 corpus. Own mini date engine
  (`gantt_dates.dart`: dayjs-style dateFormat parse, strftime-lite
  axisFormat, durations) — no dayjs dependency. Sections/bands, tags
  (done/active/crit/milestone), `after` deps, auto ticks. Gaps: excludes/
  weekends, todayMarker, compact mode; lenient on unparseable metadata
  (matches upstream demos which contain typos).
- [x] **SVG backend** (`src/render/svg_renderer.dart`) — renderSceneToSvg
  for all diagram types from pure Dart; `dart run tool/render_svg.dart
  file.mmd > out.svg`. Gap: soft-wrap points are not in the IR, so SVG
  text wraps only at explicit \n (Flutter painter re-wraps correctly).
- [x] **Quadrant / journey / timeline** (single-file diagrams under
  `diagrams/<type>/<type>.dart`) — 2+1+3 corpus fixtures, 9 tests.
  Journey draws score faces + actor legend; timeline stacks events under
  period boxes; quadrant has no text rotation (y labels sit left of plot).
  Frontmatter fences may be indented (detect.dart tolerates).
- [x] **Comparison website** (`apps/website`, Jaspr static + `apps/flutter_embed`):
  side-by-side mermaid.js (CDN) vs mermaid dart (embedded Flutter web view,
  JS-interop bridge in web/embed_bridge.js + custom flutter_bootstrap.js
  template). Build: `tool/build_website.sh` → apps/website/build/jaspr.
- [x] **xychart / mindmap / requirement / C4** (single-file ports) —
  21+2+2+5 corpus fixtures, 12 tests. xychart matches upstream palette
  (pale lavender bars, grey line) and nice tick steps; mindmap uses a
  deterministic **radial** tree (angular sectors ∝ leaf count; upstream is
  force-directed — same look without the simulation); C4 boundaries via
  member-bounds dashed rects. Mindmap has visual parity with upstream:
  saturated section palette sampled from the real render, depth-lightened
  fills, drop-shadow strip, luminance-based label text, tapering edges.
  Gaps: xychart `horizontal` parsed-but-ignored, mindmap icons/classes
  skipped, C4 UpdateRelStyle/Lay_* hints ignored.
- [x] **gitGraph** (`diagrams/git/git_graph.dart`, single file) — 33/33
  corpus fixtures (extracted from upstream demos/git.html), 7 tests.
  commit (id/type/tag), branch, checkout/switch, merge (id/type/tag),
  cherry-pick; LR (default) + TB direction; lane-per-branch temporal
  layout (x = insertion seq); commit types normal/reverse(crossed)/
  highlight(square); merge = hollow ring; branch-point + merge edges;
  tag flags; branch labels with luminance-based text. Palette sampled
  from upstream default-theme render (git0 #0000ec, git1 #dede00, …).
  Gaps: parallelCommits/rotateCommitLabel/showCommitLabel config,
  cherry-pick parent arrows, BT/RL treated as TB/LR.
- [x] Website covers all samples; per-chart visual comparison done
  against mermaid.js in-browser (fidelity passes #2–4). Embed app fix:
  FittedBox must not sit inside an unbounded scroll view or tall diagrams
  clip. Docs-style page: samples carry a category + one-line description;
  chips grouped under Diagrams / Charts & data / Theming, with the diagram
  name + description shown above the side-by-side panes.
- [x] **Theme directives** (`src/directives.dart`): `%%{init}%%` with
  `theme` (default/dark/forest/neutral) + `themeVariables` (loose-JSON
  tolerated), frontmatter `config.theme`. primaryColor drives mainBkg like
  upstream theme-base. Dark theme paints no background (matches mermaid.js
  on-page look). Styled comparison samples on the website (dark, forest,
  custom variables, classDef).
- [ ] Long tail (upstream has these, not yet ported): sankey, block,
  packet, kanban, architecture, radar, treemap, and niche ones (cynefin,
  eventmodeling, ishikawa, railroad, swimlanes, venn, wardley, zenuml).
  gitGraph (previously listed) is now done.
- [ ] Frontmatter `config.themeVariables` (nested YAML) not yet parsed.
- [ ] Consolidate the per-diagram private copies of curveBasis/intersect
  into a shared edges util (3 copies now).
- [ ] SVG backend in mermaid_core (scene → SVG string; enables golden
  diffs against upstream).
- [x] **CLI** (`bin/mermaid.dart`, executable `mermaid_dart`): reads file or
  stdin, writes SVG (native) or PNG (pipes the SVG through rsvg-convert/
  resvg/ImageMagick on PATH), `--theme`, `-o`, `-f`.
- [x] **Release prep for mermaid_core**: LICENSE (MIT + mermaid/dagre
  attribution), real README, 0.1.0 CHANGELOG, example/, pubspec metadata
  (description/repository/topics/executables, dropped `publish_to:none`).
  `dart pub publish --dry-run` → **0 warnings**. NOTE: set the real
  `repository` URL before publishing (placeholder `makevisible/mermaid_dart`).
  `mermaid_flutter` can't publish until `mermaid_core` is on pub (path dep).

## Requested advanced features (2026-06-13) — scoped roadmap

User asked for five v11-era rendering features, each verified for parity
against mermaid.js. Difficulty/approach below; ordered easiest → hardest.
All key off resolved config (`%%{init}%%` / frontmatter `config:`), so the
shared groundwork is a **MermaidConfig** carrying `look`, `handDrawnSeed`,
`layout`, `fontConfig`, `icons` — extend `src/directives.dart` to surface
it alongside the theme.

- [x] **Hand-drawn look** (`look: 'handDrawn'`, `handDrawnSeed`) — DONE
  (`src/render/rough.dart`). Deterministic scene→scene "roughen" pass: a
  seeded LCG perturbs every filled/stroked shape into hachure fill lines
  (−41°, gap 5.2, fillWeight 4) plus a doubled sketchy outline; beziers in
  edge paths are flattened then re-sketched. Wired via `resolveLook()`
  (init directive + frontmatter `look`/`handDrawnSeed`) and the render
  facade post-process. Matches upstream roughjs defaults; verified
  side-by-side on the website. 9 tests. Gap: rough's overshoot at corners
  is approximated (single cubic per edge, not rough's 2-segment curve).
- [x] **Icons** (`registerIconPacks`, iconify packs; `@{ icon: "prefix:name" }`)
  — DONE for flowchart. `src/icons/svg_path.dart` parses SVG path `d`
  strings via the `path_parsing` dep (arcs/quadratics → cubics);
  `src/icons/icon_registry.dart` has `registerIconPack`/`lookupIcon`/
  `renderIcon` (fit + center glyph, fill each `<path>`) + a built-in
  `icon:` pack (cloud/database/star/heart/cog). Flowchart: `FlowNode.icon`,
  parser captures `@{ icon: }`, layout reserves a 36px glyph square above
  the label. 7 tests. Gaps: architecture-diagram icons (needs that diagram);
  website side-by-side parity needs the mermaid.js embed to register the
  SAME pack (it ships none) — verified via standalone render instead.
- [x] **Math** (`$$...$$` in labels; upstream uses KaTeX) — DONE for the
  common+complex constructs. `src/math/tex_math.dart` lays out TeX with
  **low-level scene primitives** (glyph SceneText + rule/bracket SceneShape),
  so it renders in every backend incl. SVG — no widget/webview. Supports:
  `^`/`_`, `\frac`, `\sqrt`, grouping, greek/operator symbols, `\text`/
  `\mathrm`, `\overbrace`/`\underbrace` (compose with `^`/`_` labels),
  `\vec`/`\hat`/`\bar`/`\overline` accents, and environments
  `\begin{matrix|bmatrix|pmatrix|vmatrix|Bmatrix|cases}` (rows `\\`, cols
  `&`, sized delimiters drawn as paths). Wired into whole-`$$` flowchart
  **node AND edge** labels. The full canonical mermaid math example renders;
  verified side-by-side. 10 tests.
  - Italic single-letter variables; upright+spaced function names; `\sqrt`
    drawn as a connected radical path (checkmark→overline, sized to the
    radicand — like flutter_math/KaTeX, not a glyph); `\left<d>…\right<d>`
    auto-sized delimiters; `\begin{array}{spec}` with column alignment;
    `\vec/\hat/\bar/\overline`; spacing macros (`\,\:\;\quad`); ~90-symbol
    table (full greek, `\nabla \hbar \Psi \partial`, set/logic/arrow ops,
    dots). The Maxwell / Schrödinger / quadratic-formula examples render.
  - `flutter_tex` rejected for IR use (MathJax+webview widget, no pure-Dart
    TeX→SVG string); `flutter_math_fork` was the inspiration for the
    path-drawn radical.
  - Remaining gaps: inline mixed text+math in one label (only whole-`$$`
    labels), big-operator limits (`\sum_{i=1}^n` stacks), KaTeX's actual math
    font (we italicize the label font). Font parity in the Flutter target
    would want `flutter_math_fork` (paints widgets, not scene IR).
- [ ] **Other layout engines** (`layout: 'elk' | 'tidy-tree' | 'cose-bilkent'`).
  *Very high — the big rock.* Upstream registers pluggable layout loaders
  (`rendering-util/render.ts registerLayoutLoaders`); elk is the
  GWT-compiled elkjs, cose-bilkent a cytoscape extension — neither has a
  Dart port. Realistic paths: port elkjs to Dart (months), a web-only
  JS-interop bridge to elkjs (defeats pure-Dart goal), or write a simpler
  layered alternative that won't match elk pixel-for-pixel. Recommend
  deferring or doing a JS-bridge spike for the website only.
- [ ] **Architecture layout tuning** (v11.15.0: `{group}` placement, edge
  direction hints L/R/T/B, junctions). *Blocked on prerequisite.* These
  knobs belong to the **architecture** diagram, which isn't ported yet.
  Two steps: port architecture (`diagrams/architecture/`), then its tuning.

## Known gaps / quirks

- Novel v11 geometries (doc, hourglass, braces, ...) render as rect
  (`_knownUnsupportedV11Shapes`).
- `linkStyle ... interpolate X` parsed but curve is always basis.
- Click links are stored in the model but not yet surfaced as tap targets
  in MermaidDiagram (SceneGroup.id exists for hit-testing).
- ApproximateTextMeasurer is Helvetica-metrics; fine for tests, not pixel
  exact vs TextPainter — never assert exact pixel positions in core tests.
- Background agents in this environment tend to get killed; prefer inline
  work or foreground agent batches.

## Conventions

- Tests import `package:mermaid_core/src/...` files directly (not the
  barrel).
- Upstream-derived behavior gets a comment pointing at the upstream file.
- Vendored-code fixes are marked `// Vendored fix:` with rationale.
- Commits: imperative subject + short why-body.

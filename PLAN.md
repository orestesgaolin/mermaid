# Mermaid → Dart port: plan & handoff

A Flutter-first Dart port of [mermaid-js](https://github.com/mermaid-js/mermaid).
**Read this before touching the code.** Updated: 2026-06-10.

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

- [x] Flowchart slice (see above) — 60/60 corpus.
- [x] Demo auto-fit scaling.
- [ ] **Edge→subgraph-id endpoints** (`a --> subgraphId`): for isolated
  (direction-differing) clusters this already works (synthetic node). For
  compound clusters: route dagre edge to a representative member node, then
  clip the rendered path at the stored cluster rect, arrow on the border
  (upstream does the same in mermaid-graphlib `adjustClustersAndEdges`).
- [ ] **Sequence diagram** — biggest value. Upstream: jison 420 lines,
  bespoke renderer 2150 lines. Subset for v1: participants/actors (order,
  aliases, create/destroy later), all message arrows (solid/dotted ×
  filled/open/cross/async, +/- activations), activation bars (stacked),
  notes (left of/right of/over A,B), blocks: loop/alt+else/opt/par+and/
  critical/break with nesting, autonumber, title. Layout: column per
  participant (header boxes top + repeated bottom), x = max label widths;
  y advances per event; self-messages bend right; block frames with
  pentagon label tab.
- [ ] **Class diagram** — jison 440 lines. Classes (fields/methods,
  +-#~ visibility, static/abstract markers, generics `~T~`), relations
  (`<|--`, `*--`, `o--`, `-->`, `..>`, `..|>`, `--`), labels + cardinality
  strings, namespaces later. Layout: dagre with rect nodes of 3 compartments;
  markers: hollow triangle, filled/hollow diamond, plain arrow.
- [ ] State diagram (reuses much of class/flow machinery), ER, gantt
  (needs a date lib decision — `package:intl` likely enough), pie (trivial).
- [ ] SVG backend in mermaid_core (scene → SVG string; good for golden
  diffs against upstream too).
- [ ] Publishing prep: rename vendored dagre exports out of the public API,
  README, licenses (NOTICE for dagre port), pub.dev scores.

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

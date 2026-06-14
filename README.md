# mermaid_dart

A **pure-Dart, Flutter-first port of [mermaid.js](https://github.com/mermaid-js/mermaid)** — parse a Mermaid source string and render it natively, no JavaScript, no WebView, no SVG round-trip.

It detects, parses and lays out **28 diagram types** into a backend-agnostic *render scene*, then paints that scene either with Flutter's canvas (`mermaid_flutter`) or as an SVG string / CLI (`mermaid_core`).

```dart
import 'package:flutter/material.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

const diagram = MermaidDiagram(source: '''
graph TD
  A[Start] --> B{Works?}
  B -->|yes| C[Ship it]
  B -->|no| A
''');
```

## Supported diagrams (28)

flowchart · sequence · class · state · ER · pie · gantt · quadrant · journey ·
timeline · xychart · mindmap · requirement · C4 · gitGraph · sankey · packet ·
block · radar · treemap · kanban · architecture · cynefin · venn · ishikawa ·
wardley · eventModeling · railroad

Plus `%%{init}%%` / frontmatter **theme directives** (default/dark/forest/neutral
+ `themeVariables`), the sketchy **`look: handDrawn`** style (a faithful roughjs
port), iconify-style **icons** on nodes, **math** in labels (`$$…$$`, a TeX
subset), and the **`elk` / `tidy-tree`** alternate layout engines.

## Packages

| Package | Pub | What it is |
|---|---|---|
| [`mermaid_core`](packages/mermaid_core) | publishable | Pure-Dart engine: detect → parse → typed model → layout → `RenderScene`, an SVG renderer, and the `mermaid_dart` CLI. No Flutter. |
| [`mermaid_flutter`](packages/mermaid_flutter) | publishable | `MermaidDiagram` widget + `ScenePainter` (a `CustomPainter`) and `TextPainter`-based text measurement for pixel-accurate native rendering. |
| `mermaid_samples` | internal | Shared catalogue of example diagrams reused by the demo, website and tests. |

`mermaid_flutter` depends on `mermaid_core`, so `mermaid_core` publishes first.

## Apps

| App | What it is |
|---|---|
| [`apps/demo`](apps/demo) | macOS desktop app: a live source editor with a preview pane and a theme editor, showcasing all 28 types. |
| [`apps/website`](apps/website) | Static [Jaspr](https://jaspr.site) site rendering mermaid.js (CDN) and this port **side by side** for visual parity comparison — **[live demo](https://roszkowski.dev/mermaid/)**. The Dart renderer is embedded with [`jaspr_flutter_embed`](https://pub.dev/packages/jaspr_flutter_embed), so a single `jaspr build` produces the whole site (Flutter web build included). |

## Architecture

An immutable pipeline, each stage independently testable:

```
source → parse → typed model → measure (TextMeasurer) → layout → RenderScene IR → backend
                                                                                   ├── ScenePainter (Flutter)
                                                                                   └── renderSceneToSvg (SVG/CLI)
```

The `RenderScene` is a backend-agnostic tree of shapes, paths and text in
absolute coordinates. Text measurement is pluggable: `ApproximateTextMeasurer`
(Helvetica metrics, good for SVG and tests) or `FlutterTextMeasurer`
(`TextPainter`, pixel-accurate in an app).

## Development

This is a Dart [pub workspace](https://dart.dev/tools/pub/workspaces); resolve
everything from the root:

```console
$ dart pub get
```

Common tasks:

```console
# Core engine: analyze, test, corpus validation
$ dart analyze packages/mermaid_core
$ dart test packages/mermaid_core
$ cd packages/mermaid_core && dart run tool/validate_corpus.dart

# CLI: render a .mmd to SVG or PNG
$ cd packages/mermaid_core && dart run bin/mermaid.dart diagram.mmd -o out.svg

# Demo app (macOS)
$ cd apps/demo && flutter run -d macos
```

## Parity

"Parity" here means a structural render-diff plus matching upstream constants,
verified against 184 upstream demo fixtures and by manual side-by-side
comparison with the mermaid.js CDN. Per-diagram parity status and known
residuals live under [`parity/`](parity).

## License

MIT — a port of mermaid.js (MIT). `mermaid_core` vendors a derivative of
`dart_dagre` (Apache-2.0) under `lib/src/vendor/dagre/`, which keeps its own
`LICENSE`.

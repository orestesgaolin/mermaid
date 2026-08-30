# Mermaid for Dart and Flutter

This repository contains a Dart implementation of Mermaid diagram parsing and
layout, plus renderers for SVG and Flutter. It does not use JavaScript, a
WebView, or a browser at runtime.

The [comparison site](https://roszkowski.dev/mermaid/) renders the Dart and
mermaid.js results side by side.

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

## Packages

| Package | Purpose |
| --- | --- |
| [`elk`](packages/elk) | Pure Dart layered graph layout with compound graphs, ports, and orthogonal routing. |
| [`mermaid_core`](packages/mermaid_core) | Mermaid parser, layout engine, render scene, SVG renderer, and command-line tool. |
| [`mermaid_flutter`](packages/mermaid_flutter) | Flutter widgets and a `CustomPainter` renderer for `mermaid_core`. |
| `mermaid_samples` | Internal sample catalogue used by the demo, website, and tests. |

`mermaid_core` supports flowcharts, sequence diagrams, class diagrams, state
diagrams, ER diagrams, pie charts, Gantt charts, quadrant charts, journeys,
timelines, XY charts, mindmaps, requirements, C4, git graphs, Sankey diagrams,
packet diagrams, block diagrams, radar charts, treemaps, Kanban boards,
architecture diagrams, Cynefin diagrams, Venn diagrams, Ishikawa diagrams,
Wardley maps, event modeling, and railroad diagrams.

It also supports Mermaid theme directives, `look: handDrawn`, icons, math in
labels, and the `elk` and `tidy-tree` layout engines.

## Repository layout

- `apps/demo`: macOS editor and preview app
- `apps/website`: side-by-side comparison site
- `packages`: published libraries and shared samples
- `parity`: notes about compatibility with mermaid.js

The rendering pipeline is:

```text
source -> parse -> model -> measure -> layout -> RenderScene -> SVG or Flutter
```

## Development

The repository is a [pub workspace](https://dart.dev/tools/pub/workspaces).
Resolve dependencies from the root:

```console
$ flutter pub get
```

Common checks:

```console
$ dart analyze packages/mermaid_core packages/mermaid_flutter
$ dart test packages/mermaid_core
$ flutter test packages/mermaid_flutter
```

Run the command-line renderer from `packages/mermaid_core`:

```console
$ dart run bin/mermaid.dart diagram.mmd -o diagram.svg
```

Release setup and the tag workflow are documented in
[`RELEASING.md`](RELEASING.md).

## License

MIT. The project contains code derived from mermaid.js (MIT) and dart_dagre
(Apache-2.0); vendored code retains its original license.

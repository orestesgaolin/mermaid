# mermaid_core

A **pure Dart** port of [mermaid.js](https://github.com/mermaid-js/mermaid):
it detects, parses and lays out diagrams into a backend-agnostic *render
scene*, then renders that scene to SVG. No Flutter dependency — pair it with
`mermaid_flutter` for native Flutter painting, or use the built-in SVG
renderer and CLI anywhere Dart runs.

## Supported diagrams (28)

flowchart · sequence · class · state · ER · pie · gantt · quadrant ·
journey · timeline · xychart · mindmap · requirement · C4 · gitGraph ·
sankey · packet · block · radar · treemap · kanban · architecture ·
cynefin · venn · ishikawa · wardley · eventModeling · railroad

Plus: `%%{init}%%` / frontmatter theme directives (default/dark/forest/
neutral + `themeVariables`), the hand-drawn `look: handDrawn` style (a
faithful roughjs port), iconify-style **icons** on flowchart nodes
(`@{ icon: "pack:name" }`), and **math** in labels (`$$...$$` — a TeX subset:
super/subscripts, `\frac`, `\sqrt`, matrices, `cases`, braces, accents).

## Library usage

```dart
import 'package:mermaid_core/mermaid_core.dart';

void main() {
  const mermaid = Mermaid(measurer: ApproximateTextMeasurer());
  final scene = mermaid.render('''
graph TD
  A[Start] --> B{Works?}
  B -->|yes| C[Ship it]
  B -->|no| A
''');
  print(renderSceneToSvg(scene)); // SVG string
}
```

`render()` returns a `RenderScene` (groups of shapes/text in absolute
coordinates). `renderSceneToSvg()` turns it into an SVG string; a Flutter
backend can paint the same scene directly.

> **Text measurement.** `ApproximateTextMeasurer` uses Helvetica metrics —
> good for SVG and tests. For pixel-accurate layout in a Flutter app, use the
> `TextPainter`-backed measurer from `mermaid_flutter`.

## Command-line tool

```console
$ dart pub global activate mermaid_core
$ mermaid_dart diagram.mmd -o out.svg
$ mermaid_dart diagram.mmd -o out.png        # format inferred from extension
$ cat diagram.mmd | mermaid_dart --theme dark
```

PNG output pipes the SVG through the first rasterizer found on `PATH`
(`rsvg-convert`, `resvg`, or ImageMagick `magick`/`convert`).

## Fidelity

Validated against 184 upstream mermaid demo fixtures, and compared
side-by-side with mermaid.js in the browser. Known deltas are tracked in the
project's `parity/` docs (e.g. KaTeX math fonts, ELK layout engine).

## Licensing

MIT. This is a port of mermaid.js (MIT). It vendors a derivative of
`dart_dagre` (Apache-2.0) under `lib/src/vendor/dagre/`, which keeps its own
`LICENSE`.

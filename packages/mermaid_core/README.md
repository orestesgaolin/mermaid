# mermaid_core

`mermaid_core` parses Mermaid source, lays it out, and produces a
backend-independent render scene. It includes an SVG renderer and a
command-line tool and has no Flutter dependency.

See the [live comparison demo](https://roszkowski.dev/mermaid/) for
side-by-side output from this implementation and mermaid.js.

The package currently supports 28 diagram types, Mermaid theme directives,
`look: handDrawn`, icons, math in labels, and alternate ELK and tidy-tree
layouts. Compatibility notes and known differences from mermaid.js are kept in
the repository's [`parity`](../../parity) directory.

## Library use

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

  print(renderSceneToSvg(scene));
}
```

`Mermaid.render` returns a `RenderScene` containing shapes and text in absolute
coordinates. `renderSceneToSvg` serializes that scene to SVG.

`ApproximateTextMeasurer` uses bundled metrics suitable for SVG output and
tests. Flutter applications should use the `TextPainter`-based measurer from
`mermaid_flutter` when their layout must match Flutter font rendering.

## Command-line tool

Activate the package globally:

```console
$ dart pub global activate mermaid_core
$ mermaid_dart diagram.mmd -o diagram.svg
$ cat diagram.mmd | mermaid_dart --theme dark
```

The output format is inferred from the file extension. PNG output requires
`rsvg-convert`, `resvg`, or ImageMagick on `PATH`.

## License

MIT. This package contains code derived from mermaid.js (MIT) and a vendored
derivative of dart_dagre (Apache-2.0). See `LICENSE` and the license under
`lib/src/vendor/dagre`.

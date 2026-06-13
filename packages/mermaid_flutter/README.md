# mermaid_flutter

Native **Flutter** rendering for [`mermaid_core`](https://pub.dev/packages/mermaid_core)
— a pure-Dart port of [mermaid.js](https://github.com/mermaid-js/mermaid).
It pairs `mermaid_core`'s parser/layout with pixel-accurate text measurement
(`TextPainter`) and a `CustomPainter` that paints the render scene directly —
no SVG, no WebView, no platform views.

## Features

- **`MermaidDiagram` widget** — give it a source string, it parses, lays out
  and paints the diagram.
- **Exact text metrics** via `FlutterTextMeasurer` (matches the painter), so
  layout is correct for whatever fonts your app uses.
- **Live-editing friendly** — keeps the last good render on screen with an
  error overlay while you type invalid source (`keepLastGoodSceneOnError`).
- Supports every diagram type and feature `mermaid_core` does: 15 diagram
  types, theme directives, hand-drawn look, icons, and math.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

class Example extends StatelessWidget {
  const Example({super.key});

  @override
  Widget build(BuildContext context) {
    return const MermaidDiagram(
      source: '''
graph TD
  A[Start] --> B{Works?}
  B -->|yes| C[Ship it]
  B -->|no| A
''',
    );
  }
}
```

The widget sizes itself to the diagram. To fit it into a box, wrap it:

```dart
FittedBox(child: MermaidDiagram(source: src))                 // scale to fit
InteractiveViewer(child: MermaidDiagram(source: src))         // pan / zoom
```

### Theming and errors

```dart
MermaidDiagram(
  source: src,
  theme: MermaidTheme.darkTheme,        // or .named('forest'), custom copyWith
  keepLastGoodSceneOnError: true,       // default — great for live editors
  errorBuilder: (context, error) => Text('$error'),
)
```

A `%%{init}%%` directive or frontmatter `config.theme` in the source still
overrides the `theme` argument, just like mermaid.js.

## Lower-level API

`MermaidDiagram` is a thin wrapper. You can also drive the pieces directly:

- `FlutterTextMeasurer` — implements `mermaid_core`'s `TextMeasurer`.
- `ScenePainter` — a `CustomPainter` that paints a `RenderScene`.

```dart
final scene = Mermaid(measurer: const FlutterTextMeasurer()).render(src);
CustomPaint(size: scene.size, painter: ScenePainter(scene));
```

## See also

- [`mermaid_core`](https://pub.dev/packages/mermaid_core) — the pure-Dart
  engine, plus an SVG renderer and the `mermaid_dart` CLI.

## License

MIT (a port of mermaid.js, MIT).

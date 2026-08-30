# mermaid_flutter

`mermaid_flutter` renders Mermaid diagrams with Flutter. It uses
`mermaid_core` for parsing and layout, `TextPainter` for text measurement, and
`CustomPainter` for drawing. It does not use SVG, WebViews, or platform views.

## Basic use

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

`MermaidDiagram` sizes itself to the rendered diagram. `MermaidView` adds a
fitted interactive view with pan, zoom, reset, lock, directional controls, and
a fullscreen dialog:

```dart
SizedBox(
  height: 480,
  child: MermaidView(source: source),
)
```

## Themes and errors

```dart
MermaidDiagram(
  source: source,
  theme: MermaidTheme.darkTheme,
  keepLastGoodSceneOnError: true,
  errorBuilder: (context, error) => Text('$error'),
)
```

Theme directives in the Mermaid source take precedence over the `theme`
argument. With `keepLastGoodSceneOnError`, the widget keeps the previous valid
diagram visible while reporting a new parse error.

For lower-level use, `FlutterTextMeasurer` implements the `mermaid_core`
measurement interface and `ScenePainter` paints a `RenderScene` directly.

## License

MIT. This package is part of a Dart port of mermaid.js, which is also MIT
licensed.

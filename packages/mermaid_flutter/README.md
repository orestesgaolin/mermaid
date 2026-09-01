# mermaid_flutter

`mermaid_flutter` renders Mermaid diagrams with Flutter. It uses
`mermaid_core` for parsing and layout, `TextPainter` for text measurement, and
`CustomPainter` for drawing. It does not use SVG, WebViews, or platform views.

See the [live comparison demo](https://roszkowski.dev/mermaid/) for
side-by-side output from this implementation and mermaid.js.

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

Use `MermaidViewController` when an application needs to follow a changing
node or control the viewport. Controller commands wait for the updated diagram
layout and return `false` when the view is detached, layout is unavailable, or
the node id is unknown.

```dart
final controller = MermaidViewController();

MermaidView(source: source, controller: controller);

await controller.focusNode('current_step', zoom: 1.5);
await controller.fitAll(animate: false);
controller.addListener(() {
  final matrix = controller.transformation; // A read-only snapshot.
});
```

A controller attaches to one view at a time. Remove the view before reusing
the controller elsewhere, and dispose the controller when its owner is done.

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

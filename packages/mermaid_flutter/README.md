# mermaid_flutter

`mermaid_flutter` renders Mermaid diagrams with Flutter. It uses
`mermaid_core` for parsing and layout, `TextPainter` for text measurement, and
`CustomPainter` for drawing. It does not use SVG, WebViews, or platform views.

See the [live comparison demo](https://roszkowski.dev/mermaid/) for
side-by-side output from this implementation and mermaid.js.

## Basic use

```dart
import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
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

Flowchart highlights can change without parsing or laying out the source
again. Use resolved node ids and Mermaid link declaration indices:

```dart
MermaidView(
  source: structuralSource,
  controller: controller,
  nodePaintOverrides: {
    currentNodeId: const core.FlowNodePaintOverride(
      fill: core.Color(0xffffcc00),
      stroke: core.Color(0xffcc3300),
      textColor: core.Color(0xff112233),
    ),
  },
  linkPaintOverrides: {
    activeLinkIndex: const core.FlowLinkPaintOverride(
      stroke: core.Color(0xff0066ff),
      strokeWidth: 4,
    ),
  },
  onNodeTap: (id, _) => controller.focusNode(id),
  onEdgeTap: (from, to, linkIndex) {
    // Show transition metadata and update linkPaintOverrides.
  },
)
```

Changing `source` or `theme` still performs a complete render. The demo app
combines these overrides with node focus, edge metadata, and fit controls.

Desktop and web applications can expose node hover state without adding a
widget per node. Hover uses the same scene bounds and paint-order precedence as
node taps. The tooltip is an overlay and does not change diagram geometry.

```dart
MermaidView(
  source: source,
  onNodeHover: (id) => hoveredNodeId.value = id,
  hoverCursor: SystemMouseCursors.click,
  nodeTooltipBuilder: (context, id) => Card(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Text('Node $id'),
    ),
  ),
)
```

Accessibility nodes are opt-in. Each id-carrying diagram node exposes its
human label, stable id, and painted bounds. A tap action is included when
`onNodeTap` is supplied. Decorative groups, edges, and edge labels are omitted.
Flowchart traversal follows source declaration order.

```dart
MermaidView(
  source: source,
  semanticNodes: true,
  onNodeTap: (id, link) {
    // Screen-reader activation and pointer taps use the same callback.
  },
)
```

Widget tests can use `find.bySemanticsLabel('Start')` or
`find.bySemanticsIdentifier('node_id')`. The option is off by default, so
existing rendering and interaction costs do not change.

## Headless PNG export

Export source or a previously rendered scene without mounting a widget tree:

```dart
final png = await renderToPng(
  source,
  pixelRatio: 2,
  theme: core.MermaidTheme.darkTheme,
  nodePaintOverrides: highlightedNodes,
  linkPaintOverrides: highlightedLinks,
);
```

`renderToPng` and `renderSceneToPng` require a Flutter runner such as
`flutter test` or `flutter_tester`; they do not run in a pure Dart VM process.
Registered Flutter fonts determine text metrics and output, so load custom
fonts before export. Parse, layout, rasterization, and encoding failures are
preserved. Runtime renderer limits may be lower than the API's preflight size
limits.

## Themes and errors

```dart
final mermaidTheme = MaterialMermaidTheme.fromTheme(Theme.of(context));

MermaidDiagram(source: source, theme: mermaidTheme)
```

`MaterialMermaidTheme` maps Material surface, container, outline, text, and
categorical color roles to all supported Mermaid diagram palettes. Switching
the surrounding `ThemeData` between light and dark therefore updates diagram
colors without consumer-side field mapping. You can also use
`MaterialMermaidTheme.fromColorScheme(colorScheme, textTheme: textTheme)`.

When a `TextTheme` is supplied, `bodyMedium.fontFamily` and
`bodyMedium.fontSize` become the Mermaid font settings. Text metrics are part
of diagram layout, so changing either value can change node sizes and edge
routing. Without a `TextTheme`, Mermaid's platform-independent font defaults
are retained.

Theme directives in source still take precedence over the widget `theme`.
Theme-token references inside source styles are not currently supported.

Error handling remains independent of theme selection:

```dart
MermaidDiagram(
  source: source,
  theme: mermaidTheme,
  keepLastGoodSceneOnError: true,
  errorBuilder: (context, error) => Text('$error'),
)
```

With `keepLastGoodSceneOnError`, the widget keeps the previous valid diagram
visible while reporting a new parse error.

For lower-level use, `FlutterTextMeasurer` implements the `mermaid_core`
measurement interface and `ScenePainter` paints a `RenderScene` directly.

## License

MIT. This package is part of a Dart port of mermaid.js, which is also MIT
licensed.

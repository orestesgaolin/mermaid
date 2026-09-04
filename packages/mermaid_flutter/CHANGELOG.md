## 0.2.0

**Behavior changes**

- `onNodeTap` now fires only for diagram nodes (`SceneGroupRole.node`).
  Sequence frames, class namespaces, composite states, C4 boundaries, journey
  sections, and pie legend entries are no longer tap targets.
- Requires `mermaid_core` 0.2.0.

**Changes**

- Preserve requested monospace fonts and add platform symbol-font fallbacks for
  Unicode diagram labels.
- Add `MermaidViewController` with observable transforms, animated or immediate
  fit, and focus-by-node-id support.
- Add `MermaidDiagram.onSceneChanged` for access to post-layout scene geometry.
- Add `onEdgeTap` to `MermaidDiagram` and `MermaidView`, with precise stroke
  and label hit testing and stable Mermaid link indices.
- Add paint-only flowchart node and link overrides to `MermaidDiagram` and
  `MermaidView`; override changes reuse the parsed and laid-out base scene.
- Add desktop/web node hover callbacks, node-only cursors, and optional tooltip
  overlays to `MermaidDiagram` and `MermaidView`.
- Add opt-in node semantics with human labels, stable identifiers, transformed
  bounds, deterministic traversal, and accessible tap actions.
- Add headless `renderToPng` and `renderSceneToPng` APIs for Flutter runners.
- Add `MaterialMermaidTheme.fromTheme` and `fromColorScheme` to map Material
  colors and text roles to a light or dark `MermaidTheme`.
- Render gradient strokes and multiply-composited links consistently in
  `ScenePainter` and headless PNG output.
- Keep node, edge, hover, semantics, and scene callbacks working when
  paint-only overrides change.
- The built-in fullscreen popup uses the view's own `padding`, `zoomStep`,
  `panStep`, and `showControls` instead of falling back to the defaults.
- Refresh the pub.dev screenshots for the corrected layouts.

## 0.1.2

- Update `mermaid_core` to 0.1.2 for corrected flowchart, Event Modeling,
  Kanban, and C4 layouts.

## 0.1.1

- Make arrow controls move the viewport in the direction shown.
- Re-fit the diagram after viewport size changes, including when closing the
  fullscreen view.

## 0.1.0

Initial release.

- `MermaidDiagram` widget: parses, lays out and paints any `mermaid_core`
  diagram natively (no SVG/WebView).
- `FlutterTextMeasurer` (TextPainter-based) and `ScenePainter` (CustomPainter)
  for lower-level use.
- Live-editing support: keeps the last good render with an error overlay.
- Theme argument plus `%%{init}%%`/frontmatter overrides.

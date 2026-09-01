## Unreleased

- Add `MermaidViewController` for observable viewport transforms, animated or
  immediate fit, and node focus by id.
- Add `MermaidDiagram.onSceneChanged` for post-layout scene geometry access.

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

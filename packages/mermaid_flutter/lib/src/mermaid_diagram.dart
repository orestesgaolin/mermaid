/// High-level widget: mermaid source in, painted diagram out.
library;

import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;

import 'flutter_text_measurer.dart';
import 'scene_painter.dart';

/// Renders a mermaid diagram from [source].
///
/// The scene is built synchronously in [State.build] and memoized on
/// `(source, theme)`. While the user is editing, a syntax error does not
/// blank the diagram: the last successfully rendered scene stays visible
/// (slightly dimmed) with a compact error overlay, so previews update in
/// real time without flicker. Set [keepLastGoodSceneOnError] to false to
/// always replace the diagram with [errorBuilder]'s widget instead.
class MermaidDiagram extends StatefulWidget {
  const MermaidDiagram({
    super.key,
    required this.source,
    this.theme = core.MermaidTheme.defaultTheme,
    this.errorBuilder,
    this.keepLastGoodSceneOnError = true,
    this.onNodeTap,
  });

  /// Called when a node/group is tapped, with its id and optional click link
  /// (from a flowchart `click`/`href`). Only fires for groups carrying an id
  /// or a link. Use it to open links or drive selection.
  final void Function(String id, String? link)? onNodeTap;

  /// Mermaid diagram source text.
  final String source;

  /// Resolved mermaid theme used for layout and painting.
  final core.MermaidTheme theme;

  /// Builds the widget shown when rendering fails and no previous good
  /// scene exists (or [keepLastGoodSceneOnError] is false). Receives the
  /// thrown error (e.g. `MermaidParseException`, `UnsupportedError`).
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Keep showing the last successful render (with an error overlay) when
  /// the current source fails to parse or lay out.
  final bool keepLastGoodSceneOnError;

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  String? _builtSource;
  core.MermaidTheme? _builtTheme;
  core.RenderScene? _scene;
  Object? _error;

  void _rebuildSceneIfNeeded() {
    if (_builtSource == widget.source && _builtTheme == widget.theme) {
      return;
    }
    _builtSource = widget.source;
    _builtTheme = widget.theme;
    try {
      _scene = core.Mermaid(
        measurer: const FlutterTextMeasurer(),
        theme: widget.theme,
      ).render(widget.source);
      _error = null;
    } catch (error) {
      // Keep _scene: the last good render stays visible during editing.
      _error = error;
      if (!widget.keepLastGoodSceneOnError) _scene = null;
    }
  }

  /// Finds the topmost (last-painted) group with an id/link whose bounds
  /// contain [p]. Returns (id, link) or null.
  (String, String?)? _hitTest(List<core.SceneNode> nodes, Offset p) {
    (String, String?)? found;
    void walk(List<core.SceneNode> ns) {
      for (final n in ns) {
        if (n is core.SceneGroup) {
          if (n.id != null || n.link != null) {
            final b = core.sceneBounds(n.children);
            if (b != null &&
                p.dx >= b.left &&
                p.dx <= b.right &&
                p.dy >= b.top &&
                p.dy <= b.bottom) {
              // Later in paint order wins; keep updating.
              found = (n.id ?? '', n.link);
            }
          }
          walk(n.children);
        }
      }
    }

    walk(nodes);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    _rebuildSceneIfNeeded();

    final error = _error;
    final scene = _scene;
    if (scene == null) {
      final builder = widget.errorBuilder;
      if (error == null) return const SizedBox.shrink();
      if (builder != null) return builder(context, error);
      return _DefaultErrorPanel(error: error);
    }

    final background = scene.background;
    Widget paint = CustomPaint(
      painter: ScenePainter(scene),
      size: Size(scene.size.width, scene.size.height),
    );
    final onNodeTap = widget.onNodeTap;
    if (onNodeTap != null) {
      paint = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final hit = _hitTest(scene.nodes, d.localPosition);
          if (hit != null) onNodeTap(hit.$1, hit.$2);
        },
        child: paint,
      );
    }
    Widget diagram = SizedBox(
      width: scene.size.width,
      height: scene.size.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background != null ? Color(background.value) : null,
        ),
        child: paint,
      ),
    );

    if (error != null) {
      // Stale render: dim it and pin a compact error chip on top.
      diagram = Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(opacity: 0.45, child: diagram),
          Positioned(
            left: 0,
            top: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: scene.size.width.clamp(200.0, 460.0)),
              child: _ErrorChip(error: error),
            ),
          ),
        ],
      );
    }
    return diagram;
  }
}

class _ErrorChip extends StatelessWidget {
  const _ErrorChip({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xEEFFF1F1),
        border: Border.all(color: const Color(0x88CC3333)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$error',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFFB00020), fontSize: 11),
      ),
    );
  }
}

class _DefaultErrorPanel extends StatelessWidget {
  const _DefaultErrorPanel({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: const Color(0x14FF0000),
        border: Border.all(color: const Color(0x66FF0000)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        '$error',
        style: const TextStyle(color: Color(0xFFB00020), fontSize: 13),
      ),
    );
  }
}

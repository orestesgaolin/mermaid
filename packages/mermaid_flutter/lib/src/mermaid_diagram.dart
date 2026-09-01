/// High-level widget: mermaid source in, painted diagram out.
library;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;

import 'flutter_text_measurer.dart';
import 'scene_painter.dart';

typedef MermaidSceneRenderer = core.RenderScene Function(
  String source,
  core.MermaidTheme theme,
);

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
    this.onEdgeTap,
    this.onSceneChanged,
    this.nodePaintOverrides = const {},
    this.linkPaintOverrides = const {},
    this.sceneRenderer,
  });

  /// Called when a diagram node is tapped, with its id and optional click link
  /// (from a flowchart `click`/`href`). Only [core.SceneGroupRole.node] groups
  /// carrying an id or link are interactive here; clusters, annotations, edge
  /// strokes, and edge labels do not invoke this callback.
  final void Function(String id, String? link)? onNodeTap;

  /// Called when a flowchart edge stroke or label is tapped.
  ///
  /// Stroke hit testing extends 8 logical pixels in scene space beyond the
  /// painted half-width. Dashed strokes use a continuous centreline hit area.
  /// Node hit regions take precedence when they overlap an edge.
  final void Function(String fromId, String toId, int linkIndex)? onEdgeTap;

  /// Called after the frame when a new source and theme produce a render scene.
  ///
  /// This is primarily useful to coordinate scene-space geometry with a
  /// surrounding viewport. The callback is not repeated for ordinary widget
  /// rebuilds that reuse the same scene, and it is not called for a failed
  /// render that keeps the last good scene visible. It is safe for this
  /// callback to update widget state.
  final ValueChanged<core.RenderScene>? onSceneChanged;

  /// Resolved paint-only flowchart node updates keyed by node id.
  ///
  /// Updating this map reuses the parsed and laid-out base scene. Source and
  /// theme changes still run the complete renderer.
  final Map<String, core.FlowNodePaintOverride> nodePaintOverrides;

  /// Resolved paint-only flowchart edge updates keyed by Mermaid link index.
  final Map<int, core.FlowLinkPaintOverride> linkPaintOverrides;

  /// Optional full-scene renderer, useful for instrumentation and custom
  /// renderer ownership. A change to this callback rebuilds the base scene,
  /// so callers must retain the same callback instance across widget rebuilds.
  final MermaidSceneRenderer? sceneRenderer;

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
  core.RenderScene? _baseScene;
  Object? _error;
  core.RenderScene? _deliveredScene;
  int _sceneGeneration = 0;
  MermaidSceneRenderer? _builtRenderer;
  Map<String, core.FlowNodePaintOverride> _builtNodeOverrides = const {};
  Map<int, core.FlowLinkPaintOverride> _builtLinkOverrides = const {};

  void _rebuildSceneIfNeeded() {
    final renderer = widget.sceneRenderer;
    final rebuildBase = _builtSource != widget.source ||
        _builtTheme != widget.theme ||
        _builtRenderer != renderer;
    if (rebuildBase) {
      _builtSource = widget.source;
      _builtTheme = widget.theme;
      _builtRenderer = renderer;
      _sceneGeneration++;
      try {
        _baseScene = renderer?.call(widget.source, widget.theme) ??
            core.Mermaid(
              measurer: const FlutterTextMeasurer(),
              theme: widget.theme,
            ).render(widget.source);
        _error = null;
      } catch (error) {
        // Keep the last good render visible during editing.
        _error = error;
        if (!widget.keepLastGoodSceneOnError) {
          _baseScene = null;
          _scene = null;
        }
      }
    }

    final nodeOverrides = {
      for (final entry in widget.nodePaintOverrides.entries)
        entry.key: _snapshotNodeOverride(entry.value),
    };
    final linkOverrides = {
      for (final entry in widget.linkPaintOverrides.entries)
        entry.key: _snapshotLinkOverride(entry.value),
    };
    final overridesChanged = !mapEquals(_builtNodeOverrides, nodeOverrides) ||
        !mapEquals(_builtLinkOverrides, linkOverrides);
    if ((rebuildBase && _error == null) || overridesChanged) {
      _builtNodeOverrides = nodeOverrides;
      _builtLinkOverrides = linkOverrides;
      final base = _baseScene;
      if (base != null) {
        _scene = core.applyFlowchartPaintOverrides(
          base,
          nodes: nodeOverrides,
          links: linkOverrides,
        );
      }
    }
  }

  core.FlowNodePaintOverride _snapshotNodeOverride(
    core.FlowNodePaintOverride value,
  ) =>
      core.FlowNodePaintOverride(
        fill: value.fill,
        stroke: value.stroke,
        strokeWidth: value.strokeWidth,
        strokeDash: value.strokeDash == null
            ? null
            : List.unmodifiable(value.strokeDash!),
        textColor: value.textColor,
      );

  core.FlowLinkPaintOverride _snapshotLinkOverride(
    core.FlowLinkPaintOverride value,
  ) =>
      core.FlowLinkPaintOverride(
        stroke: value.stroke,
        strokeWidth: value.strokeWidth,
        strokeDash: value.strokeDash == null
            ? null
            : List.unmodifiable(value.strokeDash!),
      );

  /// Finds the topmost (last-painted) node group with an id/link whose bounds
  /// contain [p]. Returns (id, link) or null.
  (String, String?)? _hitTest(List<core.SceneNode> nodes, Offset p) {
    (String, String?)? found;
    void walk(List<core.SceneNode> ns) {
      for (final n in ns) {
        if (n is core.SceneGroup) {
          if (n.role == core.SceneGroupRole.node &&
              (n.id != null || n.link != null)) {
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

  core.SceneEdgeMetadata? _hitTestEdge(
    List<core.SceneNode> nodes,
    Offset position,
  ) {
    core.SceneEdgeMetadata? found;
    final point = core.Point(position.dx, position.dy);

    bool strokeHit(core.SceneGroup group) {
      if (group.children.isEmpty) return false;
      var hit = false;
      void walk(Iterable<core.SceneNode> children) {
        for (final child in children) {
          switch (child) {
            case core.SceneGroup(:final children):
              walk(children);
            case core.SceneShape(
                geometry: final core.PathGeometry path,
                :final stroke,
              ):
              if (stroke != null &&
                  stroke.width > 0 &&
                  stroke.color.alpha > 0 &&
                  core.distanceToPath(path, point) <= 8 + stroke.width / 2) {
                hit = true;
              }
            case core.SceneShape():
            case core.SceneText():
          }
        }
      }

      // Flowchart edge groups emit the main path first. Marker geometry is not
      // part of the stroke target; in hand-drawn scenes the first child becomes
      // a nested group containing the rough path strokes.
      walk([group.children.first]);
      return hit;
    }

    void walk(Iterable<core.SceneNode> children) {
      for (final child in children) {
        if (child is! core.SceneGroup) continue;
        final edge = child.edge;
        if (edge != null) {
          final hit = switch (child.role) {
            core.SceneGroupRole.edgeLabel =>
              core.sceneBounds(child.children)?.contains(point) ?? false,
            core.SceneGroupRole.edge => strokeHit(child),
            _ => false,
          };
          if (hit) found = edge;
        }
        walk(child.children);
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

    if (error == null &&
        widget.onSceneChanged != null &&
        !identical(_deliveredScene, scene)) {
      final generation = _sceneGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            generation == _sceneGeneration &&
            !identical(_deliveredScene, scene)) {
          final callback = widget.onSceneChanged;
          if (callback != null) {
            _deliveredScene = scene;
            callback(scene);
          }
        }
      });
    }

    final background = scene.background;
    Widget paint = CustomPaint(
      painter: ScenePainter(scene),
      size: Size(scene.size.width, scene.size.height),
    );
    final onNodeTap = widget.onNodeTap;
    final onEdgeTap = widget.onEdgeTap;
    if (onNodeTap != null || onEdgeTap != null) {
      paint = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final hit = _hitTest(scene.nodes, d.localPosition);
          if (hit != null) {
            if (onNodeTap != null) onNodeTap(hit.$1, hit.$2);
            return;
          }
          if (onEdgeTap != null) {
            final edge = _hitTestEdge(scene.nodes, d.localPosition);
            if (edge != null) {
              onEdgeTap(edge.fromId, edge.toId, edge.linkIndex);
            }
          }
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
                maxWidth: scene.size.width.clamp(200.0, 460.0),
              ),
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

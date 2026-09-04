/// High-level widget: mermaid source in, painted diagram out.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;

import 'flutter_text_measurer.dart';
import 'scene_painter.dart';

/// Builds the complete render scene for a source and theme.
///
/// This replaces the built-in renderer and exists for tests and
/// instrumentation. It is not part of the supported production surface: the
/// widget rebuilds its base scene whenever this callback's identity changes,
/// so an inline closure re-renders on every widget rebuild.
@visibleForTesting
typedef MermaidSceneRenderer =
    core.RenderScene Function(String source, core.MermaidTheme theme);

/// Builds the tooltip shown for a hovered Mermaid node.
typedef MermaidNodeTooltipBuilder =
    Widget Function(BuildContext context, String id);

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
    this.onNodeHover,
    this.hoverCursor = SystemMouseCursors.click,
    this.nodeTooltipBuilder,
    this.semanticNodes = false,
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

  /// Called when the pointer enters a different hit-testable node, and with
  /// null when it leaves the current node.
  final ValueChanged<String?>? onNodeHover;

  /// Cursor used while the pointer is over a hit-testable node.
  final MouseCursor hoverCursor;

  /// Builds an optional overlay anchored below the hovered node.
  ///
  /// The overlay ignores pointer events and does not affect diagram geometry.
  final MermaidNodeTooltipBuilder? nodeTooltipBuilder;

  /// Exposes one semantics node per id-carrying diagram node.
  ///
  /// Nodes use their human label with the stable id as fallback. Traversal
  /// follows scene order, which is source declaration order for flowcharts.
  /// Decorative groups, edges, and edge labels are excluded. Off by default.
  final bool semanticNodes;

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

  /// Optional full-scene renderer, useful for instrumentation in tests. A
  /// change to this callback rebuilds the base scene, so callers must retain
  /// the same callback instance across widget rebuilds.
  @visibleForTesting
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
  int _deliveredSceneGeneration = -1;
  int _sceneGeneration = 0;
  MermaidSceneRenderer? _builtRenderer;
  Map<String, core.FlowNodePaintOverride> _builtNodeOverrides = const {};
  Map<int, core.FlowLinkPaintOverride> _builtLinkOverrides = const {};
  String? _hoveredNodeId;
  _SceneIndex? _index;
  final _tooltipController = OverlayPortalController(
    debugLabel: 'Mermaid node tooltip',
  );

  /// Whether the overlay portal that owns [_tooltipController] is in the tree.
  ///
  /// The portal is only built while a tooltip builder is supplied. Calling
  /// `show()` or `hide()` on a controller with no portal asserts inside
  /// Flutter, so every controller command is guarded by this.
  bool get _hasTooltipOverlay => widget.nodeTooltipBuilder != null;

  @override
  void didUpdateWidget(MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sceneChanged =
        oldWidget.source != widget.source ||
        oldWidget.theme != widget.theme ||
        oldWidget.sceneRenderer != widget.sceneRenderer;
    if (_hoveredNodeId != null && sceneChanged) {
      _hoveredNodeId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _hoveredNodeId != null) return;
        if (_hasTooltipOverlay) _tooltipController.hide();
        widget.onNodeHover?.call(null);
      });
    } else if ((oldWidget.nodeTooltipBuilder != null) != _hasTooltipOverlay) {
      // Only the presence of a builder changes the overlay's lifetime; an
      // inline closure has a new identity on every rebuild and must not
      // schedule work. Removing a builder disposes the portal, which leaves
      // nothing to hide.
      if (_hasTooltipOverlay && _hoveredNodeId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _hoveredNodeId == null || !_hasTooltipOverlay) return;
          _tooltipController.show();
        });
      }
    }
  }

  @override
  void dispose() {
    final onNodeHover = widget.onNodeHover;
    if (_hoveredNodeId != null && onNodeHover != null) {
      _hoveredNodeId = null;
      // MouseRegion reports no exit when its region leaves the tree, so a
      // consumer's hover highlight would stick after the diagram is gone.
      // The tree is locked during teardown; report after the frame so a
      // listener that calls setState is not building into a locked tree.
      WidgetsBinding.instance.addPostFrameCallback((_) => onNodeHover(null));
    }
    super.dispose();
  }

  void _updateHoveredNode(String? id) {
    if (_hoveredNodeId == id) return;
    setState(() => _hoveredNodeId = id);
    if (_hasTooltipOverlay) {
      if (id == null) {
        _tooltipController.hide();
      } else {
        _tooltipController.show();
      }
    }
    widget.onNodeHover?.call(id);
  }

  /// Node geometry and metadata for [scene], memoized on scene identity so
  /// pointer moves and hover-driven rebuilds do not walk the scene again.
  _SceneIndex _indexOf(core.RenderScene scene) {
    final cached = _index;
    if (cached != null && identical(cached.scene, scene)) return cached;
    return _index = _SceneIndex(scene);
  }

  void _rebuildSceneIfNeeded() {
    final renderer = widget.sceneRenderer;
    final rebuildBase =
        _builtSource != widget.source ||
        _builtTheme != widget.theme ||
        _builtRenderer != renderer;
    if (rebuildBase) {
      _builtSource = widget.source;
      _builtTheme = widget.theme;
      _builtRenderer = renderer;
      _sceneGeneration++;
      try {
        _baseScene =
            renderer?.call(widget.source, widget.theme) ??
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
    final overridesChanged =
        !mapEquals(_builtNodeOverrides, nodeOverrides) ||
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
  ) => core.FlowNodePaintOverride(
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
  ) => core.FlowLinkPaintOverride(
    stroke: value.stroke,
    strokeWidth: value.strokeWidth,
    strokeDash: value.strokeDash == null
        ? null
        : List.unmodifiable(value.strokeDash!),
  );

  /// Finds the topmost (last-painted) node whose bounds contain [p].
  _DiagramNode? _hitTest(core.RenderScene scene, Offset p) {
    final point = core.Point(p.dx, p.dy);
    _DiagramNode? found;
    for (final node in _indexOf(scene).nodes) {
      // Later in paint order wins; keep updating.
      if (node.bounds.contains(point)) found = node;
    }
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

    final callbackScene = _baseScene;
    if (error == null &&
        callbackScene != null &&
        widget.onSceneChanged != null &&
        _deliveredSceneGeneration != _sceneGeneration) {
      final generation = _sceneGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            generation == _sceneGeneration &&
            _deliveredSceneGeneration != generation) {
          final callback = widget.onSceneChanged;
          if (callback != null) {
            _deliveredSceneGeneration = generation;
            callback(callbackScene);
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
          final hit = _hitTest(scene, d.localPosition);
          if (hit != null) {
            if (onNodeTap != null) onNodeTap(hit.id ?? '', hit.link);
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

    if (widget.semanticNodes) {
      final semanticNodes = _indexOf(scene).semanticNodes;
      paint = Stack(
        fit: StackFit.expand,
        children: [
          paint,
          for (var index = 0; index < semanticNodes.length; index++)
            Positioned.fromRect(
              rect: semanticNodes[index].rect,
              child: _SemanticNodeTarget(
                node: semanticNodes[index],
                sortKey: OrdinalSortKey(index.toDouble()),
                onTap: onNodeTap == null
                    ? null
                    : () => onNodeTap(
                        semanticNodes[index].id!,
                        semanticNodes[index].link,
                      ),
              ),
            ),
        ],
      );
    }

    final hoveredNodeId = _hoveredNodeId;
    final tooltipBuilder = widget.nodeTooltipBuilder;
    final hasNodeInteraction =
        onNodeTap != null ||
        widget.onNodeHover != null ||
        tooltipBuilder != null;
    if (hasNodeInteraction) {
      paint = MouseRegion(
        cursor: hoveredNodeId == null ? MouseCursor.defer : widget.hoverCursor,
        onHover: (event) {
          final hit = _hitTest(scene, event.localPosition);
          _updateHoveredNode(hit?.id);
        },
        onExit: (_) => _updateHoveredNode(null),
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

    if (tooltipBuilder != null) {
      diagram = OverlayPortal.overlayChildLayoutBuilder(
        controller: _tooltipController,
        overlayChildBuilder: (context, info) {
          final id = _hoveredNodeId;
          final bounds = id == null ? null : _indexOf(scene).boundsOf(id);
          if (id == null || bounds == null) return const SizedBox.shrink();
          final below =
              MatrixUtils.transformPoint(
                info.childPaintTransform,
                Offset(bounds.left, bounds.bottom),
              ) +
              const Offset(0, 8);
          final above =
              MatrixUtils.transformPoint(
                info.childPaintTransform,
                Offset(bounds.left, bounds.top),
              ) -
              const Offset(0, 8);
          return CustomSingleChildLayout(
            delegate: _NodeTooltipLayoutDelegate(below: below, above: above),
            child: IgnorePointer(child: tooltipBuilder(context, id)),
          );
        },
        child: diagram,
      );
    }

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

/// One scene's interactive nodes, measured once.
///
/// Hit testing, semantics, and tooltip anchoring all need the same node
/// bounds, so they share [core.RenderSceneBounds.nodeBounds] instead of each
/// walking the scene and recomputing bounds.
class _SceneIndex {
  _SceneIndex(this.scene) : nodes = _indexDiagramNodes(scene);

  final core.RenderScene scene;

  /// Hit-testable nodes in paint order (last painted last).
  final List<_DiagramNode> nodes;

  List<_DiagramNode>? _semanticNodes;
  Map<String, _DiagramNode>? _byId;

  /// The subset exposed to the semantics tree: nodes with a stable id.
  List<_DiagramNode> get semanticNodes => _semanticNodes ??= List.unmodifiable([
    for (final node in nodes)
      if (node.id != null) node,
  ]);

  /// Scene-space bounds of the node with [id], or null when it has none.
  core.Rect? boundsOf(String id) => (_byId ??= {
    for (final node in semanticNodes) node.id!: node,
  })[id]?.bounds;
}

List<_DiagramNode> _indexDiagramNodes(core.RenderScene scene) {
  final boundsById = scene.nodeBounds;
  final ordered = <Object, _DiagramNode>{};

  void walk(Iterable<core.SceneNode> children) {
    for (final child in children) {
      if (child is! core.SceneGroup) continue;
      final id = child.id;
      if (child.role == core.SceneGroupRole.node &&
          (id != null || child.link != null)) {
        // Named nodes reuse the scene's own bounds index; a group carrying
        // only a link has no key there and is measured directly.
        final bounds = id != null
            ? boundsById[id]
            : core.sceneBounds(child.children);
        if (bounds != null) {
          final label = child.semanticLabel?.trim();
          final node = _DiagramNode(
            id: id,
            label: label == null || label.isEmpty ? id ?? '' : label,
            bounds: bounds,
            link: child.link,
            tooltip: child.tooltip,
          );
          // Reinsert duplicates so order and geometry both follow the
          // last-painted node, matching pointer hit testing.
          final key = id ?? node;
          ordered.remove(key);
          ordered[key] = node;
        }
      }
      walk(child.children);
    }
  }

  walk(scene.nodes);
  return List.unmodifiable(ordered.values);
}

class _DiagramNode {
  _DiagramNode({
    required this.id,
    required this.label,
    required this.bounds,
    this.link,
    this.tooltip,
  }) : rect = Rect.fromLTRB(
         bounds.left,
         bounds.top,
         bounds.right,
         bounds.bottom,
       );

  final String? id;
  final String label;
  final core.Rect bounds;
  final Rect rect;
  final String? link;
  final String? tooltip;
}

class _SemanticNodeTarget extends StatelessWidget {
  const _SemanticNodeTarget({
    required this.node,
    required this.sortKey,
    required this.onTap,
  });

  final _DiagramNode node;
  final OrdinalSortKey sortKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final id = node.id!;
    final tap = onTap;
    final child = tap == null
        ? const SizedBox.expand()
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: tap,
            child: const SizedBox.expand(),
          );
    return Semantics(
      key: ValueKey('mermaid-node:$id'),
      container: true,
      excludeSemantics: true,
      identifier: id,
      label: node.label,
      tooltip: node.tooltip,
      sortKey: sortKey,
      enabled: tap == null ? null : true,
      button: tap != null,
      onTap: tap,
      child: child,
    );
  }
}

class _NodeTooltipLayoutDelegate extends SingleChildLayoutDelegate {
  const _NodeTooltipLayoutDelegate({required this.below, required this.above});

  static const _margin = 8.0;

  final Offset below;
  final Offset above;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(
        math.max(0, constraints.maxWidth - _margin * 2),
        math.max(0, constraints.maxHeight - _margin * 2),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(_margin, size.width - childSize.width - _margin);
    final x = below.dx.clamp(_margin, maxX).toDouble();
    final belowFits = below.dy + childSize.height <= size.height - _margin;
    final proposedY = belowFits ? below.dy : above.dy - childSize.height;
    final maxY = math.max(_margin, size.height - childSize.height - _margin);
    return Offset(x, proposedY.clamp(_margin, maxY).toDouble());
  }

  @override
  bool shouldRelayout(_NodeTooltipLayoutDelegate oldDelegate) =>
      oldDelegate.below != below || oldDelegate.above != above;
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

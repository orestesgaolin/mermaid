/// An interactive viewer around [MermaidDiagram], mirroring how mermaid.js
/// presents diagrams on the web: pan & zoom, a directional arrow pad, zoom
/// in/out, reset-to-fit, a pan/zoom lock toggle and a fullscreen popup.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;

import 'mermaid_diagram.dart';

/// Displays a mermaid diagram with interactive pan/zoom controls.
///
/// The diagram is framed to fit on first layout (and re-framed when the source
/// changes, unless you've panned/zoomed — then your view is kept). Drag to pan
/// and scroll/pinch to zoom; the on-canvas controls give discrete pan, zoom,
/// reset and a fullscreen popup. Wrap it in a bounded box (it fills its
/// parent).
class MermaidView extends StatefulWidget {
  const MermaidView({
    super.key,
    required this.source,
    this.theme = core.MermaidTheme.defaultTheme,
    this.errorBuilder,
    this.keepLastGoodSceneOnError = true,
    this.onNodeTap,
    this.minScale = 0.2,
    this.maxScale = 8.0,
    this.zoomStep = 1.25,
    this.panStep = 64.0,
    this.padding = 20.0,
    this.showControls = true,
    this.allowFullscreen = true,
    this.backgroundColor,
  });

  /// Mermaid diagram source text.
  final String source;

  /// Resolved mermaid theme used for layout and painting.
  final core.MermaidTheme theme;

  /// See [MermaidDiagram.errorBuilder].
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// See [MermaidDiagram.keepLastGoodSceneOnError].
  final bool keepLastGoodSceneOnError;

  /// See [MermaidDiagram.onNodeTap].
  final void Function(String id, String? link)? onNodeTap;

  /// Zoom bounds and the factor applied per zoom-button press.
  final double minScale;
  final double maxScale;
  final double zoomStep;

  /// Pixels panned per arrow-button press (in viewport space).
  final double panStep;

  /// Padding (px) left around the diagram when fitting it to the viewport.
  final double padding;

  /// Whether to show the on-canvas control cluster.
  final bool showControls;

  /// Whether the controls include a fullscreen popup button.
  final bool allowFullscreen;

  /// Background painted behind the diagram (defaults to transparent).
  final Color? backgroundColor;

  @override
  State<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends State<MermaidView> {
  final _tc = TransformationController();
  final _childKey = GlobalKey();
  bool _interactive = true;
  bool _didFit = false;
  Matrix4? _fittedMatrix;
  Size _viewport = Size.zero;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MermaidView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source || oldWidget.theme != widget.theme) {
      // Re-frame a changed diagram only if the user hasn't moved the view.
      if (_fittedMatrix == null || _tc.value == _fittedMatrix) _didFit = false;
    }
  }

  /// The diagram's natural (unscaled) size, read from the painted child.
  Size? get _childSize {
    final box = _childKey.currentContext?.findRenderObject() as RenderBox?;
    final s = box?.size;
    return (s != null && s.width > 0 && s.height > 0) ? s : null;
  }

  /// Scale + centre the diagram to fit the viewport.
  void _fit() {
    final cs = _childSize;
    if (cs == null || _viewport == Size.zero) return;
    final pad = widget.padding;
    final s = math
        .min((_viewport.width - 2 * pad) / cs.width,
            (_viewport.height - 2 * pad) / cs.height)
        .clamp(widget.minScale, widget.maxScale);
    final tx = (_viewport.width - cs.width * s) / 2;
    final ty = (_viewport.height - cs.height * s) / 2;
    _tc.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, s, 1);
    _fittedMatrix = _tc.value.clone();
  }

  /// Zoom by [factor] about the viewport centre (clamped to min/max scale).
  void _zoom(double factor) {
    if (_viewport == Size.zero) return;
    final cur = _tc.value.getMaxScaleOnAxis();
    final target = (cur * factor).clamp(widget.minScale, widget.maxScale);
    final f = target / cur;
    if ((f - 1).abs() < 1e-6) return;
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    _tc.value = (Matrix4.identity()
          ..translateByDouble(c.dx, c.dy, 0, 1)
          ..scaleByDouble(f, f, f, 1)
          ..translateByDouble(-c.dx, -c.dy, 0, 1))
        .multiplied(_tc.value);
  }

  /// Pan by ([dx], [dy]) in viewport space.
  void _pan(double dx, double dy) {
    _tc.value = Matrix4.translationValues(dx, dy, 0).multiplied(_tc.value);
  }

  void _openFullscreen() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: MermaidView(
                source: widget.source,
                theme: widget.theme,
                errorBuilder: widget.errorBuilder,
                keepLastGoodSceneOnError: widget.keepLastGoodSceneOnError,
                onNodeTap: widget.onNodeTap,
                minScale: widget.minScale,
                maxScale: widget.maxScale,
                backgroundColor: widget.backgroundColor ?? Colors.white,
                allowFullscreen: false,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _CtlButton(
                icon: Icons.close,
                tooltip: 'Close',
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_didFit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didFit) return;
        if (_childSize != null && _viewport != Size.zero) {
          _didFit = true;
          _fit();
        }
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        return DecoratedBox(
          decoration: BoxDecoration(color: widget.backgroundColor),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: InteractiveViewer(
                    transformationController: _tc,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: widget.minScale,
                    maxScale: widget.maxScale,
                    panEnabled: _interactive,
                    scaleEnabled: _interactive,
                    child: MermaidDiagram(
                      key: _childKey,
                      source: widget.source,
                      theme: widget.theme,
                      errorBuilder: widget.errorBuilder,
                      keepLastGoodSceneOnError: widget.keepLastGoodSceneOnError,
                      onNodeTap: widget.onNodeTap,
                    ),
                  ),
                ),
              ),
              if (widget.showControls) ..._buildControls(),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildControls() {
    return [
      // Top-right: pan/zoom lock toggle + fullscreen popup.
      Positioned(
        top: 8,
        right: 8,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CtlButton(
              icon: _interactive ? Icons.open_with : Icons.lock_outline,
              tooltip: _interactive ? 'Lock pan & zoom' : 'Enable pan & zoom',
              active: _interactive,
              onTap: () => setState(() => _interactive = !_interactive),
            ),
            if (widget.allowFullscreen) ...[
              const SizedBox(width: 6),
              _CtlButton(
                icon: Icons.open_in_full,
                tooltip: 'Open in popup',
                onTap: _openFullscreen,
              ),
            ],
          ],
        ),
      ),
      // Bottom-right: arrow pad + zoom + reset/centre.
      Positioned(
        bottom: 8,
        right: 8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              _CtlButton(
                  icon: Icons.keyboard_arrow_up,
                  tooltip: 'Pan up',
                  onTap: () => _pan(0, -widget.panStep)),
              const SizedBox(width: 6),
              _CtlButton(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  onTap: () => _zoom(widget.zoomStep)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _CtlButton(
                  icon: Icons.keyboard_arrow_left,
                  tooltip: 'Pan left',
                  onTap: () => _pan(-widget.panStep, 0)),
              const SizedBox(width: 6),
              _CtlButton(
                  icon: Icons.center_focus_strong,
                  tooltip: 'Reset / centre',
                  onTap: _fit),
              const SizedBox(width: 6),
              _CtlButton(
                  icon: Icons.keyboard_arrow_right,
                  tooltip: 'Pan right',
                  onTap: () => _pan(widget.panStep, 0)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _CtlButton(
                  icon: Icons.keyboard_arrow_down,
                  tooltip: 'Pan down',
                  onTap: () => _pan(0, widget.panStep)),
              const SizedBox(width: 6),
              _CtlButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  onTap: () => _zoom(1 / widget.zoomStep)),
            ]),
          ],
        ),
      ),
    ];
  }
}

/// A small rounded control button used by [MermaidView].
class _CtlButton extends StatelessWidget {
  const _CtlButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: active ? const Color(0xFFE8E4F6) : Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFD9D5E4)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 18, color: const Color(0xFF4A4458)),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}

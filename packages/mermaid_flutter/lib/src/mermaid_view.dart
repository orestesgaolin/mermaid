/// An interactive viewer around [MermaidDiagram], mirroring how mermaid.js
/// presents diagrams on the web: pan & zoom, a directional arrow pad, zoom
/// in/out, reset-to-fit, a pan/zoom lock toggle and a fullscreen popup.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;

import 'mermaid_diagram.dart';

/// Controls the viewport of one attached [MermaidView].
///
/// A controller can be attached to one view at a time. Commands return `false`
/// when the controller is detached, disposed, the view has no usable layout,
/// or [focusNode] cannot resolve the requested node. Each command waits until
/// updated diagram layout has been reported, so a focus requested with a
/// source update uses the new scene rather than stale node bounds.
///
/// The controller is a [ChangeNotifier]. [transformation] returns a cloned
/// snapshot of the matrix used by the view, so callers cannot mutate the view
/// through the returned value. Dispose the controller after removing its view;
/// disposing while attached only detaches this public command surface and the
/// view continues to operate.
class MermaidViewController extends ChangeNotifier {
  Matrix4 _transformation = Matrix4.identity();
  _MermaidViewControllerBinding? _binding;
  bool _disposed = false;

  /// A read-only snapshot of the current scene-to-viewport transformation.
  Matrix4 get transformation => _transformation.clone();

  /// Whether this controller is currently attached to a [MermaidView].
  bool get isAttached => !_disposed && _binding != null;

  /// Fits the complete diagram inside the viewport.
  Future<bool> fitAll({bool animate = true}) {
    final binding = _binding;
    if (_disposed || binding == null) return Future.value(false);
    return binding.fitAll(animate);
  }

  /// Centres node [id], optionally changing to [zoom].
  Future<bool> focusNode(String id, {double? zoom, bool animate = true}) {
    final binding = _binding;
    if (_disposed || binding == null) return Future.value(false);
    return binding.focusNode(id, zoom, animate);
  }

  /// Releases listeners and prevents further attachment or commands.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _binding?.cancelPending();
    _binding = null;
    super.dispose();
  }

  void _attach(_MermaidViewControllerBinding binding) {
    if (_disposed) {
      throw FlutterError(
        'A disposed MermaidViewController cannot be attached.',
      );
    }
    if (_binding != null && !identical(_binding, binding)) {
      throw FlutterError(
        'A MermaidViewController can only control one MermaidView at a time.',
      );
    }
    _binding = binding;
  }

  void _detach(_MermaidViewControllerBinding binding) {
    if (identical(_binding, binding)) {
      binding.cancelPending();
      _binding = null;
    }
  }

  void _publish(Matrix4 value, {bool notify = true}) {
    if (_disposed) return;
    _transformation = value.clone();
    if (notify) notifyListeners();
  }
}

class _MermaidViewControllerBinding {
  _MermaidViewControllerBinding({
    required this.fitAll,
    required this.focusNode,
    required this.cancelPending,
  });

  final Future<bool> Function(bool animate) fitAll;
  final Future<bool> Function(String id, double? zoom, bool animate) focusNode;
  final VoidCallback cancelPending;
}

/// Displays a mermaid diagram with interactive pan/zoom controls.
///
/// The diagram is framed to fit on first layout and whenever the viewport
/// changes size. A source change is also re-framed unless you've panned or
/// zoomed. Drag to pan and scroll/pinch to zoom; the on-canvas controls give
/// discrete pan, zoom, reset and a fullscreen popup. Wrap it in a bounded box
/// (it fills its parent).
class MermaidView extends StatefulWidget {
  const MermaidView({
    super.key,
    required this.source,
    this.controller,
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
    this.onRequestFullscreen,
    this.backgroundColor,
  });

  /// Mermaid diagram source text.
  final String source;

  /// Optional controller for fit, focus, and transformation observation.
  ///
  /// Omitting it preserves the built-in pan, zoom, fit, and fullscreen
  /// behavior. One controller can be attached to only one view at a time.
  final MermaidViewController? controller;

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

  /// If set, the fullscreen button calls this instead of showing the built-in
  /// in-Flutter dialog. Use it when the diagram is embedded inside a larger
  /// host (e.g. a Flutter web view on an HTML page) where an in-Flutter dialog
  /// can't escape the view's bounds — the host can then present a true
  /// full-page overlay.
  final VoidCallback? onRequestFullscreen;

  /// Background painted behind the diagram (defaults to transparent).
  final Color? backgroundColor;

  @override
  State<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends State<MermaidView>
    with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  final _childKey = GlobalKey();
  late final AnimationController _animation;
  late final _MermaidViewControllerBinding _controllerBinding;
  bool _interactive = true;
  bool _didFit = false;
  Matrix4? _fittedMatrix;
  Size _viewport = Size.zero;
  Map<String, core.Rect>? _nodeBounds;
  int _commandEpoch = 0;
  bool _applyingFit = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _controllerBinding = _MermaidViewControllerBinding(
      fitAll: _fitFromController,
      focusNode: _focusNodeFromController,
      cancelPending: _cancelExternalCommand,
    );
    _tc.addListener(_publishTransformation);
    widget.controller?._attach(_controllerBinding);
    _syncTransformation();
  }

  @override
  void dispose() {
    widget.controller?._detach(_controllerBinding);
    _animation.dispose();
    _tc.removeListener(_publishTransformation);
    _tc.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MermaidView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(_controllerBinding);
      widget.controller?._attach(_controllerBinding);
      _syncTransformation();
    }
    if (oldWidget.source != widget.source || oldWidget.theme != widget.theme) {
      final wasApplyingFit = _applyingFit;
      _animation.stop();
      _nodeBounds = null;
      // Re-frame a changed diagram only if the user hasn't moved the view.
      if (wasApplyingFit ||
          _fittedMatrix == null ||
          _tc.value == _fittedMatrix) {
        _didFit = false;
      }
      if (wasApplyingFit) _fittedMatrix = null;
    }
  }

  void _publishTransformation() => widget.controller?._publish(_tc.value);

  void _syncTransformation() =>
      widget.controller?._publish(_tc.value, notify: false);

  void _handleSceneChanged(core.RenderScene scene) {
    _nodeBounds = scene.nodeBounds;
  }

  void _cancelExternalCommand() {
    _commandEpoch++;
    _animation.stop();
  }

  /// The diagram's natural (unscaled) size, read from the painted child.
  Size? get _childSize {
    final box = _childKey.currentContext?.findRenderObject() as RenderBox?;
    final s = box?.size;
    return (s != null && s.width > 0 && s.height > 0) ? s : null;
  }

  /// Scale + centre the diagram to fit the viewport.
  Matrix4? _fitMatrix() {
    final cs = _childSize;
    if (cs == null || _viewport == Size.zero) return null;
    final pad = widget.padding;
    final s = math
        .min(
          (_viewport.width - 2 * pad) / cs.width,
          (_viewport.height - 2 * pad) / cs.height,
        )
        .clamp(widget.minScale, widget.maxScale);
    final tx = (_viewport.width - cs.width * s) / 2;
    final ty = (_viewport.height - cs.height * s) / 2;
    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, s, 1);
  }

  void _fit() {
    _cancelExternalCommand();
    _fitImmediately();
  }

  void _fitImmediately() {
    final matrix = _fitMatrix();
    if (matrix == null) return;
    _animation.stop();
    _tc.value = matrix;
    _fittedMatrix = _tc.value.clone();
  }

  Future<bool> _afterLayout(Future<bool> Function() operation) {
    final completer = Completer<bool>();
    final epoch = _commandEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || epoch != _commandEpoch) {
          completer.complete(false);
          return;
        }
        completer.complete(await operation());
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
    return completer.future;
  }

  Future<bool> _fitFromController(bool animate) {
    _cancelExternalCommand();
    return _afterLayout(() async {
      final matrix = _fitMatrix();
      if (matrix == null) return false;
      _didFit = true;
      _applyingFit = true;
      try {
        final applied = await _applyTransformation(matrix, animate: animate);
        if (applied) _fittedMatrix = matrix.clone();
        return applied;
      } finally {
        _applyingFit = false;
      }
    });
  }

  Future<bool> _focusNodeFromController(String id, double? zoom, bool animate) {
    if (zoom != null && (!zoom.isFinite || zoom <= 0)) {
      return Future.value(false);
    }
    _cancelExternalCommand();
    return _afterLayout(() async {
      final bounds = _nodeBounds?[id];
      if (bounds == null || _viewport == Size.zero) return false;
      // An explicit focus requested with a source update takes precedence over
      // the automatic fit scheduled for that same layout frame.
      _didFit = true;
      _fittedMatrix = null;
      final scale = (zoom ?? _tc.value.getMaxScaleOnAxis()).clamp(
        widget.minScale,
        widget.maxScale,
      );
      final center = bounds.center;
      final matrix = Matrix4.identity()
        ..translateByDouble(
          _viewport.width / 2 - center.x * scale,
          _viewport.height / 2 - center.y * scale,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, scale, 1);
      return _applyTransformation(matrix, animate: animate);
    });
  }

  Future<bool> _applyTransformation(
    Matrix4 target, {
    required bool animate,
  }) async {
    if (!mounted) return false;
    _animation.stop();
    if (!animate) {
      _tc.value = target;
      return true;
    }
    final tween = Matrix4Tween(begin: _tc.value.clone(), end: target);
    void tick() {
      final value = tween.evaluate(_animation);
      _tc.value = value;
    }

    _animation.addListener(tick);
    try {
      await _animation.forward(from: 0).orCancel;
      return mounted;
    } on TickerCanceled {
      return false;
    } finally {
      _animation.removeListener(tick);
    }
  }

  /// Zoom by [factor] about the viewport centre (clamped to min/max scale).
  void _zoom(double factor) {
    if (_viewport == Size.zero) return;
    _cancelExternalCommand();
    final cur = _tc.value.getMaxScaleOnAxis();
    final target = (cur * factor).clamp(widget.minScale, widget.maxScale);
    final f = target / cur;
    if ((f - 1).abs() < 1e-6) return;
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    _tc.value =
        (Matrix4.identity()
              ..translateByDouble(c.dx, c.dy, 0, 1)
              ..scaleByDouble(f, f, f, 1)
              ..translateByDouble(-c.dx, -c.dy, 0, 1))
            .multiplied(_tc.value);
  }

  /// Pan by ([dx], [dy]) in viewport space.
  void _pan(double dx, double dy) {
    _cancelExternalCommand();
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final vp = constraints.biggest;
        if (vp != _viewport) {
          _animation.stop();
          _viewport = vp;
          // A transform that made sense in the previous viewport can leave
          // the diagram off-screen after entering or leaving fullscreen.
          _didFit = false;
        }
        if (!_didFit) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _didFit) return;
            if (_childSize != null && _viewport != Size.zero) {
              _didFit = true;
              _fitImmediately();
            }
          });
        }
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
                    onInteractionStart: (_) => _cancelExternalCommand(),
                    child: MermaidDiagram(
                      key: _childKey,
                      source: widget.source,
                      theme: widget.theme,
                      errorBuilder: widget.errorBuilder,
                      keepLastGoodSceneOnError: widget.keepLastGoodSceneOnError,
                      onNodeTap: widget.onNodeTap,
                      onSceneChanged: _handleSceneChanged,
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
                onTap: widget.onRequestFullscreen ?? _openFullscreen,
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CtlButton(
                  icon: Icons.keyboard_arrow_up,
                  tooltip: 'Move view up',
                  onTap: () => _pan(0, widget.panStep),
                ),
                const SizedBox(width: 6),
                _CtlButton(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  onTap: () => _zoom(widget.zoomStep),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CtlButton(
                  icon: Icons.keyboard_arrow_left,
                  tooltip: 'Move view left',
                  onTap: () => _pan(widget.panStep, 0),
                ),
                const SizedBox(width: 6),
                _CtlButton(
                  icon: Icons.center_focus_strong,
                  tooltip: 'Reset / centre',
                  onTap: _fit,
                ),
                const SizedBox(width: 6),
                _CtlButton(
                  icon: Icons.keyboard_arrow_right,
                  tooltip: 'Move view right',
                  onTap: () => _pan(-widget.panStep, 0),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CtlButton(
                  icon: Icons.keyboard_arrow_down,
                  tooltip: 'Move view down',
                  onTap: () => _pan(0, -widget.panStep),
                ),
                const SizedBox(width: 6),
                _CtlButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  onTap: () => _zoom(1 / widget.zoomStep),
                ),
              ],
            ),
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

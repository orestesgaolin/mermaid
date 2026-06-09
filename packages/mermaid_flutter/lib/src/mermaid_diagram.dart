/// High-level widget: mermaid source in, painted diagram out.
library;

import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;

import 'flutter_text_measurer.dart';
import 'scene_painter.dart';

/// Renders a mermaid diagram from [source].
///
/// The scene is built synchronously in [State.build] and memoized on
/// `(source, theme)`; any error thrown while parsing or laying out the
/// diagram is caught and rendered via [errorBuilder] (or a default
/// red-tinted panel).
class MermaidDiagram extends StatefulWidget {
  const MermaidDiagram({
    super.key,
    required this.source,
    this.theme = core.MermaidTheme.defaultTheme,
    this.errorBuilder,
  });

  /// Mermaid diagram source text.
  final String source;

  /// Resolved mermaid theme used for layout and painting.
  final core.MermaidTheme theme;

  /// Builds the widget shown when rendering [source] fails. Receives the
  /// thrown error (e.g. `MermaidParseException`, `UnsupportedError`).
  final Widget Function(BuildContext context, Object error)? errorBuilder;

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
      _scene = null;
      _error = error;
    }
  }

  @override
  Widget build(BuildContext context) {
    _rebuildSceneIfNeeded();

    final error = _error;
    if (error != null) {
      final builder = widget.errorBuilder;
      if (builder != null) return builder(context, error);
      return _DefaultErrorPanel(error: error);
    }

    final scene = _scene!;
    final background = scene.background;
    return SizedBox(
      width: scene.size.width,
      height: scene.size.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background != null ? Color(background.value) : null,
        ),
        child: CustomPaint(
          painter: ScenePainter(scene),
          size: Size(scene.size.width, scene.size.height),
        ),
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

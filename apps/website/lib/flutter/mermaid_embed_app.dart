/// The Flutter widget embedded into the comparison page via
/// `jaspr_flutter_embed`. It renders the Dart port's `MermaidDiagram` and
/// exposes a tiny JS bridge so the surrounding Jaspr editor can push new
/// source live without remounting the Flutter view:
///
///   window.mermaidDartEmbed.render(source)   // update the diagram
///   window.__mermaidDartInitialSource        // source read at boot
///
/// This file imports Flutter, so it is only ever compiled for the web build;
/// the Jaspr component references it through an `@Import.onWeb` stub.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

@JS('mermaidDartEmbed')
external set _mermaidDartEmbed(JSObject value);

@JS('__mermaidDartInitialSource')
external JSString? get _initialSource;

// Defined in web/embed_bridge.js — promotes the Flutter pane to a full-page
// overlay (an in-Flutter dialog can't escape the embedded view's bounds).
@JS('mermaidDartToggleFullscreen')
external void _toggleFullscreen();

class MermaidEmbedApp extends StatefulWidget {
  const MermaidEmbedApp({super.key});

  @override
  State<MermaidEmbedApp> createState() => _MermaidEmbedAppState();
}

class _MermaidEmbedAppState extends State<MermaidEmbedApp> {
  String _source = '';

  @override
  void initState() {
    super.initState();
    _source = _initialSource?.toDart ?? 'graph TD\n  A[mermaid] --> B[dart]';
    // Publish the render bridge; the host page calls it on every edit.
    final bridge = JSObject();
    bridge.setProperty(
      'render'.toJS,
      ((JSString source) {
        if (!mounted) return;
        setState(() => _source = source.toDart);
      }).toJS,
    );
    _mermaidDartEmbed = bridge;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.white,
        // Interactive viewer (pan/zoom, arrows, reset, fullscreen) — the same
        // way mermaid.js presents a diagram on the web. It fits the diagram to
        // the pane on load and re-frames it when the source changes.
        child: MermaidView(
          source: _source,
          backgroundColor: Colors.white,
          // Errors replace the diagram so the comparison stays honest.
          keepLastGoodSceneOnError: false,
          // Let the host page present a true full-page overlay (a Flutter
          // dialog would be trapped inside this small embedded view).
          onRequestFullscreen: () {
            try {
              _toggleFullscreen();
            } catch (_) {}
          },
        ),
      ),
    );
  }
}

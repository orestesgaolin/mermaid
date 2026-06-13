import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

/// JS bridge: the host page calls `window.mermaidDartEmbed.render(src)`;
/// defining the object also signals readiness to the host.
@JS('mermaidDartEmbed')
external set _mermaidDartEmbed(JSObject value);

@JS('__mermaidDartInitialSource')
external JSString? get _initialSource;

void main() {
  runApp(const _EmbedApp());
}

class _EmbedApp extends StatefulWidget {
  const _EmbedApp();

  @override
  State<_EmbedApp> createState() => _EmbedAppState();
}

class _EmbedAppState extends State<_EmbedApp> {
  String _source = '';

  @override
  void initState() {
    super.initState();
    _source = _initialSource?.toDart ?? 'graph TD\n  A[mermaid] --> B[dart]';
    final bridge = JSObject();
    bridge.setProperty(
      'render'.toJS,
      ((JSString source) {
        setState(() => _source = source.toDart);
      }).toJS,
    );
    _mermaidDartEmbed = bridge;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Colors.white,
        // FittedBox directly under the (bounded) host element so diagrams
        // scale to fill the pane (up or down) — matching mermaid.js, which
        // also scales its SVG to the container, instead of sitting small.
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              // Errors replace the diagram so the comparison stays honest.
              child: MermaidDiagram(
                source: _source,
                keepLastGoodSceneOnError: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

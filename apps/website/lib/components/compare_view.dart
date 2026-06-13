/// Interactive comparison: the selected sample is rendered by mermaid.js
/// (left) and by the embedded Flutter build of mermaid dart (right).
library;

import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

import '../samples.dart';

// Bridge functions defined in web/embed_bridge.js.
@JS('renderMermaidJs')
external void _renderMermaidJs(web.HTMLElement el, JSString source);

@JS('loadMermaidDart')
external void _loadMermaidDart(web.HTMLElement host, JSString initialSource);

@JS('updateMermaidDart')
external void _updateMermaidDart(JSString source);

@client
class CompareView extends StatefulComponent {
  const CompareView({super.key});

  @override
  State<CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<CompareView> {
  int _selected = 0;
  bool _flutterStarted = false;
  final _jsPane = GlobalNodeKey<web.HTMLElement>();
  final _flutterPane = GlobalNodeKey<web.HTMLElement>();

  Sample get _sample => samples[_selected];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      Future.delayed(Duration.zero, _sync);
    }
  }

  void _select(int index) {
    setState(() => _selected = index);
    if (kIsWeb) {
      Future.delayed(Duration.zero, _sync);
    }
  }

  void _sync() {
    final jsPane = _jsPane.currentNode;
    if (jsPane != null) {
      _renderMermaidJs(jsPane, _sample.source.toJS);
    }
    if (!_flutterStarted) {
      final host = _flutterPane.currentNode;
      if (host != null) {
        _flutterStarted = true;
        _loadMermaidDart(host, _sample.source.toJS);
      }
    } else {
      _updateMermaidDart(_sample.source.toJS);
    }
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'compare', [
      for (final category in sampleCategories) ...[
        div(classes: 'cat-label', [.text(category)]),
        div(classes: 'chips', [
          for (var i = 0; i < samples.length; i++)
            if (samples[i].category == category)
              button(
                classes: i == _selected ? 'chip selected' : 'chip',
                onClick: () => _select(i),
                [.text(samples[i].name)],
              ),
        ]),
      ],
      div(classes: 'doc', [
        h2([.text(_sample.name)]),
        p(classes: 'doc-desc', [.text(_sample.description)]),
      ]),
      pre(classes: 'source', [code([.text(_sample.source.trim())])]),
      div(classes: 'panes', [
        div(classes: 'pane', [
          div(classes: 'pane-title', [.text('mermaid.js (browser)')]),
          div(key: _jsPane, classes: 'pane-body', id: 'pane-mermaid-js', [
            .text('Loading mermaid.js…'),
          ]),
        ]),
        div(classes: 'pane', [
          div(classes: 'pane-title', [.text('mermaid dart (Flutter)')]),
          div(
            key: _flutterPane,
            classes: 'pane-body flutter-host',
            id: 'pane-mermaid-dart',
            [.text('Loading Flutter…')],
          ),
        ]),
      ]),
    ]);
  }
}

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

/// Layout engines offered in the picker (label, config value).
const _layouts = <(String, String)>[
  ('Default (dagre)', 'dagre'),
  ('ELK', 'elk'),
  ('Tidy tree', 'tidy-tree'),
];

class _CompareViewState extends State<CompareView> {
  int _selected = 0;
  String _layout = 'dagre';
  bool _flutterStarted = false;

  /// Live editor contents; starts from the selected sample and is edited in
  /// place. Both previews re-render from this, not from the sample.
  String _source = samples[0].source.trim();
  Timer? _debounce;
  final _jsPane = GlobalNodeKey<web.HTMLElement>();
  final _flutterPane = GlobalNodeKey<web.HTMLElement>();
  final _editor = GlobalNodeKey<web.HTMLTextAreaElement>();

  Sample get _sample => samples[_selected];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      Future.delayed(Duration.zero, _sync);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Picking a sample replaces the editor contents and re-renders.
  void _select(int index) {
    setState(() {
      _selected = index;
      _source = samples[index].source.trim();
    });
    if (kIsWeb) {
      _editor.currentNode?.value = _source;
      Future.delayed(Duration.zero, _sync);
    }
  }

  /// Each keystroke updates [_source] and re-renders both panes after a short
  /// debounce (no setState — that would reset the textarea caret).
  void _onInput(web.Event event) {
    final ta = event.target as web.HTMLTextAreaElement?;
    if (ta == null) return;
    _source = ta.value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _sync);
  }

  void _selectLayout(String layout) {
    setState(() => _layout = layout);
    if (kIsWeb) Future.delayed(Duration.zero, _sync);
  }

  /// Injects the chosen `layout` as an `%%{init}%%` directive (after any
  /// frontmatter) so both renderers pick it up, without touching the editor.
  String get _effective {
    if (_layout == 'dagre') return _source;
    final directive = "%%{init: {'layout': '$_layout'}}%%";
    final s = _source.trimLeft();
    if (s.startsWith('---')) {
      final end = s.indexOf('\n---', 3);
      if (end >= 0) {
        final close = s.indexOf('\n', end + 1);
        final cut = close >= 0 ? close + 1 : s.length;
        return '${s.substring(0, cut)}$directive\n${s.substring(cut)}';
      }
    }
    return '$directive\n$_source';
  }

  void _sync() {
    final src = _effective;
    final jsPane = _jsPane.currentNode;
    if (jsPane != null) {
      _renderMermaidJs(jsPane, src.toJS);
    }
    if (!_flutterStarted) {
      final host = _flutterPane.currentNode;
      if (host != null) {
        _flutterStarted = true;
        _loadMermaidDart(host, src.toJS);
      }
    } else {
      _updateMermaidDart(src.toJS);
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
      div(classes: 'layout-row', [
        span(classes: 'layout-label', [.text('Layout')]),
        for (final (label, value) in _layouts)
          button(
            classes: value == _layout ? 'chip selected' : 'chip',
            onClick: () => _selectLayout(value),
            [.text(label)],
          ),
        span(classes: 'layout-hint', [
          .text('applies to flowcharts (graph diagrams)'),
        ]),
      ]),
      textarea(
        key: _editor,
        classes: 'source editor',
        rows: 8,
        attributes: {'spellcheck': 'false', 'autocomplete': 'off'},
        events: {'input': _onInput},
        [.text(_source)],
      ),
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

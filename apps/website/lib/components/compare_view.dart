/// Interactive comparison: the selected sample is rendered by mermaid.js
/// (left) and by the embedded Flutter build of mermaid dart (right).
///
/// The Flutter side is mounted by `jaspr_flutter_embed`'s [FlutterEmbedView]
/// (so `jaspr build` produces the Flutter web build — no separate step). Live
/// edits are pushed into the running view through the tiny JS bridge the embed
/// widget publishes (`window.mermaidDartEmbed.render`), avoiding a remount.
library;

import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_flutter_embed/jaspr_flutter_embed.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

import '../samples.dart';

// The embedded Flutter widget — real on the web build, a stub during static
// server pre-rendering (it pulls in dart:ui / Flutter, which the VM lacks).
@Import.onWeb('../flutter/mermaid_embed_app.dart', show: [#MermaidEmbedApp])
import 'compare_view.imports.dart';

// Bridge functions defined in web/embed_bridge.js.
@JS('renderMermaidJs')
external void _renderMermaidJs(web.HTMLElement el, JSString source);

// Sets window.__mermaidDartInitialSource and calls the embed's render bridge
// (a no-op until the Flutter view has booted and published it).
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

/// Render looks offered in the picker (label, `look` config value).
const _looks = <(String, String)>[
  ('Default', 'classic'),
  ('Hand-drawn', 'handDrawn'),
];

/// Diagram types for which an alternate layout engine (ELK / tidy-tree) applies.
/// The layout picker is hidden for everything else (pie, gantt, sequence, …),
/// where the engine choice has no effect.
final _layoutCapableDiagram = RegExp(
  r'^\s*(flowchart|graph|stateDiagram(?:-v2)?|mindmap)\b',
  multiLine: true,
);

class _CompareViewState extends State<CompareView> {
  int _selected = 0;
  String _layout = 'dagre';
  String _look = 'classic';

  /// Live editor contents; starts from the selected sample and is edited in
  /// place. Both previews re-render from this, not from the sample.
  String _source = samples[0].source.trim();
  Timer? _debounce;
  final _jsPane = GlobalNodeKey<web.HTMLElement>();
  final _editor = GlobalNodeKey<web.HTMLTextAreaElement>();

  Sample get _sample => samples[_selected];

  /// Whether the current diagram supports an alternate layout engine.
  bool get _supportsLayout => _layoutCapableDiagram.hasMatch(_source);

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

  /// Picking a sample replaces the editor contents (keeping the current
  /// layout choice baked in) and re-renders.
  void _select(int index) {
    final src = samples[index].source.trim();
    setState(() {
      _selected = index;
      // Hand-drawn persists across samples; a sample that ships hand-drawn
      // flips the toggle on so it stays in sync.
      if (src.contains('handDrawn')) _look = 'handDrawn';
      // Don't carry a stale ELK/tidy choice into a diagram that can't use it.
      if (!_layoutCapableDiagram.hasMatch(src)) _layout = 'dagre';
      _source = _decorate(src);
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

  /// Selecting a layout rewrites the editor text: the `%%{init}%%` layout
  /// directive is added/updated/removed in-place so the source shown matches
  /// what both panes render.
  void _selectLayout(String layout) {
    setState(() {
      _layout = layout;
      _source = _decorate(_source);
    });
    if (kIsWeb) {
      _editor.currentNode?.value = _source;
      Future.delayed(Duration.zero, _sync);
    }
  }

  void _selectLook(String look) {
    setState(() {
      _look = look;
      _source = _decorate(_source);
    });
    if (kIsWeb) {
      _editor.currentNode?.value = _source;
      Future.delayed(Duration.zero, _sync);
    }
  }

  /// Applies the current layout + look choices to [base] as managed
  /// `%%{init}%%` directives (idempotent — re-running normalises in place).
  String _decorate(String base) => _withInitDirective(
        _withInitDirective(base, 'layout', _layout == 'dagre' ? null : _layout),
        'look',
        _look == 'handDrawn' ? 'handDrawn' : null,
      );

  /// Adds/updates/removes a managed single-key `%%{init}%%` directive ([key] is
  /// `layout` or `look`). A null [value] removes it; otherwise it's inserted
  /// after frontmatter (if present) else at the top. Other init directives
  /// (e.g. a sample's `theme`) are left untouched.
  static String _withInitDirective(String base, String key, String? value) {
    var s = base.replaceAll(
        RegExp('^[ \\t]*%%\\{\\s*init[^\\n]*$key[^\\n]*\\}%%[ \\t]*\\n?',
            multiLine: true),
        '');
    s = s.trimRight();
    if (value == null) return s;
    final directive = "%%{init: {'$key': '$value'}}%%";
    final t = s.trimLeft();
    if (t.startsWith('---')) {
      final end = t.indexOf('\n---', 3);
      if (end >= 0) {
        final close = t.indexOf('\n', end + 1);
        final cut = close >= 0 ? close + 1 : t.length;
        return '${t.substring(0, cut)}$directive\n${t.substring(cut)}';
      }
    }
    return '$directive\n$s';
  }

  /// Opens a pre-filled GitHub issue with the current editor source embedded,
  /// so a render mismatch can be reported with one click.
  void _reportIssue() {
    final body = StringBuffer()
      ..writeln('### What looks wrong?')
      ..writeln()
      ..writeln('_Describe how the Flutter pane differs from mermaid.js._')
      ..writeln()
      ..writeln('### Mermaid source')
      ..writeln()
      ..writeln('```mermaid')
      ..writeln(_source)
      ..writeln('```')
      ..writeln()
      ..writeln('### Diagram: ${_sample.name}');
    final uri = Uri.https('github.com', '/orestesgaolin/mermaid/issues/new', {
      'title': 'Render issue: ${_sample.name}',
      'body': body.toString(),
    });
    web.window.open(uri.toString(), '_blank');
  }

  void _sync() {
    final src = _source;
    final jsPane = _jsPane.currentNode;
    if (jsPane != null) {
      _renderMermaidJs(jsPane, src.toJS);
    }
    // Sets the initial-source global (read by the embed at boot) and pushes
    // the update to the running Flutter view if it has booted.
    _updateMermaidDart(src.toJS);
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
      if (_supportsLayout)
        div(classes: 'layout-row', [
          span(classes: 'layout-label', [.text('Layout')]),
          for (final (label, value) in _layouts)
            button(
              classes: value == _layout ? 'chip selected' : 'chip',
              onClick: () => _selectLayout(value),
              [.text(label)],
            ),
          span(classes: 'layout-hint', [
            .text('applies to flowchart, state and mindmap diagrams'),
          ]),
        ]),
      div(classes: 'layout-row', [
        span(classes: 'layout-label', [.text('Look')]),
        for (final (label, value) in _looks)
          button(
            classes: value == _look ? 'chip selected' : 'chip',
            onClick: () => _selectLook(value),
            [.text(label)],
          ),
        span(classes: 'layout-hint', [
          .text('hand-drawn works for every diagram type'),
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
      div(classes: 'actions', [
        button(
          classes: 'report-btn',
          onClick: _reportIssue,
          [.text('⚑ Report an issue with this diagram')],
        ),
        span(classes: 'actions-hint', [
          .text('opens a GitHub issue pre-filled with the source above'),
        ]),
      ]),
      div(classes: 'panes', [
        div(classes: 'pane', [
          div(classes: 'pane-title', [.text('mermaid.js (browser)')]),
          div(key: _jsPane, classes: 'pane-body', id: 'pane-mermaid-js', [
            .text('Loading mermaid.js…'),
          ]),
        ]),
        div(classes: 'pane', [
          div(classes: 'pane-title', [.text('mermaid dart (Flutter)')]),
          FlutterEmbedView(
            id: 'pane-mermaid-dart',
            classes: 'pane-body flutter-host',
            loader: div([.text('Loading Flutter…')]),
            widget: kIsWeb ? MermaidEmbedApp() : null,
          ),
        ]),
      ]),
    ]);
  }
}

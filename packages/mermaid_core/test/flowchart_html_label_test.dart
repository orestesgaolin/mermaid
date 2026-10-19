/// HTML markup in flowchart labels (issue #79): emphasis tags become styled
/// runs, other tags are removed, as mermaid.js shows them with htmlLabels.
library;

import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

const _measurer = ApproximateTextMeasurer();
const _renderer = Mermaid(measurer: _measurer);

const _issue79 = '''
flowchart TD
    E["<b>Endpoint</b><br/>Receives external requests<br/>Knows about: Service"]
    S["<b>Service / Use Case</b><br/>Knows about: Repository (interface)"]
    R["<b>Repository</b><br/>Returns: Model (domain)"]
    D["<b>Data Source / Gateway</b><br/>Knows about: raw I/O (sockets, DB)"]
    E --> S --> R --> D
''';

SceneGroup _group(List<SceneNode> nodes, String id) {
  for (final node in nodes) {
    if (node is SceneGroup) {
      if (node.id == id) return node;
      try {
        return _group(node.children, id);
      } on StateError {
        continue;
      }
    }
  }
  throw StateError('no group $id');
}

List<SceneText> _texts(SceneNode node) => switch (node) {
  SceneText() => [node],
  SceneGroup(:final children) => [for (final c in children) ..._texts(c)],
  _ => const [],
};

Rect _nodeBox(SceneGroup group) => group.children
    .whereType<SceneShape>()
    .map((s) => s.geometry)
    .whereType<RectGeometry>()
    .first
    .rect;

bool _inside(Rect inner, Rect outer) =>
    inner.left >= outer.left - 0.001 &&
    inner.right <= outer.right + 0.001 &&
    inner.top >= outer.top - 0.001 &&
    inner.bottom <= outer.bottom + 0.001;

void main() {
  group('issue #79 diagram', () {
    final scene = _renderer.render(_issue79);

    test('no node paints tag text', () {
      for (final id in ['E', 'S', 'R', 'D']) {
        for (final t in _texts(_group(scene.nodes, id))) {
          expect(t.text, isNot(contains('<')), reason: 'node $id');
          expect(t.text, isNot(contains('>')), reason: 'node $id');
        }
      }
    });

    test('the <b> run is bold, the other lines are regular', () {
      final texts = _texts(_group(scene.nodes, 'E'));
      expect(texts.map((t) => t.text), [
        'Endpoint',
        'Receives external requests',
        'Knows about: Service',
      ]);
      expect(texts[0].style.fontWeight, 700);
      expect(texts[1].style.fontWeight, 400);
      expect(texts[2].style.fontWeight, 400);
      // Lines stack top to bottom.
      expect(texts[0].bounds.bottom, lessThanOrEqualTo(texts[1].bounds.top));
      expect(texts[1].bounds.bottom, lessThanOrEqualTo(texts[2].bounds.top));
    });

    test('the node box fits the text measured in bold', () {
      for (final id in ['E', 'S', 'R', 'D']) {
        final group = _group(scene.nodes, id);
        final box = _nodeBox(group);
        final texts = _texts(group);
        final bold = texts.firstWhere((t) => t.style.fontWeight == 700);
        // The run is sized with the bold style it paints with, which is wider
        // than the same text at regular weight.
        expect(
          bold.bounds.width,
          _measurer.measure(bold.text, bold.style).width,
        );
        expect(
          bold.bounds.width,
          greaterThan(
            _measurer
                .measure(bold.text, bold.style.copyWith(fontWeight: 400))
                .width,
          ),
        );
        for (final t in texts) {
          expect(_inside(t.bounds, box), isTrue, reason: '$id "${t.text}"');
        }
      }
    });

    test('long lines wrap at whitespace within wrappingWidth', () {
      final texts = _texts(_group(scene.nodes, 'D'));
      expect(texts.map((t) => t.text), [
        'Data Source / Gateway',
        'Knows about: raw I/O',
        '(sockets, DB)',
      ]);
      for (final t in texts) {
        expect(t.bounds.width, lessThanOrEqualTo(200));
      }
      // The semantic label reads as the source: soft wraps are not in it.
      expect(
        _group(scene.nodes, 'D').semanticLabel,
        'Data Source / Gateway\nKnows about: raw I/O (sockets, DB)',
      );
    });

    test('semantic label and SVG carry the text without tags', () {
      expect(
        _group(scene.nodes, 'E').semanticLabel,
        'Endpoint\nReceives external requests\nKnows about: Service',
      );
      final svg = renderSceneToSvg(scene);
      expect(svg, contains('font-weight="700"'));
      expect(svg, isNot(contains('&lt;b')));
      expect(svg, isNot(contains('&lt;/b')));
    });
  });

  test('<strong>, <em> and nesting map to bold and italic runs', () {
    final scene = _renderer.render(
      'flowchart LR\n  A["<em><strong>both</strong> slant</em> <i>i</i>"]',
    );
    final texts = _texts(_group(scene.nodes, 'A'));
    expect(texts.map((t) => (t.text, t.style.fontWeight, t.style.italic)), [
      ('both', 700, true),
      ('slant', 400, true),
      ('i', 400, true),
    ]);
    // Runs follow each other on one line: the space between them is kept as
    // run advance, not painted.
    expect(texts[1].bounds.left, greaterThan(texts[0].bounds.right));
    expect(texts[1].bounds.top, texts[0].bounds.top);
  });

  test('other tags are removed, script text is dropped, a lone < stays', () {
    final scene = _renderer.render(
      'flowchart LR\n'
      '  A["<span style=\'color:red\'>keep</span> <u>u</u> a < b'
      '<script>bad()</script><!-- note -->"]',
    );
    final group = _group(scene.nodes, 'A');
    expect(group.semanticLabel, 'keep u a < b');
    expect(_texts(group).map((t) => t.text), ['keep u a < b']);
    expect(_texts(group).single.style.fontWeight, 400);
  });

  test('edge labels render <b> as a bold run', () {
    final scene = _renderer.render(
      'flowchart LR\n  A -->|"<b>calls</b> api"| B',
    );
    final label = _group(scene.nodes, 'edgelabel_A_B_0');
    final texts = _texts(label);
    expect(texts.map((t) => (t.text, t.style.fontWeight)), [
      ('calls', 700),
      ('api', 400),
    ]);
    final background = label.children
        .whereType<SceneShape>()
        .map((s) => s.geometry)
        .whereType<RectGeometry>()
        .first
        .rect;
    for (final t in texts) {
      expect(_inside(t.bounds, background), isTrue, reason: t.text);
    }
    expect(_group(scene.nodes, 'edge_A_B_0').semanticLabel, 'calls api');
  });

  test('subgraph titles render <b> as a bold run inside the cluster', () {
    final scene = _renderer.render('''
flowchart TB
  subgraph G["<b>Core</b> layer"]
    A --> B
  end
''');
    final cluster = _group(scene.nodes, 'G');
    expect(cluster.semanticLabel, 'Core layer');
    final texts = _texts(cluster);
    expect(texts.map((t) => (t.text, t.style.fontWeight)), [
      ('Core', 700),
      ('layer', 400),
    ]);
    final rect = _nodeBox(cluster);
    for (final t in texts) {
      expect(_inside(t.bounds, rect), isTrue, reason: t.text);
    }
  });
}

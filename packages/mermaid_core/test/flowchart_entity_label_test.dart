/// Entity codes in flowchart labels (issue #86): `#quot;`, `#35;` and HTML
/// character references show as the character, as in mermaid.js.
library;

import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

const _measurer = ApproximateTextMeasurer();
const _renderer = Mermaid(measurer: _measurer);

SceneGroup? _find(List<SceneNode> nodes, String id) {
  for (final node in nodes) {
    if (node is! SceneGroup) continue;
    if (node.id == id) return node;
    final nested = _find(node.children, id);
    if (nested != null) return nested;
  }
  return null;
}

List<SceneText> _texts(SceneNode node) => switch (node) {
  SceneText() => [node],
  SceneGroup(:final children) => [for (final c in children) ..._texts(c)],
  _ => const [],
};

List<SceneText> _allTexts(RenderScene scene) => [
  for (final n in scene.nodes) ..._texts(n),
];

List<SceneText> _nodeTexts(RenderScene scene, String id) =>
    _texts(_find(scene.nodes, id)!);

/// The painted text of node [id]; wrapped lines are joined with a space.
String _nodeText(RenderScene scene, String id) =>
    _nodeTexts(scene, id).map((t) => t.run?.text ?? t.text).join(' ');

double _nodeWidth(RenderScene scene, String id) => _find(scene.nodes, id)!
    .children
    .whereType<SceneShape>()
    .map((s) => s.geometry)
    .whereType<RectGeometry>()
    .first
    .rect
    .width;

void main() {
  group('issue #86 diagram', () {
    final scene = _renderer.render('''
flowchart LR
  n1["Token #quot;leaks#quot; via #35;frag #lt;b#gt; and #96;x#96;"]
  n2["b"]
  n1 --> n2
''');

    test('the node shows the decoded characters at normal weight', () {
      // The label is wider than the 200 px wrapping width, so it wraps.
      expect(_nodeTexts(scene, 'n1').map((t) => t.text), [
        'Token "leaks" via #frag <b>',
        'and `x`',
      ]);
      expect(
        _find(scene.nodes, 'n1')!.semanticLabel,
        'Token "leaks" via #frag <b> and `x`',
      );
      for (final t in _nodeTexts(scene, 'n1')) {
        expect(t.style.fontWeight, 400);
        expect(t.style.italic, isFalse);
      }
      expect(_nodeText(scene, 'n2'), 'b');
    });

    test('the SVG text holds the characters, escaped once', () {
      final svg = renderSceneToSvg(scene);
      expect(svg, contains('>Token "leaks" via #frag &lt;b&gt;</tspan>'));
      expect(svg, contains('>and `x`</tspan>'));
      expect(svg, isNot(contains('#quot;')));
      expect(svg, isNot(contains('⁠')));
    });
  });

  test('a decoded label has the size of the same label typed directly', () {
    final scene = _renderer.render('''
flowchart LR
  coded["a #lt; b #amp; #apos;c#apos; #35;1"]
  typed["a < b & 'c' #1"]
  html["a &lt; b &amp; &apos;c&apos; &#35;1"]
  coded --> typed --> html
''');
    expect(_nodeText(scene, 'coded'), "a < b & 'c' #1");
    expect(_nodeText(scene, 'html'), "a < b & 'c' #1");
    expect(_nodeWidth(scene, 'html'), _nodeWidth(scene, 'typed'));
    expect(_nodeWidth(scene, 'coded'), _nodeWidth(scene, 'typed'));
  });

  test('decimal, hexadecimal and named codes decode; unknown names stay', () {
    final scene = _renderer.render('''
flowchart LR
  a["I #9829; #hearts; &#x2665; &hearts;"]
  b["#nosuch; &nosuch; #x41;"]
  a --> b
''');
    expect(_nodeText(scene, 'a'), 'I ♥ ♥ ♥ ♥');
    expect(_nodeText(scene, 'b'), '#nosuch; &nosuch; #x41;');
  });

  test('an entity is decoded once', () {
    final scene = _renderer.render('''
flowchart LR
  a["#amp;lt; &amp;gt; #35;quot;"]
''');
    expect(_nodeText(scene, 'a'), '&lt; &gt; #quot;');
  });

  test('a real tag is bold, a coded tag beside it is text', () {
    final scene = _renderer.render('''
flowchart LR
  a["<b>bold</b> #lt;b#gt;plain#lt;/b#gt; <#98;> &lt;i&gt;"]
''');
    final texts = _nodeTexts(scene, 'a');
    expect(texts.map((t) => t.text), ['bold', '<b>plain</b> <b> <i>']);
    expect(texts[0].style.fontWeight, 700);
    expect(texts[1].style.fontWeight, 400);
    expect(texts[1].style.italic, isFalse);
    expect(_find(scene.nodes, 'a')!.semanticLabel, 'bold <b>plain</b> <b> <i>');
  });

  test('a coded <br> is text and does not break the line', () {
    final scene = _renderer.render('''
flowchart LR
  a["one #lt;br#gt; two"]
''');
    expect(_nodeTexts(scene, 'a').map((t) => t.text), ['one <br> two']);
  });

  test('edge labels and subgraph titles decode', () {
    final scene = _renderer.render('''
flowchart LR
  subgraph sg["Group #35;1 #lt;b#gt;"]
    a --> |"#quot;piped#quot;"| b
  end
  b -- say #quot;hi#quot; --> c
''');
    final texts = _allTexts(scene).map((t) => t.run?.text ?? t.text).toList();
    expect(texts, contains('Group #1 <b>'));
    expect(texts, contains('"piped"'));
    expect(texts, contains('say "hi"'));
  });

  group('a ; that closes an entity code does not end the statement', () {
    test('in unquoted labels on one line with other statements', () {
      final scene = _renderer.render('''
flowchart LR
  a -- no #35;1 --> b; b -->|#lt;ok#gt;| c; c[C #amp; D]
''');
      final texts = _allTexts(scene).map((t) => t.text).toList();
      expect(texts, containsAll(['no #1', '<ok>', 'C & D']));
      expect(_find(scene.nodes, 'a'), isNotNull);
      expect(_find(scene.nodes, 'b'), isNotNull);
    });

    test('a color with decimal digits still ends its style statement', () {
      final scene = _renderer.render('''
flowchart LR
  a --> b; style a fill:#123; b --> c; style c fill:#456,stroke:#789;
''');
      Color fill(String id) => _find(
        scene.nodes,
        id,
      )!.children.whereType<SceneShape>().first.fill!.color;
      expect(fill('a'), const Color(0xff112233));
      expect(fill('c'), const Color(0xff445566));
      expect(_find(scene.nodes, 'c'), isNotNull);
    });
  });
}

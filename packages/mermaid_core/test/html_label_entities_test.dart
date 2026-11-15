/// Entity codes in the labels that mermaid.js shows as HTML labels, outside
/// flowcharts: `#amp;`, `#lt;` and `#35;` show as the character.
library;

import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());

List<SceneText> _texts(SceneNode node) => switch (node) {
  SceneText() => [node],
  SceneGroup(:final children) => [for (final c in children) ..._texts(c)],
  _ => const [],
};

List<SceneText> _render(String source) => [
  for (final n in _renderer.render(source).nodes) ..._texts(n),
];

/// Diagram source and the label texts it must paint.
const _cases = <String, (String, List<String>)>{
  'class label, relation label and note': (
    '''
classDiagram
  class A["Tom #amp; Jerry"]
  class B
  A --> B : uses #lt;T#gt;
  note for A "say #quot;hi#quot;"
''',
    ['Tom & Jerry', 'uses <T>', 'say "hi"'],
  ),
  'state description, transition label and note': (
    '''
stateDiagram-v2
  s1 : Tom #amp; Jerry
  s1 --> s2 : a #lt; b
  note right of s1 : say #quot;hi#quot;
''',
    ['Tom & Jerry', 'a < b', 'say "hi"'],
  ),
  'ER entity alias, attribute comment and relationship label': (
    '''
erDiagram
  A["Tom #amp; Jerry"] {
    string name "a #lt; b"
  }
  A ||--o{ B : "has #35;1"
''',
    ['Tom & Jerry', 'a < b', 'has #1'],
  ),
  'requirement field value': (
    '''
requirementDiagram
  requirement r1 {
    id: 1
    text: "a #lt; b #amp; c"
    risk: high
    verifymethod: test
  }
''',
    ['Text: a < b & c'],
  ),
  'block label and block edge label': (
    '''
block-beta
  a["Tom #amp; Jerry"] b["x"]
  a -- "a #lt; b" --> b
''',
    ['Tom & Jerry', 'a < b'],
  ),
  'mindmap nodes': (
    '''
mindmap
  root((Tom #amp; Jerry))
    child[a #lt; b]
''',
    ['Tom & Jerry', 'a < b'],
  ),
  'kanban section, card and assigned label': (
    '''
kanban
  todo[To do #35;1]
    t1[Tom #amp; Jerry]
    t2[Other]@{ assigned: "a #lt; b" }
''',
    ['To do #1', 'Tom & Jerry', 'a < b'],
  ),
};

void main() {
  for (final MapEntry(key: name, value: (source, expected)) in _cases.entries) {
    test(name, () {
      final painted = _render(source).map((t) => t.text).toList();
      expect(painted, containsAll(expected));
      for (final text in painted) {
        expect(text, isNot(matches(r'#\w+;')));
        expect(text, isNot(contains('⁠')));
      }
    });
  }

  test('a real tag is bold, a coded tag beside it is text', () {
    final texts = _render('''
stateDiagram-v2
  s1 : <b>bold</b> #lt;b#gt;plain#lt;/b#gt;
''');
    final bold = texts.singleWhere((t) => t.text == 'bold');
    final plain = texts.singleWhere((t) => t.text == '<b>plain</b>');
    expect(bold.style.fontWeight, 700);
    expect(plain.style.fontWeight, lessThan(700));
  });

  test('&nbsp; in a block label is a no-break space', () {
    final painted = _render('''
block-beta
  a["one&nbsp;two"]
''').map((t) => t.text);
    expect(painted, contains('one\u00a0two'));
  });
}

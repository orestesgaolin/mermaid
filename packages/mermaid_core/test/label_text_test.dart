/// The parsed label type of the diagram models: plain text, or lines of
/// styled spans. The text never holds markup.
library;

import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());

List<SceneText> _texts(SceneNode node) => switch (node) {
  SceneText() => [node],
  SceneGroup(:final children) => [for (final c in children) ..._texts(c)],
  _ => const [],
};

void main() {
  group('flowchart model', () {
    test('tags become spans and line breaks become lines', () {
      final graph = parseFlowchart('''
flowchart LR
  subgraph sg["<i>Group</i> one"]
    E["<b>Endpoint</b><br/>Receives <i>requests</i>"]
  end
  E -->|"<b>calls</b> it"| S[Service]
''');
      final label = graph.nodes['E']!.label;
      expect(label.text, 'Endpoint\nReceives requests');
      expect(label.isStyled, isTrue);
      expect(label.lines, [
        [const LabelSpan('Endpoint', bold: true)],
        [
          const LabelSpan('Receives '),
          const LabelSpan('requests', italic: true),
        ],
      ]);
      expect(graph.edges.single.label!.lines, [
        [const LabelSpan('calls', bold: true), const LabelSpan(' it')],
      ]);
      expect(graph.subgraphs.single.title.lines, [
        [const LabelSpan('Group', italic: true), const LabelSpan(' one')],
      ]);
      // A label without styles is equal to its plain text.
      expect(graph.nodes['S']!.label, const LabelText('Service'));
      expect(graph.nodes['S']!.label.isStyled, isFalse);
    });

    test('a tag written with entity codes is text, not a span', () {
      final graph = parseFlowchart('''
flowchart LR
  a["#lt;b#gt;plain#lt;/b#gt;"]
''');
      expect(graph.nodes['a']!.label, const LabelText('<b>plain</b>'));
      final painted = _texts(
        _renderer
            .render('flowchart LR\n  a["#lt;b#gt;plain#lt;/b#gt;"]')
            .nodes
            .whereType<SceneGroup>()
            .firstWhere((g) => g.id == 'a'),
      );
      expect(painted.map((t) => t.text), ['<b>plain</b>']);
      expect(painted.single.style.fontWeight, 400);
    });

    test('** written with entity codes is text in a Markdown string', () {
      final graph = parseFlowchart('''
flowchart LR
  a["`#42;#42;x#42;#42; and **y**`"]
''');
      final label = graph.nodes['a']!.label;
      expect(label.text, '**x** and y');
      expect(label.lines, [
        [const LabelSpan('**x** and '), const LabelSpan('y', bold: true)],
      ]);
    });
  });

  test('a second state description is a new line and keeps its spans', () {
    final diagram = parseStateDiagram('''
stateDiagram-v2
  s1 : <b>first</b>
  s1 : second
''');
    final label = diagram.states['s1']!.label;
    expect(label.text, 'first\nsecond');
    expect(label.lines, [
      [const LabelSpan('first', bold: true)],
      [const LabelSpan('second')],
    ]);
  });

  test('a requirement field keeps the spans of its value after the name', () {
    final texts = [
      for (final n in _renderer.render('''
requirementDiagram
  requirement r1 {
    id: 1
    text: "<b>must</b> pass"
  }
''').nodes)
        ..._texts(n),
    ];
    final must = texts.singleWhere((t) => t.text == 'must');
    final prefix = texts.singleWhere((t) => t.text == 'Text:');
    expect(must.style.fontWeight, 700);
    expect(prefix.style.fontWeight, lessThan(700));
    expect(prefix.bounds.right, lessThanOrEqualTo(must.bounds.left));
  });
}

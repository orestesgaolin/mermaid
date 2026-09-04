/// Title precedence for `radar-beta`.
///
/// Upstream's `setDiagramTitle` overwrites whatever the frontmatter set, so a
/// body `title` line always wins — the same rule every other diagram in this
/// package follows. The radar parser used `??=` and kept the frontmatter one.
library;

import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:test/test.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());

List<SceneNode> _flatten(List<SceneNode> nodes) => [
  for (final node in nodes) ...[
    node,
    if (node is SceneGroup) ..._flatten(node.children),
  ],
];

Iterable<String> _texts(String source) => _flatten(
  _renderer.render(source).nodes,
).whereType<SceneText>().map((text) => text.text);

const _body = '''
radar-beta
  axis a["A"], b["B"], c["C"]
  curve x["X"]{1, 2, 3}
''';

void main() {
  test('a body title overrides the frontmatter title', () {
    final texts = _texts(
      '---\ntitle: From frontmatter\n---\n'
      '${_body.replaceFirst('radar-beta\n', 'radar-beta\n  title From body\n')}',
    );
    expect(texts, contains('From body'));
    expect(texts, isNot(contains('From frontmatter')));
  });

  test('the frontmatter title is still used when the body has none', () {
    expect(
      _texts('---\ntitle: From frontmatter\n---\n$_body'),
      contains('From frontmatter'),
    );
  });

  test('a later body title overrides an earlier one', () {
    final texts = _texts(
      _body.replaceFirst(
        'radar-beta\n',
        'radar-beta\n  title First\n  title Second\n',
      ),
    );
    expect(texts, contains('Second'));
    expect(texts, isNot(contains('First')));
  });
}

/// `config.elk` options reach the ELK flowchart layout.
library;

import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

import 'support/scene.dart';

const _mermaid = Mermaid(measurer: ApproximateTextMeasurer());

const _body = '''
flowchart TD
  A --> C
  A --> D
  B --> C
  B --> D
  A --> E
  B --> E''';

String _geometry(String source) => sceneGeometry(_mermaid.render(source));

void main() {
  test('YAML frontmatter elk options apply like an init directive', () {
    final yaml = _geometry(
      '---\nconfig:\n  layout: elk\n  elk:\n'
      '    nodePlacementAlignment: RIGHTUP\n---\n$_body',
    );
    final init = _geometry(
      '%%{init: {"layout": "elk", '
      '"elk": {"nodePlacementAlignment": "RIGHTUP"}}}%%\n$_body',
    );
    final plain = _geometry('---\nconfig:\n  layout: elk\n---\n$_body');
    expect(yaml, init);
    expect(yaml, isNot(plain));
  });
}

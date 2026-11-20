/// mermaid 12 ELK presets (`elk.preset`) for flowcharts, issue #92.
library;

import 'package:elk/elk.dart' as elk;
import 'package:mermaid_core/mermaid_core.dart';
import 'package:mermaid_core/src/ir/scene_utils.dart' show sceneNodeBounds;
import 'package:test/test.dart';

import 'support/scene.dart';

const _mermaid = Mermaid(measurer: ApproximateTextMeasurer());

String _elk(String body, {String? preset, String extra = ''}) =>
    '---\nconfig:\n  layout: elk\n'
    '${preset == null && extra.isEmpty ? '' : '  elk:\n'}'
    '${preset == null ? '' : '    preset: $preset\n'}$extra---\n$body';

Map<String, Rect> _boxes(String source) => {
  for (final g in groupsOf(_mermaid.render(source).nodes))
    if (g.id != null &&
        !g.id!.startsWith('edge_') &&
        sceneNodeBounds(g) != null)
      g.id!: sceneNodeBounds(g)!,
};

const _hops = '''
flowchart TD
  A --> C
  A --> D
  B --> C
  B --> D
  A --> E
  B --> E''';

const _feedback = '''
flowchart TD
  A([Start]) --> B[Step 1]
  B --> C{Flow 1}
  C -- Choice 1.1 --> D[Step 2.1]
  C -- Choice 1.3 --> I[Step 2.3]
  C -- Choice 1.2 --> E[Step 2.2]
  D --> F{Flow 2}
  E --> F
  F -- Choice 2.1 --> H[Feedback node]
  H --> B
  F -- Choice 2.2 --> G((Finish))''';

void main() {
  test('default preset balances placement', () {
    final b = _boxes(_elk(_hops));
    final a = b['A']!.center.x;
    expect(a, greaterThan(b['C']!.right));
    expect(a, lessThan(b['D']!.center.x));
  });

  test('legacy preset restores the unbalanced placement', () {
    final b = _boxes(_elk(_hops, preset: 'legacy'));
    expect(b['A']!.center.x, lessThan(b['C']!.right));
  });

  test('default preset keeps the entry node above a loop', () {
    final b = _boxes(_elk(_feedback));
    expect(b['A']!.bottom, lessThan(b['B']!.top));
    expect(b['B']!.bottom, lessThan(b['C']!.top));
    expect(b['F']!.bottom, lessThan(b['H']!.top));
  });

  test('legacy preset restores greedy cycle breaking', () {
    final b = _boxes(_elk(_feedback, preset: 'legacy'));
    expect(b['A']!.top, greaterThan(b['C']!.bottom));
  });

  test('explicit elk keys win over the preset', () {
    expect(
      _boxes(
        _elk(
          _feedback,
          extra:
              '    nodePlacementAlignment: NONE\n'
              '    cycleBreakingStrategy: GREEDY\n',
        ),
      ),
      _boxes(_elk(_feedback, preset: 'legacy')),
    );
  });

  test('an unknown preset name falls back to default', () {
    expect(_boxes(_elk(_hops, preset: 'Legacy')), _boxes(_elk(_hops)));
  });

  test('reserves a ports-surrounding margin inside subgraph frames', () {
    const src = '''
flowchart LR
  a1 --> b1
  a2 --> b1
  a3 --> b1
  subgraph S
    b1
  end''';
    Rect frame(elk.ElkLayoutOptions options) => groupsOf(
      layoutFlowchart(
        parseFlowchart(src),
        measurer: const ApproximateTextMeasurer(),
        theme: MermaidTheme.defaultTheme,
        engine: 'elk',
        elkOptions: options,
      ).nodes,
    ).where((g) => g.id == 'S').map(sceneNodeBounds).single!;
    final options = resolveElkConfig(src);
    expect(options.spacingPortsSurroundingTop, 12);
    expect(options.spacingPortsSurroundingBottom, 12);
    final without = frame(
      options.copyWith(
        spacingPortsSurroundingTop: 0,
        spacingPortsSurroundingBottom: 0,
      ),
    );
    expect(frame(options).height, greaterThanOrEqualTo(without.height + 12));
  });
}

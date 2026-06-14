/// Parse + render smoke tests for cynefin, venn, ishikawa, wardley,
/// eventmodeling and railroad.
library;

import 'package:mermaid_core/src/detect.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:test/test.dart';

const _m = Mermaid(measurer: ApproximateTextMeasurer());

List<SceneNode> _flat(List<SceneNode> n) => [
      for (final x in n) ...[
        x,
        if (x is SceneGroup) ..._flat(x.children),
      ],
    ];

Iterable<String> _texts(RenderScene s) =>
    _flat(s.nodes).whereType<SceneText>().map((t) => t.text);

void main() {
  test('detect recognizes all six headers', () {
    expect(detectDiagramType('cynefin-beta\n clear'), DiagramType.cynefin);
    expect(detectDiagramType('venn-beta\n set A'), DiagramType.venn);
    expect(detectDiagramType('ishikawa-beta\n P'), DiagramType.ishikawa);
    expect(detectDiagramType('wardley-beta\n title X'), DiagramType.wardley);
    expect(detectDiagramType('eventmodeling\n tf 01 ui A'),
        DiagramType.eventModeling);
    expect(detectDiagramType('railroad-diagram\n a = "x" ;'),
        DiagramType.railroad);
  });

  test('cynefin renders domains and items', () {
    final s = _m.render('''
cynefin-beta
  title Test
  clear
    "Restart"
  complex
    "Investigate"
''');
    expect(_texts(s), containsAll(['Clear', 'Restart', 'Investigate']));
  });

  test('venn renders sets and union label', () {
    final s = _m.render('''
venn-beta
  set Frontend
  set Backend
  union Frontend,Backend["APIs"]
''');
    expect(_texts(s), containsAll(['Frontend', 'Backend', 'APIs']));
  });

  test('ishikawa renders problem head and categories', () {
    final s = _m.render('''
ishikawa-beta
    Blurry Photo
    Process
        Out of focus
    Equipment
        Dirty lens
''');
    expect(_texts(s), containsAll(['Blurry Photo', 'Process', 'Out of focus']));
  });

  test('wardley renders components and axis stages', () {
    final s = _m.render('''
wardley-beta
title Tea
component Kettle [0.43, 0.35]
component Power [0.10, 0.70]
Kettle -> Power
evolve Kettle 0.62
''');
    expect(_texts(s), containsAll(['Kettle', 'Power', 'Genesis']));
  });

  test('eventmodeling renders typed lanes', () {
    final s = _m.render('''
eventmodeling
tf 01 ui CartUI
tf 02 cmd AddItem
tf 03 evt ItemAdded
''');
    // Upstream conceptual swimlanes: UI/Automation, Command/Read Model, Events.
    expect(
      _texts(s),
      containsAll(
        ['CartUI', 'AddItem', 'UI/Automation', 'Command/Read Model'],
      ),
    );
  });

  test('railroad renders rule alternatives', () {
    final s = _m.render('''
railroad-diagram
digit = "0" | "1" | "2" ;
''');
    // Upstream renders the rule name with a trailing ' =' on the rail.
    expect(_texts(s), containsAll(['digit =', '0', '1', '2']));
  });
}

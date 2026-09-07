import 'support/scene.dart';
import 'package:mermaid_core/mermaid_core.dart';
import 'package:mermaid_core/src/diagrams/git/git_graph.dart';
import 'package:test/test.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());

Rect _largestRect(SceneGroup group) => group.children
    .whereType<SceneShape>()
    .map((shape) => shape.geometry)
    .whereType<RectGeometry>()
    .map((geometry) => geometry.rect)
    .reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);

void main() {
  test('frontmatter changes flowchart scene padding', () {
    final normal = _renderer.render('flowchart LR\nA --> B');
    final padded = _renderer.render('''
---
config:
  flowchart:
    diagramPadding: 42
---
flowchart LR
A --> B
''');
    expect(padded.size.width - normal.size.width, closeTo(68, 0.01));
    expect(
      FlowchartConfig.fromSource('''
%%{init: {"flowchart": {"padding": 21, "wrappingWidth": 90}}}%%
flowchart LR
A
''').padding,
      21,
    );
  });

  test('flowchart title and subgraph title margins change scene geometry', () {
    const source = '''
---
title: Overview
---
flowchart TB
subgraph Group
  A
end
''';
    final normal = _renderer.render(source);
    final configured = _renderer.render('''
---
title: Overview
---
%%{init: {"flowchart": {"titleTopMargin": 35,
 "subGraphTitleMargin": {"top": 18, "bottom": 22}}}}%%
flowchart TB
subgraph Group
  A
end
''');
    final normalGroup = flattenScene(
      normal.nodes,
    ).whereType<SceneGroup>().singleWhere((group) => group.id == 'Group');
    final configuredGroup = flattenScene(
      configured.nodes,
    ).whereType<SceneGroup>().singleWhere((group) => group.id == 'Group');
    expect(
      _largestRect(configuredGroup).height - _largestRect(normalGroup).height,
      closeTo(40, 0.01),
    );
    expect(configured.size.height, greaterThan(normal.size.height + 30));
  });

  test('class config hides empty compartments and changes scene padding', () {
    final visible = _renderer.render('classDiagram\nclass A');
    final hidden = _renderer.render('''
%%{init: {"class": {"hideEmptyMembersBox": true, "diagramPadding": 30}}}%%
classDiagram
class A
''');
    expect(hidden.size.height, lessThan(visible.size.height + 44));
    final config = ClassConfig.fromSource('''
---
config:
  class:
    hideEmptyMembersBox: true
    diagramPadding: 30
---
classDiagram
class A
''');
    expect(config.hideEmptyMembersBox, isTrue);
    expect(config.diagramPadding, 30);
  });

  test('class hierarchicalNamespaces expands dotted namespace clusters', () {
    final hierarchical = _renderer.render('''
classDiagram
namespace A.B.C {
  class Item
}
''');
    final ids = flattenScene(
      hierarchical.nodes,
    ).whereType<SceneGroup>().map((group) => group.id);
    expect(
      ids,
      containsAll(['namespace_A', 'namespace_A.B', 'namespace_A.B.C']),
    );

    final compact = _renderer.render('''
%%{init: {"class": {"hierarchicalNamespaces": false}}}%%
classDiagram
namespace A.B.C {
  class Item
}
''');
    final compactIds = flattenScene(
      compact.nodes,
    ).whereType<SceneGroup>().map((group) => group.id);
    expect(compactIds, contains('namespace_A.B.C'));
    expect(compactIds, isNot(contains('namespace_A.B')));
  });

  test(
    'sequence frontmatter removes unused participant and sizes label tab',
    () {
      final normal = _renderer.render(
        'sequenceDiagram\nparticipant A\nparticipant B\nA->>A: hi',
      );
      final configured = _renderer.render('''
---
config:
  sequence:
    hideUnusedParticipants: true
    labelBoxWidth: 120
    labelBoxHeight: 35
    bottomMarginAdj: 20
---
sequenceDiagram
participant A
participant B
A->>A: hi
loop retry
A->>A: again
end
''');
      expect(configured.size.width, lessThan(normal.size.width));
      final config = SequenceConfig.fromSource('''
%%{init: {"sequence": {"hideUnusedParticipants": true, "bottomMarginAdj": 20}}}%%
sequenceDiagram
A->>A: hi
''');
      expect(config.hideUnusedParticipants, isTrue);
      expect(config.bottomMarginAdj, 20);
    },
  );

  test('sequence typography and right-angle self messages reach the scene', () {
    final scene = _renderer.render('''
%%{init: {"sequence": {"actorFontSize": "19px", "actorFontWeight": 700,
 "noteFontSize": 17, "messageFontSize": 15, "rightAngles": true}}}%%
sequenceDiagram
participant A
A->>A: message
Note over A: note
''');
    final texts = flattenScene(scene.nodes).whereType<SceneText>().toList();
    final actorTexts = texts.where((text) => text.text == 'A');
    expect(actorTexts.every((text) => text.style.fontSize == 19), isTrue);
    expect(actorTexts.every((text) => text.style.fontWeight == 700), isTrue);
    expect(
      texts.singleWhere((text) => text.text == 'message').style.fontSize,
      15,
    );
    expect(texts.singleWhere((text) => text.text == 'note').style.fontSize, 17);
    final commands = flattenScene(scene.nodes)
        .whereType<SceneShape>()
        .map((shape) => shape.geometry)
        .whereType<PathGeometry>()
        .expand((path) => path.commands);
    expect(commands.whereType<CubicTo>(), isEmpty);
  });

  test('gantt init config changes chart geometry and typography', () {
    final config = GanttConfig.fromSource('''
%%{init: {"gantt": {"topPadding": 80, "leftPadding": 120, "rightPadding": 20,
 "gridLineStartPadding": 50, "fontSize": 15, "sectionFontSize": 17,
 "numberSectionStyles": 2}}}%%
gantt
dateFormat YYYY-MM-DD
section Work
A: 2026-01-01, 2d
''');
    expect(config.topPadding, 80);
    expect(config.leftPadding, 120);
    expect(config.rightPadding, 20);
    expect(config.fontSize, 15);
    expect(config.sectionFontSize, 17);
    expect(config.numberSectionStyles, 2);
    expect(
      _renderer
          .render('''
%%{init: {"gantt": {"topPadding": 80, "fontSize": 15}}}%%
gantt
dateFormat YYYY-MM-DD
A: 2026-01-01, 2d
''')
          .size
          .height,
      greaterThan(100),
    );
  });

  test('gitGraph nested nodeLabel and diagram padding affect layout', () {
    final config = GitGraphConfig.fromSource('''
%%{init: {"gitGraph": {"diagramPadding": 31, "nodeLabel": {"width": 140,
 "height": 80}}}}%%
gitGraph
commit id: "one"
''');
    expect(config.diagramPadding, 31);
    expect(config.nodeLabelWidth, 140);
    expect(config.nodeLabelHeight, 80);
    final normal = _renderer.render('gitGraph\ncommit id: "one"');
    final padded = _renderer.render('''
%%{init: {"gitGraph": {"diagramPadding": 31}}}%%
gitGraph
commit id: "one"
''');
    expect(padded.size.width - normal.size.width, closeTo(30, 0.01));
  });

  test('class, state, and gitGraph title margins change scene height', () {
    for (final entry in <(String, String)>[
      ('class', 'classDiagram\nclass A'),
      ('state', 'stateDiagram-v2\n[*] --> A'),
      ('gitGraph', 'gitGraph\ncommit id: "one"'),
    ]) {
      final source = '---\ntitle: Overview\n---\n${entry.$2}';
      final normal = _renderer.render(source);
      final configured = _renderer.render(
        '---\ntitle: Overview\nconfig:\n  ${entry.$1}:\n'
        '    titleTopMargin: 70\n---\n${entry.$2}',
      );
      expect(configured.size.height - normal.size.height, closeTo(45, 0.01));
    }
  });

  test('existing state spacing values remain typed from frontmatter', () {
    final config = StateConfig.fromSource('''
---
config:
  state:
    padding: 19
    nodeSpacing: 70
    rankSpacing: 90
---
stateDiagram-v2
[*] --> A
''');
    expect(config.padding, 19);
    expect(config.nodeSpacing, 70);
    expect(config.rankSpacing, 90);
    final geometry = StateConfig.fromSource('''
%%{init: {"state": {"noteMargin": 22, "forkWidth": 100,
 "forkHeight": 12, "radius": 9}}}%%
stateDiagram-v2
[*] --> A
''');
    expect(geometry.noteMargin, 22);
    expect(geometry.forkWidth, 100);
    expect(geometry.forkHeight, 12);
    expect(geometry.radius, 9);
  });

  test('gantt compact mode reuses rows only for non-overlapping tasks', () {
    const body = '''
gantt
dateFormat YYYY-MM-DD
section Work
First: first, 2026-01-01, 2d
Overlapping: overlap, 2026-01-02, 3d
Later: later, 2026-01-05, 2d
''';
    final normal = _renderer.render(body);
    final compact = _renderer.render('''
%%{init: {"gantt": {"displayMode": "compact"}}}%%
$body''');

    double taskTop(RenderScene scene, String id) {
      final group = flattenScene(
        scene.nodes,
      ).whereType<SceneGroup>().singleWhere((group) => group.id == id);
      return (group.children.whereType<SceneShape>().first.geometry
              as RectGeometry)
          .rect
          .top;
    }

    expect(taskTop(normal, 'first'), isNot(taskTop(normal, 'later')));
    expect(taskTop(compact, 'first'), taskTop(compact, 'later'));
    expect(taskTop(compact, 'overlap'), isNot(taskTop(compact, 'first')));
    expect(compact.size.height, lessThan(normal.size.height));
    expect(
      GanttConfig.fromSource('''
%%{init: {"gantt": {"displayMode": "unsupported"}}}%%
gantt
A: 2026-01-01, 1d
''').displayMode,
      isEmpty,
    );
  });

  test('gantt weekday aligns configured weekly ticks', () {
    final scene = _renderer.render('''
%%{init: {"gantt": {"tickInterval": "1week", "weekday": "monday",
 "axisFormat": "%a"}}}%%
gantt
dateFormat YYYY-MM-DD
First: first, 2026-01-05, 2d
Last: last, 2026-01-25, 1d
''');
    final labels = flattenScene(
      scene.nodes,
    ).whereType<SceneText>().map((text) => text.text).toList();
    expect(labels.where((label) => label == 'Mon'), isNotEmpty);
    expect(labels.where((label) => label == 'Sun'), isEmpty);
    expect(
      GanttConfig.fromSource('''
%%{init: {"gantt": {"weekday": "noday"}}}%%
gantt
A: 2026-01-01, 1d
''').weekday,
      'sunday',
    );
  });
}

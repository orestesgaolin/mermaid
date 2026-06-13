/// Parse + layout smoke tests for block, radar, treemap, kanban, architecture.
library;

import 'package:mermaid_core/src/detect.dart';
import 'package:mermaid_core/src/diagrams/architecture/architecture.dart';
import 'package:mermaid_core/src/diagrams/block/block.dart';
import 'package:mermaid_core/src/diagrams/kanban/kanban.dart';
import 'package:mermaid_core/src/diagrams/radar/radar.dart';
import 'package:mermaid_core/src/diagrams/treemap/treemap.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

List<SceneNode> flatten(List<SceneNode> n) => [
      for (final x in n) ...[
        x,
        if (x is SceneGroup) ...flatten(x.children),
      ],
    ];

Iterable<String> texts(RenderScene s) =>
    flatten(s.nodes).whereType<SceneText>().map((t) => t.text);

void main() {
  group('detect', () {
    test('recognizes the new headers', () {
      expect(detectDiagramType('block-beta\n a b'), DiagramType.block);
      expect(detectDiagramType('radar-beta\n axis a,b,c'), DiagramType.radar);
      expect(detectDiagramType('treemap-beta\n "A": 1'), DiagramType.treemap);
      expect(detectDiagramType('kanban\n c[X]'), DiagramType.kanban);
      expect(detectDiagramType('architecture-beta\n service a'),
          DiagramType.architecture);
    });
  });

  test('block: columns, spans, nested group, edges', () {
    final d = parseBlock('''
block-beta
  columns 3
  a["A"] b["B"] c:2
  block:g:3
    columns 2
    d e
  end
  a --> b
''');
    expect(d.columns, 3);
    expect(d.root.whereType<BlockGroup>().length, 1);
    expect(d.edges.single.from, 'a');
    expect(d.edges.single.arrowTo, isTrue);
    final scene = layoutBlock(d, measurer: measurer, theme: theme);
    expect(texts(scene), containsAll(['A', 'B']));
  });

  test('radar: axes, curves, range', () {
    final c = parseRadar('''
radar-beta
  axis a["A"], b["B"], c["C"]
  curve x["X"]{1, 2, 3}
  max 5
  min 0
''');
    expect(c.axes, ['A', 'B', 'C']);
    expect(c.curves.single.values, [1, 2, 3]);
    expect(c.max, 5);
    final scene = layoutRadar(c, measurer: measurer, theme: theme);
    expect(texts(scene), containsAll(['A', 'B', 'C', 'X']));
  });

  test('treemap: hierarchy and summed branches', () {
    final t = parseTreemap('''
treemap-beta
"Cat"
    "A": 10
    "B": 20
''');
    expect(t.roots.single.label, 'Cat');
    expect(t.roots.single.total, 30);
    final scene = layoutTreemap(t, measurer: measurer, theme: theme);
    expect(texts(scene).any((s) => s.contains('A')), isTrue);
  });

  test('kanban: columns and tasks by indentation', () {
    final b = parseKanban('''
kanban
  todo[To Do]
    t1[Task one]
  done[Done]
''');
    expect(b.columns.length, 2);
    expect(b.columns.first.title, 'To Do');
    expect(b.columns.first.tasks, ['Task one']);
    final scene = layoutKanban(b, measurer: measurer, theme: theme);
    expect(texts(scene), containsAll(['To Do', 'Task one', 'Done']));
  });

  test('architecture: groups, services, port edges', () {
    final a = parseArchitecture('''
architecture-beta
  group api(cloud)[API]
  service db(database)[Database] in api
  service server(server)[Server] in api
  db:L -- R:server
''');
    expect(a.groups.single.id, 'api');
    expect(a.services.map((s) => s.id), containsAll(['db', 'server']));
    expect(a.edges.single.fromSide, 'L');
    expect(a.edges.single.toSide, 'R');
    final scene = layoutArchitecture(a, measurer: measurer, theme: theme);
    expect(texts(scene), containsAll(['API', 'Database', 'Server']));
  });
}

/// Parse + layout smoke tests for block, radar, treemap, kanban, architecture.
library;

import 'dart:math' as math;

import 'package:mermaid_core/src/detect.dart';
import 'package:mermaid_core/src/diagrams/architecture/architecture.dart';
import 'package:mermaid_core/src/diagrams/block/block.dart';
import 'package:mermaid_core/src/diagrams/kanban/kanban.dart';
import 'package:mermaid_core/src/diagrams/radar/radar.dart';
import 'package:mermaid_core/src/diagrams/treemap/treemap.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

List<SceneNode> flatten(List<SceneNode> n) => [
  for (final x in n) ...[x, if (x is SceneGroup) ...flatten(x.children)],
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
      expect(
        detectDiagramType('architecture-beta\n service a'),
        DiagramType.architecture,
      );
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

  test('block: spanning groups and their children fill the parent row', () {
    final scene = layoutBlock(
      parseBlock('''
block-beta
  columns 3
  A["Input"] B["Process"] C["Output"]
  block:group:3
    D["Worker 1"] E["Worker 2"]
  end
'''),
      measurer: measurer,
      theme: theme,
    );

    Rect nodeRect(String id) {
      final group = flatten(
        scene.nodes,
      ).whereType<SceneGroup>().firstWhere((node) => node.id == id);
      return (group.children.whereType<SceneShape>().first.geometry
              as RectGeometry)
          .rect;
    }

    final topLeft = nodeRect('A').left;
    final topRight = nodeRect('C').right;
    final groupRect =
        (scene.nodes.whereType<SceneShape>().single.geometry as RectGeometry)
            .rect;
    expect(groupRect.left, topLeft);
    expect(groupRect.right, topRight);

    final worker1 = nodeRect('D');
    final worker2 = nodeRect('E');
    expect(worker1.left, groupRect.left + 8);
    expect(worker2.right, groupRect.right - 8);
  });

  test('block: point arrow stays between adjacent boxes', () {
    final scene = layoutBlock(
      parseBlock('''
block-beta
  columns 3
  A["Input"] B["Process"] C["Output"]
  block:group:3
    D["Worker 1"] E["Worker 2"]
  end
  A --> B
'''),
      measurer: measurer,
      theme: theme,
    );

    Rect nodeRect(String id) {
      final group = flatten(
        scene.nodes,
      ).whereType<SceneGroup>().firstWhere((node) => node.id == id);
      return (group.children.whereType<SceneShape>().first.geometry
              as RectGeometry)
          .rect;
    }

    final source = nodeRect('A');
    final target = nodeRect('B');
    final marker = flatten(scene.nodes)
        .whereType<SceneShape>()
        .map((shape) => shape.geometry)
        .whereType<PolygonGeometry>()
        .single;

    expect(
      marker.points.map((point) => point.x),
      everyElement(inInclusiveRange(source.right, target.left)),
    );
    expect(marker.points.map((point) => point.x).reduce(math.max), target.left);
  });

  test('radar: axes, curves, range', () {
    final c = parseRadar('''
radar-beta
  title Skills
  axis a["A"], b["B"], c["C"]
  curve x["X"]{1, 2, 3}
  max 5
  min 0
''');
    expect(c.axes, ['A', 'B', 'C']);
    expect(c.curves.single.values, [1, 2, 3]);
    expect(c.max, 5);
    expect(c.title, 'Skills');
    final scene = layoutRadar(c, measurer: measurer, theme: theme);
    expect(texts(scene), containsAll(['Skills', 'A', 'B', 'C', 'X']));
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

  test('treemap: root and section padding match d3 hierarchy', () {
    final scene = layoutTreemap(
      parseTreemap('''
treemap-beta
"Frontend"
    "UI": 40
    "State": 25
"Backend"
    "API": 35
    "DB": 20
'''),
      measurer: measurer,
      theme: theme,
    );
    final sections = flatten(scene.nodes)
        .whereType<SceneShape>()
        .where((shape) => shape.stroke?.width == 2)
        .map((shape) => (shape.geometry as RectGeometry).rect)
        .toList();

    expect(sections, hasLength(2));
    expect(sections.first.top, greaterThanOrEqualTo(8 + 35));
    expect(sections.first.left, greaterThanOrEqualTo(8 + 10));

    final leaves = flatten(scene.nodes)
        .whereType<SceneShape>()
        .where((shape) => shape.stroke?.width == 3)
        .map((shape) => (shape.geometry as RectGeometry).rect)
        .toList();
    expect(leaves, hasLength(4));
    expect(leaves[0].top, leaves[1].top);
    expect(leaves[2].top, leaves[3].top);
  });

  test('treemap uses the configured default aspect ratio for leaf rows', () {
    final scene = layoutTreemap(
      parseTreemap('''
treemap-beta
"Frontend"
    "UI": 40
    "State": 25
"Backend"
    "API": 35
    "DB": 20
'''),
      measurer: measurer,
      theme: theme,
    );
    final labels = {
      for (final text in scene.nodes.whereType<SceneText>())
        if (const {'UI', 'State'}.contains(text.text))
          text.text: text.bounds.center,
    };

    expect(labels.keys, containsAll(['UI', 'State']));
    expect(labels['UI']!.y, closeTo(labels['State']!.y, 0.001));
    expect(labels['UI']!.x, lessThan(labels['State']!.x));
  });

  test('kanban: columns and tasks by indentation', () {
    final b = parseKanban('''
kanban
  todo[To Do]
    t1[Design API]
    t2[Write specs]
  done[Done]
''');
    expect(b.columns.length, 2);
    expect(b.columns.first.title, 'To Do');
    expect(b.columns.first.tasks, ['Design API', 'Write specs']);
    final scene = layoutKanban(b, measurer: measurer, theme: theme);
    expect(texts(scene), containsAll(['To Do', 'Design API', 'Done']));

    final rects = flatten(scene.nodes)
        .whereType<SceneShape>()
        .where((shape) => shape.geometry is RectGeometry)
        .toList();
    final section = (rects.first.geometry as RectGeometry).rect;
    final cards = rects
        .where((shape) => shape.fill?.color.value == theme.background.value)
        .map((shape) => (shape.geometry as RectGeometry).rect)
        .toList();
    final title = flatten(
      scene.nodes,
    ).whereType<SceneText>().singleWhere((text) => text.text == 'To Do');

    expect(
      title.bounds.top,
      section.top,
      reason: 'the title should sit inside the section header',
    );
    expect(cards.first.left - section.left, closeTo(7.5, 0.001));
    expect(
      section.bottom - cards[1].bottom,
      closeTo(10, 0.001),
      reason: 'the section should keep one padding unit below its last card',
    );
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

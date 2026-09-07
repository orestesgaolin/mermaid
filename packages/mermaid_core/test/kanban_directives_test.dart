import 'package:mermaid_core/mermaid_core.dart';
import 'package:mermaid_core/src/diagrams/kanban/kanban.dart';
import 'package:test/test.dart';

import 'support/scene.dart';

void main() {
  const source = '''
kanban
  todo[To Do]
    task[Ship the deliberately long release title without clipping]
  classDef urgent fill:#ffeecc,stroke:rgb(0, 102, 204),stroke-width:3px,color:#123456
  class task urgent
  style task fill:#ff0000,stroke-dasharray:4 2
  click task href "https://example.test/tasks/1" "Open task"
''';

  test(
    'style and class directives resolve paint and retain wrapped geometry',
    () {
      final board = parseKanban(source);
      final task = board.columns.single.cards.single;
      expect(task.classes, ['urgent']);
      expect(task.styles['fill'], '#ff0000');

      final scene = const Mermaid(
        measurer: ApproximateTextMeasurer(),
      ).render(source);
      final group = groupsOf(
        scene.nodes,
      ).singleWhere((node) => node.id == 'task');
      final card = shapesOf(
        group.children,
      ).firstWhere((shape) => shape.geometry is RectGeometry);
      final cardRect = (card.geometry as RectGeometry).rect;
      final title = textsOf(
        group.children,
      ).singleWhere((text) => text.text.startsWith('Ship the deliberately'));

      expect(card.fill?.color, const Color(0xffff0000));
      expect(card.stroke?.color, const Color(0xff0066cc));
      expect(card.stroke?.width, 3);
      expect(card.stroke?.dash, [4, 2]);
      expect(title.color, const Color(0xff123456));
      expect(title.bounds.height, greaterThan(title.style.fontSize * 2));
      expect(
        cardRect.contains(Point(title.bounds.left, title.bounds.top)),
        isTrue,
      );
      expect(
        cardRect.contains(Point(title.bounds.right, title.bounds.bottom)),
        isTrue,
      );
    },
  );

  test('URL click directive reaches scene and standalone SVG metadata', () {
    final scene = const Mermaid(
      measurer: ApproximateTextMeasurer(),
    ).render(source);
    final group = groupsOf(
      scene.nodes,
    ).singleWhere((node) => node.id == 'task');

    expect(group.link, 'https://example.test/tasks/1');
    expect(group.tooltip, 'Open task');
    expect(group.semanticLabel, contains('Ship the deliberately long'));
    final svg = renderSceneToSvg(scene);
    expect(svg, contains('<a href="https://example.test/tasks/1"'));
    expect(svg, contains('<title>Open task</title>'));
    expect(svg, contains('fill="#ff0000"'));
  });
}

import 'package:mermaid_core/mermaid_core.dart';
import 'package:mermaid_core/src/diagrams/kanban/kanban.dart';
import 'package:test/test.dart';

void main() {
  const renderer = Mermaid(measurer: ApproximateTextMeasurer());

  test('registered task icon reserves title space and renders into SVG', () {
    const source = '''
kanban
  todo[To Do]
    task[Ship release]
    task@{ icon: "icon:star" }
''';
    final board = parseKanban(source);
    expect(board.columns.single.cards.single.icon, 'icon:star');

    final scene = renderer.render(source);
    final nodes = _flatten(scene.nodes).toList();
    final title = nodes.whereType<SceneText>().singleWhere(
      (node) => node.text == 'Ship release',
    );
    final iconPaths = nodes.whereType<SceneShape>().where(
      (node) =>
          node.geometry is PathGeometry &&
          (node.geometry as PathGeometry).commands.isNotEmpty,
    );

    expect(iconPaths, isNotEmpty);
    expect(
      iconPaths.every(
        (node) => geometryBounds(node.geometry).right <= title.bounds.left,
      ),
      isTrue,
    );
    expect(renderSceneToSvg(scene), contains('<path'));
  });

  test('unknown task icon falls back to the ordinary title layout', () {
    const plain = '''
kanban
  todo[To Do]
    task[Ship release]
''';
    const missing = '''
kanban
  todo[To Do]
    task[Ship release]
    task@{ icon: "missing:not-registered" }
''';

    Rect titleBounds(String source) => _flatten(renderer.render(source).nodes)
        .whereType<SceneText>()
        .singleWhere((node) => node.text == 'Ship release')
        .bounds;

    expect(titleBounds(missing), titleBounds(plain));
  });
}

Iterable<SceneNode> _flatten(Iterable<SceneNode> nodes) sync* {
  for (final node in nodes) {
    yield node;
    if (node is SceneGroup) yield* _flatten(node.children);
  }
}

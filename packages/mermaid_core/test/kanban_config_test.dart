import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

void main() {
  test('ticket metadata has its own linked row inside the card', () {
    const source = '''
%%{init: {"kanban": {"ticketBaseUrl": "https://example.test/t/#TICKET#"}}}%%
kanban
  todo[To Do]
    task[Design API]
    task@{
      ticket: ABC-1
      assigned: Sam
    }
''';
    final scene = const Mermaid(
      measurer: ApproximateTextMeasurer(),
    ).render(source);
    final nodes = _flatten(scene.nodes).toList();
    final title = nodes.whereType<SceneText>().singleWhere(
      (text) => text.text == 'Design API',
    );
    final ticket = nodes.whereType<SceneText>().singleWhere(
      (text) => text.text == 'ABC-1',
    );
    final card = nodes
        .whereType<SceneShape>()
        .where(
          (shape) =>
              shape.geometry is RectGeometry &&
              shape.fill?.color == MermaidTheme.defaultTheme.background,
        )
        .map((shape) => (shape.geometry as RectGeometry).rect)
        .singleWhere((rect) => rect.contains(title.bounds.center));
    final link = nodes.whereType<SceneGroup>().singleWhere(
      (group) => group.children.contains(ticket),
    );

    expect(title.bounds.bottom, lessThanOrEqualTo(ticket.bounds.top));
    expect(card.contains(Point(ticket.bounds.left, ticket.bounds.top)), isTrue);
    expect(
      card.contains(Point(ticket.bounds.right, ticket.bounds.bottom)),
      isTrue,
    );
    expect(ticket.underline, isTrue);
    expect(link.id, 'task');
    expect(link.role, SceneGroupRole.node);
    expect(link.link, 'https://example.test/t/ABC-1');
  });
}

Iterable<SceneNode> _flatten(Iterable<SceneNode> nodes) sync* {
  for (final node in nodes) {
    yield node;
    if (node is SceneGroup) yield* _flatten(node.children);
  }
}

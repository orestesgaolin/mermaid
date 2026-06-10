/// Structural tests for the class diagram layout.
library;

import 'package:mermaid_core/src/diagrams/class_diagram/class_layout.dart';
import 'package:mermaid_core/src/diagrams/class_diagram/class_parser.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/ir/scene_utils.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

RenderScene layout(String body) => layoutClassDiagram(
      parseClassDiagram('classDiagram\n$body'),
      measurer: const ApproximateTextMeasurer(),
      theme: MermaidTheme.defaultTheme,
    );

List<SceneNode> flatten(List<SceneNode> nodes) => [
      for (final n in nodes) ...[
        n,
        if (n is SceneGroup) ...flatten(n.children),
      ],
    ];

SceneGroup group(RenderScene s, String id) => flatten(s.nodes)
    .whereType<SceneGroup>()
    .firstWhere((g) => g.id == id);

void main() {
  test('box contains name, attributes and methods in order', () {
    final s = layout('class Animal {\n+String name\n+eat() bool\n}');
    final texts = flatten(group(s, 'Animal').children)
        .whereType<SceneText>()
        .toList();
    expect(texts.map((t) => t.text).toList(),
        ['Animal', '+String name', '+eat() bool']);
    expect(texts[0].bounds.top, lessThan(texts[1].bounds.top));
    expect(texts[1].bounds.top, lessThan(texts[2].bounds.top));
  });

  test('separator lines split the compartments', () {
    final s = layout('class A {\n+x\n+f()\n}');
    final seps = flatten(group(s, 'A').children).whereType<SceneShape>().where(
        (n) => n.geometry is PathGeometry && n.fill == null);
    expect(seps.length, 2);
  });

  test('annotation renders in guillemets above the name', () {
    final s = layout('class Shape {\n<<interface>>\n}');
    final texts =
        flatten(group(s, 'Shape').children).whereType<SceneText>().toList();
    expect(texts.first.text, '«interface»');
    expect(texts.first.bounds.top,
        lessThan(texts.firstWhere((t) => t.text == 'Shape').bounds.top));
  });

  test('inheritance emits a hollow triangle near the parent box', () {
    final s = layout('Animal <|-- Duck');
    final rel = group(s, 'rel_Animal_Duck_0');
    final triangle = flatten(rel.children).whereType<SceneShape>().firstWhere(
        (n) =>
            n.geometry is PolygonGeometry &&
            (n.geometry as PolygonGeometry).points.length == 3);
    expect(triangle.fill!.color, MermaidTheme.defaultTheme.background);
    final triBounds = geometryBounds(triangle.geometry);
    final parent = sceneNodeBounds(group(s, 'Animal'))!;
    final child = sceneNodeBounds(group(s, 'Duck'))!;
    final dParent = (triBounds.center.y - parent.bottom).abs();
    final dChild = (triBounds.center.y - child.top).abs();
    expect(dParent, lessThan(dChild));
  });

  test('dashed dependency has a dash pattern', () {
    final s = layout('A ..> B');
    final rel = group(s, 'rel_A_B_0');
    final line = flatten(rel.children).whereType<SceneShape>().firstWhere(
        (n) => n.geometry is PathGeometry && n.stroke?.dash != null);
    expect(line.stroke!.dash, isNotEmpty);
  });

  test('cardinalities render near both ends', () {
    final s = layout('Customer "1" --> "many" Ticket');
    final texts = flatten(s.nodes).whereType<SceneText>().map((t) => t.text);
    expect(texts, containsAll(['1', 'many']));
  });

  test('relation label has a background', () {
    final s = layout('A --> B : uses');
    final texts = flatten(s.nodes).whereType<SceneText>().map((t) => t.text);
    expect(texts, contains('uses'));
  });

  test('direction LR orders boxes horizontally', () {
    final s = layout('direction LR\nA --> B');
    final a = sceneNodeBounds(group(s, 'A'))!;
    final b = sceneNodeBounds(group(s, 'B'))!;
    expect(b.center.x, greaterThan(a.center.x));
    expect((b.center.y - a.center.y).abs(), lessThan(5));
  });

  test('namespace cluster contains its members', () {
    final s = layout('namespace Shapes {\nclass Circle\nclass Square\n}');
    final cluster = sceneNodeBounds(group(s, 'namespace_Shapes'))!;
    for (final id in ['Circle', 'Square']) {
      expect(cluster.contains(sceneNodeBounds(group(s, id))!.center), isTrue);
    }
  });

  test('note for class renders yellow box with dashed connector', () {
    final s = layout('class A\nnote for A "remember"');
    final texts = flatten(s.nodes).whereType<SceneText>().map((t) => t.text);
    expect(texts, contains('remember'));
    final dashed = flatten(s.nodes).whereType<SceneShape>().where(
        (n) => n.geometry is PathGeometry && n.stroke?.dash != null);
    expect(dashed, isNotEmpty);
  });

  test('scene bounds enclose everything', () {
    final s = layout('Animal <|-- Duck : isa\nAnimal : +int age\n'
        'namespace N {\nclass X\n}\nnote for X "hi"');
    for (final n in flatten(s.nodes)) {
      final b = sceneNodeBounds(n);
      if (b == null) continue;
      expect(b.left, greaterThanOrEqualTo(-0.5));
      expect(b.top, greaterThanOrEqualTo(-0.5));
      expect(b.right, lessThanOrEqualTo(s.size.width + 0.5));
      expect(b.bottom, lessThanOrEqualTo(s.size.height + 0.5));
    }
  });
}

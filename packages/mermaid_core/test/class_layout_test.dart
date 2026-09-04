/// Structural tests for the class diagram layout.
library;

import 'support/fixtures.dart';

import 'package:mermaid_core/src/diagrams/class_diagram/class_layout.dart';
import 'package:mermaid_core/src/diagrams/class_diagram/class_parser.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/ir/scene_utils.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

RenderScene layoutSource(String source) => layoutClassDiagram(
  parseClassDiagram(source),
  measurer: const ApproximateTextMeasurer(),
  theme: MermaidTheme.defaultTheme,
);

RenderScene layout(String body) => layoutSource('classDiagram\n$body');

List<SceneNode> flatten(List<SceneNode> nodes) => [
  for (final n in nodes) ...[n, if (n is SceneGroup) ...flatten(n.children)],
];

SceneGroup group(RenderScene s, String id) =>
    flatten(s.nodes).whereType<SceneGroup>().firstWhere((g) => g.id == id);

/// The edge group for the `from --> to` relation. Relation ids carry the
/// parse index as a suffix, so looking one up by endpoints keeps the test
/// stable when statements are added or reordered in a fixture.
SceneGroup relationGroup(RenderScene s, String from, String to) => flatten(
  s.nodes,
).whereType<SceneGroup>().singleWhere(
  (g) =>
      g.role == SceneGroupRole.edge &&
      (g.id?.startsWith('rel_${from}_${to}_') ?? false),
);

/// The label group that belongs to [edge] (same parse index).
SceneGroup relationLabel(RenderScene s, SceneGroup edge) =>
    group(s, 'rellabel_${edge.id!.split('_').last}');

PathGeometry edgePath(SceneGroup edge) => flatten(edge.children)
    .whereType<SceneShape>()
    .map((shape) => shape.geometry)
    .whereType<PathGeometry>()
    .first;

void main() {
  test('box contains name, attributes and methods in order', () {
    final s = layout('class Animal {\n+String name\n+eat() : bool\n}');
    final texts = flatten(
      group(s, 'Animal').children,
    ).whereType<SceneText>().toList();
    expect(texts.map((t) => t.text).toList(), [
      'Animal',
      '+String name',
      '+eat() : bool',
    ]);
    expect(texts[0].bounds.top, lessThan(texts[1].bounds.top));
    expect(texts[1].bounds.top, lessThan(texts[2].bounds.top));
  });

  test('separator lines split the compartments', () {
    final s = layout('class A {\n+x\n+f()\n}');
    final seps = flatten(group(s, 'A').children).whereType<SceneShape>().where(
      (n) => n.geometry is PathGeometry && n.fill == null,
    );
    expect(seps.length, 2);
  });

  test('annotation renders in guillemets above the name', () {
    final s = layout('class Shape {\n<<interface>>\n}');
    final texts = flatten(
      group(s, 'Shape').children,
    ).whereType<SceneText>().toList();
    expect(texts.first.text, '«interface»');
    expect(
      texts.first.bounds.top,
      lessThan(texts.firstWhere((t) => t.text == 'Shape').bounds.top),
    );
  });

  test('inheritance emits a hollow triangle near the parent box', () {
    final s = layout('Animal <|-- Duck');
    final rel = group(s, 'rel_Animal_Duck_0');
    final triangle = flatten(rel.children).whereType<SceneShape>().firstWhere(
      (n) =>
          n.geometry is PolygonGeometry &&
          (n.geometry as PolygonGeometry).points.length == 3,
    );
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
      (n) => n.geometry is PathGeometry && n.stroke?.dash != null,
    );
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
    final label = group(s, 'rellabel_0');
    final background = label.children.whereType<SceneShape>().single;
    final themed = MermaidTheme.defaultTheme.edgeLabelBackground;
    // The generic edge-label colour, painted opaque so the relation line does
    // not show through it.
    expect(background.fill?.color, themed.withOpacity(1));
    expect(background.fill?.color.alpha, 255);
    expect(background.fill?.color.red, themed.red);
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

  test('disjoint namespace clusters do not overlap across relations', () {
    final s = layout('''
namespace Shapes {
  class Shape
  class Circle
  class Square
}
namespace Vehicles {
  class Vehicle
  class Car
  class Bike
}
Shape <|-- Circle
Shape <|-- Square
Vehicle <|-- Car
Vehicle <|-- Bike
Car --> Circle : Logo Shape
Bike --> Square : Logo Shape
''');
    final shapes = sceneNodeBounds(group(s, 'namespace_Shapes'))!;
    final vehicles = sceneNodeBounds(group(s, 'namespace_Vehicles'))!;
    final overlaps =
        shapes.left < vehicles.right &&
        shapes.right > vehicles.left &&
        shapes.top < vehicles.bottom &&
        shapes.bottom > vehicles.top;

    expect(overlaps, isFalse);
    expect(vehicles.contains(sceneNodeBounds(group(s, 'Car'))!.center), isTrue);
  });

  test('cross-namespace relations enter destination boxes vertically', () {
    final s = layout('''
namespace Shapes {
  class Circle
  class Square
}
namespace Vehicles {
  class Car
  class Bike
}
Car --> Circle : Logo Shape
Bike --> Square : Logo Shape
''');

    for (final entry in [('Car', 'Circle'), ('Bike', 'Square')]) {
      final path = edgePath(relationGroup(s, entry.$1, entry.$2));
      final endpoint = (path.commands.last as LineTo).p;
      final destination = sceneNodeBounds(group(s, entry.$2))!;

      expect(endpoint.x, closeTo(destination.center.x, 0.001));
      expect(
        endpoint.y,
        anyOf(
          closeTo(destination.top, 0.001),
          closeTo(destination.bottom, 0.001),
        ),
      );
    }
  });

  test('cross-namespace relations follow the rank axis under direction LR', () {
    final s = layout('''
direction LR
namespace Shapes {
  class Circle
  class Square
}
namespace Vehicles {
  class Car
  class Bike
}
Car --> Circle : Logo Shape
Bike --> Square : Logo Shape
''');

    for (final entry in [('Car', 'Circle'), ('Bike', 'Square')]) {
      final path = edgePath(relationGroup(s, entry.$1, entry.$2));
      final endpoint = (path.commands.last as LineTo).p;
      final source = sceneNodeBounds(group(s, entry.$1))!;
      final destination = sceneNodeBounds(group(s, entry.$2))!;

      // LR ranks run left to right, so the arrowhead must land on the
      // destination's left edge, not on its top or bottom.
      expect(source.right, lessThan(destination.left));
      expect(endpoint.x, closeTo(destination.left, 0.001));
      expect(endpoint.y, inInclusiveRange(destination.top, destination.bottom));
    }
  });

  test('fixture 11 labels sit on edges and inheritance enters rank edge', () {
    final source = readFixture('upstream_class/11.mmd');
    final s = layoutSource(source);
    for (final entry in [('Car', 'Circle'), ('Bike', 'Square')]) {
      final edge = relationGroup(s, entry.$1, entry.$2);
      final labelCenter = sceneNodeBounds(relationLabel(s, edge))!.center;
      expect(distanceToPath(edgePath(edge), labelCenter), lessThan(0.6));
    }

    final vehicle = sceneNodeBounds(group(s, 'Vehicle'))!;
    for (final child in ['Car', 'Bike']) {
      final triangle = flatten(relationGroup(s, 'Vehicle', child).children)
          .whereType<SceneShape>()
          .map((shape) => shape.geometry)
          .whereType<PolygonGeometry>()
          .single;
      final tip = triangle.points.first;
      expect(tip.y, closeTo(vehicle.bottom, 0.001));
      expect(tip.x, inInclusiveRange(vehicle.left, vehicle.right));
    }

    for (final inheritance in [
      ('Shape', ['Circle', 'Square']),
      ('Vehicle', ['Car', 'Bike']),
    ]) {
      final edgeGeometry = inheritance.$2.map((child) {
        final geometry = flatten(
          relationGroup(s, inheritance.$1, child).children,
        ).whereType<SceneShape>().map((shape) => shape.geometry);
        final triangle = geometry.whereType<PolygonGeometry>().single;
        final path = geometry.whereType<PathGeometry>().single;
        return (
          tip: triangle.points.first,
          pathStart: (path.commands.first as MoveTo).p,
        );
      }).toList();
      final tips = edgeGeometry.map((edge) => edge.tip).toList();
      final parent = sceneNodeBounds(group(s, inheritance.$1))!;

      expect(tips[0].y, closeTo(parent.bottom, 0.001));
      expect(tips[1].y, closeTo(parent.bottom, 0.001));
      expect(
        (tips[0].x - tips[1].x).abs(),
        greaterThan(1),
        reason:
            '${inheritance.$1} inheritance routes must keep separate '
            'ports and arrowheads',
      );
      expect(
        (edgeGeometry[0].pathStart.x - edgeGeometry[1].pathStart.x).abs(),
        greaterThan(1),
        reason:
            '${inheritance.$1} inheritance strokes must remain separate '
            'through their parent-edge approach',
      );
    }
  });

  test('note for class renders yellow box with dashed connector', () {
    final s = layout('class A\nnote for A "remember"');
    final texts = flatten(s.nodes).whereType<SceneText>().map((t) => t.text);
    expect(texts, contains('remember'));
    final dashed = flatten(s.nodes).whereType<SceneShape>().where(
      (n) => n.geometry is PathGeometry && n.stroke?.dash != null,
    );
    expect(dashed, isNotEmpty);
  });

  test('scene bounds enclose everything', () {
    final s = layout(
      'Animal <|-- Duck : isa\nAnimal : +int age\n'
      'namespace N {\nclass X\n}\nnote for X "hi"',
    );
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

/// Tests for the flowchart layout engine. FlowGraph instances are built
/// directly (no parser) and laid out with the approximate text measurer.
library;

import 'dart:math' as math;

import 'package:mermaid_core/src/diagrams/flowchart/flow_layout.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_model.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

RenderScene layout(FlowGraph graph) =>
    layoutFlowchart(graph, measurer: measurer, theme: theme);

FlowNode node(String id, {String? label, FlowNodeShape shape = FlowNodeShape.rect}) =>
    FlowNode(id: id, label: label ?? id, shape: shape);

FlowGraph chain({
  FlowDirection direction = FlowDirection.tb,
  EdgeStroke stroke = EdgeStroke.normal,
  ArrowHead headTo = ArrowHead.point,
  String? edgeLabel,
}) =>
    FlowGraph(
      direction: direction,
      nodes: {
        'A': node('A', label: 'Alpha'),
        'B': node('B', label: 'Beta'),
      },
      edges: [
        FlowEdge(from: 'A', to: 'B', stroke: stroke, headTo: headTo, label: edgeLabel),
      ],
    );

/// A 6-node diamond-shaped DAG: A fans out to B/C, which reach F via D/E.
FlowGraph diamondDag() => FlowGraph(
      direction: FlowDirection.tb,
      nodes: {
        for (final id in ['A', 'B', 'C', 'D', 'E', 'F'])
          id: node(id, label: 'Node $id'),
      },
      edges: const [
        FlowEdge(from: 'A', to: 'B'),
        FlowEdge(from: 'A', to: 'C'),
        FlowEdge(from: 'B', to: 'D'),
        FlowEdge(from: 'C', to: 'E'),
        FlowEdge(from: 'D', to: 'F'),
        FlowEdge(from: 'E', to: 'F'),
      ],
    );

// --- scene inspection helpers -----------------------------------------------

SceneGroup findGroup(RenderScene scene, String id) {
  final g = _findGroup(scene.nodes, id);
  if (g == null) fail('no group with id $id in scene');
  return g;
}

SceneGroup? _findGroup(List<SceneNode> nodes, String id) {
  for (final n in nodes) {
    if (n is SceneGroup) {
      if (n.id == id) return n;
      final inner = _findGroup(n.children, id);
      if (inner != null) return inner;
    }
  }
  return null;
}

Iterable<SceneShape> shapesIn(SceneNode n) sync* {
  if (n is SceneShape) yield n;
  if (n is SceneGroup) {
    for (final c in n.children) {
      yield* shapesIn(c);
    }
  }
}

Iterable<SceneText> textsIn(SceneNode n) sync* {
  if (n is SceneText) yield n;
  if (n is SceneGroup) {
    for (final c in n.children) {
      yield* textsIn(c);
    }
  }
}

Rect groupBounds(SceneGroup g) {
  Rect? acc;
  for (final s in shapesIn(g)) {
    final b = geometryBounds(s.geometry);
    acc = acc == null ? b : acc.union(b);
  }
  for (final t in textsIn(g)) {
    acc = acc == null ? t.bounds : acc.union(t.bounds);
  }
  if (acc == null) fail('group ${g.id} has no geometry');
  return acc;
}

Rect geometryBounds(ShapeGeometry g) => switch (g) {
      RectGeometry(:final rect) => rect,
      CircleGeometry(:final center, :final radius) =>
        Rect.fromCenter(center, radius * 2, radius * 2),
      EllipseGeometry(:final center, :final rx, :final ry) =>
        Rect.fromCenter(center, rx * 2, ry * 2),
      PolygonGeometry(:final points) => pointsBounds(points),
      PathGeometry(:final commands) =>
        pointsBounds([for (final c in commands) ...commandPoints(c)]),
    };

List<Point> commandPoints(PathCommand c) => switch (c) {
      MoveTo(:final p) => [p],
      LineTo(:final p) => [p],
      QuadTo(:final c, :final p) => [c, p],
      CubicTo(:final c1, :final c2, :final p) => [c1, c2, p],
      ClosePath() => const <Point>[],
    };

Rect pointsBounds(List<Point> pts) {
  var minX = pts.first.x, maxX = pts.first.x;
  var minY = pts.first.y, maxY = pts.first.y;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// The painted edge path of an edge group (the stroked PathGeometry).
PathGeometry edgePath(SceneGroup edgeGroup) {
  for (final s in shapesIn(edgeGroup)) {
    if (s.geometry is PathGeometry && s.stroke != null) {
      return s.geometry as PathGeometry;
    }
  }
  fail('edge group ${edgeGroup.id} has no stroked path');
}

Point pathStart(PathGeometry p) => (p.commands.first as MoveTo).p;

Point pathEnd(PathGeometry p) {
  for (final c in p.commands.reversed) {
    final pts = commandPoints(c);
    if (pts.isNotEmpty) return pts.last;
  }
  fail('path has no endpoint');
}

bool overlaps(Rect a, Rect b) =>
    a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

/// Distance from [p] to the boundary of [r] (0 when exactly on it).
double distanceToRectBoundary(Point p, Rect r) {
  if (r.contains(p)) {
    return [
      p.x - r.left,
      r.right - p.x,
      p.y - r.top,
      r.bottom - p.y,
    ].reduce(math.min);
  }
  final dx = math.max(math.max(r.left - p.x, 0), p.x - r.right);
  final dy = math.max(math.max(r.top - p.y, 0), p.y - r.bottom);
  return math.sqrt(dx * dx + dy * dy);
}

void main() {
  group('flowchart layout', () {
    test('(a) two-node chain: B strictly below A for TB', () {
      final scene = layout(chain(direction: FlowDirection.tb));
      final a = groupBounds(findGroup(scene, 'A'));
      final b = groupBounds(findGroup(scene, 'B'));
      expect(b.top, greaterThan(a.bottom),
          reason: 'B must start below the bottom of A');
    });

    test('(a) two-node chain: B strictly right of A for LR', () {
      final scene = layout(chain(direction: FlowDirection.lr));
      final a = groupBounds(findGroup(scene, 'A'));
      final b = groupBounds(findGroup(scene, 'B'));
      expect(b.left, greaterThan(a.right),
          reason: 'B must start right of the right edge of A');
    });

    test('(a2) BT places B above A; RL places B left of A', () {
      final bt = layout(chain(direction: FlowDirection.bt));
      expect(groupBounds(findGroup(bt, 'B')).bottom,
          lessThan(groupBounds(findGroup(bt, 'A')).top));
      final rl = layout(chain(direction: FlowDirection.rl));
      expect(groupBounds(findGroup(rl, 'B')).right,
          lessThan(groupBounds(findGroup(rl, 'A')).left));
    });

    test('(b) no overlapping node bounds in a 6-node diamond DAG', () {
      final scene = layout(diamondDag());
      final ids = ['A', 'B', 'C', 'D', 'E', 'F'];
      final bounds = {for (final id in ids) id: groupBounds(findGroup(scene, id))};
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          expect(overlaps(bounds[ids[i]]!, bounds[ids[j]]!), isFalse,
              reason: '${ids[i]} and ${ids[j]} must not overlap');
        }
      }
    });

    test('(c) edge endpoints lie on shape boundaries, not at centers', () {
      // Open link (no arrowheads) so the path is not shortened for markers.
      final scene = layout(chain(headTo: ArrowHead.none));
      final a = groupBounds(findGroup(scene, 'A'));
      final b = groupBounds(findGroup(scene, 'B'));
      final path = edgePath(findGroup(scene, 'edge_A_B_0'));
      final start = pathStart(path);
      final end = pathEnd(path);

      expect(distanceToRectBoundary(start, a), lessThanOrEqualTo(2),
          reason: 'path start must touch the boundary of A');
      expect(distanceToRectBoundary(end, b), lessThanOrEqualTo(2),
          reason: 'path end must touch the boundary of B');
      expect(start.distanceTo(a.center), greaterThan(10),
          reason: 'path start must not be at the center of A');
      expect(end.distanceTo(b.center), greaterThan(10),
          reason: 'path end must not be at the center of B');
    });

    test('(d) scene size encloses every geometry point', () {
      final graph = FlowGraph(
        direction: FlowDirection.tb,
        nodes: {
          'A': node('A', shape: FlowNodeShape.diamond),
          'B': node('B', shape: FlowNodeShape.circle),
          'C': node('C', shape: FlowNodeShape.cylinder),
        },
        edges: const [
          FlowEdge(from: 'A', to: 'B', label: 'go'),
          FlowEdge(from: 'B', to: 'C'),
        ],
        title: 'My diagram',
      );
      final scene = layout(graph);
      Rect? acc;
      void visit(SceneNode n) {
        if (n is SceneGroup) {
          n.children.forEach(visit);
        } else if (n is SceneShape) {
          final b = geometryBounds(n.geometry);
          acc = acc == null ? b : acc!.union(b);
        } else if (n is SceneText) {
          acc = acc == null ? n.bounds : acc!.union(n.bounds);
        }
      }

      scene.nodes.forEach(visit);
      final all = acc!;
      expect(all.left, greaterThanOrEqualTo(-0.001));
      expect(all.top, greaterThanOrEqualTo(-0.001));
      expect(all.right, lessThanOrEqualTo(scene.size.width + 0.001));
      expect(all.bottom, lessThanOrEqualTo(scene.size.height + 0.001));
    });

    test('(e) dotted edge has a dash pattern, thick edge has width > 3', () {
      final dotted = layout(chain(stroke: EdgeStroke.dotted));
      final dottedStroke =
          edgePathShape(findGroup(dotted, 'edge_A_B_0')).stroke!;
      expect(dottedStroke.dash, isNotNull);
      expect(dottedStroke.dash, isNotEmpty);

      final thick = layout(chain(stroke: EdgeStroke.thick));
      final thickStroke = edgePathShape(findGroup(thick, 'edge_A_B_0')).stroke!;
      expect(thickStroke.width, greaterThan(3));

      final normal = layout(chain());
      final normalStroke =
          edgePathShape(findGroup(normal, 'edge_A_B_0')).stroke!;
      expect(normalStroke.width, 2);
      expect(normalStroke.dash, isNull);
    });

    test('(e2) invisible edge paints nothing but keeps its group', () {
      final scene = layout(chain(stroke: EdgeStroke.invisible));
      final g = findGroup(scene, 'edge_A_B_0');
      expect(g.children, isEmpty);
    });

    test('(f) point arrowhead triangle exists near the target node', () {
      final scene = layout(chain());
      final edge = findGroup(scene, 'edge_A_B_0');
      final b = groupBounds(findGroup(scene, 'B'));
      final triangles = shapesIn(edge)
          .where((s) =>
              s.geometry is PolygonGeometry &&
              (s.geometry as PolygonGeometry).points.length == 3 &&
              s.fill != null)
          .toList();
      expect(triangles, hasLength(1),
          reason: 'edge with headTo=point must have one filled triangle');
      final pts = (triangles.single.geometry as PolygonGeometry).points;
      final tipDistance =
          pts.map((p) => distanceToRectBoundary(p, b)).reduce(math.min);
      expect(tipDistance, lessThanOrEqualTo(2),
          reason: 'arrow tip must touch the target boundary');
    });

    test('(g) subgraph cluster rect contains its member nodes', () {
      final graph = FlowGraph(
        direction: FlowDirection.tb,
        nodes: {
          'A': node('A'),
          'B': node('B'),
          'C': node('C'),
          'D': node('D'),
        },
        edges: const [
          FlowEdge(from: 'A', to: 'B'),
          FlowEdge(from: 'B', to: 'C'),
          FlowEdge(from: 'C', to: 'D'),
        ],
        subgraphs: const [
          FlowSubgraph(id: 'sub1', title: 'Inner work', nodeIds: ['B', 'C']),
        ],
      );
      final scene = layout(graph);
      final cluster = findGroup(scene, 'sub1');
      final clusterRect = shapesIn(cluster)
          .map((s) => s.geometry)
          .whereType<RectGeometry>()
          .first
          .rect;
      for (final id in ['B', 'C']) {
        final nb = groupBounds(findGroup(scene, id));
        expect(nb.left, greaterThanOrEqualTo(clusterRect.left));
        expect(nb.right, lessThanOrEqualTo(clusterRect.right));
        expect(nb.top, greaterThanOrEqualTo(clusterRect.top));
        expect(nb.bottom, lessThanOrEqualTo(clusterRect.bottom));
      }
      // Cluster title rendered.
      expect(textsIn(cluster).map((t) => t.text), contains('Inner work'));
      // Z-order: cluster group precedes member node groups in scene.nodes.
      final order = scene.nodes.whereType<SceneGroup>().map((g) => g.id).toList();
      expect(order.indexOf('sub1'), lessThan(order.indexOf('B')));
    });

    test('(h) node labels and edge labels appear in the scene', () {
      final scene = layout(chain(edgeLabel: 'yes'));
      final allTexts = <String>[];
      for (final n in scene.nodes) {
        allTexts.addAll(textsIn(n).map((t) => t.text));
      }
      expect(allTexts, containsAll(['Alpha', 'Beta', 'yes']));

      // Edge label has a background rect.
      final labelGroup = findGroup(scene, 'edgelabel_A_B_0');
      final bg = shapesIn(labelGroup)
          .where((s) => s.geometry is RectGeometry && s.fill != null);
      expect(bg, isNotEmpty);
    });

    test('(i) doubleCircle emits two circles; diamond emits 4-point polygon',
        () {
      final graph = FlowGraph(
        direction: FlowDirection.tb,
        nodes: {
          'A': node('A', shape: FlowNodeShape.doubleCircle),
          'B': node('B', shape: FlowNodeShape.diamond),
        },
        edges: const [FlowEdge(from: 'A', to: 'B')],
      );
      final scene = layout(graph);

      final circles = shapesIn(findGroup(scene, 'A'))
          .map((s) => s.geometry)
          .whereType<CircleGeometry>()
          .toList();
      expect(circles, hasLength(2));
      final radii = circles.map((c) => c.radius).toList()..sort();
      expect(radii[1] - radii[0], closeTo(5, 0.001),
          reason: 'inner/outer circle gap is 5');

      final polys = shapesIn(findGroup(scene, 'B'))
          .map((s) => s.geometry)
          .whereType<PolygonGeometry>()
          .toList();
      expect(polys, hasLength(1));
      expect(polys.single.points, hasLength(4));
    });

    test('per-node style resolution: classDefs and inline styles', () {
      final graph = FlowGraph(
        direction: FlowDirection.tb,
        nodes: {
          'A': const FlowNode(
            id: 'A',
            label: 'A',
            shape: FlowNodeShape.rect,
            classes: ['hot'],
          ),
          'B': const FlowNode(
            id: 'B',
            label: 'B',
            shape: FlowNodeShape.rect,
            styles: {'fill': '#00ff00', 'stroke-width': '3px'},
          ),
        },
        edges: const [FlowEdge(from: 'A', to: 'B')],
        classDefs: const {
          'hot': {'fill': 'red', 'color': 'white'},
        },
      );
      final scene = layout(graph);
      final aShape = shapesIn(findGroup(scene, 'A')).first;
      expect(aShape.fill!.color.value, 0xffff0000);
      expect(textsIn(findGroup(scene, 'A')).first.color.value, 0xffffffff);
      final bShape = shapesIn(findGroup(scene, 'B')).first;
      expect(bShape.fill!.color.value, 0xff00ff00);
      expect(bShape.stroke!.width, 3);
    });

    test('all shape kinds lay out without overlap and stay in bounds', () {
      final shapes = FlowNodeShape.values;
      final nodes = <String, FlowNode>{};
      final edges = <FlowEdge>[];
      for (var i = 0; i < shapes.length; i++) {
        final id = 'n$i';
        nodes[id] = FlowNode(id: id, label: 'Shape ${shapes[i].name}', shape: shapes[i]);
        if (i > 0) edges.add(FlowEdge(from: 'n${i - 1}', to: id));
      }
      final scene =
          layout(FlowGraph(direction: FlowDirection.tb, nodes: nodes, edges: edges));
      for (var i = 0; i < shapes.length; i++) {
        final b = groupBounds(findGroup(scene, 'n$i'));
        expect(b.width, greaterThan(0));
        for (var j = i + 1; j < shapes.length; j++) {
          expect(overlaps(b, groupBounds(findGroup(scene, 'n$j'))), isFalse,
              reason: 'n$i (${shapes[i].name}) overlaps n$j (${shapes[j].name})');
        }
      }
    });

    test('title is rendered bold above the content', () {
      final scene = layout(FlowGraph(
        direction: FlowDirection.tb,
        nodes: {'A': node('A')},
        edges: const [],
        title: 'Hello title',
      ));
      final titleText = scene.nodes
          .whereType<SceneText>()
          .firstWhere((t) => t.text == 'Hello title');
      expect(titleText.style.fontWeight, greaterThanOrEqualTo(700));
      final a = groupBounds(findGroup(scene, 'A'));
      expect(titleText.bounds.bottom, lessThanOrEqualTo(a.top));
    });
  });
}

SceneShape edgePathShape(SceneGroup edgeGroup) {
  for (final s in shapesIn(edgeGroup)) {
    if (s.geometry is PathGeometry && s.stroke != null) return s;
  }
  fail('edge group ${edgeGroup.id} has no stroked path');
}

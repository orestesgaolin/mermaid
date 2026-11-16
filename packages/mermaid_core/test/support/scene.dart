import 'package:mermaid_core/mermaid_core.dart';

/// Depth-first traversal, including container groups.
List<SceneNode> flattenScene(Iterable<SceneNode> nodes) => [
  for (final node in nodes) ...[
    node,
    if (node is SceneGroup) ...flattenScene(node.children),
  ],
];

Iterable<SceneGroup> groupsOf(Iterable<SceneNode> nodes) =>
    flattenScene(nodes).whereType<SceneGroup>();
Iterable<SceneShape> shapesOf(Iterable<SceneNode> nodes) =>
    flattenScene(nodes).whereType<SceneShape>();
Iterable<SceneText> textsOf(Iterable<SceneNode> nodes) =>
    flattenScene(nodes).whereType<SceneText>();

/// The route an edge path follows: a rounded corner gives back its corner
/// point, line hops are skipped, and points on a straight run are dropped.
List<Point> edgeRoute(Iterable<PathCommand> commands) {
  final out = <Point>[];
  void add(Point p) {
    if (out.isNotEmpty && out.last.distanceTo(p) < 0.01) return;
    if (out.length >= 2) {
      final a = out[out.length - 2], b = out.last;
      final cross = (b.x - a.x) * (p.y - b.y) - (b.y - a.y) * (p.x - b.x);
      if (cross.abs() < 0.01) out.removeLast();
    }
    out.add(p);
  }

  for (final c in commands) {
    switch (c) {
      case MoveTo(:final p) || LineTo(:final p):
        add(p);
      case QuadTo(:final c, :final p):
        add(c);
        add(p);
      default:
    }
  }
  return out;
}

/// Geometry only: deliberately excludes paint. The determinism suite checks
/// that this detects a changed label layout while ignoring paint changes.
String sceneGeometry(RenderScene scene) {
  final out = StringBuffer()
    ..writeln(
      'scene ${_number(scene.size.width)} ${_number(scene.size.height)}',
    );

  void writeNodes(Iterable<SceneNode> nodes, int depth) {
    for (final node in nodes) {
      final prefix = '  ' * depth;
      switch (node) {
        case SceneGroup(:final id, :final role, :final children):
          out.writeln(
            '$prefix group ${role.name} ${id ?? '-'} '
            '${_rect(sceneBounds(children))}',
          );
          writeNodes(children, depth + 1);
        case SceneShape(:final geometry):
          out.writeln('$prefix shape ${_geometry(geometry)}');
        case SceneText(:final text, :final bounds, :final rotation):
          out.writeln(
            '$prefix text ${text.replaceAll('\n', r'\n')} '
            '${_rect(bounds)} rotation=${_number(rotation)}',
          );
      }
    }
  }

  writeNodes(scene.nodes, 0);
  return out.toString();
}

String _geometry(ShapeGeometry geometry) => switch (geometry) {
  RectGeometry(:final rect, :final rx, :final ry) =>
    'rect ${_rect(rect)} rx=${_number(rx)} ry=${_number(ry)}',
  CircleGeometry(:final center, :final radius) =>
    'circle ${_point(center)} r=${_number(radius)}',
  EllipseGeometry(:final center, :final rx, :final ry) =>
    'ellipse ${_point(center)} rx=${_number(rx)} ry=${_number(ry)}',
  PolygonGeometry(:final points) => 'polygon ${points.map(_point).join(' ')}',
  PathGeometry(:final commands) => 'path ${commands.map(_command).join(' ')}',
};

String _command(PathCommand command) => switch (command) {
  MoveTo(:final p) => 'M${_point(p)}',
  LineTo(:final p) => 'L${_point(p)}',
  QuadTo(:final c, :final p) => 'Q${_point(c)},${_point(p)}',
  CubicTo(:final c1, :final c2, :final p) =>
    'C${_point(c1)},${_point(c2)},${_point(p)}',
  ClosePath() => 'Z',
};

String _rect(Rect? rect) => rect == null
    ? '-'
    : '${_number(rect.left)},${_number(rect.top)},'
          '${_number(rect.width)},${_number(rect.height)}';

String _point(Point point) => '${_number(point.x)},${_number(point.y)}';

String _number(double value) {
  if (value == 0) return '0.0';
  return value.toString();
}

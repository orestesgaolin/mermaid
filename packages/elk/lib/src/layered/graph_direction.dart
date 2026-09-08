import '../api/options.dart';
import 'intermediate_edges.dart' show junctionPoints;
import 'lgraph.dart';

/// Converts a graph's internal layout coordinates from its local output
/// direction into its parent graph's coordinate frame. Applying this
/// bottom-up lets every nested graph choose its own output direction.
class GraphDirection {
  GraphDirection(this.from, this.to);
  final ElkDirection from;
  final ElkDirection to;

  (double, double) point(double x, double y) {
    final (ox, oy) = switch (from) {
      ElkDirection.right => (x, y),
      ElkDirection.left => (-x, y),
      ElkDirection.down => (y, x),
      ElkDirection.up => (y, -x),
    };
    return switch (to) {
      ElkDirection.right => (ox, oy),
      ElkDirection.left => (-ox, oy),
      ElkDirection.down => (oy, ox),
      ElkDirection.up => (-oy, ox),
    };
  }

  (double, double, double, double) rect(
    double x,
    double y,
    double w,
    double h,
  ) {
    final (x1, y1) = point(x, y);
    final (x2, y2) = point(x + w, y + h);
    return (
      x1 < x2 ? x1 : x2,
      y1 < y2 ? y1 : y2,
      (x2 - x1).abs(),
      (y2 - y1).abs(),
    );
  }

  PortSide side(PortSide side) {
    final vector = switch (side) {
      PortSide.north => (0.0, -1.0),
      PortSide.south => (0.0, 1.0),
      PortSide.east => (1.0, 0.0),
      PortSide.west => (-1.0, 0.0),
      _ => (0.0, 0.0),
    };
    final (x, y) = point(vector.$1, vector.$2);
    return x > 0
        ? PortSide.east
        : x < 0
        ? PortSide.west
        : y > 0
        ? PortSide.south
        : y < 0
        ? PortSide.north
        : side;
  }

  void apply(LGraph graph, Iterable<LEdge> edges) {
    if (from == to) return;
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        final (nx, ny, nw, nh) = rect(
          node.position.x,
          node.position.y,
          node.size.x,
          node.size.y,
        );
        final (rx, ry, _, __) = rect(0, 0, node.size.x, node.size.y);
        void label(LLabel l, double originX, double originY) {
          final r = rect(l.position.x, l.position.y, l.size.x, l.size.y);
          l.position
            ..x = r.$1 - originX
            ..y = r.$2 - originY;
          l.size
            ..x = r.$3
            ..y = r.$4;
        }

        for (final l in node.labels) {
          label(l, rx, ry);
        }
        for (final p in node.ports) {
          final r = rect(p.position.x, p.position.y, p.size.x, p.size.y);
          final anchor = point(
            p.position.x + p.anchor.x,
            p.position.y + p.anchor.y,
          );
          final pr = rect(0, 0, p.size.x, p.size.y);
          for (final l in p.labels) {
            label(l, pr.$1, pr.$2);
          }
          p.position
            ..x = r.$1 - rx
            ..y = r.$2 - ry;
          p.size
            ..x = r.$3
            ..y = r.$4;
          p.anchor
            ..x = anchor.$1 - r.$1
            ..y = anchor.$2 - r.$2;
          p.side = side(p.side);
        }
        node.position
          ..x = nx
          ..y = ny;
        node.size
          ..x = nw
          ..y = nh;
      }
    }
    for (final edge in edges.toSet()) {
      for (final p in [
        ...edge.bendPoints.points,
        ...?edge.getProperty(junctionPoints)?.points,
      ]) {
        final r = point(p.x, p.y);
        p
          ..x = r.$1
          ..y = r.$2;
      }
      for (final l in edge.labels) {
        final r = rect(l.position.x, l.position.y, l.size.x, l.size.y);
        l.position
          ..x = r.$1
          ..y = r.$2;
        l.size
          ..x = r.$3
          ..y = r.$4;
      }
    }
  }
}

/// The render scene IR: a backend-agnostic, fully resolved description of a
/// laid-out diagram. Coordinates are absolute in scene space (y down), colors
/// and fonts are resolved — backends (Flutter CustomPainter, SVG writer) only
/// translate primitives, they make no layout or styling decisions.
library;

import '../color.dart';
import '../geometry.dart';
import '../text/text_style.dart';

class RenderScene {
  const RenderScene({
    required this.size,
    required this.nodes,
    this.background,
  });

  /// Tight bounding size of the diagram including padding.
  final Size size;
  final Color? background;
  final List<SceneNode> nodes;
}

sealed class SceneNode {
  const SceneNode();
}

/// Logical grouping (a diagram node, an edge with its label, a cluster).
/// Purely structural: children use absolute scene coordinates.
class SceneGroup extends SceneNode {
  const SceneGroup({required this.children, this.id, this.semanticLabel});

  /// Stable identifier (e.g. flowchart node id) for hit-testing/interactivity.
  final String? id;

  /// Accessibility label for this group, if any.
  final String? semanticLabel;
  final List<SceneNode> children;
}

class SceneShape extends SceneNode {
  const SceneShape({required this.geometry, this.fill, this.stroke});

  final ShapeGeometry geometry;
  final Fill? fill;
  final Stroke? stroke;
}

class SceneText extends SceneNode {
  const SceneText({
    required this.text,
    required this.bounds,
    required this.style,
    required this.color,
    this.align = TextAlignH.center,
    this.rotation = 0,
  });

  /// May contain `\n`; backends wrap to [bounds].width using the same rules
  /// as the TextMeasurer that produced the layout.
  final String text;

  /// The measured block the text occupies; paint inside it.
  final Rect bounds;
  final TextStyleSpec style;
  final Color color;
  final TextAlignH align;

  /// Rotation in degrees (clockwise) about the center of [bounds]. Used e.g.
  /// for vertical axis labels. 0 ⇒ horizontal.
  final double rotation;
}

enum TextAlignH { left, center, right }

class Fill {
  const Fill(this.color, {this.gradient});

  /// Solid color; also the fallback if a backend ignores [gradient].
  final Color color;

  /// Optional linear gradient (in absolute scene coordinates). When set,
  /// backends fill with the gradient instead of [color].
  final SceneGradient? gradient;
}

/// A linear gradient between two points, with evenly-spaced color stops.
class SceneGradient {
  const SceneGradient(this.from, this.to, this.colors);
  final Point from;
  final Point to;

  /// Two or more stops, distributed evenly from [from] to [to].
  final List<Color> colors;
}

class Stroke {
  const Stroke({required this.color, this.width = 1, this.dash});

  final Color color;
  final double width;

  /// SVG-style dash array (on, off, on, off, ...), null for solid.
  final List<double>? dash;
}

sealed class ShapeGeometry {
  const ShapeGeometry();
}

class RectGeometry extends ShapeGeometry {
  const RectGeometry(this.rect, {this.rx = 0, this.ry = 0});

  final Rect rect;
  final double rx;
  final double ry;
}

class CircleGeometry extends ShapeGeometry {
  const CircleGeometry(this.center, this.radius);

  final Point center;
  final double radius;
}

class EllipseGeometry extends ShapeGeometry {
  const EllipseGeometry(this.center, this.rx, this.ry);

  final Point center;
  final double rx;
  final double ry;
}

class PolygonGeometry extends ShapeGeometry {
  const PolygonGeometry(this.points);

  final List<Point> points;
}

class PathGeometry extends ShapeGeometry {
  const PathGeometry(this.commands);

  final List<PathCommand> commands;
}

sealed class PathCommand {
  const PathCommand();
}

class MoveTo extends PathCommand {
  const MoveTo(this.p);
  final Point p;
}

class LineTo extends PathCommand {
  const LineTo(this.p);
  final Point p;
}

class CubicTo extends PathCommand {
  const CubicTo(this.c1, this.c2, this.p);
  final Point c1;
  final Point c2;
  final Point p;
}

class QuadTo extends PathCommand {
  const QuadTo(this.c, this.p);
  final Point c;
  final Point p;
}

class ClosePath extends PathCommand {
  const ClosePath();
}

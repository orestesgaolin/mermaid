/// Minimal immutable 2D geometry types, independent of dart:ui.
library;

import 'dart:math' as math;

class Point {
  const Point(this.x, this.y);

  final double x;
  final double y;

  static const zero = Point(0, 0);

  Point operator +(Point other) => Point(x + other.x, y + other.y);
  Point operator -(Point other) => Point(x - other.x, y - other.y);
  Point operator *(double f) => Point(x * f, y * f);

  double distanceTo(Point other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point($x, $y)';
}

class Size {
  const Size(this.width, this.height);

  final double width;
  final double height;

  static const zero = Size(0, 0);

  @override
  bool operator ==(Object other) =>
      other is Size && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Size($width, $height)';
}

class Rect {
  const Rect.fromLTWH(this.left, this.top, this.width, this.height);

  const Rect.fromLTRB(double left, double top, double right, double bottom)
      : this.fromLTWH(left, top, right - left, bottom - top);

  Rect.fromCenter(Point center, double width, double height)
      : this.fromLTWH(center.x - width / 2, center.y - height / 2, width, height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  Point get center => Point(left + width / 2, top + height / 2);
  Size get size => Size(width, height);

  Rect inflate(double d) =>
      Rect.fromLTWH(left - d, top - d, width + 2 * d, height + 2 * d);

  Rect translate(double dx, double dy) =>
      Rect.fromLTWH(left + dx, top + dy, width, height);

  Rect union(Rect other) => Rect.fromLTRB(
        math.min(left, other.left),
        math.min(top, other.top),
        math.max(right, other.right),
        math.max(bottom, other.bottom),
      );

  bool contains(Point p) =>
      p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'Rect.fromLTWH($left, $top, $width, $height)';
}

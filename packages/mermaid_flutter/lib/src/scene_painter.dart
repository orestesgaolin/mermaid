/// CustomPainter that translates a [core.RenderScene] into canvas calls.
/// Purely mechanical: all layout and styling decisions were already made by
/// mermaid_core; this only maps IR primitives to dart:ui.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;

import 'flutter_text_measurer.dart';

class ScenePainter extends CustomPainter {
  const ScenePainter(this.scene);

  final core.RenderScene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final background = scene.background;
    if (background != null && background.alpha != 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Color(background.value),
      );
    }
    for (final node in scene.nodes) {
      _paintNode(canvas, node);
    }
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) =>
      !identical(oldDelegate.scene, scene);

  void _paintNode(Canvas canvas, core.SceneNode node) {
    switch (node) {
      case core.SceneGroup(:final children):
        for (final child in children) {
          _paintNode(canvas, child);
        }
      case core.SceneShape():
        _paintShape(canvas, node);
      case core.SceneText():
        _paintText(canvas, node);
    }
  }

  void _paintShape(Canvas canvas, core.SceneShape shape) {
    final path = _pathFromGeometry(shape.geometry);

    final fill = shape.fill;
    if (fill != null && (fill.gradient != null || fill.color.alpha != 0)) {
      final paint = Paint()..style = PaintingStyle.fill;
      final g = fill.gradient;
      if (g != null) {
        paint.shader = ui.Gradient.linear(
          Offset(g.from.x, g.from.y),
          Offset(g.to.x, g.to.y),
          [for (final c in g.colors) Color(c.value)],
        );
      } else {
        paint.color = Color(fill.color.value);
      }
      canvas.drawPath(path, paint);
    }

    final stroke = shape.stroke;
    if (stroke != null && stroke.color.alpha != 0 && stroke.width > 0) {
      final dash = stroke.dash;
      final strokePath =
          (dash != null && dash.isNotEmpty) ? dashPath(path, dash) : path;
      canvas.drawPath(
        strokePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width
          ..strokeJoin = StrokeJoin.round
          ..color = Color(stroke.color.value),
      );
    }
  }

  void _paintText(Canvas canvas, core.SceneText text) {
    // +1 for float safety: the measurer ceils sizes, so the painted block may
    // need a hair more room than bounds.width to avoid spurious wrapping.
    final blockWidth = text.bounds.width + 1;
    final painter = TextPainter(
      text: TextSpan(
        text: text.text,
        style: textStyleFromSpec(text.style, color: Color(text.color.value))
            .copyWith(
          decoration:
              text.underline ? TextDecoration.underline : TextDecoration.none,
        ),
      ),
      textAlign: switch (text.align) {
        core.TextAlignH.left => TextAlign.left,
        core.TextAlignH.center => TextAlign.center,
        core.TextAlignH.right => TextAlign.right,
      },
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(minWidth: blockWidth, maxWidth: blockWidth);
    if (text.rotation != 0) {
      final cx = text.bounds.center.x, cy = text.bounds.center.y;
      canvas
        ..save()
        ..translate(cx, cy)
        ..rotate(text.rotation * 3.141592653589793 / 180)
        ..translate(-cx, -cy);
      painter.paint(canvas, Offset(text.bounds.left, text.bounds.top));
      canvas.restore();
    } else {
      painter.paint(canvas, Offset(text.bounds.left, text.bounds.top));
    }
    painter.dispose();
  }

  Path _pathFromGeometry(core.ShapeGeometry geometry) {
    final path = Path();
    switch (geometry) {
      case core.RectGeometry(:final rect, :final rx, :final ry):
        final r = Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
        if (rx > 0 || ry > 0) {
          path.addRRect(
            RRect.fromRectXY(r, rx > 0 ? rx : ry, ry > 0 ? ry : rx),
          );
        } else {
          path.addRect(r);
        }
      case core.CircleGeometry(:final center, :final radius):
        path.addOval(
          Rect.fromCircle(center: Offset(center.x, center.y), radius: radius),
        );
      case core.EllipseGeometry(:final center, :final rx, :final ry):
        path.addOval(
          Rect.fromCenter(
            center: Offset(center.x, center.y),
            width: rx * 2,
            height: ry * 2,
          ),
        );
      case core.PolygonGeometry(:final points):
        if (points.isNotEmpty) {
          path.moveTo(points.first.x, points.first.y);
          for (final p in points.skip(1)) {
            path.lineTo(p.x, p.y);
          }
          path.close();
        }
      case core.PathGeometry(:final commands):
        for (final command in commands) {
          switch (command) {
            case core.MoveTo(:final p):
              path.moveTo(p.x, p.y);
            case core.LineTo(:final p):
              path.lineTo(p.x, p.y);
            case core.CubicTo(:final c1, :final c2, :final p):
              path.cubicTo(c1.x, c1.y, c2.x, c2.y, p.x, p.y);
            case core.QuadTo(:final c, :final p):
              path.quadraticBezierTo(c.x, c.y, p.x, p.y);
            case core.ClosePath():
              path.close();
          }
        }
    }
    return path;
  }
}

/// Converts [source] into a dashed path following an SVG-style dash array
/// (on, off, on, off, ...) using path metrics.
Path dashPath(Path source, List<double> pattern) {
  final effective = pattern.where((d) => d > 0).toList();
  if (effective.isEmpty) return source;
  final dest = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var index = 0;
    var draw = true;
    while (distance < metric.length) {
      final length = effective[index % effective.length];
      if (draw) {
        dest.addPath(
          metric.extractPath(distance, distance + length),
          Offset.zero,
        );
      }
      distance += length;
      draw = !draw;
      index++;
    }
  }
  return dest;
}

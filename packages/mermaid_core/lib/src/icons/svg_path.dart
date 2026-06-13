/// Parses an SVG path `d` string into our [PathCommand] IR, reusing the
/// battle-tested `path_parsing` package (the same parser flutter_svg uses).
/// All commands (incl. arcs and quadratics) are normalized to move/line/cubic,
/// which our backends already render.
library;

import 'package:path_parsing/path_parsing.dart';

import '../geometry.dart';
import '../ir/scene.dart';

/// Converts an SVG path data string to [PathCommand]s. Returns an empty list
/// if [d] is null/blank or fails to parse.
List<PathCommand> parseSvgPath(String? d) {
  if (d == null || d.trim().isEmpty) return const [];
  final proxy = _CommandProxy();
  try {
    writeSvgPathDataToPath(d, proxy);
  } catch (_) {
    return proxy.commands; // keep whatever parsed before the error
  }
  return proxy.commands;
}

class _CommandProxy extends PathProxy {
  final commands = <PathCommand>[];

  @override
  void moveTo(double x, double y) => commands.add(MoveTo(Point(x, y)));

  @override
  void lineTo(double x, double y) => commands.add(LineTo(Point(x, y)));

  @override
  void cubicTo(
          double x1, double y1, double x2, double y2, double x3, double y3) =>
      commands.add(CubicTo(Point(x1, y1), Point(x2, y2), Point(x3, y3)));

  @override
  void close() => commands.add(const ClosePath());
}

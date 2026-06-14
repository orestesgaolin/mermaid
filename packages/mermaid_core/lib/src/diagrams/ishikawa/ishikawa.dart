/// Ishikawa / fishbone diagram (`ishikawa-beta`): the effect/problem as a
/// fish head at the top of a vertical spine, with cause "bones" angling up and
/// down off the spine and arbitrary-depth sub-cause bones branching off them.
library;

import 'dart:math' as math;

import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

/// A node in the arbitrary-depth cause tree (mirrors upstream `IshikawaNode`).
class IshikawaNode {
  IshikawaNode(this.text);
  final String text;
  final children = <IshikawaNode>[];
}

class IshikawaDiagram {
  const IshikawaDiagram(this.root);

  /// The effect/problem node; its [IshikawaNode.children] are the top-level
  /// causes. Null when the source has no body lines.
  final IshikawaNode? root;
}

// Layout constants ported from upstream `ishikawaRenderer.ts`.
const double _fontSizeDefault = 14;
const double _spineBaseLength = 250;
const double _boneStub = 30;
const double _boneBase = 60;
const double _bonePerChild = 5;
final double _angle = 82 * math.pi / 180;
final double _cosA = math.cos(_angle);
final double _sinA = math.sin(_angle);

IshikawaDiagram parseIshikawa(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  var seenHeader = false;

  IshikawaNode? root;
  // Stack of (level, node) entries mapping indentation to nesting.
  final stack = <_StackEntry>[];
  int? baseLevel;

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c);
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*ishikawa(-beta)?\b').hasMatch(line)) {
        throw MermaidParseException('expected "ishikawa" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }

    final rawLevel = line.length - line.trimLeft().length;
    final label = line.trim();

    if (root == null) {
      root = IshikawaNode(label);
      stack
        ..clear()
        ..add(_StackEntry(0, root));
      continue;
    }

    // baseLevel is taken from the FIRST cause (not the effect/root line) so the
    // relative indentation between causes is preserved even when the effect
    // line is indented more than its causes.
    baseLevel ??= rawLevel;

    var level = rawLevel - baseLevel + 1;
    if (level <= 0) level = 1;

    // Pop until the top has a strictly lower level (= the parent).
    while (stack.length > 1 && stack.last.level >= level) {
      stack.removeLast();
    }

    final parent = stack.last.node;
    final node = IshikawaNode(label);
    parent.children.add(node);
    stack.add(_StackEntry(level, node));
  }

  if (!seenHeader) throw const MermaidParseException('empty ishikawa source');
  return IshikawaDiagram(root);
}

class _StackEntry {
  _StackEntry(this.level, this.node);
  final int level;
  final IshikawaNode node;
}

RenderScene layoutIshikawa(
  IshikawaDiagram d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final root = d.root;
  final fontSize = theme.fontSize == 0 ? _fontSizeDefault : theme.fontSize;
  final labelStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: fontSize,
  );
  // Head label is font-weight 600, 14px (upstream `.ishikawa-head-label`).
  final headStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: 14,
    fontWeight: 600,
  );

  final ctx = _LayoutContext(
    measurer: measurer,
    theme: theme,
    fontSize: fontSize,
    labelStyle: labelStyle,
    headStyle: headStyle,
  );

  final nodes = ctx.nodes;

  if (root == null) {
    return RenderScene(
      size: const Size(40, 40),
      background: theme.background,
      nodes: const [],
    );
  }

  final causes = root.children;

  var spineX = 0.0;
  var spineY = _spineBaseLength;

  // Draw the head; the head group is recentered on the final spineY below.
  ctx.drawHead(spineX, spineY, root.text);

  if (causes.isEmpty) {
    // Spine collapses to a point; just the head is shown.
    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(spineX, spineY)),
        LineTo(Point(spineX, spineY)),
      ]),
      stroke: Stroke(color: theme.lineColor, width: 2),
    ));
    return ctx.finish();
  }

  spineX -= 20;

  final upperCauses = <IshikawaNode>[];
  final lowerCauses = <IshikawaNode>[];
  for (var i = 0; i < causes.length; i++) {
    (i.isEven ? upperCauses : lowerCauses).add(causes[i]);
  }

  final upperStats = _sideStats(upperCauses);
  final lowerStats = _sideStats(lowerCauses);
  final descendantTotal = upperStats.total + lowerStats.total;

  var upperLen = _spineBaseLength;
  var lowerLen = _spineBaseLength;
  if (descendantTotal > 0) {
    const pool = _spineBaseLength * 2;
    const minLen = _spineBaseLength * 0.3;
    upperLen = math.max(minLen, pool * (upperStats.total / descendantTotal));
    lowerLen = math.max(minLen, pool * (lowerStats.total / descendantTotal));
  }

  final minSpacing = fontSize * 2;
  upperLen = math.max(upperLen, upperStats.max * minSpacing);
  lowerLen = math.max(lowerLen, lowerStats.max * minSpacing);

  spineY = math.max(upperLen, _spineBaseLength);
  // Recenter the head group onto the final spine origin.
  ctx.headDy = spineY - _spineBaseLength;

  // Track the leftmost label x as the spine origin extends to enclose bones.
  var spineLeft = spineX;

  final pairCount = (causes.length / 2).ceil();
  for (var p = 0; p < pairCount; p++) {
    final entries = <(IshikawaNode, int, double)>[
      if (p * 2 < causes.length) (causes[p * 2], -1, upperLen),
      if (p * 2 + 1 < causes.length) (causes[p * 2 + 1], 1, lowerLen),
    ];
    var pairLeft = double.infinity;
    for (final (cause, dir, len) in entries) {
      final left = ctx.drawBranch(cause, spineX, spineY, dir, len);
      pairLeft = math.min(pairLeft, left);
    }
    if (pairLeft.isFinite) {
      spineX = math.min(spineX, pairLeft);
      spineLeft = math.min(spineLeft, pairLeft);
    }
  }

  // Spine from the head (x=0) leftward to the leftmost bone label.
  nodes.add(SceneShape(
    geometry: PathGeometry([
      MoveTo(Point(spineLeft, spineY)),
      LineTo(Point(0, spineY)),
    ]),
    stroke: Stroke(color: theme.lineColor, width: 2),
  ));

  return ctx.finish();
}

class _SideStats {
  _SideStats(this.total, this.max);
  final int total;
  final int max;
}

int _countDescendants(IshikawaNode node) {
  var sum = 0;
  for (final child in node.children) {
    sum += 1 + _countDescendants(child);
  }
  return sum;
}

_SideStats _sideStats(List<IshikawaNode> nodes) {
  var total = 0;
  var max = 0;
  for (final node in nodes) {
    final d = _countDescendants(node);
    total += d;
    if (d > max) max = d;
  }
  return _SideStats(total, max);
}

class _LabelEntry {
  _LabelEntry({
    required this.text,
    required this.depth,
    required this.parentIndex,
    required this.childCount,
  });
  final String text;
  final int depth;
  final int parentIndex;
  final int childCount;
}

class _BoneInfo {
  _BoneInfo({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.childCount,
  });
  final double x0;
  final double y0;
  final double x1;
  final double y1;
  final int childCount;
  int childrenDrawn = 0;
}

class _FlattenResult {
  _FlattenResult(this.entries, this.yOrder);
  final List<_LabelEntry> entries;
  final List<int> yOrder;
}

// Flatten children so Y positions can be assigned without recursion when
// drawing. Even depths are placed in pre-order (close to the spine), odd depths
// in post-order to keep diagonal bones within their parent wedge.
_FlattenResult _flattenTree(List<IshikawaNode> children, int direction) {
  final entries = <_LabelEntry>[];
  final yOrder = <int>[];

  void walk(List<IshikawaNode> nodes, int pid, int depth) {
    final ordered = direction == -1 ? nodes.reversed.toList() : nodes;
    for (final child in ordered) {
      final idx = entries.length;
      final gc = child.children;
      entries.add(_LabelEntry(
        depth: depth,
        text: _wrapText(child.text, 15),
        parentIndex: pid,
        childCount: gc.length,
      ));
      if (depth.isEven) {
        // Even-depth: pre-order (closer to the spine).
        yOrder.add(idx);
        if (gc.isNotEmpty) walk(gc, idx, depth + 1);
      } else {
        // Odd-depth: post-order (within the parent diagonal).
        if (gc.isNotEmpty) walk(gc, idx, depth + 1);
        yOrder.add(idx);
      }
    }
  }

  walk(children, -1, 2);
  return _FlattenResult(entries, yOrder);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _LayoutContext {
  _LayoutContext({
    required this.measurer,
    required this.theme,
    required this.fontSize,
    required this.labelStyle,
    required this.headStyle,
  });

  final TextMeasurer measurer;
  final MermaidTheme theme;
  final double fontSize;
  final TextStyleSpec labelStyle;
  final TextStyleSpec headStyle;

  final nodes = <SceneNode>[];

  // Deferred vertical offset to recenter the head group onto the final spineY.
  double headDy = 0;
  // Index range of head nodes so finish() can apply [headDy].
  int _headStart = -1;
  int _headEnd = -1;

  RenderScene finish() {
    if (headDy != 0 && _headStart >= 0) {
      for (var i = _headStart; i < _headEnd; i++) {
        nodes[i] = translateSceneNode(nodes[i], 0, headDy);
      }
    }
    final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 200, 200);
    const m = 20.0;
    return RenderScene(
      size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
      background: theme.background,
      nodes: [
        for (final nd in nodes) translateSceneNode(nd, m - bounds.left, m - bounds.top)
      ],
    );
  }

  // Measure a (possibly multi-line) label, returning its width/height.
  Size _measureMultiline(String text, TextStyleSpec style) {
    final lines = _splitLines(text);
    final lh = style.fontSize * 1.05;
    var w = 0.0;
    for (final line in lines) {
      final s = measurer.measure(line, style);
      if (s.width > w) w = s.width;
    }
    final h = lines.length * lh;
    return Size(w, h);
  }

  /// Draws the fish-head shape and label centered at (x, y). The head nodes can
  /// be shifted vertically later via [headDy].
  void drawHead(double x, double y, String label) {
    _headStart = nodes.length;
    final maxChars = math.max(6, (110 / (14 * 0.6)).floor());
    final wrapped = _wrapText(label, maxChars);
    final tb = _measureMultiline(wrapped, headStyle);
    final w = math.max(60.0, tb.width + 6);
    final h = math.max(40.0, tb.height * 2 + 40);

    // Path: M 0 -h/2 L 0 h/2 Q w*2.4 0 0 -h/2 Z (relative to the head origin).
    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(x, y - h / 2)),
        LineTo(Point(x, y + h / 2)),
        QuadTo(Point(x + w * 2.4, y), Point(x, y - h / 2)),
        const ClosePath(),
      ]),
      fill: Fill(theme.mainBkg),
      stroke: Stroke(color: theme.lineColor, width: 2),
    ));
    // Label horizontally centered within the head wedge body.
    final labelCx = x + w / 2 + 3;
    _drawMultilineText(
      wrapped,
      labelCx,
      y,
      headStyle,
      TextAlignH.center,
    );

    _headEnd = nodes.length;
  }

  /// Draws a top-level branch (cause) and all its descendants. Returns the
  /// leftmost x reached by any label drawn (used to extend the spine).
  double drawBranch(
    IshikawaNode node,
    double startX,
    double startY,
    int direction,
    double length,
  ) {
    final children = node.children;
    final lineLen = length * (children.isNotEmpty ? 1.0 : 0.2);
    final dx = -_cosA * lineLen;
    final dy = _sinA * lineLen * direction;
    final endX = startX + dx;
    final endY = startY + dy;

    var leftmost = double.infinity;

    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(startX, startY)),
        LineTo(Point(endX, endY)),
      ]),
      stroke: Stroke(color: theme.lineColor, width: 2),
    ));
    // Arrow points back toward the spine origin (marker-start).
    _drawArrow(startX, startY, startX - endX, startY - endY, 2);

    final causeLeft = _drawCauseLabel(node.text, endX, endY, direction);
    leftmost = math.min(leftmost, causeLeft);

    if (children.isEmpty) return leftmost;

    final flat = _flattenTree(children, direction);
    final entries = flat.entries;
    final entryCount = entries.length;
    final ys = List<double>.filled(entryCount, 0);
    for (var slot = 0; slot < flat.yOrder.length; slot++) {
      final entryIdx = flat.yOrder[slot];
      ys[entryIdx] = startY + dy * ((slot + 1) / (entryCount + 1));
    }

    final bones = <int, _BoneInfo>{};
    bones[-1] = _BoneInfo(
      x0: startX,
      y0: startY,
      x1: endX,
      y1: endY,
      childCount: children.length,
    );

    final diagonalX = -_cosA;
    final diagonalY = _sinA * direction;

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final y = ys[i];
      final par = bones[e.parentIndex]!;

      double bx0;
      double by0;
      double bx1;

      if (e.depth.isEven) {
        // Horizontal bone: attach to the parent's diagonal at the target Y,
        // extend left.
        final dyP = par.y1 - par.y0;
        bx0 = _lerp(par.x0, par.x1, dyP != 0 ? (y - par.y0) / dyP : 0.5);
        by0 = y;
        bx1 = bx0 -
            (e.childCount > 0
                ? _boneBase + e.childCount * _bonePerChild
                : _boneStub);
        nodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(bx0, y)),
            LineTo(Point(bx1, y)),
          ]),
          stroke: Stroke(color: theme.lineColor, width: 1),
        ));
        _drawArrow(bx0, y, 1, 0, 1);
        // 'align': end-anchored, vertically centered at (bx1, y).
        final left = _drawSubLabel(e.text, bx1, y, _SubAnchor.middle);
        leftmost = math.min(leftmost, left);
      } else {
        // Diagonal bone: start from an evenly-spaced point on the parent's
        // horizontal, angle toward the target Y.
        final k = par.childrenDrawn++;
        bx0 = _lerp(par.x0, par.x1, (par.childCount - k) / (par.childCount + 1));
        by0 = par.y0;
        bx1 = bx0 + diagonalX * ((y - by0) / diagonalY);
        nodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(bx0, by0)),
            LineTo(Point(bx1, y)),
          ]),
          stroke: Stroke(color: theme.lineColor, width: 1),
        ));
        _drawArrow(bx0, by0, bx0 - bx1, by0 - y, 1);
        // 'up'/'down': end-anchored, baseline above (dir<0) / hanging below.
        final left = _drawSubLabel(
          e.text,
          bx1,
          y,
          direction < 0 ? _SubAnchor.up : _SubAnchor.down,
        );
        leftmost = math.min(leftmost, left);
      }

      if (e.childCount > 0) {
        bones[i] = _BoneInfo(
          x0: bx0,
          y0: by0,
          x1: bx1,
          y1: y,
          childCount: e.childCount,
        );
      }
    }

    return leftmost;
  }

  /// Top-level cause label: centered text with a white background box behind.
  /// Returns the leftmost x of the box.
  double _drawCauseLabel(String text, double x, double y, int direction) {
    final wrapped = _wrapText(text, 15);
    final size = _measureMultiline(wrapped, labelStyle);
    final cy = y + 11 * direction;
    final boxRect = Rect.fromLTWH(
      x - size.width / 2 - 20,
      cy - size.height / 2 - 2,
      size.width + 40,
      size.height + 4,
    );
    nodes.add(SceneShape(
      geometry: RectGeometry(boxRect),
      fill: Fill(theme.mainBkg),
      stroke: Stroke(color: theme.lineColor, width: 2),
    ));
    _drawMultilineText(wrapped, x, cy, labelStyle, TextAlignH.center);
    return boxRect.left;
  }

  /// Sub-branch label (no box). End-anchored at (x, y). Returns leftmost x.
  double _drawSubLabel(String text, double x, double y, _SubAnchor anchor) {
    final size = _measureMultiline(text, labelStyle);
    // End-anchored: text extends to the left of x.
    final lh = labelStyle.fontSize * 1.05;
    final lines = _splitLines(text);
    double topY;
    switch (anchor) {
      case _SubAnchor.middle:
        topY = y - size.height / 2;
      case _SubAnchor.up: // baseline at y => block sits above y
        topY = y - size.height;
      case _SubAnchor.down: // hanging at y => block sits below y
        topY = y;
    }
    // Multi-line block right-aligned to x.
    final blockTop = topY - ((lines.length - 1) * lh) / 2;
    final bounds = Rect.fromLTWH(x - size.width, blockTop, size.width, size.height);
    nodes.add(SceneText(
      text: lines.join('\n'),
      bounds: bounds,
      style: labelStyle,
      color: theme.textColor,
      align: TextAlignH.right,
    ));
    return bounds.left;
  }

  // Draws a center-anchored multi-line text block centered at (cx, cy).
  void _drawMultilineText(
    String text,
    double cx,
    double cy,
    TextStyleSpec style,
    TextAlignH align,
  ) {
    final lines = _splitLines(text);
    final lh = style.fontSize * 1.05;
    var w = 0.0;
    for (final line in lines) {
      final s = measurer.measure(line, style);
      if (s.width > w) w = s.width;
    }
    final h = lines.length * lh;
    nodes.add(SceneText(
      text: lines.join('\n'),
      bounds: Rect.fromCenter(Point(cx, cy), w, h),
      style: style,
      color: theme.textColor,
      align: align,
    ));
  }

  // Small filled arrow triangle whose tip sits at (x, y), pointing along (dx,dy).
  void _drawArrow(double x, double y, double dx, double dy, double strokeWidth) {
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final ux = dx / len;
    final uy = dy / len;
    const s = 6.0;
    final px = -uy * s;
    final py = ux * s;
    nodes.add(SceneShape(
      geometry: PolygonGeometry([
        Point(x, y),
        Point(x - ux * s * 2 + px, y - uy * s * 2 + py),
        Point(x - ux * s * 2 - px, y - uy * s * 2 - py),
      ]),
      fill: Fill(theme.lineColor),
      stroke: Stroke(color: theme.lineColor, width: 1),
    ));
  }
}

enum _SubAnchor { middle, up, down }

List<String> _splitLines(String text) =>
    text.split(RegExp(r'<br\s*/?>|\n'));

String _wrapText(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  final lines = <String>[];
  for (final word in text.split(RegExp(r'\s+'))) {
    if (lines.isNotEmpty && lines.last.length + 1 + word.length <= maxChars) {
      lines[lines.length - 1] = '${lines.last} $word';
    } else {
      lines.add(word);
    }
  }
  return lines.join('\n');
}

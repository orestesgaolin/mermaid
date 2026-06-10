/// Mindmap: model, parser and layout — one file.
///
/// Reference: upstream mindmap langium grammar + mindmapRenderer. Upstream
/// lays out with cytoscape cose-bilkent; this port uses a deterministic
/// two-sided tidy tree (children fan out right and left of the root), which
/// is the classic mindmap look.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

enum MindmapShape { plain, rect, rounded, circle, bang, cloud, hexagon }

class MindmapNode {
  MindmapNode({
    required this.label,
    required this.shape,
    required this.depth,
  });

  final String label;
  final MindmapShape shape;
  final int depth;
  final children = <MindmapNode>[];
}

class Mindmap {
  const Mindmap({required this.root});

  final MindmapNode root;
}

Mindmap parseMindmap(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  MindmapNode? root;
  // (indent, node) stack from root to current.
  final stack = <(int, MindmapNode)>[];
  var seenHeader = false;

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    var line = raw.trimRight();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trimRight();
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*mindmap\b').hasMatch(line)) {
        throw MermaidParseException('expected "mindmap" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }
    final indent = line.length - line.trimLeft().length;
    final content = line.trim();
    // Icon/class decorations attach to the previous node; not rendered yet.
    if (content.startsWith('::icon') || content.startsWith(':::')) continue;

    final (shape, label) = _parseNodeText(content, i + 1);
    if (root == null) {
      root = MindmapNode(label: label, shape: shape, depth: 0);
      stack.add((indent, root));
      continue;
    }
    while (stack.isNotEmpty && indent <= stack.last.$1) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      throw MermaidParseException(
          'multiple roots are not allowed in a mindmap', line: i + 1);
    }
    final parent = stack.last.$2;
    final node =
        MindmapNode(label: label, shape: shape, depth: parent.depth + 1);
    parent.children.add(node);
    stack.add((indent, node));
  }
  if (!seenHeader || root == null) {
    throw const MermaidParseException('empty mindmap source');
  }
  return Mindmap(root: root);
}

(MindmapShape, String) _parseNodeText(String content, int line) {
  String normalize(String s) => s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .trim();
  // id((label)) etc — the leading id is optional and unused for layout.
  final m = RegExp(r'^([\wÀ-￿-]*)\s*'
          r'(\(\(|\)\)|\(-|\)|\(|\[|\{\{)(.*?)(\)\)|\(\(|-\)|\(|\)|\]|\}\})\s*$')
      .firstMatch(content);
  if (m == null) return (MindmapShape.plain, normalize(content));
  final open = m.group(2)!;
  final label = normalize(m.group(3)!);
  return switch (open) {
    '((' => (MindmapShape.circle, label),
    '))' => (MindmapShape.bang, label),
    '(-' => (MindmapShape.cloud, label),
    '(' => (MindmapShape.rounded, label),
    '[' => (MindmapShape.rect, label),
    '{{' => (MindmapShape.hexagon, label),
    _ => (MindmapShape.plain, label),
  };
}

/// Section colors per first-level branch, from upstream theme git/section
/// palette feel.
const _branchColors = <Color>[
  Color(0xff9370db),
  Color(0xff2e8bc0),
  Color(0xffe8a33d),
  Color(0xff5fb6a9),
  Color(0xffbf6790),
  Color(0xff7fbf67),
  Color(0xffb56576),
  Color(0xff6788bf),
];

class _PlacedMind {
  _PlacedMind(this.node, this.size);

  final MindmapNode node;
  final Size size;
  Point center = Point.zero;
  double subtreeExtent = 0;
  Color color = const Color(0xff9370db);
}

RenderScene layoutMindmap(
  Mindmap map, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const levelGap = 90.0;
  const siblingGap = 14.0;
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final nodes = <SceneNode>[];
  final placed = <MindmapNode, _PlacedMind>{};

  _PlacedMind measure(MindmapNode n) {
    final style = n.depth == 0 ? baseStyle.copyWith(fontWeight: 700) : baseStyle;
    final labelSize = measurer.measure(n.label, style, maxWidth: 170);
    final w = n.shape == MindmapShape.circle
        ? math.max(labelSize.width, labelSize.height) + 30
        : labelSize.width + 24;
    final h = n.shape == MindmapShape.circle
        ? math.max(labelSize.width, labelSize.height) + 30
        : labelSize.height + 16;
    final p = _PlacedMind(n, Size(w, h));
    placed[n] = p;
    var extent = 0.0;
    for (final c in n.children) {
      extent += measure(c).subtreeExtent + siblingGap;
    }
    extent = math.max(extent - siblingGap, h);
    p.subtreeExtent = extent;
    return p;
  }

  measure(map.root);

  // Split first-level branches: alternate right/left, balancing extents.
  final right = <MindmapNode>[];
  final left = <MindmapNode>[];
  var rightExtent = 0.0, leftExtent = 0.0;
  for (final c in map.root.children) {
    if (rightExtent <= leftExtent) {
      right.add(c);
      rightExtent += placed[c]!.subtreeExtent + siblingGap;
    } else {
      left.add(c);
      leftExtent += placed[c]!.subtreeExtent + siblingGap;
    }
  }

  void position(MindmapNode n, int dir, double x, double top) {
    final p = placed[n]!;
    p.center = Point(x + dir * p.size.width / 2, top + p.subtreeExtent / 2);
    var childTop = top;
    for (final c in n.children) {
      final cp = placed[c]!;
      position(c, dir, x + dir * (p.size.width + levelGap - 30), childTop);
      childTop += cp.subtreeExtent + siblingGap;
    }
  }

  final rootP = placed[map.root]!;
  rootP.center = Point.zero;
  var top = -rightExtent / 2;
  for (final c in right) {
    position(c, 1, rootP.size.width / 2 + levelGap - 30, top);
    top += placed[c]!.subtreeExtent + siblingGap;
  }
  top = -leftExtent / 2;
  for (final c in left) {
    position(c, -1, -(rootP.size.width / 2 + levelGap - 30), top);
    top += placed[c]!.subtreeExtent + siblingGap;
  }

  // Branch colors: each first-level child tints its subtree.
  void tint(MindmapNode n, Color color) {
    placed[n]!.color = color;
    for (final c in n.children) {
      tint(c, color);
    }
  }

  for (var i = 0; i < map.root.children.length; i++) {
    tint(map.root.children[i], _branchColors[i % _branchColors.length]);
  }

  // Edges: cubic from parent edge to child edge.
  void edges(MindmapNode n) {
    final p = placed[n]!;
    for (final c in n.children) {
      final cp = placed[c]!;
      final dir = cp.center.x >= p.center.x ? 1 : -1;
      final start = Point(p.center.x + dir * p.size.width / 2, p.center.y);
      final end = Point(cp.center.x - dir * cp.size.width / 2, cp.center.y);
      final mid = (end.x - start.x).abs() / 2;
      nodes.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(start),
          CubicTo(Point(start.x + dir * mid, start.y),
              Point(end.x - dir * mid, end.y), end),
        ]),
        stroke: Stroke(color: cp.color.withOpacity(0.7), width: 2.5),
      ));
      edges(c);
    }
  }

  edges(map.root);

  // Nodes on top.
  void draw(MindmapNode n) {
    final p = placed[n]!;
    final style =
        n.depth == 0 ? baseStyle.copyWith(fontWeight: 700) : baseStyle;
    final labelSize = measurer.measure(n.label, style, maxWidth: 170);
    final rect = Rect.fromCenter(p.center, p.size.width, p.size.height);
    final fill = n.depth == 0
        ? theme.mainBkg
        : Color.fromARGB(40, p.color.red, p.color.green, p.color.blue);
    final children = <SceneNode>[];
    switch (n.shape) {
      case MindmapShape.circle:
        children.add(SceneShape(
          geometry: CircleGeometry(p.center, p.size.width / 2),
          fill: Fill(fill),
          stroke: Stroke(color: p.color, width: 2),
        ));
      case MindmapShape.rect:
        children.add(SceneShape(
          geometry: RectGeometry(rect),
          fill: Fill(fill),
          stroke: Stroke(color: p.color, width: 2),
        ));
      case MindmapShape.hexagon:
        final m = rect.height / 3;
        children.add(SceneShape(
          geometry: PolygonGeometry([
            Point(rect.left + m, rect.top),
            Point(rect.right - m, rect.top),
            Point(rect.right, rect.center.y),
            Point(rect.right - m, rect.bottom),
            Point(rect.left + m, rect.bottom),
            Point(rect.left, rect.center.y),
          ]),
          fill: Fill(fill),
          stroke: Stroke(color: p.color, width: 2),
        ));
      case MindmapShape.bang || MindmapShape.cloud:
        // Approximated as a stadium until dedicated geometry lands.
        children.add(SceneShape(
          geometry:
              RectGeometry(rect, rx: rect.height / 2, ry: rect.height / 2),
          fill: Fill(fill),
          stroke: Stroke(color: p.color, width: 2),
        ));
      case MindmapShape.rounded:
        children.add(SceneShape(
          geometry: RectGeometry(rect, rx: 10, ry: 10),
          fill: Fill(fill),
          stroke: Stroke(color: p.color, width: 2),
        ));
      case MindmapShape.plain:
        // Underline-style: just the label with a baseline stroke.
        children.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(rect.left, rect.bottom)),
            LineTo(Point(rect.right, rect.bottom)),
          ]),
          stroke: Stroke(color: p.color, width: 2),
        ));
    }
    children.add(SceneText(
      text: n.label,
      bounds:
          Rect.fromCenter(p.center, labelSize.width, labelSize.height),
      style: style,
      color: theme.textColor,
    ));
    nodes.add(SceneGroup(
        id: 'mind_${n.label}', semanticLabel: n.label, children: children));
    n.children.forEach(draw);
  }

  draw(map.root);

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  const pad = 16.0;
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

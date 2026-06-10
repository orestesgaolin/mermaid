/// Mindmap: model, parser and layout — one file.
///
/// Reference: upstream mindmap langium grammar + mindmapRenderer. Upstream
/// lays out with cytoscape cose-bilkent; this port uses a deterministic
/// radial tree (angular sectors proportional to leaf count), which settles
/// to roughly the same organic look without a force simulation.
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

/// Section colors per first-level branch (mermaid default mindmap look:
/// saturated pastel fills).
const _branchColors = <Color>[
  Color(0xfffcfc62),
  Color(0xffcbe65a),
  Color(0xffb87df2),
  Color(0xff4fc3f7),
  Color(0xffff8a65),
  Color(0xfff06292),
  Color(0xff9fa8da),
  Color(0xff80cbc4),
];

/// Root node fill (upstream renders a large filled circle).
const _rootFill = Color(0xff1f1fd1);

/// Perceived luminance, for choosing readable text on a fill.
double _luminance(Color c) =>
    (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) / 255;

Color _lighten(Color c, double amount) => Color.fromARGB(
      255,
      (c.red + (255 - c.red) * amount).round(),
      (c.green + (255 - c.green) * amount).round(),
      (c.blue + (255 - c.blue) * amount).round(),
    );

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
  const siblingGap = 14.0;
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final nodes = <SceneNode>[];
  final placed = <MindmapNode, _PlacedMind>{};

  _PlacedMind measure(MindmapNode n) {
    final style = n.depth == 0 ? baseStyle.copyWith(fontWeight: 700) : baseStyle;
    final labelSize = measurer.measure(n.label, style, maxWidth: 170);
    final circlePad = n.depth == 0 ? 52.0 : 30.0;
    final w = n.shape == MindmapShape.circle
        ? math.max(labelSize.width, labelSize.height) + circlePad
        : labelSize.width + 26;
    final h = n.shape == MindmapShape.circle
        ? math.max(labelSize.width, labelSize.height) + circlePad
        : labelSize.height + 18;
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

  // Radial layout, like upstream's settled force simulation: each branch
  // gets an angular sector proportional to its leaf count, nodes sit at a
  // radius that grows with depth (stretched horizontally because labels
  // are wide).
  int leaves(MindmapNode n) => n.children.isEmpty
      ? 1
      : n.children.fold(0, (a, c) => a + leaves(c));

  final rootP = placed[map.root]!;
  rootP.center = Point.zero;

  void placeRadial(MindmapNode n, double a0, double a1, int depth) {
    final p = placed[n]!;
    if (depth > 0) {
      final angle = (a0 + a1) / 2;
      final r = 92.0 * depth + 15.0 * (depth - 1);
      // Wide labels need extra horizontal reach.
      p.center = Point(
        math.cos(angle) * (r * 1.3 + p.size.width / 2),
        math.sin(angle) * r,
      );
    }
    final total = leaves(n);
    var a = a0;
    for (final c in n.children) {
      final span = (a1 - a0) * leaves(c) / total;
      placeRadial(c, a, a + span, depth + 1);
      a += span;
    }
  }

  // Start at the upper right and walk clockwise, mirroring the typical
  // upstream result.
  placeRadial(map.root, -math.pi / 3, 2 * math.pi - math.pi / 3, 0);

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
      // Center-to-center; nodes paint on top, hiding the covered ends.
      final width = math.max(3.0, 11.0 - cp.node.depth * 2.8);
      nodes.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(p.center),
          CubicTo(
            Point(p.center.x + (cp.center.x - p.center.x) * 0.55,
                p.center.y + (cp.center.y - p.center.y) * 0.1),
            Point(p.center.x + (cp.center.x - p.center.x) * 0.9,
                p.center.y + (cp.center.y - p.center.y) * 0.85),
            cp.center,
          ),
        ]),
        stroke: Stroke(color: cp.color, width: width),
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
    // Filled nodes like upstream: the root is a dark filled circle with
    // inverted text; branches fill with the section color, lightening with
    // depth.
    final isRoot = n.depth == 0;
    final fill = isRoot
        ? _rootFill
        : _lighten(p.color, ((n.depth - 1) * 0.18).clamp(0.0, 0.6));
    final children = <SceneNode>[];
    // Upstream nodes carry a drop shadow rendered as a soft strip below.
    if (!isRoot) {
      children.add(SceneShape(
        geometry: RectGeometry(
            Rect.fromCenter(Point(p.center.x, p.center.y + 5),
                p.size.width, p.size.height),
            rx: 8,
            ry: 8),
        fill: const Fill(Color(0x3d6c6c9e)),
      ));
    }
    switch (n.shape) {
      case MindmapShape.circle:
        children.add(SceneShape(
          geometry: CircleGeometry(p.center, p.size.width / 2),
          fill: Fill(fill),
        ));
      case MindmapShape.rect:
        children.add(SceneShape(
          geometry: RectGeometry(rect),
          fill: Fill(fill),
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
        ));
      case MindmapShape.bang || MindmapShape.cloud:
        // Approximated as a stadium until dedicated geometry lands.
        children.add(SceneShape(
          geometry:
              RectGeometry(rect, rx: rect.height / 2, ry: rect.height / 2),
          fill: Fill(fill),
        ));
      case MindmapShape.rounded || MindmapShape.plain:
        children.add(SceneShape(
          geometry: RectGeometry(rect, rx: 8, ry: 8),
          fill: Fill(fill),
        ));
    }
    children.add(SceneText(
      text: n.label,
      bounds:
          Rect.fromCenter(p.center, labelSize.width, labelSize.height),
      style: style,
      // Text contrast follows the section base color, like upstream: the
      // whole purple branch reads white even on lightened leaves.
      color: _luminance(isRoot ? fill : p.color) < 0.66
          ? const Color(0xffffffff)
          : const Color(0xff1f1f1f),
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

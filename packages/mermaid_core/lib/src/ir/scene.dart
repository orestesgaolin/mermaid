/// The render scene IR: a backend-agnostic, fully resolved description of a
/// laid-out diagram. Coordinates are absolute in scene space (y down), colors
/// and fonts are resolved — backends (Flutter CustomPainter, SVG writer) only
/// translate primitives, they make no layout or styling decisions.
library;

import '../color.dart';
import '../geometry.dart';
import '../text/text_style.dart';

/// Sentinel [SceneGroup.id] marking a laid-out math expression. The hand-drawn
/// (rough) pass leaves these groups untouched, so math stays crisp instead of
/// being sketched into illegibility.
const String mathSceneGroupId = '__mermaid_math__';

class RenderScene {
  const RenderScene({required this.size, required this.nodes, this.background});

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
  const SceneGroup({
    required this.children,
    this.id,
    this.role = SceneGroupRole.node,
    this.semanticLabel,
    this.link,
    this.tooltip,
    this.edge,
  });

  /// Stable identifier (e.g. flowchart node id) for hit-testing/interactivity.
  final String? id;

  /// Structural role used by bounds lookup and interaction layers.
  ///
  /// The default preserves the historic meaning of an id-carrying group as a
  /// diagram node. Renderers must explicitly tag non-node groups.
  final SceneGroupRole role;

  /// Accessibility label for this group, if any.
  final String? semanticLabel;

  /// Click target URL (from flowchart `click`/`href`); makes the group a link.
  final String? link;

  /// Hover/tap tooltip text.
  final String? tooltip;

  /// Typed flow edge identity used by interaction layers.
  final SceneEdgeMetadata? edge;
  final List<SceneNode> children;
}

/// Identity of the flow link a [SceneGroup] paints.
///
/// Attached to edge groups (and their labels) so interaction layers can map a
/// hit back to the parsed link without re-parsing the group id.
class SceneEdgeMetadata {
  const SceneEdgeMetadata({
    required this.fromId,
    required this.toId,
    required this.linkIndex,
  });

  /// Stable id of the node the link starts at.
  final String fromId;

  /// Stable id of the node the link ends at.
  final String toId;

  /// Zero-based position of the link in source order, matching the index used
  /// by `linkStyle` and by paint-only link overrides.
  final int linkIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneEdgeMetadata &&
          other.fromId == fromId &&
          other.toId == toId &&
          other.linkIndex == linkIndex;

  @override
  int get hashCode => Object.hash(fromId, toId, linkIndex);

  @override
  String toString() => 'SceneEdgeMetadata($fromId -> $toId, link $linkIndex)';
}

/// What a [SceneGroup] represents structurally.
enum SceneGroupRole {
  /// A diagram node. Only these groups are reported by
  /// [RenderScene.nodeBounds] and are hit-tested as nodes.
  node,

  /// A container drawn around other groups (flowchart subgraph, class
  /// namespace, C4 boundary, architecture group).
  cluster,

  /// A routed connection between two nodes; carries [SceneGroup.edge].
  edge,

  /// The label block belonging to an edge; carries [SceneGroup.edge].
  edgeLabel,

  /// Decoration that is not part of the diagram graph (titles, legends,
  /// axes, section headers).
  annotation,

  /// A grouping used only to keep the scene tree tidy; it has no meaning for
  /// interaction and no stable identity.
  internal,
}

class SceneShape extends SceneNode {
  const SceneShape({
    required this.geometry,
    this.fill,
    this.stroke,
    this.blendMode = SceneBlendMode.normal,
    this.paintRole = ScenePaintRole.none,
  });

  final ShapeGeometry geometry;
  final Fill? fill;
  final Stroke? stroke;

  /// How this shape composites against what is already painted. Backends that
  /// cannot blend fall back to [SceneBlendMode.normal].
  final SceneBlendMode blendMode;

  /// What this shape paints in its diagram, retained so paint-only passes
  /// (restyling, hand-drawn conversion) can find it again. See
  /// [ScenePaintRole].
  final ScenePaintRole paintRole;

  /// A copy of this shape with the given fields replaced.
  ///
  /// A null argument keeps the current value, so this cannot clear [fill] or
  /// [stroke]; construct a new [SceneShape] for that. Prefer this over
  /// rebuilding the shape by hand in scene-to-scene transforms — it carries
  /// forward every field this class gains later.
  SceneShape copyWith({
    ShapeGeometry? geometry,
    Fill? fill,
    Stroke? stroke,
    SceneBlendMode? blendMode,
    ScenePaintRole? paintRole,
  }) => SceneShape(
    geometry: geometry ?? this.geometry,
    fill: fill ?? this.fill,
    stroke: stroke ?? this.stroke,
    blendMode: blendMode ?? this.blendMode,
    paintRole: paintRole ?? this.paintRole,
  );
}

/// How a [SceneShape] composites with the pixels beneath it.
enum SceneBlendMode {
  /// Source-over: the shape replaces what is beneath it.
  normal,

  /// Multiply: overlapping bands darken instead of hiding each other. Used by
  /// sankey link ribbons, matching upstream's `mix-blend-mode: multiply`.
  multiply,
}

class SceneText extends SceneNode {
  const SceneText({
    required this.text,
    required this.bounds,
    required this.style,
    required this.color,
    this.align = TextAlignH.center,
    this.rotation = 0,
    this.underline = false,
    this.paintRole = ScenePaintRole.none,
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

  /// Underline the text (e.g. static class members in UML).
  final bool underline;

  /// What this text paints in its diagram, retained so paint-only passes can
  /// find it again. See [ScenePaintRole].
  final ScenePaintRole paintRole;

  /// A copy of this text with the given fields replaced.
  ///
  /// A null argument keeps the current value. Prefer this over rebuilding the
  /// text by hand in scene-to-scene transforms — it carries forward every
  /// field this class gains later.
  SceneText copyWith({
    String? text,
    Rect? bounds,
    TextStyleSpec? style,
    Color? color,
    TextAlignH? align,
    double? rotation,
    bool? underline,
    ScenePaintRole? paintRole,
  }) => SceneText(
    text: text ?? this.text,
    bounds: bounds ?? this.bounds,
    style: style ?? this.style,
    color: color ?? this.color,
    align: align ?? this.align,
    rotation: rotation ?? this.rotation,
    underline: underline ?? this.underline,
    paintRole: paintRole ?? this.paintRole,
  );
}

/// Logical paint target retained after flowchart layout, so a later pass can
/// restyle a primitive without knowing how it was produced.
///
/// The `…Fill` / `…Stroke` variants are what the hand-drawn pass emits when it
/// replaces one filled-and-stroked primitive with separate sketch passes.
enum ScenePaintRole {
  /// Not a restylable flowchart primitive.
  none,

  /// The body of a flowchart node, still carrying both its fill and stroke.
  nodeBody,

  /// The hachure pass that stands in for a node body's fill.
  nodeFill,

  /// The sketch pass that stands in for a node body's outline.
  nodeStroke,

  /// A node's label: its text, its rich-text runs, its math glyphs, or its
  /// `@{ icon: }` glyph paths.
  nodeLabel,

  /// The hachure pass that stands in for a filled node-label glyph.
  nodeLabelFill,

  /// The sketch pass that stands in for a node-label glyph's outline.
  nodeLabelStroke,

  /// The routed centerline of an edge.
  edgeStroke,

  /// An edge arrowhead or endpoint decoration. Arrowheads stay crisp in
  /// hand-drawn mode, so they keep this role there too.
  edgeMarker,
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
  const Stroke({required this.color, this.width = 1, this.dash, this.gradient});

  /// Solid color; also the fallback if a backend ignores [gradient].
  final Color color;
  final double width;

  /// Optional linear gradient (in absolute scene coordinates). When set,
  /// backends stroke with the gradient instead of [color]. Translating the
  /// shape must translate these coordinates too — see `translateSceneNode`.
  final SceneGradient? gradient;

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

/// Immutable model for a parsed flowchart, mirroring the facts captured by
/// upstream flowDb (nodes, edges, subgraphs, class definitions) without the
/// mutable-singleton machinery.
library;

class FlowGraph {
  const FlowGraph({
    required this.direction,
    required this.nodes,
    required this.edges,
    this.subgraphs = const [],
    this.classDefs = const {},
    this.title,
  });

  final FlowDirection direction;

  /// Insertion-ordered by first mention, keyed by node id.
  final Map<String, FlowNode> nodes;
  final List<FlowEdge> edges;

  /// Outermost-first; nested subgraphs reference their parent by index.
  final List<FlowSubgraph> subgraphs;

  /// classDef name -> CSS-ish property map (e.g. fill, stroke, stroke-width, color).
  final Map<String, Map<String, String>> classDefs;

  /// From YAML frontmatter `title:` if present.
  final String? title;
}

enum FlowDirection { tb, bt, lr, rl }

enum FlowNodeShape {
  /// `[text]`
  rect,

  /// `(text)`
  rounded,

  /// `([text])`
  stadium,

  /// `[[text]]`
  subroutine,

  /// `[(text)]`
  cylinder,

  /// `((text))`
  circle,

  /// `(((text)))`
  doubleCircle,

  /// `>text]`
  asymmetric,

  /// `{text}`
  diamond,

  /// `{{text}}`
  hexagon,

  /// `[/text/]`
  leanRight,

  /// `[\text\]`
  leanLeft,

  /// `[/text\]`
  trapezoid,

  /// `[\text/]`
  invTrapezoid,

  /// `(-text-)`
  ellipse,

  /// Default when a node is referenced without any shape brackets.
  plain,
}

class FlowNode {
  const FlowNode({
    required this.id,
    required this.label,
    this.shape = FlowNodeShape.plain,
    this.classes = const [],
    this.styles = const {},
    this.link,
    this.tooltip,
    this.icon,
  });

  final String id;

  /// Display label. `<br/>` in source is normalized to `\n`. Defaults to [id]
  /// when the node never declared a label.
  final String label;
  final FlowNodeShape shape;

  /// Iconify reference `"prefix:name"` from `@{ icon: ... }`, if any.
  final String? icon;

  /// Class names assigned via `class a,b name` or `:::name`.
  final List<String> classes;

  /// Inline styles from `style id k:v,k:v`.
  final Map<String, String> styles;

  /// From `click id "url"` / `click id href ...`.
  final String? link;
  final String? tooltip;

  FlowNode copyWith({
    String? label,
    FlowNodeShape? shape,
    List<String>? classes,
    Map<String, String>? styles,
    String? link,
    String? tooltip,
    String? icon,
  }) =>
      FlowNode(
        id: id,
        label: label ?? this.label,
        shape: shape ?? this.shape,
        classes: classes ?? this.classes,
        styles: styles ?? this.styles,
        link: link ?? this.link,
        tooltip: tooltip ?? this.tooltip,
        icon: icon ?? this.icon,
      );
}

enum EdgeStroke { normal, dotted, thick, invisible }

enum ArrowHead { none, point, circle, cross }

class FlowEdge {
  const FlowEdge({
    required this.from,
    required this.to,
    this.label,
    this.stroke = EdgeStroke.normal,
    this.headFrom = ArrowHead.none,
    this.headTo = ArrowHead.point,
    this.minLen = 1,
    this.styles = const {},
  });

  final String from;
  final String to;
  final String? label;
  final EdgeStroke stroke;

  /// Arrow at the source end (for `<-->`, `x--x`, ...).
  final ArrowHead headFrom;

  /// Arrow at the target end. [ArrowHead.none] for open links (`---`).
  final ArrowHead headTo;

  /// Rank separation: extra dashes in the source lengthen the edge
  /// (`-->` is 1, `--->` is 2, ...).
  final int minLen;

  /// Inline styles from `linkStyle`.
  final Map<String, String> styles;

  FlowEdge copyWith({Map<String, String>? styles}) => FlowEdge(
        from: from,
        to: to,
        label: label,
        stroke: stroke,
        headFrom: headFrom,
        headTo: headTo,
        minLen: minLen,
        styles: styles ?? this.styles,
      );
}

class FlowSubgraph {
  const FlowSubgraph({
    required this.id,
    required this.title,
    required this.nodeIds,
    this.direction,
    this.parentIndex,
  });

  final String id;
  final String title;

  /// Ids of member nodes. Nested subgraphs appear in [parentIndex] links
  /// rather than here.
  final List<String> nodeIds;

  /// Local direction override (`direction LR` inside the subgraph).
  final FlowDirection? direction;

  /// Index into [FlowGraph.subgraphs] of the enclosing subgraph, if nested.
  final int? parentIndex;
}

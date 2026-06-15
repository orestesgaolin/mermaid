/// Layout configuration, mirroring the option set the Eclipse Layout Kernel
/// (and elkjs) expose for the `layered` algorithm. Names map onto the elkjs
/// option keys (e.g. [direction] → `elk.direction`, [fixedAlignment] →
/// `elk.layered.nodePlacement.bk.fixedAlignment`).
library;

/// Primary flow direction of the layout.
enum ElkDirection {
  down,
  up,
  right,
  left;

  /// Whether the layout flows along the vertical axis (DOWN/UP).
  bool get isVertical => this == ElkDirection.down || this == ElkDirection.up;
}

/// Strategy used to assign in-layer coordinates. ELK's default is
/// Brandes–Köpf; the others are accepted for API parity but currently fall
/// back to Brandes–Köpf placement.
enum ElkNodePlacement { brandesKoepf, networkSimplex, linearSegments, simple }

/// Fixed alignment for the Brandes–Köpf placement. `none` balances across all
/// four alignments (ELK's default and the most stable choice).
enum ElkFixedAlignment { none, leftUp, leftDown, rightUp, rightDown, balanced }

/// How children of a compound node participate in the parent's layout.
enum ElkHierarchyHandling { inherit, includeChildren, separateChildren }

/// Whether/how the input (model) order of nodes constrains crossing
/// minimization. `none` lets the barycenter heuristic order freely.
enum ElkConsiderModelOrder { none, nodesAndEdges, preferEdges, preferNodes }

/// Strategy used to break cycles before layering.
enum ElkCycleBreaking { greedy, depthFirst, interactive, modelOrder, greedyModelOrder }

/// Immutable layout options. Defaults match ELK/elkjs for the `layered`
/// algorithm as configured by mermaid (`spacing.baseValue` 40, Brandes–Köpf
/// placement, `fixedAlignment` NONE).
class ElkLayoutOptions {
  const ElkLayoutOptions({
    this.algorithm = 'layered',
    this.direction = ElkDirection.down,
    this.spacingBaseValue = 40,
    this.nodePlacement = ElkNodePlacement.brandesKoepf,
    this.fixedAlignment = ElkFixedAlignment.none,
    this.hierarchyHandling = ElkHierarchyHandling.includeChildren,
    this.mergeEdges = false,
    this.considerModelOrder = ElkConsiderModelOrder.none,
    this.forceNodeModelOrder = false,
    this.cycleBreaking = ElkCycleBreaking.greedy,
    this.spacingNodeNode,
    this.spacingEdgeNode,
    this.spacingNodeNodeBetweenLayers,
  });

  final String algorithm;
  final ElkDirection direction;

  /// Base spacing unit; ELK derives the concrete node/edge/layer spacings from
  /// it when those are not set explicitly. See [resolvedNodeNode] etc.
  final double spacingBaseValue;

  final ElkNodePlacement nodePlacement;
  final ElkFixedAlignment fixedAlignment;
  final ElkHierarchyHandling hierarchyHandling;
  final bool mergeEdges;
  final ElkConsiderModelOrder considerModelOrder;
  final bool forceNodeModelOrder;
  final ElkCycleBreaking cycleBreaking;

  /// Explicit spacing overrides; when null, derived from [spacingBaseValue].
  final double? spacingNodeNode;
  final double? spacingEdgeNode;
  final double? spacingNodeNodeBetweenLayers;

  /// Spacing between adjacent nodes in the same layer.
  double get resolvedNodeNode => spacingNodeNode ?? spacingBaseValue;

  /// Spacing between a node and an edge routed past it.
  double get resolvedEdgeNode => spacingEdgeNode ?? spacingBaseValue * 0.5;

  /// Spacing between adjacent layers (ELK scales the base value up between
  /// layers to leave room for orthogonal edge channels).
  double get resolvedNodeNodeBetweenLayers =>
      spacingNodeNodeBetweenLayers ?? spacingBaseValue;

  ElkLayoutOptions copyWith({
    String? algorithm,
    ElkDirection? direction,
    double? spacingBaseValue,
    ElkNodePlacement? nodePlacement,
    ElkFixedAlignment? fixedAlignment,
    ElkHierarchyHandling? hierarchyHandling,
    bool? mergeEdges,
    ElkConsiderModelOrder? considerModelOrder,
    bool? forceNodeModelOrder,
    ElkCycleBreaking? cycleBreaking,
    double? spacingNodeNode,
    double? spacingEdgeNode,
    double? spacingNodeNodeBetweenLayers,
  }) {
    return ElkLayoutOptions(
      algorithm: algorithm ?? this.algorithm,
      direction: direction ?? this.direction,
      spacingBaseValue: spacingBaseValue ?? this.spacingBaseValue,
      nodePlacement: nodePlacement ?? this.nodePlacement,
      fixedAlignment: fixedAlignment ?? this.fixedAlignment,
      hierarchyHandling: hierarchyHandling ?? this.hierarchyHandling,
      mergeEdges: mergeEdges ?? this.mergeEdges,
      considerModelOrder: considerModelOrder ?? this.considerModelOrder,
      forceNodeModelOrder: forceNodeModelOrder ?? this.forceNodeModelOrder,
      cycleBreaking: cycleBreaking ?? this.cycleBreaking,
      spacingNodeNode: spacingNodeNode ?? this.spacingNodeNode,
      spacingEdgeNode: spacingEdgeNode ?? this.spacingEdgeNode,
      spacingNodeNodeBetweenLayers:
          spacingNodeNodeBetweenLayers ?? this.spacingNodeNodeBetweenLayers,
    );
  }
}

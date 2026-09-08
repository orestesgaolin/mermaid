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
enum ElkCycleBreaking {
  greedy,
  depthFirst,
  interactive,
  modelOrder,
  greedyModelOrder,
}

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
    this.spacingLabelLabel = 0,
    this.spacingEdgeLabel = 2,
    this.spacingNodeLabel = 5,
    this.spacingPortLabel = 1,
    this.spacingPortsSurroundingTop = 0,
    this.spacingPortsSurroundingBottom = 0,
    this.spacingNodeNode,
    this.spacingEdgeNode,
    this.spacingNodeNodeBetweenLayers,
    this.spacingEdgeEdge = 10,
    this.improveStraightness = false,
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
  final double spacingLabelLabel;
  final double spacingEdgeLabel;
  final double spacingNodeLabel;
  final double spacingPortLabel;
  final double spacingPortsSurroundingTop;
  final double spacingPortsSurroundingBottom;
  final double? spacingNodeNode;
  final double? spacingEdgeNode;
  final double? spacingNodeNodeBetweenLayers;
  final double spacingEdgeEdge;

  /// Enables ELK's BK threshold strategy, which trades compactness for more
  /// straight edge segments.
  final bool improveStraightness;

  /// Spacing between adjacent nodes in the same layer.
  double get resolvedNodeNode => spacingNodeNode ?? spacingBaseValue;

  /// Spacing between a node and an edge routed past it.
  double get resolvedEdgeNode => spacingEdgeNode ?? spacingBaseValue * 0.5;

  /// Spacing between adjacent layers (ELK scales the base value up between
  /// layers to leave room for orthogonal edge channels).
  double get resolvedNodeNodeBetweenLayers =>
      spacingNodeNodeBetweenLayers ?? spacingBaseValue;

  /// Parses an elkjs-style `layoutOptions` map (keys like `elk.direction`,
  /// `spacing.baseValue`, `elk.layered.nodePlacement.bk.fixedAlignment`).
  /// Supported keys accept full `org.eclipse.elk.`, `elk.`, and short aliases,
  /// in that precedence order. Layered spacing uses `layered.spacing.*`; the
  /// legacy `spacing.nodeNodeBetweenLayers` key is also accepted.
  /// Unknown keys are ignored; absent ones keep their defaults.
  factory ElkLayoutOptions.fromElkJson(Map<String, dynamic> m) {
    double? asNum(Object? v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    bool asBool(Object? v) => v == true || v == 'true';
    ElkDirection dir(Object? v) => switch ('$v'.toUpperCase()) {
      'UP' => ElkDirection.up,
      'LEFT' => ElkDirection.left,
      'RIGHT' => ElkDirection.right,
      _ => ElkDirection.down,
    };
    ElkFixedAlignment align(Object? v) => switch ('$v'.toUpperCase()) {
      'LEFTUP' => ElkFixedAlignment.leftUp,
      'LEFTDOWN' => ElkFixedAlignment.leftDown,
      'RIGHTUP' => ElkFixedAlignment.rightUp,
      'RIGHTDOWN' => ElkFixedAlignment.rightDown,
      'BALANCED' => ElkFixedAlignment.balanced,
      _ => ElkFixedAlignment.none,
    };
    // Full identifiers win when an input supplies more than one alias.
    Object? option(String key) =>
        m['org.eclipse.elk.$key'] ?? m['elk.$key'] ?? m[key];
    Object? layeredOption(String key) => option('layered.$key');
    return ElkLayoutOptions(
      algorithm: (option('algorithm') ?? 'layered').toString(),
      direction: dir(option('direction')),
      spacingBaseValue: asNum(option('spacing.baseValue')) ?? 40,
      fixedAlignment: align(layeredOption('nodePlacement.bk.fixedAlignment')),
      mergeEdges: asBool(layeredOption('mergeEdges')),
      cycleBreaking: switch ('${layeredOption('cycleBreaking.strategy')}'
          .toUpperCase()) {
        'DEPTH_FIRST' => ElkCycleBreaking.depthFirst,
        'INTERACTIVE' => ElkCycleBreaking.interactive,
        'MODEL_ORDER' => ElkCycleBreaking.modelOrder,
        'GREEDY_MODEL_ORDER' => ElkCycleBreaking.greedyModelOrder,
        _ => ElkCycleBreaking.greedy,
      },
      considerModelOrder:
          switch ('${layeredOption('considerModelOrder.strategy')}'
              .toUpperCase()) {
            'NODES_AND_EDGES' => ElkConsiderModelOrder.nodesAndEdges,
            'PREFER_EDGES' => ElkConsiderModelOrder.preferEdges,
            'PREFER_NODES' => ElkConsiderModelOrder.preferNodes,
            _ => ElkConsiderModelOrder.none,
          },
      forceNodeModelOrder: asBool(
        layeredOption('crossingMinimization.forceNodeModelOrder'),
      ),
      spacingLabelLabel: asNum(option('spacing.labelLabel')) ?? 0,
      spacingEdgeLabel: asNum(option('spacing.edgeLabel')) ?? 2,
      spacingNodeLabel: asNum(option('spacing.nodeLabel')) ?? 5,
      spacingPortLabel: asNum(option('spacing.portLabel')) ?? 1,
      spacingPortsSurroundingTop:
          asNum(option('spacing.portsSurrounding.top')) ?? 0,
      spacingPortsSurroundingBottom:
          asNum(option('spacing.portsSurrounding.bottom')) ?? 0,
      spacingNodeNode: asNum(option('spacing.nodeNode')),
      spacingEdgeNode: asNum(option('spacing.edgeNode')),
      spacingNodeNodeBetweenLayers: asNum(
        layeredOption('spacing.nodeNodeBetweenLayers') ??
            option('spacing.nodeNodeBetweenLayers'),
      ),
      spacingEdgeEdge: asNum(option('spacing.edgeEdge')) ?? 10,
      improveStraightness:
          '${layeredOption('nodePlacement.bk.edgeStraightening')}'
              .toUpperCase() ==
          'IMPROVE_STRAIGHTNESS',
    );
  }

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
    double? spacingLabelLabel,
    double? spacingEdgeLabel,
    double? spacingNodeLabel,
    double? spacingPortLabel,
    double? spacingPortsSurroundingTop,
    double? spacingPortsSurroundingBottom,
    double? spacingNodeNode,
    double? spacingEdgeNode,
    double? spacingNodeNodeBetweenLayers,
    double? spacingEdgeEdge,
    bool? improveStraightness,
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
      spacingLabelLabel: spacingLabelLabel ?? this.spacingLabelLabel,
      spacingEdgeLabel: spacingEdgeLabel ?? this.spacingEdgeLabel,
      spacingNodeLabel: spacingNodeLabel ?? this.spacingNodeLabel,
      spacingPortLabel: spacingPortLabel ?? this.spacingPortLabel,
      spacingPortsSurroundingTop:
          spacingPortsSurroundingTop ?? this.spacingPortsSurroundingTop,
      spacingPortsSurroundingBottom:
          spacingPortsSurroundingBottom ?? this.spacingPortsSurroundingBottom,
      spacingNodeNode: spacingNodeNode ?? this.spacingNodeNode,
      spacingEdgeNode: spacingEdgeNode ?? this.spacingEdgeNode,
      spacingNodeNodeBetweenLayers:
          spacingNodeNodeBetweenLayers ?? this.spacingNodeNodeBetweenLayers,
      spacingEdgeEdge: spacingEdgeEdge ?? this.spacingEdgeEdge,
      improveStraightness: improveStraightness ?? this.improveStraightness,
    );
  }
}

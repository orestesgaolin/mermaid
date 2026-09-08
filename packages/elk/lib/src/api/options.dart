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

/// Insets around the root layout, in final output coordinates.
class ElkPadding {
  const ElkPadding({
    this.top = 0,
    this.left = 0,
    this.bottom = 0,
    this.right = 0,
  }) : assert(top >= 0 && top < double.infinity),
       assert(left >= 0 && left < double.infinity),
       assert(bottom >= 0 && bottom < double.infinity),
       assert(right >= 0 && right < double.infinity);

  final double top, left, bottom, right;

  static ElkPadding _fromJson(Object? value) {
    final fields = <String, double>{};
    if (value is String) {
      for (final match in RegExp(
        r'(top|left|bottom|right)\s*=\s*([+-]?[0-9]+(?:\.[0-9]+)?)',
      ).allMatches(value)) {
        final number = double.tryParse(match[2]!);
        if (number != null && number.isFinite && number >= 0)
          fields[match[1]!] = number;
      }
    }
    return ElkPadding(
      top: fields['top'] ?? 0,
      left: fields['left'] ?? 0,
      bottom: fields['bottom'] ?? 0,
      right: fields['right'] ?? 0,
    );
  }
}

/// Immutable layout options. Defaults match ELK/elkjs for the `layered`
/// algorithm as configured by mermaid (`spacing.baseValue` 40, Brandes–Köpf
/// placement, `fixedAlignment` NONE).
class ElkLayoutOptions {
  const ElkLayoutOptions({
    this.algorithm = 'layered',
    this.padding = const ElkPadding(),
    ElkDirection? direction,
    this.spacingBaseValue = 40,
    this.nodePlacement = ElkNodePlacement.brandesKoepf,
    this.fixedAlignment = ElkFixedAlignment.none,
    ElkHierarchyHandling? hierarchyHandling,
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
    this.spacingNodeSelfLoop,
    this.spacingNodeNode,
    this.spacingEdgeNode,
    this.spacingNodeNodeBetweenLayers,
    this.spacingEdgeEdge = 10,
    this.improveStraightness = false,
  }) : directionOverride = direction,
       hierarchyHandlingOverride = hierarchyHandling;

  final String algorithm;

  /// Explicit root padding. Unspecified padding preserves tight output bounds.
  final ElkPadding padding;

  /// Explicit direction supplied for this graph or compound node.
  ///
  /// A null value lets a nested graph inherit its enclosing direction. At the
  /// root, absence resolves to [ElkDirection.down] to preserve the package
  /// default.
  final ElkDirection? directionOverride;

  ElkDirection get direction => directionOverride ?? ElkDirection.down;

  /// Base spacing unit; ELK derives the concrete node/edge/layer spacings from
  /// it when those are not set explicitly. See [resolvedNodeNode] etc.
  final double spacingBaseValue;

  final ElkNodePlacement nodePlacement;
  final ElkFixedAlignment fixedAlignment;

  /// Explicit hierarchy mode supplied for this graph or compound node.
  ///
  /// A null value lets a nested graph inherit its enclosing mode. At the root,
  /// absence resolves to [ElkHierarchyHandling.includeChildren] to preserve the
  /// package default.
  final ElkHierarchyHandling? hierarchyHandlingOverride;

  ElkHierarchyHandling get hierarchyHandling =>
      hierarchyHandlingOverride ?? ElkHierarchyHandling.includeChildren;
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
  final double? spacingNodeSelfLoop;
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

  /// Spacing between a node and its self loops. ELK defaults this to 10 even
  /// when general edge-to-node spacing is derived from a larger base value.
  double get resolvedNodeSelfLoop =>
      spacingNodeSelfLoop ?? spacingEdgeNode ?? 10;

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
    final directionValue = option('direction');
    final hierarchyValue = option('hierarchyHandling');
    final surrounding = option('spacing.portsSurrounding');
    double? surroundingSide(String side) {
      if (surrounding is Map) return asNum(surrounding[side]);
      if (surrounding is String) {
        final match = RegExp(
          '$side\\s*=\\s*([+-]?[0-9]+(?:\\.[0-9]+)?)',
        ).firstMatch(surrounding);
        return asNum(match?[1]);
      }
      return null;
    }

    return ElkLayoutOptions(
      algorithm: (option('algorithm') ?? 'layered').toString(),
      padding: ElkPadding._fromJson(option('padding')),
      direction: directionValue == null ? null : dir(directionValue),
      spacingBaseValue: asNum(option('spacing.baseValue')) ?? 40,
      fixedAlignment: align(layeredOption('nodePlacement.bk.fixedAlignment')),
      hierarchyHandling: hierarchyValue == null
          ? null
          : switch ('$hierarchyValue'.toUpperCase()) {
              'INHERIT' => ElkHierarchyHandling.inherit,
              'SEPARATE_CHILDREN' => ElkHierarchyHandling.separateChildren,
              _ => ElkHierarchyHandling.includeChildren,
            },
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
      spacingNodeLabel:
          asNum(option('spacing.labelNode') ?? option('spacing.nodeLabel')) ??
          5,
      spacingPortLabel:
          asNum(
            option('spacing.labelPortHorizontal') ??
                option('spacing.labelPortVertical') ??
                option('spacing.portLabel'),
          ) ??
          1,
      spacingPortsSurroundingTop:
          surroundingSide('top') ??
          asNum(option('spacing.portsSurrounding.top')) ??
          0,
      spacingPortsSurroundingBottom:
          surroundingSide('bottom') ??
          asNum(option('spacing.portsSurrounding.bottom')) ??
          0,
      spacingNodeSelfLoop: asNum(option('spacing.nodeSelfLoop')),
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
    ElkPadding? padding,
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
    double? spacingNodeSelfLoop,
    double? spacingNodeNode,
    double? spacingEdgeNode,
    double? spacingNodeNodeBetweenLayers,
    double? spacingEdgeEdge,
    bool? improveStraightness,
  }) {
    return ElkLayoutOptions(
      algorithm: algorithm ?? this.algorithm,
      padding: padding ?? this.padding,
      direction: direction ?? directionOverride,
      spacingBaseValue: spacingBaseValue ?? this.spacingBaseValue,
      nodePlacement: nodePlacement ?? this.nodePlacement,
      fixedAlignment: fixedAlignment ?? this.fixedAlignment,
      hierarchyHandling: hierarchyHandling ?? hierarchyHandlingOverride,
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
      spacingNodeSelfLoop: spacingNodeSelfLoop ?? this.spacingNodeSelfLoop,
      spacingNodeNode: spacingNodeNode ?? this.spacingNodeNode,
      spacingEdgeNode: spacingEdgeNode ?? this.spacingEdgeNode,
      spacingNodeNodeBetweenLayers:
          spacingNodeNodeBetweenLayers ?? this.spacingNodeNodeBetweenLayers,
      spacingEdgeEdge: spacingEdgeEdge ?? this.spacingEdgeEdge,
      improveStraightness: improveStraightness ?? this.improveStraightness,
    );
  }
}

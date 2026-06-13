/// Flowchart layout: sizes nodes via the text measurer, runs dagre, routes
/// edges, and emits a fully resolved RenderScene.
///
/// Geometry conventions follow upstream mermaid:
/// - node shape sizing math is ported from
///   `rendering-util/rendering-elements/shapes/*` (question, hexagon,
///   cylinder, circle, doubleCircle, stadium, subroutine, lean/trapezoid,
///   rectLeftInvArrow),
/// - boundary clipping uses ports of `rendering-elements/intersect/*`
///   (rect, ellipse/circle, polygon, line),
/// - edge paths use d3-shape's curveBasis algorithm.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../geometry.dart';
import '../../icons/icon_registry.dart';
import '../../ir/scene.dart';
import '../../math/tex_math.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';
import '../../vendor/dagre/dart_dagre.dart' as dagre;
import 'flow_model.dart';

/// Upstream flowchart defaults (defaultConfig.ts / flowchart schema).
const double _nodePadding = 15;

/// Icon glyph square + gap to the label below it, for `@{ icon: }` nodes.
const double _iconSize = 36;
const double _iconGap = 4;
const double _diagramPadding = 8;
const double _clusterPadding = 8;
const double _wrappingWidth = 200;
const double _nodeSpacing = 50;
const double _rankSpacing = 50;
const double _doubleCircleGap = 5;
const double _subroutineFrame = 8;

RenderScene layoutFlowchart(
  FlowGraph graph, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  ensureBuiltinIconPacks();
  final baseStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: theme.fontSize,
  );
  final fragment = _layoutGraph(graph, measurer, theme, baseStyle);
  var sceneNodes = fragment.nodes;
  var bounds = fragment.bounds;

  // Diagram title above the content.
  final title = graph.title;
  if (title != null && title.isNotEmpty) {
    final titleStyle = baseStyle.copyWith(fontWeight: 700);
    final titleSize =
        measurer.measure(title, titleStyle, maxWidth: _wrappingWidth);
    final titleNode = SceneText(
      text: title,
      bounds: Rect.fromLTWH(
        bounds.center.x - titleSize.width / 2,
        bounds.top - _diagramPadding - titleSize.height,
        titleSize.width,
        titleSize.height,
      ),
      style: titleStyle,
      color: theme.titleColor,
    );
    sceneNodes = [...sceneNodes, titleNode];
    bounds = bounds.union(titleNode.bounds);
  }

  // Translate so the min corner sits at (padding, padding).
  final dx = _diagramPadding - bounds.left;
  final dy = _diagramPadding - bounds.top;
  sceneNodes = [for (final n in sceneNodes) _translateNode(n, dx, dy)];

  return RenderScene(
    size: Size(
      bounds.width + 2 * _diagramPadding,
      bounds.height + 2 * _diagramPadding,
    ),
    background: theme.background,
    nodes: sceneNodes,
  );
}

/// Laid-out content in local coordinates (not yet translated to padding).
class _Fragment {
  _Fragment(this.nodes, this.bounds);

  final List<SceneNode> nodes;
  final Rect bounds;
}

/// A subgraph whose effective direction differs from its parent's; it is laid
/// out recursively and participates in the parent layout as one big node.
class _IsolatedCluster {
  _IsolatedCluster({
    required this.subgraph,
    required this.fragment,
    required this.titleSize,
    required this.width,
    required this.height,
  });

  final FlowSubgraph subgraph;
  final _Fragment fragment;
  final Size titleSize;
  final double width;
  final double height;

  double get titleBand => titleSize.height > 0 ? titleSize.height + 4 : 0;
}

_Fragment _layoutGraph(
  FlowGraph graph,
  TextMeasurer measurer,
  MermaidTheme theme,
  TextStyleSpec baseStyle,
) {
  // --- 0. Subgraphs with their own direction become recursive fragments. ---
  // dagre has no per-cluster rankdir, so (like upstream mermaid) such a
  // subgraph is laid out separately and inserted into the parent layout as a
  // single fixed-size node.
  final sgs = graph.subgraphs;
  final effDir = List<FlowDirection>.filled(sgs.length, graph.direction);
  final isolated = List<bool>.filled(sgs.length, false);
  for (var i = 0; i < sgs.length; i++) {
    final parent = sgs[i].parentIndex;
    final parentDir = parent == null ? graph.direction : effDir[parent];
    effDir[i] = sgs[i].direction ?? parentDir;
    isolated[i] = effDir[i] != parentDir;
  }
  bool hasIsolatedAncestor(int i) {
    for (var p = sgs[i].parentIndex; p != null; p = sgs[p].parentIndex) {
      if (isolated[p]) return true;
    }
    return false;
  }

  bool isDescendantOf(int i, int root) {
    for (var p = sgs[i].parentIndex; p != null; p = sgs[p].parentIndex) {
      if (p == root) return true;
    }
    return false;
  }

  final removedSubgraphs = <int>{};
  final absorbedBy = <String, int>{}; // node id -> isolated root index
  final isolatedClusters = <int, _IsolatedCluster>{};
  for (var root = 0; root < sgs.length; root++) {
    if (!isolated[root] || hasIsolatedAncestor(root)) continue;
    final descIdx = [
      for (var i = 0; i < sgs.length; i++)
        if (isDescendantOf(i, root)) i,
    ];
    removedSubgraphs
      ..add(root)
      ..addAll(descIdx);
    final memberIds = <String>{
      ...sgs[root].nodeIds,
      for (final d in descIdx) ...sgs[d].nodeIds,
    };
    for (final id in memberIds) {
      absorbedBy[id] = root;
    }

    // Nested subgraphs move into the sub-graph with remapped parent indices
    // (descIdx is ascending, so parents are remapped before their children).
    final remap = <int, int>{};
    final subSgs = <FlowSubgraph>[];
    for (final d in descIdx) {
      remap[d] = subSgs.length;
      final orig = sgs[d];
      subSgs.add(FlowSubgraph(
        id: orig.id,
        title: orig.title,
        nodeIds: orig.nodeIds,
        direction: orig.direction,
        parentIndex: orig.parentIndex == root ? null : remap[orig.parentIndex!],
      ));
    }
    final fragment = _layoutGraph(
      FlowGraph(
        direction: effDir[root],
        nodes: {
          for (final e in graph.nodes.entries)
            if (memberIds.contains(e.key)) e.key: e.value,
        },
        edges: [
          for (final e in graph.edges)
            if (memberIds.contains(e.from) && memberIds.contains(e.to)) e,
        ],
        subgraphs: subSgs,
        classDefs: graph.classDefs,
      ),
      measurer,
      theme,
      baseStyle,
    );
    final titleSize = sgs[root].title.isEmpty
        ? Size.zero
        : measurer.measure(sgs[root].title, baseStyle,
            maxWidth: _wrappingWidth);
    final cluster = _IsolatedCluster(
      subgraph: sgs[root],
      fragment: fragment,
      titleSize: titleSize,
      width: math.max(fragment.bounds.width, titleSize.width) +
          2 * _clusterPadding,
      height: fragment.bounds.height +
          2 * _clusterPadding +
          (titleSize.height > 0 ? titleSize.height + 4 : 0),
    );
    isolatedClusters[root] = cluster;
  }

  /// Maps an edge endpoint to the node that represents it in this layout
  /// (the isolated cluster's synthetic node for absorbed members).
  String resolveId(String id) =>
      absorbedBy.containsKey(id) ? sgs[absorbedBy[id]!].id : id;

  bool isAbsorbedEdge(FlowEdge e) =>
      absorbedBy.containsKey(e.from) &&
      absorbedBy[e.from] == absorbedBy[e.to];

  final subgraphIndexById = <String, int>{
    for (var i = 0; i < sgs.length; i++) sgs[i].id: i,
  };

  // --- 1+2. Resolve styles, measure labels, compute shape boxes. -----------
  final placed = <String, _PlacedNode>{};
  final syntheticIds = <String>{};
  for (final node in graph.nodes.values) {
    if (absorbedBy.containsKey(node.id)) continue;
    // An edge endpoint naming a subgraph makes the parser auto-create a
    // phantom node with the subgraph's id; the cluster wins.
    if (subgraphIndexById.containsKey(node.id)) continue;
    final style = _resolveNodeStyle(node, graph, theme);
    // A label that is wholly `$$...$$` is laid out as math.
    final mathSrc = wholeMath(node.label);
    if (mathSrc != null) {
      final ml = layoutMath(mathSrc, baseStyle, measurer, style.textColor);
      placed[node.id] = _PlacedNode(
        node: node,
        style: style,
        labelSize: ml.size,
        math: ml,
        shape: _Shape.forNode(node.shape, ml.size),
      );
      continue;
    }
    final textSize =
        measurer.measure(node.label, baseStyle, maxWidth: _wrappingWidth);
    // An icon reserves a square area above the label; inflate the sizing box.
    final hasIcon = node.icon != null && lookupIcon(node.icon!) != null;
    final boxSize = hasIcon
        ? Size(math.max(textSize.width, _iconSize + 8),
            textSize.height + _iconSize + _iconGap)
        : textSize;
    placed[node.id] = _PlacedNode(
      node: node,
      style: style,
      labelSize: boxSize,
      textSize: hasIcon ? textSize : null,
      shape: _Shape.forNode(node.shape, boxSize),
    );
  }
  for (final cluster in isolatedClusters.values) {
    final id = cluster.subgraph.id;
    syntheticIds.add(id);
    placed[id] = _PlacedNode(
      node: FlowNode(id: id, label: cluster.subgraph.title),
      style: _resolveNodeStyle(
          FlowNode(id: id, label: cluster.subgraph.title), graph, theme),
      labelSize: Size.zero,
      shape: _RectShape(cluster.width, cluster.height),
    );
  }

  // Innermost subgraph wins when a node id is listed at several levels
  // (subgraphs are ordered outermost-first).
  final parentOf = <String, String>{};
  for (var i = 0; i < sgs.length; i++) {
    if (removedSubgraphs.contains(i)) continue;
    for (final id in sgs[i].nodeIds) {
      if (placed.containsKey(id)) parentOf[id] = sgs[i].id;
    }
  }
  // Synthetic cluster nodes nest under their nearest surviving ancestor.
  for (final entry in isolatedClusters.entries) {
    for (var p = sgs[entry.key].parentIndex; p != null; p = sgs[p].parentIndex) {
      if (!removedSubgraphs.contains(p)) {
        parentOf[entry.value.subgraph.id] = sgs[p].id;
        break;
      }
    }
  }

  // --- 3. Build the dagre graph. -------------------------------------------
  final g = dagre.DagreGraph();
  for (final p in placed.values) {
    g.addNode(dagre.DagreNode(
      p.node.id,
      width: p.shape.width,
      height: p.shape.height,
      parent: parentOf[p.node.id],
    ));
  }
  for (var i = 0; i < sgs.length; i++) {
    if (removedSubgraphs.contains(i)) continue;
    var p = sgs[i].parentIndex;
    while (p != null && removedSubgraphs.contains(p)) {
      p = sgs[p].parentIndex;
    }
    g.addNode(dagre.DagreNode(sgs[i].id, parent: p != null ? sgs[p].id : null));
  }
  // Dagre cannot target a compound cluster directly; edges to a (non-
  // isolated) subgraph id are routed to a representative member node and the
  // painted path is clipped back to the cluster rect (upstream does the same
  // in mermaid-graphlib adjustClustersAndEdges).
  String? representativeOf(int sgIndex) {
    for (final id in sgs[sgIndex].nodeIds) {
      final r = resolveId(id);
      if (placed.containsKey(r)) return r;
    }
    for (var i = 0; i < sgs.length; i++) {
      if (sgs[i].parentIndex == sgIndex) {
        final r = representativeOf(i);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// For edge endpoints that name a compound subgraph: (dagre node id,
  /// cluster id to clip against).
  (String, String?) resolveEndpoint(String rawId) {
    final id = resolveId(rawId);
    if (placed.containsKey(id)) return (id, null);
    final sgIndex = subgraphIndexById[id];
    if (sgIndex != null && !removedSubgraphs.contains(sgIndex)) {
      final rep = representativeOf(sgIndex);
      if (rep != null) return (rep, id);
    }
    return (id, null);
  }

  final edgeLabelSizes = <int, Size>{};
  final edgeMath = <int, MathLayout>{};
  for (var i = 0; i < graph.edges.length; i++) {
    final e = graph.edges[i];
    if (isAbsorbedEdge(e)) continue;
    Size? labelSize;
    final label = e.label;
    if (label != null && label.isNotEmpty) {
      final mathSrc = wholeMath(label);
      if (mathSrc != null) {
        final ml = layoutMath(mathSrc, baseStyle, measurer, theme.textColor);
        edgeMath[i] = ml;
        labelSize = ml.size;
      } else {
        labelSize =
            measurer.measure(label, baseStyle, maxWidth: _wrappingWidth);
      }
      edgeLabelSizes[i] = labelSize;
    }
    final (from, clusterFrom) = resolveEndpoint(e.from);
    final (to, clusterTo) = resolveEndpoint(e.to);
    // Self-loops are routed manually after layout (dagre would thread them
    // through a degenerate dummy chain).
    if (from == to && clusterFrom == null && clusterTo == null) continue;
    g.addEdge(dagre.DagreEdge(
      from,
      to,
      id: 'e$i',
      minLen: e.minLen.toDouble(),
      width: labelSize?.width ?? 0,
      height: labelSize?.height ?? 0,
      labelPos: dagre.LabelPosition.center,
    ));
  }

  // --- 4. Run layout. -------------------------------------------------------
  final result = dagre.layout(
    g,
    dagre.DagreConfig(
      rankDir: _rankDir(graph.direction),
      nodeSep: _nodeSpacing,
      rankSep: _rankSpacing,
    ),
  );
  for (final p in placed.values) {
    p.center = result.graph.nodeMap[p.node.id]!.position!.center;
  }

  // --- 5. Emit scene nodes (in dagre coordinate space; translated later). ---
  final clusterGroups = <SceneNode>[];
  final edgeGroups = <SceneNode>[];
  final edgeLabelGroups = <SceneNode>[];
  final nodeGroups = <SceneNode>[];

  // Clusters, outermost first so nested ones paint on top.
  final clusterRects = <String, Rect>{};
  final clusterTitleStyle = baseStyle.copyWith(fontWeight: 400);
  for (var sgIndex = 0; sgIndex < sgs.length; sgIndex++) {
    final sg = sgs[sgIndex];
    if (removedSubgraphs.contains(sgIndex)) {
      // Isolated clusters draw their own chrome below (their dagre entry is
      // a regular node, not a compound cluster).
      continue;
    }
    final pos = result.graph.nodeMap[sg.id]?.position;
    if (pos == null) continue;
    final titleSize = sg.title.isEmpty
        ? Size.zero
        : measurer.measure(sg.title, clusterTitleStyle,
            maxWidth: _wrappingWidth);
    final rect = Rect.fromLTRB(
      pos.left - _clusterPadding,
      pos.top - _clusterPadding - titleSize.height,
      pos.right + _clusterPadding,
      pos.bottom + _clusterPadding,
    );
    clusterRects[sg.id] = rect;
    clusterGroups.add(SceneGroup(
      id: sg.id,
      semanticLabel: sg.title.isEmpty ? null : sg.title,
      children: [
        SceneShape(
          geometry: RectGeometry(rect),
          fill: Fill(theme.clusterBkg),
          stroke: Stroke(color: theme.clusterBorder),
        ),
        if (sg.title.isNotEmpty)
          SceneText(
            text: sg.title,
            bounds: Rect.fromLTWH(
              rect.center.x - titleSize.width / 2,
              rect.top + 4,
              titleSize.width,
              titleSize.height,
            ),
            style: clusterTitleStyle,
            color: theme.titleColor,
          ),
      ],
    ));
  }

  // Isolated-direction clusters: chrome plus the recursively laid-out
  // fragment translated into the synthetic node's final rect.
  for (final cluster in isolatedClusters.values) {
    final p = placed[cluster.subgraph.id]!;
    final rect = Rect.fromCenter(p.center, cluster.width, cluster.height);
    final children = <SceneNode>[
      SceneShape(
        geometry: RectGeometry(rect),
        fill: Fill(theme.clusterBkg),
        stroke: Stroke(color: theme.clusterBorder),
      ),
      if (cluster.subgraph.title.isNotEmpty)
        SceneText(
          text: cluster.subgraph.title,
          bounds: Rect.fromLTWH(
            rect.center.x - cluster.titleSize.width / 2,
            rect.top + 4,
            cluster.titleSize.width,
            cluster.titleSize.height,
          ),
          style: clusterTitleStyle,
          color: theme.titleColor,
        ),
    ];
    final dx = rect.left + _clusterPadding - cluster.fragment.bounds.left;
    final dy = rect.top +
        _clusterPadding +
        cluster.titleBand -
        cluster.fragment.bounds.top;
    children.addAll(
        [for (final n in cluster.fragment.nodes) _translateNode(n, dx, dy)]);
    clusterGroups.add(SceneGroup(
      id: cluster.subgraph.id,
      semanticLabel:
          cluster.subgraph.title.isEmpty ? null : cluster.subgraph.title,
      children: children,
    ));
  }

  // Edges and their labels.
  final selfLoopCount = <String, int>{};
  for (var i = 0; i < graph.edges.length; i++) {
    final e = graph.edges[i];
    if (isAbsorbedEdge(e)) continue; // Rendered inside the cluster fragment.
    final groupId = 'edge_${e.from}_${e.to}_$i';
    if (e.stroke == EdgeStroke.invisible) {
      // Keep an (empty) group so the edge still participates in spacing and
      // hit-testing structure, but paint nothing.
      edgeGroups.add(SceneGroup(id: groupId, children: const []));
      continue;
    }
    final (fromId, clusterFrom) = resolveEndpoint(e.from);
    final (toId, clusterTo) = resolveEndpoint(e.to);
    final source = clusterFrom != null
        ? _clusterEndpointNode(clusterRects[clusterFrom]!)
        : placed[fromId]!;
    final target = clusterTo != null
        ? _clusterEndpointNode(clusterRects[clusterTo]!)
        : placed[toId]!;
    final style = _resolveEdgeStyle(e, theme);

    if (fromId == toId && clusterFrom == null && clusterTo == null) {
      final loopIndex = selfLoopCount[fromId] ?? 0;
      selfLoopCount[fromId] = loopIndex + 1;
      final (loopNodes, labelCenter) = _selfLoop(
          source, e, style, loopIndex, edgeLabelSizes[i]);
      edgeGroups
          .add(SceneGroup(id: groupId, semanticLabel: e.label, children: loopNodes));
      final labelSize = edgeLabelSizes[i];
      if (labelSize != null) {
        edgeLabelGroups.add(_edgeLabelGroup(
            e, i, labelCenter, labelSize, baseStyle, theme,
            math: edgeMath[i]));
      }
      continue;
    }

    final dagreEdge = result.graph.findEdgeById('e$i')!;

    var points = List<Point>.from(dagreEdge.points);
    if (points.length < 2) {
      points = [source.center, target.center];
    }
    // Cluster endpoints: the dagre path runs to a representative node deep
    // inside the cluster; cut it back so it meets the cluster border.
    if (clusterTo != null) {
      points = _dropInsideRect(points, clusterRects[clusterTo]!, fromEnd: true);
    }
    if (clusterFrom != null) {
      points =
          _dropInsideRect(points, clusterRects[clusterFrom]!, fromEnd: false);
    }
    // Clip ends to the actual shape boundary (dagre only clips to the
    // bounding rect).
    points[0] = source.shape
        .intersect(source.center, points.length > 1 ? points[1] : target.center);
    points[points.length - 1] = target.shape.intersect(
        target.center, points.length > 1 ? points[points.length - 2] : source.center);

    final children = <SceneNode>[];

    // Arrow markers shorten the path so the line does not poke through them.
    final endTip = points.last;
    final endDir = _direction(points[points.length - 2], endTip);
    if (e.headTo != ArrowHead.none) {
      points[points.length - 1] =
          endTip - endDir * _markerShorten(e.headTo);
    }
    final startTip = points.first;
    final startDir = _direction(points[1], startTip);
    if (e.headFrom != ArrowHead.none) {
      points[0] = startTip - startDir * _markerShorten(e.headFrom);
    }

    children.add(SceneShape(
      geometry: PathGeometry(_curveBasis(points)),
      stroke: Stroke(color: style.color, width: style.width, dash: style.dash),
    ));
    if (e.headTo != ArrowHead.none) {
      children.addAll(_marker(e.headTo, endTip, endDir, style.markerColor));
    }
    if (e.headFrom != ArrowHead.none) {
      children.addAll(_marker(e.headFrom, startTip, startDir, style.markerColor));
    }
    edgeGroups.add(SceneGroup(id: groupId, semanticLabel: e.label, children: children));

    final labelSize = edgeLabelSizes[i];
    if (labelSize != null) {
      final labelCenter = (dagreEdge.labelX != null && dagreEdge.labelY != null)
          ? Point(dagreEdge.labelX!, dagreEdge.labelY!)
          : _pathMidpoint(points);
      edgeLabelGroups.add(_edgeLabelGroup(
          e, i, labelCenter, labelSize, baseStyle, theme,
          math: edgeMath[i]));
    }
  }

  // Nodes.
  for (final p in placed.values) {
    if (syntheticIds.contains(p.node.id)) continue;
    final children = <SceneNode>[...p.shape.build(p.center, p.style)];
    if (p.math != null) {
      // Math label: paint glyphs/rules centered in the node.
      final lc = p.shape.labelCenter(p.center);
      final origin = Point(
          lc.x - p.math!.size.width / 2, lc.y - p.math!.size.height / 2);
      children.addAll(p.math!.render(origin));
    } else if (p.textSize != null) {
      // Icon node: glyph in the reserved top square, label beneath it.
      final lc = p.shape.labelCenter(p.center);
      final contentTop = lc.y - p.labelSize.height / 2;
      children.addAll(renderIcon(
        p.node.icon!,
        Rect.fromLTWH(p.center.x - _iconSize / 2, contentTop, _iconSize, _iconSize),
        p.style.textColor,
      ));
      children.add(SceneText(
        text: p.node.label,
        bounds: Rect.fromCenter(
          Point(p.center.x, contentTop + _iconSize + _iconGap + p.textSize!.height / 2),
          p.textSize!.width,
          p.textSize!.height,
        ),
        style: baseStyle,
        color: p.style.textColor,
      ));
    } else {
      children.add(SceneText(
        text: p.node.label,
        bounds: Rect.fromCenter(
          p.shape.labelCenter(p.center),
          p.labelSize.width,
          p.labelSize.height,
        ),
        style: baseStyle,
        color: p.style.textColor,
      ));
    }
    nodeGroups.add(SceneGroup(
      id: p.node.id,
      semanticLabel: p.node.label,
      children: children,
    ));
  }

  // Z-order: clusters, edges, edge labels, nodes.
  final sceneNodes = <SceneNode>[
    ...clusterGroups,
    ...edgeGroups,
    ...edgeLabelGroups,
    ...nodeGroups,
  ];
  return _Fragment(
    sceneNodes,
    _boundsOfAll(sceneNodes) ?? const Rect.fromLTWH(0, 0, 0, 0),
  );
}

SceneGroup _edgeLabelGroup(
  FlowEdge e,
  int index,
  Point labelCenter,
  Size labelSize,
  TextStyleSpec baseStyle,
  MermaidTheme theme, {
  MathLayout? math,
}) {
  const pad = 2.0;
  final bg = Rect.fromCenter(
      labelCenter, labelSize.width + 2 * pad, labelSize.height + 2 * pad);
  return SceneGroup(
    id: 'edgelabel_${e.from}_${e.to}_$index',
    children: [
      SceneShape(
        geometry: RectGeometry(bg, rx: 2, ry: 2),
        fill: Fill(theme.edgeLabelBackground),
      ),
      if (math != null)
        ...math.render(Point(
            labelCenter.x - math.size.width / 2,
            labelCenter.y - math.size.height / 2))
      else
        SceneText(
          text: e.label!,
          bounds:
              Rect.fromCenter(labelCenter, labelSize.width, labelSize.height),
          style: baseStyle,
          color: theme.textColor,
        ),
    ],
  );
}

/// Pseudo placed-node standing in for a compound cluster at an edge
/// endpoint, so boundary clipping can reuse the rect intersect.
_PlacedNode _clusterEndpointNode(Rect rect) => _PlacedNode(
      node: const FlowNode(id: '', label: ''),
      style: _NodeStyle(
        fill: Color.transparent,
        stroke: Color.transparent,
        strokeWidth: 0,
        textColor: Color.transparent,
      ),
      labelSize: Size.zero,
      shape: _RectShape(rect.width, rect.height),
    )..center = rect.center;

/// Removes the run of path points that lie inside [rect] at one end, leaving
/// the last kept point ready for boundary-intersect clipping.
List<Point> _dropInsideRect(List<Point> pts, Rect rect,
    {required bool fromEnd}) {
  final list = List<Point>.from(pts);
  if (fromEnd) {
    while (list.length > 2 && rect.contains(list[list.length - 2])) {
      list.removeLast();
    }
  } else {
    while (list.length > 2 && rect.contains(list[1])) {
      list.removeAt(0);
    }
  }
  return list;
}

/// Routes a self-edge as a compact loop on the right side of the node,
/// mirroring mermaid's look. Returns the scene nodes and the label center.
(List<SceneNode>, Point) _selfLoop(
  _PlacedNode p,
  FlowEdge e,
  _EdgeStyle style,
  int loopIndex,
  Size? labelSize,
) {
  final c = p.center;
  final start =
      p.shape.intersect(c, Point(c.x + p.shape.width, c.y - p.shape.height / 2));
  final end =
      p.shape.intersect(c, Point(c.x + p.shape.width, c.y + p.shape.height / 2));
  final ext = 40.0 + loopIndex * 16;
  final c1 = Point(start.x + ext, start.y - ext * 0.35);
  final c2 = Point(end.x + ext, end.y + ext * 0.35);

  final children = <SceneNode>[];
  var pathEnd = end;
  final endDir = _direction(c2, end);
  if (e.headTo != ArrowHead.none) {
    pathEnd = end - endDir * _markerShorten(e.headTo);
  }
  var pathStart = start;
  final startDir = _direction(c1, start);
  if (e.headFrom != ArrowHead.none) {
    pathStart = start - startDir * _markerShorten(e.headFrom);
  }
  children.add(SceneShape(
    geometry: PathGeometry([MoveTo(pathStart), CubicTo(c1, c2, pathEnd)]),
    stroke: Stroke(color: style.color, width: style.width, dash: style.dash),
  ));
  if (e.headTo != ArrowHead.none) {
    children.addAll(_marker(e.headTo, end, endDir, style.markerColor));
  }
  if (e.headFrom != ArrowHead.none) {
    children.addAll(_marker(e.headFrom, start, startDir, style.markerColor));
  }
  // Cubic apex (t = 0.5): (p0 + 3c1 + 3c2 + p3) / 8.
  final apexX = (start.x + 3 * c1.x + 3 * c2.x + end.x) / 8;
  final labelCenter = Point(
    apexX + 6 + (labelSize?.width ?? 0) / 2,
    (start.y + end.y) / 2,
  );
  return (children, labelCenter);
}

dagre.RankDir _rankDir(FlowDirection d) => switch (d) {
      FlowDirection.tb => dagre.RankDir.ttb,
      FlowDirection.bt => dagre.RankDir.btt,
      FlowDirection.lr => dagre.RankDir.ltr,
      FlowDirection.rl => dagre.RankDir.rtl,
    };

// --- Style resolution -------------------------------------------------------

class _NodeStyle {
  _NodeStyle({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.textColor,
  });

  Color fill;
  Color stroke;
  double strokeWidth;
  Color textColor;
  List<double>? dash;

  Stroke get sceneStroke =>
      Stroke(color: stroke, width: strokeWidth, dash: dash);
}

_NodeStyle _resolveNodeStyle(
    FlowNode node, FlowGraph graph, MermaidTheme theme) {
  final style = _NodeStyle(
    fill: theme.mainBkg,
    stroke: theme.nodeBorder,
    strokeWidth: 1,
    textColor: theme.textColor,
  );

  void apply(Map<String, String>? props) {
    if (props == null) return;
    props.forEach((key, value) {
      switch (key.trim()) {
        case 'fill':
          style.fill = Color.tryParse(value) ?? style.fill;
        case 'stroke':
          style.stroke = Color.tryParse(value) ?? style.stroke;
        case 'color':
          style.textColor = Color.tryParse(value) ?? style.textColor;
        case 'stroke-width':
          style.strokeWidth = _parsePx(value) ?? style.strokeWidth;
        case 'stroke-dasharray':
          style.dash = _parseDashArray(value) ?? style.dash;
      }
    });
  }

  apply(graph.classDefs['default']);
  for (final c in node.classes) {
    apply(graph.classDefs[c]);
  }
  apply(node.styles);
  return style;
}

class _EdgeStyle {
  _EdgeStyle({
    required this.color,
    required this.width,
    required this.markerColor,
    this.dash,
  });

  final Color color;
  final double width;
  final Color markerColor;
  final List<double>? dash;
}

_EdgeStyle _resolveEdgeStyle(FlowEdge edge, MermaidTheme theme) {
  var color = theme.lineColor;
  var markerColor = theme.arrowheadColor;
  var width = switch (edge.stroke) {
    EdgeStroke.thick => 3.5,
    _ => 2.0,
  };
  List<double>? dash = edge.stroke == EdgeStroke.dotted ? const [3, 3] : null;
  edge.styles.forEach((key, value) {
    switch (key.trim()) {
      case 'stroke':
        final c = Color.tryParse(value);
        if (c != null) {
          color = c;
          markerColor = c;
        }
      case 'stroke-width':
        width = _parsePx(value) ?? width;
      case 'stroke-dasharray':
        dash = _parseDashArray(value) ?? dash;
    }
  });
  return _EdgeStyle(
      color: color, width: width, markerColor: markerColor, dash: dash);
}

double? _parsePx(String value) =>
    double.tryParse(value.trim().replaceAll(RegExp(r'px$'), ''));

List<double>? _parseDashArray(String value) {
  final parts = value
      .split(RegExp(r'[,\s]+'))
      .where((p) => p.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (parts.isEmpty || parts.any((p) => p == null)) return null;
  return parts.cast<double>();
}

// --- Shapes -----------------------------------------------------------------

class _PlacedNode {
  _PlacedNode({
    required this.node,
    required this.style,
    required this.labelSize,
    required this.shape,
    this.textSize,
    this.math,
  });

  final FlowNode node;
  final _NodeStyle style;

  /// Box used to size the shape (inflated to include the icon when present).
  final Size labelSize;

  /// The label's own measured size; differs from [labelSize] only when an
  /// icon reserves space above the text. Null ⇒ same as [labelSize].
  final Size? textSize;

  /// Set when the label is a `$$...$$` math span rendered with primitives.
  final MathLayout? math;
  final _Shape shape;
  Point center = Point.zero;
}

/// A sized node shape: provides the dagre box, the scene geometry and the
/// boundary intersection used for edge clipping.
sealed class _Shape {
  double get width;
  double get height;

  List<SceneNode> build(Point c, _NodeStyle style);

  /// Point where the segment from [c] (shape center) towards [outside]
  /// crosses the shape boundary.
  Point intersect(Point c, Point outside);

  Point labelCenter(Point c) => c;

  /// Sizing math ported from upstream shape constructors.
  factory _Shape.forNode(FlowNodeShape shape, Size label) {
    const p = _nodePadding;
    final lw = label.width;
    final lh = label.height;
    switch (shape) {
      case FlowNodeShape.rect:
      case FlowNodeShape.plain:
        return _RectShape(lw + 2 * p, lh + 2 * p);
      case FlowNodeShape.rounded:
        return _RectShape(lw + 2 * p, lh + 2 * p, rx: 5);
      case FlowNodeShape.stadium:
        // stadium.ts: w = bbox.width + h / 4 + padding
        final h = lh + 2 * p;
        return _RectShape(lw + 2 * p + h / 4, h, rx: h / 2);
      case FlowNodeShape.subroutine:
        return _SubroutineShape(lw + 2 * p + 2 * _subroutineFrame, lh + 2 * p);
      case FlowNodeShape.cylinder:
        // cylinder.ts: rx = w / 2, ry = rx / (2.5 + w / 50)
        final w = lw + 2 * p;
        final rx = w / 2;
        final ry = rx / (2.5 + w / 50);
        return _CylinderShape(w, lh + 2 * p + 3 * ry, ry);
      case FlowNodeShape.circle:
        // circle.ts: radius = bbox.width / 2 + padding
        return _CircleShape(math.max(lw, lh) / 2 + p);
      case FlowNodeShape.doubleCircle:
        // doubleCircle.ts: gap 5, outer = inner + gap
        return _DoubleCircleShape(
            math.max(lw, lh) / 2 + p + _doubleCircleGap, _doubleCircleGap);
      case FlowNodeShape.ellipse:
        return _EllipseShape(lw / 2 + p, lh / 2 + p);
      case FlowNodeShape.diamond:
        // question.ts: s = (w + padding) + (h + padding)
        final s = lw + lh + 2 * p;
        return _PolygonShape(s, s, [
          Point(0, -s / 2),
          Point(s / 2, 0),
          Point(0, s / 2),
          Point(-s / 2, 0),
        ]);
      case FlowNodeShape.hexagon:
        // hexagon.ts: h = bbox.height + padding, m = h / 4,
        // w = bbox.width + 2 * m + padding
        final h = lh + p;
        final m = h / 4;
        final w = lw + 2 * m + p;
        return _PolygonShape(w, h, [
          Point(-w / 2 + m, -h / 2),
          Point(w / 2 - m, -h / 2),
          Point(w / 2, 0),
          Point(w / 2 - m, h / 2),
          Point(-w / 2 + m, h / 2),
          Point(-w / 2, 0),
        ]);
      case FlowNodeShape.leanRight:
        // leanRight.ts parallelogram, slant 3h/6 = h/2 each side.
        final h = lh + p;
        final w = lw + p;
        final tw = w + h;
        return _PolygonShape(tw, h, [
          Point(-tw / 2, h / 2),
          Point(w / 2, h / 2),
          Point(tw / 2, -h / 2),
          Point(-w / 2, -h / 2),
        ]);
      case FlowNodeShape.leanLeft:
        final h = lh + p;
        final w = lw + p;
        final tw = w + h;
        return _PolygonShape(tw, h, [
          Point(-w / 2, h / 2),
          Point(tw / 2, h / 2),
          Point(w / 2, -h / 2),
          Point(-tw / 2, -h / 2),
        ]);
      case FlowNodeShape.trapezoid:
        final h = lh + p;
        final w = lw + p;
        final tw = w + h;
        return _PolygonShape(tw, h, [
          Point(-tw / 2, h / 2),
          Point(tw / 2, h / 2),
          Point(w / 2, -h / 2),
          Point(-w / 2, -h / 2),
        ]);
      case FlowNodeShape.invTrapezoid:
        final h = lh + p;
        final w = lw + p;
        final tw = w + h;
        return _PolygonShape(tw, h, [
          Point(-w / 2, h / 2),
          Point(w / 2, h / 2),
          Point(tw / 2, -h / 2),
          Point(-tw / 2, -h / 2),
        ]);
      case FlowNodeShape.asymmetric:
        // rectLeftInvArrow.ts: notch depth h / 4 on the left edge.
        final h = lh + p;
        final w = lw + p;
        final tw = w + h / 4;
        return _PolygonShape(tw, h, [
          Point(-tw / 2, -h / 2),
          Point(-tw / 2 + h / 4, 0),
          Point(-tw / 2, h / 2),
          Point(tw / 2, h / 2),
          Point(tw / 2, -h / 2),
        ]);
      case FlowNodeShape.document:
        return _DocumentShape(lw + 2 * p, lh + 2 * p + 6);
      case FlowNodeShape.triangle:
        final w = lw + 2 * p;
        final h = lh + 2 * p;
        return _PolygonShape(w, h, [
          Point(0, -h / 2),
          Point(w / 2, h / 2),
          Point(-w / 2, h / 2),
        ]);
      case FlowNodeShape.flippedTriangle:
        final w = lw + 2 * p;
        final h = lh + 2 * p;
        return _PolygonShape(w, h, [
          Point(-w / 2, -h / 2),
          Point(w / 2, -h / 2),
          Point(0, h / 2),
        ]);
      case FlowNodeShape.slopedRect:
        final w = lw + 2 * p;
        final h = lh + 2 * p;
        final s = h / 5;
        return _PolygonShape(w, h, [
          Point(-w / 2, -h / 2 + s),
          Point(w / 2, -h / 2),
          Point(w / 2, h / 2),
          Point(-w / 2, h / 2),
        ]);
      case FlowNodeShape.card:
        final w = lw + 2 * p;
        final h = lh + 2 * p;
        final n = h / 4;
        return _PolygonShape(w, h, [
          Point(-w / 2 + n, -h / 2),
          Point(w / 2, -h / 2),
          Point(w / 2, h / 2),
          Point(-w / 2, h / 2),
          Point(-w / 2, -h / 2 + n),
        ]);
      case FlowNodeShape.notchedPentagon:
        final w = lw + 2 * p;
        final h = lh + 2 * p;
        final n = h / 4;
        return _PolygonShape(w, h, [
          Point(-w / 2 + n, -h / 2),
          Point(w / 2 - n, -h / 2),
          Point(w / 2, -h / 2 + n),
          Point(w / 2, h / 2),
          Point(-w / 2, h / 2),
          Point(-w / 2, -h / 2 + n),
        ]);
      case FlowNodeShape.bolt:
        final w = lw + 2 * p + 10;
        final h = lh + 2 * p;
        return _PolygonShape(w, h, [
          Point(-w / 6, -h / 2),
          Point(w / 2, -h / 6),
          Point(w / 10, -h / 6),
          Point(w / 6, h / 2),
          Point(-w / 2, h / 6),
          Point(-w / 10, h / 6),
        ]);
      case FlowNodeShape.hourglass:
        // Bowtie: a 4-point self-crossing ring fills as two triangles.
        final s = math.max(lw, lh) + 2 * p;
        return _PolygonShape(s, s, [
          Point(-s / 2, -s / 2),
          Point(s / 2, -s / 2),
          Point(-s / 2, s / 2),
          Point(s / 2, s / 2),
        ]);
      case FlowNodeShape.linedRect:
        // Vertical line a short way in from the left (lined/stacked process).
        final w = lw + 2 * p + 8;
        final h = lh + 2 * p;
        return _DecoratedRectShape(w, h, [
          [Point(-w / 2 + 8, -h / 2), Point(-w / 2 + 8, h / 2)],
        ]);
      case FlowNodeShape.dividedRect:
        final w = lw + 2 * p;
        final h = lh + 2 * p + 8;
        return _DecoratedRectShape(w, h, [
          [Point(-w / 2, -h / 2 + 12), Point(w / 2, -h / 2 + 12)],
        ]);
      case FlowNodeShape.windowPane:
        final w = lw + 2 * p + 8;
        final h = lh + 2 * p + 8;
        return _DecoratedRectShape(w, h, [
          [Point(-w / 2 + 10, -h / 2), Point(-w / 2 + 10, h / 2)],
          [Point(-w / 2, -h / 2 + 10), Point(w / 2, -h / 2 + 10)],
        ]);
      case FlowNodeShape.crossedCircle:
        return _CrossedCircleShape(math.max(lw, lh) / 2 + p);
      case FlowNodeShape.forkJoin:
        // A thin filled bar.
        return _ForkJoinShape(math.max(lw + 2 * p, 70), 14);
      case FlowNodeShape.textShape:
        return _TextShape(lw + 2 * p, lh + 2 * p);
    }
  }
}

class _RectShape implements _Shape {
  _RectShape(this.width, this.height, {this.rx = 0});

  @override
  final double width;
  @override
  final double height;
  final double rx;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) => [
        SceneShape(
          geometry: RectGeometry(Rect.fromCenter(c, width, height),
              rx: rx, ry: rx),
          fill: Fill(style.fill),
          stroke: style.sceneStroke,
        ),
      ];

  @override
  Point intersect(Point c, Point outside) =>
      _intersectRect(c, width, height, outside);

  @override
  Point labelCenter(Point c) => c;
}

class _SubroutineShape implements _Shape {
  _SubroutineShape(this.width, this.height);

  @override
  final double width;
  @override
  final double height;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) {
    final rect = Rect.fromCenter(c, width, height);
    final x1 = rect.left + _subroutineFrame;
    final x2 = rect.right - _subroutineFrame;
    return [
      SceneShape(
        geometry: RectGeometry(rect),
        fill: Fill(style.fill),
        stroke: style.sceneStroke,
      ),
      SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(x1, rect.top)),
          LineTo(Point(x1, rect.bottom)),
          MoveTo(Point(x2, rect.top)),
          LineTo(Point(x2, rect.bottom)),
        ]),
        stroke: style.sceneStroke,
      ),
    ];
  }

  @override
  Point intersect(Point c, Point outside) =>
      _intersectRect(c, width, height, outside);

  @override
  Point labelCenter(Point c) => c;
}

class _CylinderShape implements _Shape {
  _CylinderShape(this.width, this.height, this.ry);

  @override
  final double width;
  @override
  final double height;
  final double ry;

  static const double _kappa = 0.5522847498;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) {
    final rx = width / 2;
    final top = c.y - height / 2;
    final bottom = c.y + height / 2;
    final left = c.x - rx;
    final right = c.x + rx;
    final k = _kappa;
    final topMid = top + ry;
    final bottomMid = bottom - ry;
    final cmds = <PathCommand>[
      MoveTo(Point(left, topMid)),
      // Lower half of the top ellipse.
      CubicTo(Point(left, topMid + k * ry), Point(c.x - k * rx, top + 2 * ry),
          Point(c.x, top + 2 * ry)),
      CubicTo(Point(c.x + k * rx, top + 2 * ry), Point(right, topMid + k * ry),
          Point(right, topMid)),
      // Upper half of the top ellipse (back to start).
      CubicTo(Point(right, topMid - k * ry), Point(c.x + k * rx, top),
          Point(c.x, top)),
      CubicTo(Point(c.x - k * rx, top), Point(left, topMid - k * ry),
          Point(left, topMid)),
      // Left wall.
      LineTo(Point(left, bottomMid)),
      // Bottom bulge.
      CubicTo(Point(left, bottomMid + k * ry), Point(c.x - k * rx, bottom),
          Point(c.x, bottom)),
      CubicTo(Point(c.x + k * rx, bottom), Point(right, bottomMid + k * ry),
          Point(right, bottomMid)),
      // Right wall.
      LineTo(Point(right, topMid)),
    ];
    return [
      SceneShape(
        geometry: PathGeometry(cmds),
        fill: Fill(style.fill),
        stroke: style.sceneStroke,
      ),
    ];
  }

  @override
  Point intersect(Point c, Point outside) {
    // cylinder.ts: rect intersection, with the y adjusted onto the
    // elliptical cap when the hit is on the top/bottom edge.
    final pos = _intersectRect(c, width, height, outside);
    final rx = width / 2;
    final x = pos.x - c.x;
    if (rx != 0 &&
        (x.abs() < width / 2 ||
            (x.abs() == width / 2 &&
                (pos.y - c.y).abs() > height / 2 - ry))) {
      var y = ry * ry * (1 - (x * x) / (rx * rx));
      if (y > 0) y = math.sqrt(y);
      y = ry - y;
      if (outside.y - c.y > 0) y = -y;
      return Point(pos.x, pos.y + y);
    }
    return pos;
  }

  @override
  Point labelCenter(Point c) => Point(c.x, c.y + ry / 2);
}

class _CircleShape implements _Shape {
  _CircleShape(this.radius);

  final double radius;

  @override
  double get width => radius * 2;
  @override
  double get height => radius * 2;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) => [
        SceneShape(
          geometry: CircleGeometry(c, radius),
          fill: Fill(style.fill),
          stroke: style.sceneStroke,
        ),
      ];

  @override
  Point intersect(Point c, Point outside) =>
      _intersectEllipse(c, radius, radius, outside);

  @override
  Point labelCenter(Point c) => c;
}

class _DoubleCircleShape implements _Shape {
  _DoubleCircleShape(this.outerRadius, this.gap);

  final double outerRadius;
  final double gap;

  @override
  double get width => outerRadius * 2;
  @override
  double get height => outerRadius * 2;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) => [
        SceneShape(
          geometry: CircleGeometry(c, outerRadius),
          fill: Fill(style.fill),
          stroke: style.sceneStroke,
        ),
        SceneShape(
          geometry: CircleGeometry(c, outerRadius - gap),
          fill: Fill(style.fill),
          stroke: style.sceneStroke,
        ),
      ];

  @override
  Point intersect(Point c, Point outside) =>
      _intersectEllipse(c, outerRadius, outerRadius, outside);

  @override
  Point labelCenter(Point c) => c;
}

class _EllipseShape implements _Shape {
  _EllipseShape(this.rx, this.ry);

  final double rx;
  final double ry;

  @override
  double get width => rx * 2;
  @override
  double get height => ry * 2;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) => [
        SceneShape(
          geometry: EllipseGeometry(c, rx, ry),
          fill: Fill(style.fill),
          stroke: style.sceneStroke,
        ),
      ];

  @override
  Point intersect(Point c, Point outside) =>
      _intersectEllipse(c, rx, ry, outside);

  @override
  Point labelCenter(Point c) => c;
}

class _PolygonShape implements _Shape {
  _PolygonShape(this.width, this.height, this.points);

  @override
  final double width;
  @override
  final double height;

  /// Points relative to the shape center, y-down, clockwise.
  final List<Point> points;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) => [
        SceneShape(
          geometry: PolygonGeometry([for (final p in points) p + c]),
          fill: Fill(style.fill),
          stroke: style.sceneStroke,
        ),
      ];

  @override
  Point intersect(Point c, Point outside) =>
      _intersectPolygon(c, points, outside);

  @override
  Point labelCenter(Point c) => c;
}

/// A rectangle plus extra decoration line segments (relative to center).
/// Used for lined/divided/window-pane v11 shapes.
class _DecoratedRectShape implements _Shape {
  _DecoratedRectShape(this.width, this.height, this.lines);

  @override
  final double width;
  @override
  final double height;

  /// Each entry is a [start, end] pair relative to the shape center.
  final List<List<Point>> lines;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) => [
        SceneShape(
          geometry: RectGeometry(Rect.fromCenter(c, width, height)),
          fill: Fill(style.fill),
          stroke: style.sceneStroke,
        ),
        for (final seg in lines)
          SceneShape(
            geometry: PathGeometry([MoveTo(seg[0] + c), LineTo(seg[1] + c)]),
            stroke: style.sceneStroke,
          ),
      ];

  @override
  Point intersect(Point c, Point outside) =>
      _intersectRect(c, width, height, outside);

  @override
  Point labelCenter(Point c) => c;
}

/// A rectangle with a wavy bottom edge (v11 `document`).
class _DocumentShape implements _Shape {
  _DocumentShape(this.width, this.height);

  @override
  final double width;
  @override
  final double height;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) {
    final l = c.x - width / 2, r = c.x + width / 2;
    final t = c.y - height / 2, b = c.y + height / 2;
    final wave = height * 0.12;
    return [
      SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(l, t)),
          LineTo(Point(r, t)),
          LineTo(Point(r, b - wave)),
          CubicTo(Point(r - width / 4, b - wave * 2.5),
              Point(l + width / 4, b + wave), Point(l, b - wave)),
          const ClosePath(),
        ]),
        fill: Fill(style.fill),
        stroke: style.sceneStroke,
      ),
    ];
  }

  @override
  Point intersect(Point c, Point outside) =>
      _intersectRect(c, width, height, outside);

  @override
  Point labelCenter(Point c) => Point(c.x, c.y - height * 0.05);
}

/// A circle with an inscribed X (v11 `crossed-circle` / `summary`).
class _CrossedCircleShape implements _Shape {
  _CrossedCircleShape(this.radius);

  final double radius;
  @override
  double get width => radius * 2;
  @override
  double get height => radius * 2;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) {
    final d = radius * 0.7071;
    return [
      SceneShape(
        geometry: CircleGeometry(c, radius),
        fill: Fill(style.fill),
        stroke: style.sceneStroke,
      ),
      SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(c.x - d, c.y - d)),
          LineTo(Point(c.x + d, c.y + d)),
          MoveTo(Point(c.x + d, c.y - d)),
          LineTo(Point(c.x - d, c.y + d)),
        ]),
        stroke: style.sceneStroke,
      ),
    ];
  }

  @override
  Point intersect(Point c, Point outside) =>
      _intersectEllipse(c, radius, radius, outside);

  @override
  Point labelCenter(Point c) => c;
}

/// A thin filled bar (v11 `fork` / `join`).
class _ForkJoinShape implements _Shape {
  _ForkJoinShape(this.width, this.height);

  @override
  final double width;
  @override
  final double height;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) => [
        SceneShape(
          geometry: RectGeometry(Rect.fromCenter(c, width, height)),
          fill: Fill(style.stroke), // filled bar
          stroke: style.sceneStroke,
        ),
      ];

  @override
  Point intersect(Point c, Point outside) =>
      _intersectRect(c, width, height, outside);

  @override
  Point labelCenter(Point c) => c;
}

/// Label only — no border or fill (v11 `text`).
class _TextShape implements _Shape {
  _TextShape(this.width, this.height);

  @override
  final double width;
  @override
  final double height;

  @override
  List<SceneNode> build(Point c, _NodeStyle style) => const [];

  @override
  Point intersect(Point c, Point outside) =>
      _intersectRect(c, width, height, outside);

  @override
  Point labelCenter(Point c) => c;
}

// --- Intersections (ports of rendering-elements/intersect/*) ----------------

Point _intersectRect(Point c, double width, double height, Point point) {
  final dx = point.x - c.x;
  final dy = point.y - c.y;
  var w = width / 2;
  var h = height / 2;
  if (dx == 0 && dy == 0) return c;
  double sx, sy;
  if (dy.abs() * w > dx.abs() * h) {
    if (dy < 0) h = -h;
    sx = dy == 0 ? 0 : h * dx / dy;
    sy = h;
  } else {
    if (dx < 0) w = -w;
    sx = w;
    sy = dx == 0 ? 0 : w * dy / dx;
  }
  return Point(c.x + sx, c.y + sy);
}

Point _intersectEllipse(Point c, double rx, double ry, Point point) {
  final px = c.x - point.x;
  final py = c.y - point.y;
  final det = math.sqrt(rx * rx * py * py + ry * ry * px * px);
  if (det == 0) return Point(c.x + rx, c.y);
  var dx = (rx * ry * px / det).abs();
  if (point.x < c.x) dx = -dx;
  var dy = (rx * ry * py / det).abs();
  if (point.y < c.y) dy = -dy;
  return Point(c.x + dx, c.y + dy);
}

Point _intersectPolygon(Point c, List<Point> relativePoints, Point point) {
  final intersections = <Point>[];
  for (var i = 0; i < relativePoints.length; i++) {
    final p1 = relativePoints[i] + c;
    final p2 = relativePoints[(i + 1) % relativePoints.length] + c;
    final hit = _intersectLine(c, point, p1, p2);
    if (hit != null) intersections.add(hit);
  }
  if (intersections.isEmpty) return c;
  intersections.sort(
      (a, b) => a.distanceTo(point).compareTo(b.distanceTo(point)));
  return intersections.first;
}

/// Graphics Gems II line-line intersection, ported from intersect-line.js.
Point? _intersectLine(Point p1, Point p2, Point q1, Point q2) {
  final a1 = p2.y - p1.y;
  final b1 = p1.x - p2.x;
  final c1 = p2.x * p1.y - p1.x * p2.y;

  final r3 = a1 * q1.x + b1 * q1.y + c1;
  final r4 = a1 * q2.x + b1 * q2.y + c1;
  if (r3 != 0 && r4 != 0 && r3 * r4 > 0) return null;

  final a2 = q2.y - q1.y;
  final b2 = q1.x - q2.x;
  final c2 = q2.x * q1.y - q1.x * q2.y;

  final r1 = a2 * p1.x + b2 * p1.y + c2;
  final r2 = a2 * p2.x + b2 * p2.y + c2;
  if (r1 != 0 && r2 != 0 && r1 * r2 > 0) return null;

  final denom = a1 * b2 - a2 * b1;
  if (denom == 0) return null;

  return Point((b1 * c2 - b2 * c1) / denom, (a2 * c1 - a1 * c2) / denom);
}

// --- Edge path helpers -------------------------------------------------------

Point _direction(Point from, Point to) {
  final d = to - from;
  final len = math.sqrt(d.x * d.x + d.y * d.y);
  if (len == 0) return const Point(0, 1);
  return Point(d.x / len, d.y / len);
}

double _markerShorten(ArrowHead head) => switch (head) {
      ArrowHead.point => 9,
      ArrowHead.circle => 10,
      ArrowHead.cross => 9,
      ArrowHead.none => 0,
    };

/// Marker geometry. [tip] is on the shape boundary, [dir] is the unit
/// tangent of the path pointing towards the tip.
List<SceneNode> _marker(ArrowHead head, Point tip, Point dir, Color color) {
  final perp = Point(-dir.y, dir.x);
  switch (head) {
    case ArrowHead.point:
      // Filled triangle, ~10x8 px.
      final base = tip - dir * 10;
      return [
        SceneShape(
          geometry: PolygonGeometry([
            tip,
            base + perp * 4,
            base - perp * 4,
          ]),
          fill: Fill(color),
        ),
      ];
    case ArrowHead.circle:
      return [
        SceneShape(
          geometry: CircleGeometry(tip - dir * 5, 5),
          fill: Fill(color),
        ),
      ];
    case ArrowHead.cross:
      final center = tip - dir * 5;
      const arm = 4.5;
      final d1 = (dir + perp) * (arm / math.sqrt2);
      final d2 = (dir - perp) * (arm / math.sqrt2);
      return [
        SceneShape(
          geometry: PathGeometry([
            MoveTo(center - d1),
            LineTo(center + d1),
            MoveTo(center - d2),
            LineTo(center + d2),
          ]),
          stroke: Stroke(color: color, width: 2),
        ),
      ];
    case ArrowHead.none:
      return const [];
  }
}

/// d3-shape curveBasis: cubic uniform B-spline with interpolated endpoints.
List<PathCommand> _curveBasis(List<Point> pts) {
  if (pts.isEmpty) return const [];
  if (pts.length == 1) return [MoveTo(pts.first)];
  if (pts.length == 2) return [MoveTo(pts[0]), LineTo(pts[1])];
  final cmds = <PathCommand>[MoveTo(pts[0])];
  cmds.add(LineTo(Point(
    (5 * pts[0].x + pts[1].x) / 6,
    (5 * pts[0].y + pts[1].y) / 6,
  )));
  for (var i = 2; i < pts.length; i++) {
    cmds.add(_basisSegment(pts[i - 2], pts[i - 1], pts[i]));
  }
  final n = pts.length;
  cmds.add(_basisSegment(pts[n - 2], pts[n - 1], pts[n - 1]));
  cmds.add(LineTo(pts[n - 1]));
  return cmds;
}

CubicTo _basisSegment(Point p0, Point p1, Point p) => CubicTo(
      Point((2 * p0.x + p1.x) / 3, (2 * p0.y + p1.y) / 3),
      Point((p0.x + 2 * p1.x) / 3, (p0.y + 2 * p1.y) / 3),
      Point((p0.x + 4 * p1.x + p.x) / 6, (p0.y + 4 * p1.y + p.y) / 6),
    );

Point _pathMidpoint(List<Point> pts) {
  if (pts.isEmpty) return Point.zero;
  if (pts.length.isOdd) return pts[pts.length ~/ 2];
  final a = pts[pts.length ~/ 2 - 1];
  final b = pts[pts.length ~/ 2];
  return Point((a.x + b.x) / 2, (a.y + b.y) / 2);
}

// --- Bounds & translation ----------------------------------------------------

Rect? _boundsOfAll(Iterable<SceneNode> nodes) {
  Rect? acc;
  for (final n in nodes) {
    final b = _nodeBounds(n);
    if (b == null) continue;
    acc = acc == null ? b : acc.union(b);
  }
  return acc;
}

Rect? _nodeBounds(SceneNode node) => switch (node) {
      SceneGroup(:final children) => _boundsOfAll(children),
      SceneShape(:final geometry) => _geometryBounds(geometry),
      SceneText(:final bounds) => bounds,
    };

Rect _geometryBounds(ShapeGeometry g) {
  switch (g) {
    case RectGeometry(:final rect):
      return rect;
    case CircleGeometry(:final center, :final radius):
      return Rect.fromCenter(center, radius * 2, radius * 2);
    case EllipseGeometry(:final center, :final rx, :final ry):
      return Rect.fromCenter(center, rx * 2, ry * 2);
    case PolygonGeometry(:final points):
      return _pointsBounds(points);
    case PathGeometry(:final commands):
      return _pointsBounds([
        for (final c in commands) ..._commandPoints(c),
      ]);
  }
}

List<Point> _commandPoints(PathCommand c) => switch (c) {
      MoveTo(:final p) => [p],
      LineTo(:final p) => [p],
      QuadTo(:final c, :final p) => [c, p],
      CubicTo(:final c1, :final c2, :final p) => [c1, c2, p],
      ClosePath() => const [],
    };

Rect _pointsBounds(List<Point> pts) {
  if (pts.isEmpty) return Rect.fromLTWH(0, 0, 0, 0);
  var minX = pts.first.x, maxX = pts.first.x;
  var minY = pts.first.y, maxY = pts.first.y;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

SceneNode _translateNode(SceneNode node, double dx, double dy) =>
    switch (node) {
      SceneGroup(:final id, :final semanticLabel, :final children) =>
        SceneGroup(
          id: id,
          semanticLabel: semanticLabel,
          children: [for (final c in children) _translateNode(c, dx, dy)],
        ),
      SceneShape(:final geometry, :final fill, :final stroke) => SceneShape(
          geometry: _translateGeometry(geometry, dx, dy),
          fill: fill,
          stroke: stroke,
        ),
      SceneText(:final text, :final bounds, :final style, :final color, :final align) =>
        SceneText(
          text: text,
          bounds: bounds.translate(dx, dy),
          style: style,
          color: color,
          align: align,
        ),
    };

ShapeGeometry _translateGeometry(ShapeGeometry g, double dx, double dy) {
  final d = Point(dx, dy);
  return switch (g) {
    RectGeometry(:final rect, :final rx, :final ry) =>
      RectGeometry(rect.translate(dx, dy), rx: rx, ry: ry),
    CircleGeometry(:final center, :final radius) =>
      CircleGeometry(center + d, radius),
    EllipseGeometry(:final center, :final rx, :final ry) =>
      EllipseGeometry(center + d, rx, ry),
    PolygonGeometry(:final points) =>
      PolygonGeometry([for (final p in points) p + d]),
    PathGeometry(:final commands) =>
      PathGeometry([for (final c in commands) _translateCommand(c, d)]),
  };
}

PathCommand _translateCommand(PathCommand c, Point d) => switch (c) {
      MoveTo(:final p) => MoveTo(p + d),
      LineTo(:final p) => LineTo(p + d),
      QuadTo(:final c, :final p) => QuadTo(c + d, p + d),
      CubicTo(:final c1, :final c2, :final p) => CubicTo(c1 + d, c2 + d, p + d),
      ClosePath() => c,
    };

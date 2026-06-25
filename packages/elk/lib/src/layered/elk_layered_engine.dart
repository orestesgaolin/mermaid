/// The faithful ELK-layered engine: builds an [LGraph] from the public
/// [ElkGraph], runs the ported phases + intermediate processors in ELK's
/// default order, and extracts an [ElkResult]. Coordinates are computed in
/// ELK's internal RIGHT (eastward) flow and transformed to the requested
/// [ElkDirection] on the way out (ELK does this via DIRECTION_PRE/POSTPROCESSOR;
/// the net effect on the result is the same transform).
///
/// Hierarchy (compound nodes) is supported via ELK's RECURSIVE /
/// SEPARATE_CHILDREN strategy: a compound node's children are laid out in their
/// own nested [LGraph] first, the compound node's size is set from the nested
/// bounding box, and then the parent graph is laid out treating the compound as
/// an ordinary sized node. Explicit ports, self-loops, edge labels and model
/// order are all supported. Residual TODOs: INCLUDE_CHILDREN single-pass
/// cross-hierarchy edge routing, and bit-exact within-layer ordering vs elkjs
/// (which uses a seeded RNG). See PORTING.md.
library;

import '../api/graph.dart';
import '../api/options.dart';
import '../api/result.dart';
// intermediate_constraints and intermediate_ports both define PortConstraints
// and portConstraints with the same property id but as separate Dart types.
// intermediate_constraints' processors read the property using their own type,
// so we must ensure any value stored with that property key is of their type.
// We therefore hide the conflicting names from intermediate_ports and use
// intermediate_constraints' versions for storing the constraint — but only
// AFTER EdgeAndLayerConstraintEdgeReverser runs. A small injected processor
// (_MarkFixedSideConstraints) bridges the two: it reads from the engine's
// _nodesWithFixedSides set and writes portConstraints using intermediate_ports'
// type (which PortSideProcessor then reads). This injected step runs between
// EdgeAndLayerConstraintEdgeReverser (first in pipeline) and PortSideProcessor
// (before P3), so the constraint is never in the map when the former reads it.
import 'intermediate_constraints.dart';
import 'intermediate_edges.dart';
import 'intermediate_labels.dart';
import 'intermediate_ports.dart'
    hide portConstraints, PortConstraints;
// Alias the intermediate_ports symbols we DO need under different names so that
// we can still call setProperty with the PortSideProcessor-compatible type.
// We achieve this by importing again with a prefix just for the constraint type.
import 'intermediate_ports.dart' as _ports;
import 'intermediate_selfloops.dart';
import 'intermediate_sizing.dart';
import 'lgraph.dart';
import 'property.dart';
import 'p1_greedy_cycle_breaker.dart';
import 'p2_network_simplex_layerer.dart';
import 'p3_layer_sweep_crossing_minimizer.dart';
import 'p4_bk_node_placer.dart';
import 'p5_orthogonal_routing.dart';
import 'phase.dart';

/// Padding added around a compound node's nested content (ELK's default node
/// padding for a hierarchical node).
const double _compoundPadding = 12;

/// Extra vertical margin added below a compound label band (so the title isn't
/// flush against the first child row).
const double _labelBandMargin = 6;

/// A feature of [graph] the faithful port doesn't implement yet, or null.
/// Used to fail honestly instead of silently producing a non-ELK layout.
String? unsupportedElkFeature(ElkGraph graph) {
  String? scan(List<ElkNode> nodes) {
    for (final n in nodes) {
      // Explicit ports are now supported — no longer an unsupported feature.
      final r = scan(n.children);
      if (r != null) return r;
    }
    return null;
  }

  return scan(graph.children);
}

/// Lays out [graph] with the faithful ELK-layered pipeline.
///
/// Throws [UnsupportedError] for graph features not yet ported (self-loops,
/// edge labels, model order) — there is deliberately **no dagre fallback**,
/// so output is always genuine ELK or an explicit error.
ElkResult layeredLayout(ElkGraph graph) {
  final unsupported = unsupportedElkFeature(graph);
  if (unsupported != null) {
    throw UnsupportedError(
        'elk: $unsupported is not yet implemented in the faithful ELK '
        'port (no dagre fallback by design). See lib/src/layered/PORTING.md.');
  }
  final dir = graph.layoutOptions.direction;
  // Internal flow is always RIGHT; DOWN/UP transpose the axes, LEFT/UP mirror.
  final transpose = dir == ElkDirection.down || dir == ElkDirection.up;

  final engine = _Engine(graph.layoutOptions, transpose, dir);

  // Build the (possibly hierarchical) LGraph; lay it out.
  final root = engine.buildGraph(graph.children, graph.edges);
  engine.layoutHierarchy(root);

  // Extract the root graph into the result tree.
  return engine.extractRoot(root);
}

/// Maps a declared [ElkPortSide] (in output space) to the internal [PortSide]
/// (in RIGHT-flow internal space) by applying the inverse of the output
/// transform.
///
/// The output transform is:
///   - `transpose` (DOWN/UP): internal-X → output-Y, internal-Y → output-X
///   - `dir == left`:  output-X is mirrored (large internal-X → small output-X)
///   - `dir == up`:    output-Y is mirrored (large internal-Y → small output-Y)
///
/// Inverse mapping:
///
///   DOWN:  output-EAST  (large output-X) → large internal-Y → internal-SOUTH
///          output-WEST  → internal-NORTH
///          output-SOUTH (large output-Y) → large internal-X → internal-EAST
///          output-NORTH → internal-WEST
///
///   RIGHT: no transpose, no mirror → sides are identical.
///
///   LEFT:  no transpose, X mirrored → EAST↔WEST flip.
///
///   UP:    transpose + Y mirror
///          output-EAST  → large internal-Y → internal-SOUTH
///          output-WEST  → internal-NORTH
///          output-SOUTH → internal-EAST
///          output-NORTH → internal-WEST
///          (same as DOWN because UP = transpose + mirror-Y; the Y-mirror is in
///           the output coordinate, not in the side orientation)
PortSide _outputSideToInternal(
    ElkPortSide side, bool transpose, ElkDirection dir) {
  if (transpose) {
    // DOWN and UP both swap X↔Y axes (Y-mirror in UP doesn't flip EAST/WEST).
    return switch (side) {
      ElkPortSide.east => PortSide.south,
      ElkPortSide.west => PortSide.north,
      ElkPortSide.south => PortSide.east,
      ElkPortSide.north => PortSide.west,
    };
  }
  if (dir == ElkDirection.left) {
    // X is mirrored: EAST and WEST flip.
    return switch (side) {
      ElkPortSide.east => PortSide.west,
      ElkPortSide.west => PortSide.east,
      ElkPortSide.north => PortSide.north,
      ElkPortSide.south => PortSide.south,
    };
  }
  // RIGHT (default): output space == internal space.
  return switch (side) {
    ElkPortSide.east => PortSide.east,
    ElkPortSide.west => PortSide.west,
    ElkPortSide.north => PortSide.north,
    ElkPortSide.south => PortSide.south,
  };
}

/// A lightweight pipeline processor injected just before [PortSideProcessor].
///
/// It marks nodes in [fixedSideNodes] with `portConstraints = FIXED_SIDE`,
/// using [_ports.portConstraints] (the intermediate_ports type) so that
/// [PortSideProcessor] — which reads the same property with that type — will
/// respect the explicitly pre-set port sides and not override them.
///
/// This must run AFTER [EdgeAndLayerConstraintEdgeReverser] (which reads
/// portConstraints using intermediate_constraints' type; when the property is
/// unset at that point, it safely defaults to `free`).
class _MarkFixedSideConstraints implements ILayoutProcessor {
  _MarkFixedSideConstraints(this.fixedSideNodes);
  final Set<LNode> fixedSideNodes;

  @override
  void process(LGraph graph) {
    for (final ln in fixedSideNodes) {
      if (ln.graph == graph) {
        ln.setProperty(
            _ports.portConstraints, _ports.PortConstraints.fixedSide);
      }
    }
  }
}

/// A lightweight pipeline processor injected just after [LabelAndNodeSizeProcessor].
///
/// [LabelAndNodeSizeProcessor] only places EAST and WEST ports (vertical free
/// placement). Ports on NORTH/SOUTH sides in internal space — which arise when
/// the output direction transposes the axes (DOWN/UP flow) and the caller
/// declares an explicit side that maps to NORTH or SOUTH internally — need
/// their positions set here.
///
/// For NORTH ports: port.position.y = -port.size.y (above the node top edge).
/// For SOUTH ports: port.position.y = node.size.y (below the node bottom edge).
/// Ports are centred horizontally (x = (node.size.x - port.size.x) / 2).
/// Anchor: the edge connects at the horizontal centre of the port face
/// adjacent to the node border.
class _PlaceNorthSouthPorts implements ILayoutProcessor {
  _PlaceNorthSouthPorts(this.declaredPortsById);
  final Map<LNode, Map<String, LPort>> declaredPortsById;

  @override
  void process(LGraph graph) {
    for (final layer in graph.layers) {
      for (final node in layer.nodes) {
        _processNode(node);
      }
    }
  }

  void _processNode(LNode node) {
    // Only declared ports need this treatment; auto-created ports are always
    // EAST or WEST and handled by LabelAndNodeSizeProcessor.
    final portMap = declaredPortsById[node];
    if (portMap == null) return;

    for (final lp in portMap.values) {
      if (lp.side == PortSide.north) {
        // Above the node's top edge.
        lp.position.x = (node.size.x - lp.size.x) / 2;
        lp.position.y = -lp.size.y;
        // Anchor: bottom-centre of the port (where the edge attaches).
        lp.anchor.x = lp.size.x / 2;
        lp.anchor.y = lp.size.y;
      } else if (lp.side == PortSide.south) {
        // Below the node's bottom edge.
        lp.position.x = (node.size.x - lp.size.x) / 2;
        lp.position.y = node.size.y;
        // Anchor: top-centre of the port (where the edge attaches).
        lp.anchor.x = lp.size.x / 2;
        lp.anchor.y = 0;
      }
      // EAST and WEST are already handled by LabelAndNodeSizeProcessor.
    }
  }
}

/// Links a cluster's external [LPort] to the external-port dummy inside its
/// nested graph. After the nested graph is laid out, the dummy's resolved
/// cross-axis position is copied onto the port so the parent routes the outer
/// segment to the same border point. [east] = the port is on the cluster's east
/// (output) side; otherwise west (input).
class _PortLink {
  _PortLink(this.port, this.dummy, this.east);
  final LPort port;
  final LNode dummy;
  final bool east;
}

/// A cluster border dummy with the cross-axis rank its external port's
/// parent-side neighbour was assigned (used by the INCLUDE_CHILDREN
/// coordination to order border dummies the way the parent ordered the edges).
class _RankedDummy {
  _RankedDummy(this.dummy, this.rank);
  final LNode dummy;
  final double rank;
}

/// Per-run layout engine. Holds the shared options/transform and the mapping
/// from input ids to [LNode]s so cross-references (edges) can be resolved
/// within each hierarchy level.
class _Engine {
  _Engine(this.options, this.transpose, this.dir);

  final ElkLayoutOptions options;
  final bool transpose;
  final ElkDirection dir;

  /// Original (untransposed) sizes of normal nodes, keyed by their [LNode].
  final Map<LNode, (double, double)> origSize = {};

  /// Running model (declaration) order index assigned to each built [LNode].
  int _modelOrderCounter = 0;

  /// Per-graph: id → LNode for the nodes directly in that graph.
  final Map<LGraph, Map<String, LNode>> nodesByGraph = {};

  /// Per-graph: edge id → LEdge for the edges directly in that graph.
  final Map<LGraph, Map<String, LEdge>> edgesByGraph = {};

  /// Per-node: declared port id → LPort (only for explicitly declared ports).
  /// Used both for edge resolution and for result extraction.
  final Map<LNode, Map<String, LPort>> declaredPortsById = {};

  /// Nodes that have at least one explicitly-declared port with a fixed side.
  /// Used by [_MarkFixedSideConstraints] to set portConstraints just before
  /// [PortSideProcessor] runs (so PortSideProcessor won't override explicit sides).
  final Set<LNode> _nodesWithFixedSides = {};

  /// Per-graph: this graph's direct-child input [ElkNode]s (for descent during
  /// cross-hierarchy edge splitting).
  final Map<LGraph, List<ElkNode>> _graphElkNodes = {};

  /// Per-graph: declared port id → owning [LNode] for that graph's direct
  /// children (mirror of buildGraph's local `portNodeById`).
  final Map<LGraph, Map<String, LNode>> _graphPortNode = {};

  /// Cross-hierarchy edges split into per-graph segments. Maps the original
  /// edge id to its ordered chain of [LEdge] segments (source→target). Each
  /// segment lives in some graph's edge map and is collected with root-absolute
  /// points during extraction; [_collectEdges] accumulates those points into
  /// [_crossSegmentPoints] keyed by segment instead of emitting them, and
  /// [extractRoot] concatenates them into one [ElkPositionedEdge].
  final Map<String, List<LEdge>> _crossSegments = {};

  /// Labels carried by a split cross-hierarchy edge (attached to the original
  /// edge, emitted once after stitching).
  final Map<String, List<LLabel>> _crossLabels = {};

  /// Segment [LEdge]s that belong to a split cross-hierarchy edge — so
  /// [_collectEdges] knows to accumulate rather than emit them.
  final Set<LEdge> _crossSegmentEdges = {};

  /// Accumulated root-absolute polyline for each cross-hierarchy segment.
  final Map<LEdge, List<ElkPoint>> _crossSegmentPoints = {};

  /// Deferred links: after a nested graph is laid out, copy each external-port
  /// dummy's resolved border position onto the cluster's external [LPort].
  final List<_PortLink> _portLinks = [];

  /// Output-space band (height) reserved at the top of a compound node for its
  /// label (subgraph title). ELK upstream reserves this via node labels with
  /// `nodeLabels.placement = INSIDE V_TOP`; we model it as an empty band so
  /// edges/children never overlap the title. Keyed by the compound [LNode].
  final Map<LNode, double> _compoundBand = {};

  /// Builds an [LGraph] from a level's [nodes] and [edges]. Compound children
  /// recurse into a [LNode.nestedGraph]. Edges are placed in the graph that
  /// directly contains both endpoints; cross-hierarchy edges are routed to the
  /// nearest enclosing cluster boundary, or skipped if truly cross-level.
  LGraph buildGraph(List<ElkNode> nodes, List<ElkEdge> edges) {
    final lg = LGraph();
    // Apply the resolved spacing from the public options. These derive from
    // `spacingBaseValue` (default 40) when not explicitly overridden — ELK's raw
    // defaults (20/10) are too tight and let dense graphs overlap; the
    // baseValue-derived spacing (matching mermaid-layout-elk) gives breathing
    // room. The BK placer reads the node/layer props; the orthogonal router
    // reads the edge props.
    lg.setProperty(const Property<double>('bk.spacing.nodeNode'),
        options.resolvedNodeNode);
    lg.setProperty(const Property<double>('bk.spacing.layer'),
        options.resolvedNodeNodeBetweenLayers);
    lg.setProperty(const Property<double>('p5.spacing.edgeEdge'),
        options.resolvedEdgeNode);
    lg.setProperty(const Property<double>('p5.spacing.edgeNode'),
        options.resolvedEdgeNode);
    // Model order: the crossing minimizer reads these to keep nodes in input
    // declaration order (ELK's considerModelOrder / forceNodeModelOrder).
    if (options.considerModelOrder != ElkConsiderModelOrder.none ||
        options.forceNodeModelOrder) {
      lg.setProperty(considerModelOrder, true);
    }
    if (options.forceNodeModelOrder) {
      lg.setProperty(forceNodeModelOrder, true);
    }

    // LCA edge assignment (faithful to ELK, where an edge belongs to the
    // lowest common ancestor graph of its endpoints regardless of which graph
    // it was declared in). Partition the incoming edges: an edge whose *both*
    // endpoints lie inside a single compound child is owned by that child's
    // nested graph (push it down); everything else is owned at this level.
    final ownedHere = <ElkEdge>[];
    final perChild = <String, List<ElkEdge>>{};
    for (final e in edges) {
      ElkNode? owner;
      for (final n in nodes) {
        if (n.children.isEmpty) continue; // leaves can't own (self-loops stay here)
        if (_endpointInSubtree(n, e.source) && _endpointInSubtree(n, e.target)) {
          owner = n;
          break;
        }
      }
      if (owner != null) {
        (perChild[owner.id] ??= []).add(e);
      } else {
        ownedHere.add(e);
      }
    }

    final byId = <String, LNode>{};
    nodesByGraph[lg] = byId;
    _graphElkNodes[lg] = nodes;

    // portNodeById: declared port id → owning LNode (for edge endpoint resolution).
    final portNodeById = <String, LNode>{};
    _graphPortNode[lg] = portNodeById;

    for (final n in nodes) {
      final ln = LNode(lg)..identifier = n.id;
      ln.setProperty(modelOrder, _modelOrderCounter++);
      byId[n.id] = ln;
      if (n.isCompound) {
        // Recurse: nested graph holds this node's own declared edges plus the
        // edges routed down to it by LCA assignment above.
        ln.nestedGraph =
            buildGraph(n.children, [...n.edges, ...?perChild[n.id]]);
        // Size is computed bottom-up after the nested layout; placeholder now.
        ln.size.x = 0;
        ln.size.y = 0;
        // Reserve a top band for the compound's label (subgraph title), so no
        // edge or child is laid out over it (faithful to upstream's INSIDE
        // V_TOP node-label placement).
        if (n.labels.isNotEmpty) {
          var h = 0.0;
          for (final l in n.labels) {
            if (l.height > h) h = l.height;
          }
          if (h > 0) _compoundBand[ln] = h + _labelBandMargin;
        }
      } else {
        origSize[ln] = (n.width, n.height);
        // Internal RIGHT space: transpose swaps width/height.
        ln.size.x = transpose ? n.height : n.width;
        ln.size.y = transpose ? n.width : n.height;
      }

      // Build declared LPorts for this node.
      if (n.ports.isNotEmpty) {
        final portMap = <String, LPort>{};
        declaredPortsById[ln] = portMap;
        var hasFixedSide = false;

        for (final ep in n.ports) {
          final lp = LPort(ln)..identifier = ep.id;
          portMap[ep.id] = lp;
          portNodeById[ep.id] = ln;

          if (ep.side != null) {
            lp.side = _outputSideToInternal(ep.side!, transpose, dir);
            hasFixedSide = true;
          }
          // Port size in internal space (transposed like the node).
          lp.size.x = transpose ? ep.height : ep.width;
          lp.size.y = transpose ? ep.width : ep.height;
          ln.ports.add(lp);
        }

        if (hasFixedSide) {
          // Track this node so _MarkFixedSideConstraints can set its
          // portConstraints (using the intermediate_ports type) just before
          // PortSideProcessor runs — preventing side overrides.
          _nodesWithFixedSides.add(ln);
        }
      }

      lg.layerlessNodes.add(ln);
    }

    // Resolve edges. An edge belongs to the graph that directly contains both
    // endpoints (by descendant containment). Endpoints may name a node or a
    // declared port; if a port id is found, reuse that LPort.
    final edgeMap = <String, LEdge>{};
    edgesByGraph[lg] = edgeMap;
    for (final e in ownedHere) {
      // Resolve source: may be a port id (use its node) or a node id directly.
      final sn = _resolveDirectChild(byId, portNodeById, nodes, e.source);
      final tn = _resolveDirectChild(byId, portNodeById, nodes, e.target);
      if (sn == null || tn == null) {
        // TODO(elk-faithful): truly cross-level edge (an endpoint is neither a
        // direct child of this graph nor reachable via a single enclosing
        // cluster at this level). ELK handles these with
        // CompoundGraphPreprocessor (CrossHierarchyEdge), splitting the edge at
        // each hierarchy crossing; here we skip routing it rather than
        // mis-route.
        continue;
      }
      if (sn == tn) {
        final node = byId[sn];
        if (node != null && e.source == e.target) {
          // A true self-loop: both ports on the same node (the self-loop
          // processors detach, route, and reattach it).
          final sp = LPort(node)..side = PortSide.north;
          node.ports.add(sp);
          final tp = LPort(node)..side = PortSide.north;
          node.ports.add(tp);
          final le = LEdge()..identifier = e.id;
          le.source = sp;
          le.target = tp;
          _attachLabels(le, e);
          edgeMap[e.id] = le;
        }
        // else: edge internal to a compound cluster — routed in the nested
        // graph, not at this level.
        continue;
      }
      final ln = byId[sn]!;
      final rn = byId[tn]!;
      final sChildElk = nodes.firstWhere((n) => n.id == sn);
      final tChildElk = nodes.firstWhere((n) => n.id == tn);

      // Cross-hierarchy splitting: if an endpoint lies one level inside a
      // compound child, split the edge through an external port on the cluster
      // and an external-port dummy inside its nested graph (faithful to ELK's
      // external-port mechanism). srcSegs precede the LCA segment, tgtSegs
      // follow it; together they form the edge's full polyline after stitching.
      final srcSegs = <LEdge>[];
      final tgtSegs = <LEdge>[];
      final sp = _endpointPort(ln, sChildElk, e.source, true, srcSegs);
      final tp = _endpointPort(rn, tChildElk, e.target, false, tgtSegs);

      if (sp == null || tp == null) {
        // Endpoint is deeper than one level inside a cluster — not yet ported.
        // Fall back to routing to the cluster boundary (no inner segment).
        final fsp = _resolveOrCreatePort(ln, e.source, PortSide.east);
        final ftp = _resolveOrCreatePort(rn, e.target, PortSide.west);
        final le = LEdge()..identifier = e.id;
        le.source = fsp;
        le.target = ftp;
        _attachLabels(le, e);
        edgeMap[e.id] = le;
        continue;
      }

      final le = LEdge()..identifier = e.id;
      le.source = sp;
      le.target = tp;

      if (srcSegs.isEmpty && tgtSegs.isEmpty) {
        // Same-level edge between two direct children — the classic case.
        _attachLabels(le, e);
        edgeMap[e.id] = le;
      } else {
        // Cross-hierarchy: `le` is the segment at this (LCA) level. Register the
        // full source→target chain for stitching, and mark every segment so the
        // extractor accumulates rather than emits it.
        edgeMap['__seg${_segCounter++}'] = le;
        _crossSegmentEdges.add(le);
        for (final s in [...srcSegs, ...tgtSegs]) {
          _crossSegmentEdges.add(s);
        }
        _crossSegments[e.id] = [...srcSegs, le, ...tgtSegs];
        final holder = LEdge();
        _attachLabels(holder, e);
        _crossLabels[e.id] = holder.labels;
      }
    }

    return lg;
  }

  /// Returns the [LPort] for [endpoint] on [node] if it is a declared port id,
  /// otherwise creates a new per-edge port with [defaultSide].
  ///
  /// Declared ports are reused across multiple edges (a single port may carry
  /// several edges). Auto-created ports are added to the node's port list.
  LPort _resolveOrCreatePort(
      LNode node, String endpoint, PortSide defaultSide) {
    final portMap = declaredPortsById[node];
    if (portMap != null) {
      final existing = portMap[endpoint];
      if (existing != null) return existing;
    }
    // Auto-create a per-edge port (not declared, not tracked for extraction).
    final p = LPort(node)..side = defaultSide;
    node.ports.add(p);
    return p;
  }

  /// Counter for synthetic segment edge ids (cross-hierarchy splits).
  int _segCounter = 0;

  /// Resolves [endpoint] to an [LPort] usable at the current graph level, when
  /// building an edge owned at this level. [childLn]/[childElk] is the direct
  /// child the endpoint resolves to.
  ///
  /// - If the endpoint *is* that child (its node id or one of its own declared
  ///   ports), returns the port directly — no split.
  /// - If the endpoint lies exactly one level inside a compound child, splits
  ///   the edge: mints an external port on the cluster (EAST for a source /
  ///   output, WEST for a target / input) and an external-port dummy inside the
  ///   nested graph (constrained to the last/first layer so it sits on the
  ///   border), connects the real inner node to the dummy, appends that inner
  ///   segment to [segs], and returns the cluster's external port.
  /// - If the endpoint is deeper than one level, returns null (caller falls back
  ///   to boundary routing — faithful multi-level splitting is a TODO).
  LPort? _endpointPort(LNode childLn, ElkNode childElk, String endpoint,
      bool isSource, List<LEdge> segs) {
    final isChildItself =
        childElk.id == endpoint || childElk.ports.any((p) => p.id == endpoint);
    if (isChildItself) {
      return _resolveOrCreatePort(
          childLn, endpoint, isSource ? PortSide.east : PortSide.west);
    }

    final nested = childLn.nestedGraph;
    if (nested == null) return null;

    // Find the inner LNode if the endpoint is a direct child (node or port) of
    // the cluster's nested graph (one-level crossing).
    LNode? innerLn;
    for (final c in childElk.children) {
      if (c.id == endpoint) {
        innerLn = nodesByGraph[nested]![c.id];
        break;
      }
      if (c.ports.any((p) => p.id == endpoint)) {
        innerLn = _graphPortNode[nested]![endpoint];
        break;
      }
    }
    if (innerLn == null) return null; // deeper than one level → fallback

    // External port on the cluster + external-port dummy inside the nested graph.
    final p = LPort(childLn)..side = isSource ? PortSide.east : PortSide.west;
    p.setProperty(crossHierarchyFixedPort, true);
    childLn.ports.add(p);
    _nodesWithFixedSides.add(childLn);

    final d = LNode(nested)..type = NodeType.externalPort;
    d.setProperty(layerConstraint,
        isSource ? LayerConstraint.lastSeparate : LayerConstraint.firstSeparate);
    final dPort = LPort(d)..side = isSource ? PortSide.west : PortSide.east;
    d.ports.add(dPort);
    nested.layerlessNodes.add(d);
    _portLinks.add(_PortLink(p, d, isSource));

    // Inner segment connecting the real node to the boundary dummy.
    final innerPort = _resolveOrCreatePort(
        innerLn, endpoint, isSource ? PortSide.east : PortSide.west);
    final seg = LEdge();
    if (isSource) {
      seg.source = innerPort;
      seg.target = dPort;
    } else {
      seg.source = dPort;
      seg.target = innerPort;
    }
    edgesByGraph[nested]!['__seg${_segCounter++}'] = seg;
    segs.add(seg);
    return p;
  }

  /// Copies the public edge's labels onto the [LEdge] so LabelDummyInserter can
  /// reserve space for them; sizes are in internal (RIGHT) space (transposed).
  void _attachLabels(LEdge le, ElkEdge e) {
    for (final el in e.labels) {
      final ll = LLabel(el.text);
      ll.size.x = transpose ? el.height : el.width;
      ll.size.y = transpose ? el.width : el.height;
      le.labels.add(ll);
    }
  }

  /// Maps an endpoint id to the direct child of this level that contains it
  /// (the nearest enclosing cluster boundary), or null if it lies outside this
  /// level entirely. [nodes] is this level's input node list (for descent).
  /// [portNodeById] maps declared port ids to their owning nodes at this level.
  String? _resolveDirectChild(
      Map<String, LNode> byId,
      Map<String, LNode> portNodeById,
      List<ElkNode> nodes,
      String endpoint) {
    // Direct hit on a node id.
    if (byId.containsKey(endpoint)) return endpoint;
    // Direct hit on a declared port at this level.
    final portNode = portNodeById[endpoint];
    if (portNode != null) return portNode.identifier!;
    // Search each direct child for the endpoint among its descendants (nodes
    // or ports). If found, route to that direct child's boundary.
    for (final n in nodes) {
      if (_containsDescendant(n, endpoint)) return n.id;
    }
    return null;
  }

  /// Whether [endpoint] names [node] itself, one of its ports, or any
  /// descendant node/port — i.e. the endpoint lies within [node]'s subtree.
  /// Used by LCA edge assignment.
  bool _endpointInSubtree(ElkNode node, String endpoint) {
    if (node.id == endpoint) return true;
    for (final p in node.ports) {
      if (p.id == endpoint) return true;
    }
    return _containsDescendant(node, endpoint);
  }

  /// Whether [endpoint] names a descendant node or port of [node] (excluding
  /// [node] itself, which is handled by the direct-hit check).
  bool _containsDescendant(ElkNode node, String endpoint) {
    for (final c in node.children) {
      if (c.id == endpoint) return true;
      for (final p in c.ports) {
        if (p.id == endpoint) return true;
      }
      if (_containsDescendant(c, endpoint)) return true;
    }
    return false;
  }

  /// Processors that run *before* crossing minimization (cycle breaking,
  /// layering, long-edge split, port side assignment + sort). They are
  /// order-based — they need no node sizes — so they can run on every graph in
  /// the hierarchy before any placement happens.
  List<ILayoutProcessor> _preCrossminProcessors() => [
        // self-loops detached before everything else
        SelfLoopPreProcessor(),
        // before P1
        EdgeAndLayerConstraintEdgeReverser(),
        // P1
        GreedyCycleBreaker(),
        // before P2
        LayerConstraintPreprocessor(),
        LabelDummyInserter(),
        // P2
        NetworkSimplexLayerer(),
        // before P3 (enum order: long-edge split, port side, inverted, port sort)
        LayerConstraintPostprocessor(),
        LongEdgeSplitter(),
        // Set portConstraints = FIXED_SIDE (using intermediate_ports type) for
        // nodes with declared sides, just before PortSideProcessor reads it.
        // This must run AFTER EdgeAndLayerConstraintEdgeReverser (which reads the
        // property using intermediate_constraints' type — safely unset until here).
        _MarkFixedSideConstraints(_nodesWithFixedSides),
        PortSideProcessor(),
        InvertedPortProcessor(),
        PortListSorter(),
      ];

  /// Processors that run *after* crossing minimization (margins, sizing,
  /// placement, routing). Placement needs each compound child's size, so this
  /// segment runs bottom-up.
  List<ILayoutProcessor> _postCrossminProcessors() => [
        // before P4
        InnermostNodeMarginCalculator(),
        LabelAndNodeSizeProcessor(),
        // Place NORTH/SOUTH ports (transposed-axis cases) that
        // LabelAndNodeSizeProcessor doesn't handle.
        _PlaceNorthSouthPorts(declaredPortsById),
        InLayerConstraintProcessor(),
        HyperedgeDummyMerger(),
        // P4
        BKNodePlacer(),
        // before P5
        LayerSizeAndGraphHeightCalculator(),
        // P5
        OrthogonalRoutingGenerator(),
        // after P5: route self-loops, extract label positions, then rejoin
        // long-edge/label dummies and restore reversed edges.
        SelfLoopRouter(),
        SelfLoopPostProcessor(),
        LabelDummyRemover(),
        LongEdgeJoiner(),
        ReversedEdgeRestorer(),
      ];

  void _runProcessors(List<ILayoutProcessor> ps, LGraph lg) {
    for (final p in ps) {
      p.process(lg);
    }
  }

  /// Lays out a (possibly hierarchical) graph in three phases. Splitting the
  /// per-graph pipeline at crossing minimization lets P3 run as ONE
  /// hierarchy-coordinated pass over all graphs (ELK's INCLUDE_CHILDREN), while
  /// the order-based pre-P3 work and the size-dependent post-P3 work stay
  /// per-graph. For a flat graph this is identical to running the single
  /// pipeline once.
  void layoutHierarchy(LGraph root) {
    _phasePreCrossmin(root); // cycle-break → layer → port sides, every graph
    _phaseCrossmin(root); // crossing minimization, every graph
    _coordinateExternalPortOrder(root); // INCLUDE_CHILDREN: parent drives child
    _phasePostCrossmin(root); // size → place → route, bottom-up
  }

  /// ELK INCLUDE_CHILDREN coordination (top-down). After crossing minimization,
  /// each compound child's *border dummies* (the external-port dummies pinned to
  /// its first/last layer) are reordered to match the order the parent assigned
  /// to the corresponding external ports — i.e. the cross-axis order in which
  /// the cross-hierarchy edges arrive at the cluster border. Because the inner
  /// nodes' port order is taken from the neighbouring (border-dummy) order in
  /// `_placeVerticalFreePorts`, this makes edges enter/leave a cluster in the
  /// same order their far endpoints sit at the parent level — removing the
  /// crossings our independent per-graph sweep produced (#3/#4).
  ///
  /// Faithful to ELK's bottom-up/top-down hierarchical sweep in effect: the
  /// parent's order is the authority for a cluster's boundary. We apply it
  /// top-down (root first) so deeper clusters inherit the coordinated order.
  void _coordinateExternalPortOrder(LGraph lg) {
    for (final nested in _nestedGraphsOf(lg).toList()) {
      _reorderBorderDummies(nested);
      _coordinateExternalPortOrder(nested);
    }
  }

  /// Reorders [nested]'s border dummies (grouped by the layer they sit in) by
  /// the cross-axis order of their external port's parent-side neighbour.
  void _reorderBorderDummies(LGraph nested) {
    // Average within-layer index of the parent-side neighbours of [port].
    double? parentRank(LPort port, bool east) {
      final edges = east ? port.outgoingEdges : port.incomingEdges;
      final idxs = <int>[];
      for (final e in edges) {
        final n = east ? e.target?.node : e.source?.node;
        final i = n?.index ?? -1;
        if (i >= 0) idxs.add(i);
      }
      if (idxs.isEmpty) return null;
      return idxs.reduce((a, b) => a + b) / idxs.length;
    }

    // Collect this cluster's border dummies with their desired rank.
    final ranked = <_RankedDummy>[];
    for (final link in _portLinks) {
      if (link.dummy.graph != nested) continue;
      final rank = parentRank(link.port, link.east);
      if (rank != null) ranked.add(_RankedDummy(link.dummy, rank));
    }
    if (ranked.length < 2) return;

    // Reorder within each border layer independently, keeping the slots that
    // border dummies occupy (any non-dummy nodes in the layer stay put).
    final byLayer = <Layer, List<_RankedDummy>>{};
    for (final r in ranked) {
      final layer = r.dummy.layer;
      if (layer != null) (byLayer[layer] ??= []).add(r);
    }
    for (final entry in byLayer.entries) {
      final layer = entry.key;
      final group = entry.value;
      if (group.length < 2) continue;
      final dummySet = {for (final r in group) r.dummy};
      // Positions (within layer.nodes) currently occupied by these dummies.
      final slots = <int>[];
      for (var i = 0; i < layer.nodes.length; i++) {
        if (dummySet.contains(layer.nodes[i])) slots.add(i);
      }
      group.sort((a, b) => a.rank.compareTo(b.rank));
      for (var k = 0; k < slots.length; k++) {
        layer.nodes[slots[k]] = group[k].dummy;
      }
    }
  }

  /// All nested (compound child) graphs of [lg]. A node may be layerless
  /// (before layering, phase A) or already in a layer (after layering, phases
  /// B/C), so both are scanned.
  Iterable<LGraph> _nestedGraphsOf(LGraph lg) sync* {
    for (final ln in lg.layerlessNodes) {
      if (ln.nestedGraph != null) yield ln.nestedGraph!;
    }
    for (final layer in lg.layers) {
      for (final ln in layer.nodes) {
        if (ln.nestedGraph != null) yield ln.nestedGraph!;
      }
    }
  }

  /// Phase A: run the pre-crossmin processors on every graph in the hierarchy.
  void _phasePreCrossmin(LGraph lg) {
    for (final nested in _nestedGraphsOf(lg)) {
      _phasePreCrossmin(nested);
    }
    _runProcessors(_preCrossminProcessors(), lg);
  }

  /// Phase B: crossing minimization. C2a runs it per graph (no coordination
  /// yet — behaviour-identical to the old single pipeline); C2b adds the
  /// top-down external-port-order coordination here.
  void _phaseCrossmin(LGraph lg) {
    LayerSweepCrossingMinimizer().process(lg);
    for (final nested in _nestedGraphsOf(lg)) {
      _phaseCrossmin(nested);
    }
  }

  /// Phase C: post-crossmin (size + place + route), bottom-up so each compound
  /// child is laid out and sized before its parent is placed.
  void _phasePostCrossmin(LGraph lg) {
    for (final ln in [
      for (final layer in lg.layers) ...layer.nodes,
      ...lg.layerlessNodes,
    ]) {
      final nested = ln.nestedGraph;
      if (nested == null) continue;
      _phasePostCrossmin(nested);
      final (w, h) = _internalBounds(nested);
      // The compound node's internal-space size = nested bbox + padding on all
      // sides. (Internal space is RIGHT; the nested bbox is already in it.)
      ln.size.x = w + 2 * _compoundPadding;
      ln.size.y = h + 2 * _compoundPadding;
      // Reserve the label band on the OUTPUT-top side. Output-top maps to the
      // internal flow axis (X) when transposed (DOWN/UP), else the cross axis
      // (Y). The children are pushed off the band at extraction; here we only
      // grow the compound so the parent reserves room for it.
      final band = _compoundBand[ln] ?? 0;
      if (band > 0) {
        if (transpose) {
          ln.size.x += band;
        } else {
          ln.size.y += band;
        }
      }

      // Cross-hierarchy: copy each boundary dummy's resolved cross position onto
      // the cluster's external port so the parent routes the outer segment to
      // the matching border point.
      final (_, nOy) = _internalOrigin(nested);
      for (final link in _portLinks) {
        if (link.dummy.graph != nested) continue;
        // The dummy's connection point (its inward port anchor) in nested space,
        // mapped into the cluster's own frame (content origin → +padding).
        // The dummy's port can be absent if a processor removed it; fall back to
        // the dummy's own position rather than throwing.
        final dPort = link.dummy.ports.isEmpty ? null : link.dummy.ports.first;
        final dummyCrossY = link.dummy.position.y + (dPort?.anchor.y ?? 0);
        // For non-transposed flow (LR/RL) the label band is reserved on the
        // cross axis (size.y), and `childOut` shifts the children down by `band`
        // at extraction. The external port must shift by the same band, or the
        // inner segment meets the border at a band-sized offset from the cluster
        // port — a diagonal kink that the edge clip then snaps to the border
        // (cross-hierarchy edges appearing to stop at the cluster edge instead
        // of reaching the inner node). For transposed flow (DOWN/UP) the band is
        // on the flow axis and produces a clean stub, so no cross-axis shift.
        final crossBand = transpose ? 0.0 : band;
        link.port.position
          ..x = link.east ? ln.size.x : 0
          ..y = (dummyCrossY - nOy) + _compoundPadding + crossBand;
        // Anchor at the port's own position (size is zero), so the outer edge
        // segment meets the border exactly where the inner segment does.
        link.port.anchor
          ..x = 0
          ..y = 0;
      }
    }
    _runProcessors(_postCrossminProcessors(), lg);
  }

  /// Internal-space (RIGHT) bounding-box width/height of a laid-out graph,
  /// measured over its placed normal nodes (the same set the extractor uses).
  (double, double) _internalBounds(LGraph lg) {
    final placed = _placedNodes(lg);
    if (placed.isEmpty) return (0, 0);
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final ln in placed) {
      if (ln.position.x < minX) minX = ln.position.x;
      if (ln.position.y < minY) minY = ln.position.y;
      final r = ln.position.x + ln.size.x, b = ln.position.y + ln.size.y;
      if (r > maxX) maxX = r;
      if (b > maxY) maxY = b;
    }
    return (maxX - minX, maxY - minY);
  }

  /// The placed (layered) nodes of [lg], i.e. the original input nodes that the
  /// pipeline assigned to a layer (excludes algorithm dummies).
  List<LNode> _placedNodes(LGraph lg) {
    final byId = nodesByGraph[lg]!;
    return [
      for (final ln in byId.values)
        if (ln.layer != null) ln
    ];
  }

  /// Internal-space top-left origin of a laid-out graph (the min corner over
  /// its placed nodes; BK centering can push this negative).
  (double, double) _internalOrigin(LGraph lg) {
    final placed = _placedNodes(lg);
    if (placed.isEmpty) return (0, 0);
    var minX = double.infinity, minY = double.infinity;
    for (final ln in placed) {
      if (ln.position.x < minX) minX = ln.position.x;
      if (ln.position.y < minY) minY = ln.position.y;
    }
    return (minX, minY);
  }

  // --- Extraction --------------------------------------------------------

  /// Collected edges, in root output space, gathered while walking the tree.
  final List<ElkPositionedEdge> _edges = [];

  /// Extracts the root [LGraph] to an [ElkResult]. The root is laid out in
  /// internal RIGHT space and mapped to the requested output [dir]; nested
  /// children are emitted parent-relative (elkjs convention) while edges are
  /// collected in root-absolute output space.
  ElkResult extractRoot(LGraph root) {
    final (minX, minY) = _internalOrigin(root);
    final (iw, ih) = _internalBounds(root);
    final gw = transpose ? ih : iw;
    final gh = transpose ? iw : ih;

    // Map an internal point of the root to root output space.
    ElkPoint rootOut(double x, double y) {
      final nx = x - minX, ny = y - minY;
      var ox = transpose ? ny : nx;
      var oy = transpose ? nx : ny;
      if (dir == ElkDirection.left) ox = gw - ox;
      if (dir == ElkDirection.up) oy = gh - oy;
      return ElkPoint(ox, oy);
    }

    final nodes = <ElkPositionedNode>[
      for (final ln in _placedNodes(root)) _extractNode(ln, rootOut, 0, 0),
    ];
    _collectEdges(root, rootOut, 0, 0);

    // Stitch cross-hierarchy edges: concatenate each chain's per-segment
    // polylines (collected above in root-absolute coords) into one edge,
    // dropping duplicate points where segments meet at a cluster border.
    _stitchCrossEdges();

    return ElkResult(width: gw, height: gh, children: nodes, edges: _edges);
  }

  /// Extracts a single node (recursing into its nested graph if compound).
  ///
  /// [parentOut] maps a point in this node's *own graph's* internal space to
  /// output space relative to the node's parent. [absX]/[absY] are the node's
  /// parent's absolute (root-relative) output origin, used so collected edges
  /// land in root coordinates.
  ElkPositionedNode _extractNode(
    LNode ln,
    ElkPoint Function(double, double) parentOut,
    double absX,
    double absY,
  ) {
    final nested = ln.nestedGraph;
    if (nested == null) {
      final (w, h) = origSize[ln]!;
      final tl = parentOut(ln.position.x, ln.position.y);
      var x = tl.x, y = tl.y;
      // Mirror maps the top-left corner to the right/bottom; re-anchor.
      if (dir == ElkDirection.left) x -= w;
      if (dir == ElkDirection.up) y -= h;

      // Emit declared ports in output space (relative to this node's top-left).
      final ports = _extractDeclaredPorts(ln, x, y, w, h, parentOut);

      return ElkPositionedNode(
          id: ln.identifier!, x: x, y: y, width: w, height: h, ports: ports);
    }

    // Compound node: its own size in output space.
    final ow = transpose ? ln.size.y : ln.size.x;
    final oh = transpose ? ln.size.x : ln.size.y;
    final tl = parentOut(ln.position.x, ln.position.y);
    var x = tl.x, y = tl.y;
    if (dir == ElkDirection.left) x -= ow;
    if (dir == ElkDirection.up) y -= oh;

    // This node's absolute (root-relative) output origin.
    final myAbsX = absX + x;
    final myAbsY = absY + y;

    // Children are positioned parent-relative (elkjs convention): map them in
    // the nested graph's own internal space, mirror within the nested bbox,
    // then inset by the compound padding.
    final (nMinX, nMinY) = _internalOrigin(nested);
    final (niw, nih) = _internalBounds(nested);
    final ngw = transpose ? nih : niw;
    final ngh = transpose ? niw : nih;

    final band = _compoundBand[ln] ?? 0;
    ElkPoint childOut(double cx, double cy) {
      final nx = cx - nMinX, ny = cy - nMinY;
      var ox = transpose ? ny : nx;
      var oy = transpose ? nx : ny;
      if (dir == ElkDirection.left) ox = ngw - ox;
      if (dir == ElkDirection.up) oy = ngh - oy;
      // Push children below the reserved label band at output-top.
      return ElkPoint(ox + _compoundPadding, oy + _compoundPadding + band);
    }

    final children = <ElkPositionedNode>[
      for (final c in _placedNodes(nested))
        _extractNode(c, childOut, myAbsX, myAbsY),
    ];
    // Edges internal to this cluster, collected in root-absolute output space.
    _collectEdges(nested, childOut, myAbsX, myAbsY);

    // Emit declared ports for the compound node too (if any).
    final ports = _extractDeclaredPorts(ln, x, y, ow, oh, parentOut);

    return ElkPositionedNode(
      id: ln.identifier!,
      x: x,
      y: y,
      width: ow,
      height: oh,
      children: children,
      ports: ports,
    );
  }

  /// Extracts the declared [LPort]s of [ln] as [ElkPositionedPort]s, with
  /// positions relative to the node's output top-left corner ([nodeX], [nodeY]).
  ///
  /// [parentOut] maps internal points to parent-relative output space so we can
  /// find the port's absolute anchor position, then subtract the node's output
  /// origin.
  List<ElkPositionedPort> _extractDeclaredPorts(
    LNode ln,
    double nodeX,
    double nodeY,
    double nodeW,
    double nodeH,
    ElkPoint Function(double, double) parentOut,
  ) {
    final portMap = declaredPortsById[ln];
    if (portMap == null || portMap.isEmpty) return const [];

    final result = <ElkPositionedPort>[];
    for (final entry in portMap.entries) {
      final lp = entry.value;
      // The port's absolute internal anchor (node-position + port-position + anchor).
      final absAnchor = lp.absoluteAnchor;
      // Map through the same transform as the node's positions.
      final outputPt = parentOut(absAnchor.x, absAnchor.y);
      var px = outputPt.x, py = outputPt.y;
      // Output-space port size (un-transpose).
      final pw = transpose ? lp.size.y : lp.size.x;
      final ph = transpose ? lp.size.x : lp.size.y;
      // Apply the same re-anchoring as leaf nodes for mirrored directions.
      if (dir == ElkDirection.left) px -= pw;
      if (dir == ElkDirection.up) py -= ph;
      // Convert to node-relative.
      final relX = px - nodeX;
      final relY = py - nodeY;
      result.add(ElkPositionedPort(
        id: entry.key,
        x: relX,
        y: relY,
        width: pw,
        height: ph,
      ));
    }
    return result;
  }

  /// Collects the edges of [lg] into [_edges], in root-absolute output space.
  /// [localOut] maps an internal point of [lg] to output space relative to
  /// [lg]'s owning node; [absX]/[absY] is that node's absolute output origin.
  void _collectEdges(
    LGraph lg,
    ElkPoint Function(double, double) localOut,
    double absX,
    double absY,
  ) {
    final edgeMap = edgesByGraph[lg]!;
    for (final entry in edgeMap.entries) {
      final le = entry.value;
      final src = le.source, tgt = le.target;
      if (src == null || tgt == null) continue;
      ElkPoint at(double x, double y) {
        final p = localOut(x, y);
        return ElkPoint(p.x + absX, p.y + absY);
      }

      final pts = <ElkPoint>[
        at(src.absoluteAnchor.x, src.absoluteAnchor.y),
        for (final b in le.bendPoints.points) at(b.x, b.y),
        at(tgt.absoluteAnchor.x, tgt.absoluteAnchor.y),
      ];
      // Cross-hierarchy segment: accumulate its polyline for later stitching
      // rather than emitting it as a standalone edge.
      if (_crossSegmentEdges.contains(le)) {
        _crossSegmentPoints[le] = pts;
        continue;
      }
      // Edge labels (positioned by LabelDummyRemover into le.labels).
      final labels = <ElkPositionedLabel>[
        for (final ll in le.labels)
          () {
            final p = at(ll.position.x, ll.position.y);
            return ElkPositionedLabel(
              text: ll.text,
              x: p.x,
              y: p.y,
              width: transpose ? ll.size.y : ll.size.x,
              height: transpose ? ll.size.x : ll.size.y,
            );
          }(),
      ];
      _edges.add(ElkPositionedEdge(
        id: entry.key,
        sections: [
          ElkEdgeSection(
            startPoint: pts.first,
            endPoint: pts.last,
            bendPoints: pts.sublist(1, pts.length - 1),
          ),
        ],
        labels: labels,
      ));
    }
  }

  /// Concatenates the per-segment polylines of each split cross-hierarchy edge
  /// into a single [ElkPositionedEdge], in source→target order, de-duplicating
  /// the coincident points where two segments meet at a cluster border.
  void _stitchCrossEdges() {
    for (final entry in _crossSegments.entries) {
      final pts = <ElkPoint>[];
      for (final seg in entry.value) {
        final segPts = _crossSegmentPoints[seg];
        if (segPts == null) continue;
        for (final p in segPts) {
          if (pts.isNotEmpty &&
              (pts.last.x - p.x).abs() < 0.5 &&
              (pts.last.y - p.y).abs() < 0.5) {
            continue;
          }
          pts.add(p);
        }
      }
      if (pts.length < 2) continue;
      _edges.add(ElkPositionedEdge(
        id: entry.key,
        sections: [
          ElkEdgeSection(
            startPoint: pts.first,
            endPoint: pts.last,
            bendPoints: pts.sublist(1, pts.length - 1),
          ),
        ],
        // TODO(elk-faithful): position labels on split cross-hierarchy edges.
        labels: const [],
      ));
    }
  }
}

/// State diagram layout: dagre-positioned states with start/end/choice/
/// fork/join pseudo-state shapes and composite clusters, ported (simplified)
/// from upstream stateRenderer-v3-unified.
library;

import 'dart:math' as math;

import 'package:elk/elk.dart' as elk;

import '../../color.dart';
import '../../edge_geometry.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';
import '../../vendor/dagre/dart_dagre.dart' as dagre;
import '../flowchart/elk_adapter.dart';
import '../flowchart/flow_model.dart' show FlowDirection;
import 'state_model.dart';

const double _padding = 8;
const double _diagramPadding = 8;
const double _nodeSpacing = 50;
const double _rankSpacing = 50;
const double _clusterPadding = 10;

RenderScene layoutStateDiagram(
  StateDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
  String engine = 'auto',
  elk.ElkLayoutOptions? elkOptions,
}) {
  return _StateLayout(diagram, measurer, theme, engine,
          elkOptions ?? const elk.ElkLayoutOptions())
      .run();
}

class _Placed {
  _Placed(this.node, this.width, this.height, this.labelSize);

  final StateNode node;
  final double width;
  final double height;
  final Size labelSize;
  Point center = Point.zero;

  Rect get rect => Rect.fromCenter(center, width, height);
}

class _StateLayout {
  _StateLayout(this.diagram, this.measurer, this.theme, this.engine,
      this.elkOptions)
      : baseStyle = TextStyleSpec(
          fontFamily: theme.fontFamily,
          fontSize: theme.fontSize,
        );

  final StateDiagram diagram;
  final TextMeasurer measurer;
  final MermaidTheme theme;
  final String engine;
  final elk.ElkLayoutOptions elkOptions;
  final TextStyleSpec baseStyle;

  bool get hasNestedComposite => diagram.states.values.any((state) {
        if (state.kind != StateKind.composite || state.parent == null) {
          return false;
        }
        return diagram.states[state.parent]?.kind == StateKind.composite;
      });

  // Dagre's compound layout flattens the ranks of nested clusters through the
  // representative leaf nodes used for cross-cluster transitions. That places
  // sibling states beside nested composites and produces indirect curves.
  // ELK retains the state hierarchy for this case. Keep Dagre for diagrams
  // without nested composites so their established geometry does not change.
  bool get useElk =>
      engine == 'elk' || (engine == 'auto' && hasNestedComposite);

  final placed = <String, _Placed>{};
  final clusterRects = <String, Rect>{};

  bool get horizontal =>
      diagram.direction == FlowDirection.lr ||
      diagram.direction == FlowDirection.rl;

  /// A composite declared with an empty body (`state B { }`) has nothing to
  /// wrap, so it is laid out and drawn as an ordinary box instead of a
  /// cluster. Upstream does the same: `dataFetcher` marks it a group, but the
  /// renderer has no children to place inside it.
  bool _isEmptyComposite(StateNode s) =>
      s.kind == StateKind.composite && s.children.isEmpty;

  RenderScene run() {
    for (final s in diagram.states.values) {
      if (s.kind == StateKind.composite && !_isEmptyComposite(s)) continue;
      placed[s.id] = _measure(s);
    }
    final noteBoxes = <int, _Placed>{};
    for (var i = 0; i < diagram.notes.length; i++) {
      final n = diagram.notes[i];
      final size = measurer.measure(n.text, baseStyle, maxWidth: 200);
      noteBoxes[i] = _Placed(
        StateNode(id: '__note$i', label: n.text),
        size.width + 2 * _padding,
        size.height + 2 * _padding,
        size,
      );
    }

    // --- dagre ----------------------------------------------------------------
    // Order matters for the vendored compound support: member nodes first,
    // cluster nodes after (mirrors flow_layout).
    final g = dagre.DagreGraph();
    for (final p in placed.values) {
      g.addNode(dagre.DagreNode(p.node.id,
          width: p.width, height: p.height, parent: p.node.parent));
    }
    for (final s in diagram.states.values) {
      if (s.kind == StateKind.composite && !_isEmptyComposite(s)) {
        g.addNode(dagre.DagreNode(s.id, parent: s.parent));
      }
    }
    noteBoxes.forEach((i, b) {
      g.addNode(dagre.DagreNode(b.node.id, width: b.width, height: b.height));
    });

    String? representativeOf(String compositeId) {
      final children = diagram.states[compositeId]?.children ?? const [];
      for (final c in children) {
        if (placed.containsKey(c)) return c;
        final nested = representativeOf(c);
        if (nested != null) return nested;
      }
      return null;
    }

    (String, String?) endpoint(String id) {
      if (placed.containsKey(id)) return (id, null);
      final rep = representativeOf(id);
      return rep != null ? (rep, id) : (id, null);
    }

    final labelSizes = <int, Size>{};
    for (var i = 0; i < diagram.transitions.length; i++) {
      final t = diagram.transitions[i];
      Size? size;
      if (t.label != null && t.label!.isNotEmpty) {
        size = measurer.measure(t.label!, baseStyle, maxWidth: 200);
        labelSizes[i] = size;
      }
      final (from, _) = endpoint(t.from);
      final (to, _) = endpoint(t.to);
      // Self-transitions (including composite-to-itself) are routed manually
      // after layout, like flowchart self-loops.
      if (from == to) continue;
      g.addEdge(dagre.DagreEdge(
        from,
        to,
        id: 'e$i',
        minLen: 1,
        width: size?.width ?? 0,
        height: size?.height ?? 0,
        labelPos: dagre.LabelPosition.center,
      ));
    }
    for (var i = 0; i < diagram.notes.length; i++) {
      final target = diagram.notes[i].target;
      if (placed.containsKey(target)) {
        g.addEdge(dagre.DagreEdge('__note$i', target, id: 'n$i', minLen: 1));
      }
    }

    // `elk` runs the standalone ELK layered engine (orthogonal routing,
    // genuinely different placement); everything else uses dagre.
    dagre.DagreResult? result;
    ElkLayoutResult? elkResult;
    if (useElk) {
      elkResult = layoutWithElk(g,
          direction: diagram.direction, options: elkOptions);
      for (final p in [...placed.values, ...noteBoxes.values]) {
        final c = elkResult.center(p.node.id);
        if (c != null) p.center = c;
      }
    } else {
      result = dagre.layout(
        g,
        dagre.DagreConfig(
          rankDir: switch (diagram.direction) {
            FlowDirection.tb => dagre.RankDir.ttb,
            FlowDirection.bt => dagre.RankDir.btt,
            FlowDirection.lr => dagre.RankDir.ltr,
            FlowDirection.rl => dagre.RankDir.rtl,
          },
          nodeSep: _nodeSpacing,
          rankSep: _rankSpacing,
        ),
      );
      for (final p in [...placed.values, ...noteBoxes.values]) {
        p.center = result.graph.nodeMap[p.node.id]!.position!.center;
      }
    }

    late Rect? Function(String id) compositeBounds;

    Rect? descendantBounds(String id) {
      Rect? acc;
      for (final childId in diagram.states[id]?.children ?? const <String>[]) {
        final child = diagram.states[childId];
        final b =
            placed[childId]?.rect ??
            (child?.kind == StateKind.composite
                ? compositeBounds(childId)
                : null);
        if (b == null) continue;
        acc = acc == null ? b : acc.union(b);
      }
      return acc;
    }

    compositeBounds = (String id) {
      final pos = descendantBounds(id);
      if (pos == null) return null;
      final state = diagram.states[id]!;
      final titleSize = measurer.measure(state.label, baseStyle);
      return Rect.fromLTRB(
        math.min(pos.left,
                pos.center.x - titleSize.width / 2 - _clusterPadding) -
            _clusterPadding,
        pos.top - _clusterPadding - titleSize.height - 6,
        math.max(pos.right,
                pos.center.x + titleSize.width / 2 + _clusterPadding) +
            _clusterPadding,
        pos.bottom + _clusterPadding,
      );
    };

    void translateDescendants(String id, double dx, double dy) {
      for (final childId in diagram.states[id]?.children ?? const <String>[]) {
        final child = placed[childId];
        if (child != null) {
          child.center = child.center + Point(dx, dy);
        } else {
          translateDescendants(childId, dx, dy);
        }
      }
    }

    // ELK keeps nested members hierarchical, but its representative leaf
    // endpoints can put every root-level branch on the rank below the source.
    // Mermaid keeps the first branch below and places later composite targets
    // beside the source. Apply that ordering after ELK, before cluster bounds
    // and transition endpoints are resolved.
    if (useElk && hasNestedComposite && diagram.direction == FlowDirection.tb) {
      final targetsBySource = <String, List<String>>{};
      for (final transition in diagram.transitions) {
        final from = diagram.states[transition.from];
        final to = diagram.states[transition.to];
        if (from?.kind != StateKind.composite ||
            to?.kind != StateKind.composite ||
            from!.parent != null ||
            to!.parent != null) {
          continue;
        }
        targetsBySource.putIfAbsent(from.id, () => []).add(to.id);
      }
      for (final entry in targetsBySource.entries) {
        if (entry.value.length < 2) continue;
        final sourceRect = compositeBounds(entry.key);
        if (sourceRect == null) continue;
        for (final targetId in entry.value.skip(1)) {
          final targetRect = compositeBounds(targetId);
          if (targetRect == null) continue;
          final dx = math.max(
              0.0, sourceRect.right + _nodeSpacing - targetRect.left);
          final dy = sourceRect.top + _rankSpacing - targetRect.top;
          translateDescendants(targetId, dx, dy);
        }
      }
    }

    // --- scene ------------------------------------------------------------------
    final clusterNodes = <SceneNode>[];
    final edgeNodes = <SceneNode>[];
    final labelNodes = <SceneNode>[];
    final stateNodes = <SceneNode>[];

    // Composite clusters, outermost-first (parents precede children in the
    // map since composites register before their members). The rect is the
    // union of descendant boxes: dagre's own cluster position is unreliable
    // when edges cross the cluster boundary.

    for (final s in diagram.states.values) {
      if (s.kind != StateKind.composite || _isEmptyComposite(s)) continue;
      final rect = compositeBounds(s.id);
      if (rect == null) continue;
      final titleSize = measurer.measure(s.label, baseStyle);
      clusterRects[s.id] = rect;
      final titleY = rect.top + 4;
      final dividerY = titleY + titleSize.height + 4;
      clusterNodes.add(SceneGroup(
        id: s.id,
        role: SceneGroupRole.cluster,
        semanticLabel: s.label,
        children: [
        // Outer rect uses compositeTitleBackground (= mainBkg) so the title
        // band is tinted; inner region below the divider uses the background.
        SceneShape(
          geometry: RectGeometry(rect, rx: 5, ry: 5),
          fill: Fill(theme.mainBkg),
          stroke: Stroke(color: theme.nodeBorder),
        ),
        SceneShape(
          geometry: RectGeometry(
              Rect.fromLTRB(rect.left, dividerY, rect.right, rect.bottom)),
          fill: Fill(_compositeBodyColor(s)),
        ),
        // Title band.
        SceneText(
          text: s.label,
          bounds: Rect.fromLTWH(rect.center.x - titleSize.width / 2, titleY,
              titleSize.width, titleSize.height),
          style: baseStyle.copyWith(fontWeight: 700),
          color: theme.textColor,
        ),
        SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(rect.left, dividerY)),
            LineTo(Point(rect.right, dividerY)),
          ]),
          stroke: Stroke(color: theme.nodeBorder),
        ),
        ],
      ));

      // Concurrency regions: dashed dividers in the gaps between region groups.
      if (s.regions.length > 1) {
        Rect? regionBounds(List<String> ids) {
          Rect? b;
          for (final id in ids) {
            final r = placed[id]?.rect;
            if (r != null) b = b == null ? r : b.union(r);
          }
          return b;
        }

        final bands = <Rect>[];
        for (final g in s.regions) {
          final b = regionBounds(g);
          if (b != null) bands.add(b);
        }
        for (var i = 1; i < bands.length; i++) {
          final a = bands[i - 1], b = bands[i];
          // Orient the divider by how dagre actually placed the two regions:
          // a horizontal x-gap ⇒ vertical divider, else a horizontal one.
          final xGap = b.left - a.right;
          final yGap = b.top - a.bottom;
          if (xGap >= yGap) {
            final x = (a.right + b.left) / 2;
            clusterNodes.add(SceneShape(
              geometry: PathGeometry([
                MoveTo(Point(x, titleY + titleSize.height + 4)),
                LineTo(Point(x, rect.bottom)),
              ]),
              stroke: Stroke(
                  color: theme.nodeBorder, width: 1, dash: const [4, 3]),
            ));
          } else {
            final y = (a.bottom + b.top) / 2;
            clusterNodes.add(SceneShape(
              geometry: PathGeometry([
                MoveTo(Point(rect.left, y)),
                LineTo(Point(rect.right, y)),
              ]),
              stroke: Stroke(
                  color: theme.nodeBorder, width: 1, dash: const [4, 3]),
            ));
          }
        }
      }
    }

    final selfLoopCount = <String, int>{};
    for (var i = 0; i < diagram.transitions.length; i++) {
      final t = diagram.transitions[i];
      final (fromId, clusterFrom) = endpoint(t.from);
      final (toId, clusterTo) = endpoint(t.to);

      if (fromId == toId) {
        final anchor = clusterFrom != null
            ? clusterRects[clusterFrom]!
            : placed[fromId]!.rect;
        final idx = selfLoopCount[fromId] ?? 0;
        selfLoopCount[fromId] = idx + 1;
        final labelSize = labelSizes[i];
        final ext = 36.0 + idx * 16;
        final start = Point(anchor.right, anchor.center.y - anchor.height / 4);
        final end = Point(anchor.right, anchor.center.y + anchor.height / 4);
        final c1 = Point(start.x + ext, start.y - ext * 0.3);
        final c2 = Point(end.x + ext, end.y + ext * 0.3);
        final endDir = direction(c2, end);
        final children = <SceneNode>[
          SceneShape(
            geometry: PathGeometry(
                [MoveTo(start), CubicTo(c1, c2, end - endDir * 8)]),
            stroke: Stroke(color: theme.lineColor, width: 1),
          ),
          SceneShape(
            geometry: PolygonGeometry([
              end,
              end - endDir * 10 + Point(-endDir.y, endDir.x) * 5,
              end - endDir * 10 - Point(-endDir.y, endDir.x) * 5,
            ]),
            fill: Fill(theme.arrowheadColor),
          ),
          if (labelSize != null)
            SceneText(
              text: t.label!,
              bounds: Rect.fromLTWH(
                  anchor.right + ext * 0.78 + 6,
                  anchor.center.y - labelSize.height / 2,
                  labelSize.width,
                  labelSize.height),
              style: baseStyle,
              color: theme.textColor,
              align: TextAlignH.left,
            ),
        ];
        edgeNodes.add(SceneGroup(
            id: 'trans_${t.from}_${t.to}_$i',
            role: SceneGroupRole.edge,
            semanticLabel: t.label,
            children: children));
        continue;
      }

      dagre.DagreEdge? dagreEdge;
      List<Point> points;
      if (useElk) {
        points = elkResult!.edgePoints('e$i') ??
            [placed[fromId]!.center, placed[toId]!.center];
      } else {
        dagreEdge = result!.graph.findEdgeById('e$i')!;
        points = List<Point>.from(dagreEdge.points);
      }
      if (points.length < 2) {
        points = [placed[fromId]!.center, placed[toId]!.center];
      }
      final directCompositeRoute =
          useElk && clusterFrom != null && clusterTo != null;
      if (directCompositeRoute) {
        // Root transitions between composite states should connect their
        // visible containers directly. ELK routes from representative leaf
        // nodes, which otherwise leaves a long right-angle detour outside the
        // source cluster.
        points = [
          clusterRects[clusterFrom]!.center,
          clusterRects[clusterTo]!.center,
        ];
      }
      if (clusterTo != null) {
        points = _dropInsideRect(points, clusterRects[clusterTo]!, fromEnd: true);
      }
      if (clusterFrom != null) {
        points =
            _dropInsideRect(points, clusterRects[clusterFrom]!, fromEnd: false);
      }
      final sourceRect = clusterFrom != null
          ? clusterRects[clusterFrom]!
          : _transitionRect(placed[fromId]!);
      final targetRect = clusterTo != null
          ? clusterRects[clusterTo]!
          : _transitionRect(placed[toId]!);
      final source = placed[fromId]!.node;
      final target = placed[toId]!.node;
      bool isPseudoState(StateNode node) =>
          node.kind == StateKind.start || node.kind == StateKind.end;
      final corridorX = sourceRect.center.x;
      final corridorTop = math.min(sourceRect.center.y, targetRect.center.y);
      final corridorBottom = math.max(sourceRect.center.y, targetRect.center.y);
      final directCorridorClear = placed.entries
          .where((entry) => entry.key != fromId && entry.key != toId)
          .where((entry) => entry.value.node.parent == source.parent)
          .every((entry) {
            final rect = _transitionRect(entry.value);
            final crossesX = rect.left <= corridorX && corridorX <= rect.right;
            final overlapsY =
                rect.bottom > corridorTop && rect.top < corridorBottom;
            return !crossesX || !overlapsY;
          });
      final alignedSiblingRoute =
          useElk &&
          clusterFrom == null &&
          clusterTo == null &&
          source.parent == target.parent &&
          (isPseudoState(source) || isPseudoState(target)) &&
          directCorridorClear &&
          (sourceRect.center.x - targetRect.center.x).abs() < 0.001;
      if (alignedSiblingRoute) {
        // ELK can move a bend to the edge of a circular pseudo-state even when
        // two sibling states have the same centre line. Use the direct axis so
        // initial/final arrows meet both the marker and state cleanly.
        points = [sourceRect.center, targetRect.center];
      }

      final hasNestedParallelRoute =
          directCompositeRoute &&
          diagram.transitions.any(
            (other) =>
                other != t &&
                _isDescendantOf(other.from, t.from) &&
                _isDescendantOf(other.to, t.to),
          );
      final useSeparateCorridor =
          hasNestedParallelRoute &&
          targetRect.top >= sourceRect.bottom &&
          math.min(sourceRect.right, targetRect.right) >
              math.max(sourceRect.left, targetRect.left);
      if (useSeparateCorridor) {
        // Keep the parent transition in its own corridor when a descendant
        // transition crosses the same pair of composite boundaries.
        final overlapLeft = math.max(sourceRect.left, targetRect.left);
        final overlapRight = math.min(sourceRect.right, targetRect.right);
        final x = overlapLeft + (overlapRight - overlapLeft) * 0.25;
        points = [Point(x, sourceRect.bottom), Point(x, targetRect.top)];
      }
      // ELK routes orthogonally, so clip the end segments perpendicular to the
      // border (keeping the stub axis-aligned) rather than from the node centre,
      // which would tilt a near-vertical/near-horizontal stub. Dagre paths are
      // curves, so keep the centre-based intersect for them.
      if (useSeparateCorridor) {
        // The points already lie on the two visible cluster boundaries.
      } else if (useElk && !directCompositeRoute) {
        points[0] = _clipRectPerp(sourceRect, points[0], points[1]);
        points[points.length - 1] = _clipRectPerp(
            targetRect, points[points.length - 1], points[points.length - 2]);
      } else {
        points[0] = intersectRect(sourceRect, points[1]);
        points[points.length - 1] =
            intersectRect(targetRect, points[points.length - 2]);
      }

      final endTip = points.last;
      final endDir = direction(points[points.length - 2], endTip);
      points[points.length - 1] = endTip - endDir * 8;

      edgeNodes.add(SceneGroup(
        id: 'trans_${t.from}_${t.to}_$i',
        role: SceneGroupRole.edge,
        semanticLabel: t.label,
        children: [
          SceneShape(
            geometry:
                PathGeometry(useElk ? _linearPath(points) : curveBasis(points)),
            stroke: Stroke(color: theme.lineColor, width: 1),
          ),
          SceneShape(
            geometry: PolygonGeometry([
              endTip,
              endTip - endDir * 10 + Point(-endDir.y, endDir.x) * 5,
              endTip - endDir * 10 - Point(-endDir.y, endDir.x) * 5,
            ]),
            fill: Fill(theme.arrowheadColor),
          ),
        ],
      ));

      final labelSize = labelSizes[i];
      if (labelSize != null) {
        // Centre the label ON the edge line. ELK's own label centre is offset
        // to the side of the edge (it reserves label space beside it), so for
        // ELK use the polyline's arc-length midpoint, which lies on the line
        // (NOT the index-midpoint, which lands near an end on an orthogonal path
        // and overlaps the target node). Dagre supplies its own labelX/Y.
        final c = useElk
            ? polylineMidpoint(points)
            : (dagreEdge?.labelX != null && dagreEdge?.labelY != null
                ? Point(dagreEdge!.labelX!, dagreEdge.labelY!)
                : polylineMidpoint(points));
        labelNodes.add(SceneGroup(
          id: 'translabel_$i',
          role: SceneGroupRole.edgeLabel,
          children: [
          SceneShape(
            geometry: RectGeometry(
                Rect.fromCenter(c, labelSize.width + 4, labelSize.height + 4),
                rx: 2,
                ry: 2),
            // Opaque background (the theme colour already carries its alpha) so
            // the edge line doesn't show through the label.
            fill: Fill(theme.edgeLabelBackground.withOpacity(1)),
          ),
          SceneText(
            text: t.label!,
            bounds: Rect.fromCenter(c, labelSize.width, labelSize.height),
            style: baseStyle,
            color: theme.textColor,
          ),
          ],
        ));
      }
    }

    // Notes + dashed connectors.
    for (var i = 0; i < diagram.notes.length; i++) {
      final b = noteBoxes[i]!;
      final target = placed[diagram.notes[i].target];
      if (target != null) {
        edgeNodes.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(intersectRect(b.rect, target.center)),
            LineTo(intersectRect(target.rect, b.center)),
          ]),
          stroke: Stroke(color: theme.lineColor, width: 1, dash: const [2, 2]),
        ));
      }
      stateNodes.add(SceneGroup(
        id: '__note$i',
        role: SceneGroupRole.annotation,
        children: [
        SceneShape(
          geometry: RectGeometry(b.rect),
          fill: Fill(theme.noteBkgColor),
          stroke: Stroke(color: theme.noteBorderColor),
        ),
        SceneText(
          text: diagram.notes[i].text,
          bounds: b.rect.inflate(-_padding),
          style: baseStyle,
          color: theme.noteTextColor,
        ),
        ],
      ));
    }

    for (final p in placed.values) {
      stateNodes.add(_buildState(p));
    }

    var nodes = <SceneNode>[
      ...clusterNodes,
      ...edgeNodes,
      ...labelNodes,
      ...stateNodes,
    ];
    var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 100);

    final title = diagram.title;
    if (title != null && title.isNotEmpty) {
      final style = baseStyle.copyWith(fontWeight: 700, fontSize: 18);
      final size = measurer.measure(title, style);
      final node = SceneText(
        text: title,
        bounds: Rect.fromLTWH(bounds.center.x - size.width / 2,
            bounds.top - size.height - 25, size.width, size.height),
        style: style,
        color: theme.titleColor,
      );
      nodes = [...nodes, node];
      bounds = bounds.union(node.bounds);
    }

    final dx = _diagramPadding - bounds.left;
    final dy = _diagramPadding - bounds.top;
    return RenderScene(
      size: Size(bounds.width + 2 * _diagramPadding,
          bounds.height + 2 * _diagramPadding),
      background: theme.background,
      nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
    );
  }

  Color _compositeBodyColor(StateNode state) {
    var depth = 0;
    var parentId = state.parent;
    while (parentId != null) {
      depth++;
      parentId = diagram.states[parentId]?.parent;
    }
    if (depth.isEven) return theme.background;

    // Mermaid alternates nested composite bodies with altBackground. The core
    // theme does not expose that token yet, so derive its default 6% contrast
    // from the active background instead of hard-coding a light-only colour.
    final background = theme.background.alpha == 0
        ? theme.mainBkg
        : theme.background;
    final darkBackground =
        background.red + background.green + background.blue < 384;
    final target = darkBackground ? 255 : 0;
    const amount = 0.06;
    int channel(int value) =>
        (value + (target - value) * amount).round().clamp(0, 255);
    return Color.fromARGB(
      background.alpha,
      channel(background.red),
      channel(background.green),
      channel(background.blue),
    );
  }

  bool _isDescendantOf(String candidateId, String ancestorId) {
    var parentId = diagram.states[candidateId]?.parent;
    while (parentId != null) {
      if (parentId == ancestorId) return true;
      parentId = diagram.states[parentId]?.parent;
    }
    return false;
  }

  Rect _transitionRect(_Placed state) {
    // End markers reserve an 18 px layout box but draw a 14 px outer circle.
    // Connect the transition to the visible circle instead of the invisible
    // layout padding.
    if (state.node.kind == StateKind.end) {
      return Rect.fromCenter(state.center, 14, 14);
    }
    return state.rect;
  }

  _Placed _measure(StateNode s) {
    switch (s.kind) {
      case StateKind.start:
        return _Placed(s, 14, 14, Size.zero);
      case StateKind.end:
        return _Placed(s, 18, 18, Size.zero);
      case StateKind.choice:
        return _Placed(s, 28, 28, Size.zero);
      case StateKind.fork || StateKind.join:
        return horizontal
            ? _Placed(s, 10, 70, Size.zero)
            : _Placed(s, 70, 10, Size.zero);
      case StateKind.history || StateKind.historyDeep:
        return _Placed(s, 26, 26, Size.zero);
      case StateKind.normal || StateKind.composite:
        final size = measurer.measure(s.label, baseStyle, maxWidth: 200);
        return _Placed(
            s, size.width + 2 * _padding, size.height + 2 * _padding, size);
    }
  }

  SceneGroup _buildState(_Placed p) {
    final s = p.node;
    var fill = theme.mainBkg;
    var stroke = theme.nodeBorder;
    void apply(Map<String, String>? styles) {
      if (styles == null) return;
      fill = Color.tryParse(styles['fill'] ?? '') ?? fill;
      stroke = Color.tryParse(styles['stroke'] ?? '') ?? stroke;
    }

    apply(diagram.classDefs['default']);
    for (final c in s.cssClasses) {
      apply(diagram.classDefs[c]);
    }
    apply(s.styles);

    final children = <SceneNode>[];
    switch (s.kind) {
      case StateKind.start:
        children.add(SceneShape(
          geometry: CircleGeometry(p.center, 7),
          fill: Fill(theme.lineColor),
        ));
      case StateKind.end:
        children.addAll([
          SceneShape(
            geometry: CircleGeometry(p.center, 7),
            fill: Fill(theme.background),
            stroke: Stroke(color: theme.lineColor, width: 2),
          ),
          SceneShape(
            geometry: CircleGeometry(p.center, 2.5),
            fill: Fill(theme.nodeBorder),
          ),
        ]);
      case StateKind.choice:
        children.add(SceneShape(
          geometry: PolygonGeometry([
            p.center + const Point(0, -14),
            p.center + const Point(14, 0),
            p.center + const Point(0, 14),
            p.center + const Point(-14, 0),
          ]),
          fill: Fill(fill),
          stroke: Stroke(color: stroke),
        ));
      case StateKind.fork || StateKind.join:
        children.add(SceneShape(
          geometry: RectGeometry(p.rect),
          fill: Fill(theme.lineColor),
          stroke: Stroke(color: theme.lineColor),
        ));
      case StateKind.history || StateKind.historyDeep:
        // A circle with "H" (shallow) or "H*" (deep), like upstream.
        children.add(SceneShape(
          geometry: CircleGeometry(p.center, 13),
          fill: Fill(fill),
          stroke: Stroke(color: stroke),
        ));
        children.add(SceneText(
          text: s.kind == StateKind.historyDeep ? 'H*' : 'H',
          bounds: Rect.fromCenter(p.center, 26, 18),
          style: baseStyle,
          color: theme.textColor,
        ));
      case StateKind.normal || StateKind.composite:
        children.addAll([
          SceneShape(
            geometry: RectGeometry(p.rect, rx: 5, ry: 5),
            fill: Fill(fill),
            stroke: Stroke(color: stroke),
          ),
          SceneText(
            text: s.label,
            bounds: Rect.fromCenter(
                p.center, p.labelSize.width, p.labelSize.height),
            style: baseStyle.copyWith(fontWeight: 700),
            color: theme.textColor,
          ),
        ]);
    }
    return SceneGroup(
        id: s.id,
        semanticLabel: s.label.isEmpty ? null : s.label,
        children: children);
  }

}

// --- helpers (private ports, same shapes as class_layout) --------------------

/// Straight polyline through [pts] — used for elk's orthogonal edge routes
/// (the points are already axis-aligned, so no smoothing is applied).
List<PathCommand> _linearPath(List<Point> pts) {
  if (pts.isEmpty) return const [];
  return [
    MoveTo(pts.first),
    for (var i = 1; i < pts.length; i++) LineTo(pts[i]),
  ];
}

/// Clips an orthogonal edge end to [rect]'s border while keeping the last
/// segment axis-aligned: probes along the segment's own axis (same x for a
/// vertical approach, same y for a horizontal one) instead of from the centre,
/// so a near-vertical stub doesn't tilt. [end] is ELK's boundary point, [next]
/// the adjacent bend.
Point _clipRectPerp(Rect rect, Point end, Point next) {
  final vertical = (next.x - end.x).abs() <= (next.y - end.y).abs();
  if (vertical) {
    final x = next.x.clamp(rect.left, rect.right).toDouble();
    return Point(x, next.y < rect.center.y ? rect.top : rect.bottom);
  }
  final y = next.y.clamp(rect.top, rect.bottom).toDouble();
  return Point(next.x < rect.center.x ? rect.left : rect.right, y);
}

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

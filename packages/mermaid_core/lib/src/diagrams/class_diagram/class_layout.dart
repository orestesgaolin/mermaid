/// Class diagram layout: dagre-positioned UML compartment boxes with
/// relation markers, ported (simplified) from upstream
/// classRenderer-v3-unified + rendering-elements/shapes/classBox.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../config_values.dart';
import '../../directives.dart';
import '../../edge_geometry.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';
import '../../vendor/dagre/dart_dagre.dart' as dagre;
import '../flowchart/flow_model.dart' show FlowDirection;
import 'class_model.dart';

const double _memberGap = 4;
const double _diagramPadding = 8;
const double _markerSize = 14;

/// Layout values resolved from `config.class`.
class ClassConfig {
  const ClassConfig({
    this.padding = 12,
    this.nodeSpacing = 50,
    this.rankSpacing = 50,
  });

  final double padding;
  final double nodeSpacing;
  final double rankSpacing;

  factory ClassConfig.fromSource(String source) {
    final values = resolveDiagramConfig(source, 'class');
    return ClassConfig(
      // The unified class-box renderer uses 12 px by default in this port.
      padding: nonNegativeDouble(values, 'padding', 12),
      nodeSpacing: nonNegativeDouble(values, 'nodeSpacing', 50),
      rankSpacing: nonNegativeDouble(values, 'rankSpacing', 50),
    );
  }
}

/// Upstream `styles.js` forces `g.classGroup text { font-size: 10px }`,
/// overriding the theme font size for every class box, member and title.
const double _classFontSize = 10;

/// Upstream `svgDraw.js` draws cardinality labels at `font-size: 6`.
const double _cardinalityFontSize = 6;

RenderScene layoutClassDiagram(
  ClassDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
  ClassConfig config = const ClassConfig(),
}) {
  return _ClassLayout(diagram, measurer, theme, config).run();
}

class _Box {
  _Box(this.node, this.width, this.height, this.lines);

  final ClassNode node;
  final double width;
  final double height;
  final List<_BoxLine> lines;
  Point center = Point.zero;

  Rect rectAt(Point c) => Rect.fromCenter(c, width, height);
}

class _BoxLine {
  _BoxLine(this.text, this.style, this.size, this.dy,
      {this.centered = false, this.separatorAbove = false, this.underline = false});

  final String text;
  final TextStyleSpec style;
  final Size size;

  /// Offset from box top to the line's top.
  final double dy;
  final bool centered;
  final bool separatorAbove;
  final bool underline;
}

class _ClassLayout {
  _ClassLayout(this.diagram, this.measurer, this.theme, this.config)
      : baseStyle = TextStyleSpec(
          fontFamily: theme.fontFamily,
          fontSize: _classFontSize,
        );

  final ClassDiagram diagram;
  final TextMeasurer measurer;
  final MermaidTheme theme;
  final ClassConfig config;
  final TextStyleSpec baseStyle;

  double get _padding => config.padding;
  double get _nodeSpacing => config.nodeSpacing;
  double get _rankSpacing => config.rankSpacing;

  final boxes = <String, _Box>{};

  RenderScene run() {
    for (final node in diagram.classes.values) {
      boxes[node.id] = _measureBox(node);
    }
    // Notes participate in layout as extra nodes.
    final noteBoxes = <int, _Box>{};
    for (var i = 0; i < diagram.notes.length; i++) {
      final n = diagram.notes[i];
      final size = measurer.measure(n.text, baseStyle, maxWidth: 200);
      noteBoxes[i] = _Box(
        ClassNode(id: '__note$i', label: n.text),
        size.width + 2 * _padding,
        size.height + 2 * _padding,
        [],
      );
    }

    final g = dagre.DagreGraph();
    final parentOf = <String, String>{};
    for (final ns in diagram.namespaces) {
      for (final id in ns.classIds) {
        parentOf[id] = '__ns_${ns.id}';
      }
      g.addNode(dagre.DagreNode('__ns_${ns.id}'));
    }
    for (final b in boxes.values) {
      g.addNode(dagre.DagreNode(b.node.id,
          width: b.width, height: b.height, parent: parentOf[b.node.id]));
    }
    noteBoxes.forEach((i, b) {
      g.addNode(dagre.DagreNode(b.node.id, width: b.width, height: b.height));
    });

    final labelSizes = <int, Size>{};
    for (var i = 0; i < diagram.relations.length; i++) {
      final r = diagram.relations[i];
      Size? size;
      if (r.label != null && r.label!.isNotEmpty) {
        size = measurer.measure(r.label!, baseStyle, maxWidth: 200);
        labelSizes[i] = size;
      }
      g.addEdge(dagre.DagreEdge(
        r.from,
        r.to,
        id: 'e$i',
        minLen: 1,
        width: size?.width ?? 0,
        height: size?.height ?? 0,
        labelPos: dagre.LabelPosition.center,
      ));
    }
    for (var i = 0; i < diagram.notes.length; i++) {
      final target = diagram.notes[i].forClass;
      if (target != null && boxes.containsKey(target)) {
        // minLen 0 would keep the note beside its class like upstream, but
        // the vendored dagre crashes on zero-length edges; known delta.
        g.addEdge(dagre.DagreEdge('__note$i', target, id: 'n$i', minLen: 1));
      }
    }

    final result = dagre.layout(
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
    for (final b in [...boxes.values, ...noteBoxes.values]) {
      b.center = result.graph.nodeMap[b.node.id]!.position!.center;
    }

    // Dagre keeps members inside their compound parent, but cross-namespace
    // relations can still leave two top-level compound bounds overlapping.
    // Separate disjoint namespaces on the cross axis before emitting geometry.
    final nodeOffsets = <String, Point>{};

    // Namespaces are separated in declaration order; a namespace whose members
    // are already claimed by an earlier one is nested, so it moves with it.
    final separable = <({String label, Set<String> members})>[];
    final claimed = <String>{};
    for (final ns in diagram.namespaces) {
      final members = ns.classIds.where(boxes.containsKey).toSet();
      if (members.isEmpty || members.any(claimed.contains)) continue;
      claimed.addAll(members);
      separable.add((label: ns.label, members: members));
    }

    void shiftMembers(Set<String> members, Point delta) {
      for (final id in members) {
        boxes[id]!.center = boxes[id]!.center + delta;
        nodeOffsets[id] = (nodeOffsets[id] ?? Point.zero) + delta;
      }
      // A note is anchored beside its class, so it travels with it.
      for (var i = 0; i < diagram.notes.length; i++) {
        final target = diagram.notes[i].forClass;
        if (target == null || !members.contains(target)) continue;
        final note = noteBoxes[i];
        if (note != null) note.center = note.center + delta;
      }
    }

    // Pushing one namespace clear can drive it into the next, so sweep until
    // the arrangement settles. The bound stops a pathological diagram from
    // looping; one pass is enough whenever the namespaces are already ordered.
    final separationPasses = math.max(2, separable.length);
    for (var pass = 0; pass < separationPasses; pass++) {
      var moved = false;
      final placedRects = <Rect>[];
      for (final entry in separable) {
        var clusterRect = _namespaceRect(entry.label, entry.members);
        if (clusterRect == null) continue;
        var dx = 0.0, dy = 0.0;
        for (final placed in placedRects) {
          if (!rectsOverlap(clusterRect, placed)) continue;
          if (diagram.direction == FlowDirection.tb ||
              diagram.direction == FlowDirection.bt) {
            dx = math.max(dx, placed.right + _nodeSpacing - clusterRect.left);
          } else {
            dy = math.max(dy, placed.bottom + _nodeSpacing - clusterRect.top);
          }
        }
        if (dx != 0 || dy != 0) {
          shiftMembers(entry.members, Point(dx, dy));
          clusterRect = clusterRect.translate(dx, dy);
          moved = true;
        }
        placedRects.add(clusterRect);
      }
      if (!moved) break;
    }

    final clusterNodes = <SceneNode>[];
    final edgeNodes = <SceneNode>[];
    final labelNodes = <SceneNode>[];
    final boxNodes = <SceneNode>[];

    // Multiple inheritance relations may share the same parent. Keep each
    // relation on its own rank-facing port instead of collapsing every route
    // and marker onto the center of the parent edge.
    final extensionPorts = _extensionPorts();

    // Reversed: namespaces close innermost-first during parsing, so painting
    // in reverse puts enclosing clusters behind nested ones.
    for (final ns in diagram.namespaces.reversed) {
      final rect = _namespaceRect(ns.label, ns.classIds);
      if (rect == null) continue;
      final titleSize = _namespaceTitleSize(ns.label);
      clusterNodes.add(SceneGroup(
        id: 'namespace_${ns.id}',
        role: SceneGroupRole.cluster,
        children: [
        SceneShape(
          geometry: RectGeometry(rect),
          fill: Fill(theme.clusterBkg),
          stroke: Stroke(color: theme.clusterBorder),
        ),
        SceneText(
          text: ns.label,
          bounds: Rect.fromLTWH(rect.center.x - titleSize.width / 2,
              rect.top + 4, titleSize.width, titleSize.height),
          style: baseStyle,
          color: theme.titleColor,
        ),
        ],
      ));
    }

    for (var i = 0; i < diagram.relations.length; i++) {
      final r = diagram.relations[i];
      final dagreEdge = result.graph.findEdgeById('e$i')!;
      final from = boxes[r.from]!;
      final to = boxes[r.to]!;
      var points = List<Point>.from(dagreEdge.points);
      if (points.length < 2) points = [from.center, to.center];
      final fromOffset = nodeOffsets[r.from] ?? Point.zero;
      final toOffset = nodeOffsets[r.to] ?? Point.zero;
      if (fromOffset != Point.zero || toOffset != Point.zero) {
        points = [
          for (var pi = 0; pi < points.length; pi++)
            points[pi] +
                fromOffset * (1 - pi / (points.length - 1)) +
                toOffset * (pi / (points.length - 1)),
        ];
      }
      // Cross-namespace links are routed before the namespace overlap pass
      // moves their endpoints apart, so interpolating the old route can turn
      // the final segment sideways. Restore a short approach along the rank
      // axis -- which is horizontal under `direction LR`/`RL` -- but only when
      // the pass actually displaced one of the endpoints.
      if ((fromOffset != Point.zero || toOffset != Point.zero) &&
          parentOf[r.from] != null &&
          parentOf[r.to] != null &&
          parentOf[r.from] != parentOf[r.to] &&
          points.length >= 3) {
        points[points.length - 2] = _rankApproachPoint(to, from.center);
      }
      // Keep inheritance markers on the rank-facing edge of their class.
      if (r.endFrom == RelationEnd.extension && points.length >= 3) {
        points[1] = _rankApproachPoint(
          from,
          to.center,
          crossAxis: extensionPorts[(i, r.from)],
        );
      }
      if (r.endTo == RelationEnd.extension && points.length >= 3) {
        points[points.length - 2] = _rankApproachPoint(
          to,
          from.center,
          crossAxis: extensionPorts[(i, r.to)],
        );
      }
      points[0] = intersectRect(from.rectAt(from.center), points[1]);
      points[points.length - 1] =
          intersectRect(to.rectAt(to.center), points[points.length - 2]);

      final children = <SceneNode>[];
      final startTip = points.first;
      final startDir = direction(points[1], startTip);
      final endTip = points.last;
      final endDir = direction(points[points.length - 2], endTip);
      // Pull the line back behind solid markers.
      if (_markerInset(r.endFrom) > 0) {
        points[0] = startTip - startDir * _markerInset(r.endFrom);
      }
      if (_markerInset(r.endTo) > 0) {
        points[points.length - 1] = endTip - endDir * _markerInset(r.endTo);
      }
      final path = PathGeometry(curveBasis(points));
      children.add(SceneShape(
        geometry: path,
        stroke: Stroke(
          color: theme.lineColor,
          width: 1.5,
          dash: r.dotted ? const [3, 3] : null,
        ),
      ));
      children.addAll(_marker(r.endFrom, startTip, startDir));
      children.addAll(_marker(r.endTo, endTip, endDir));
      edgeNodes.add(SceneGroup(
          id: 'rel_${r.from}_${r.to}_$i',
          role: SceneGroupRole.edge,
          semanticLabel: r.label,
          children: children));

      final labelSize = labelSizes[i];
      if (labelSize != null) {
        // Namespace separation changes the route after Dagre calculates its
        // label position. Anchor the label on the final painted curve.
        final c = pathMidpoint(path);
        labelNodes.add(SceneGroup(
          id: 'rellabel_$i',
          role: SceneGroupRole.edgeLabel,
          children: [
          SceneShape(
            geometry: RectGeometry(
                Rect.fromCenter(c, labelSize.width + 4, labelSize.height + 4),
                rx: 2,
                ry: 2),
            // Mermaid 11's unified renderer uses the generic edge-label
            // background rather than the legacy translucent `.classLabel` box.
            // Opaque (the theme colour carries its own alpha) so the relation
            // line does not show through the label.
            fill: Fill(theme.edgeLabelBackground.withOpacity(1)),
          ),
          SceneText(
            text: r.label!,
            bounds: Rect.fromCenter(c, labelSize.width, labelSize.height),
            style: baseStyle,
            color: theme.textColor,
          ),
          ],
        ));
      }
      final cardStyle = baseStyle.copyWith(fontSize: _cardinalityFontSize);
      void cardinality(String? card, Point tip, Point dir) {
        if (card == null || card.isEmpty) return;
        final size = measurer.measure(card, cardStyle);
        final pos = tip - dir * 18 + Point(-dir.y, dir.x) * 12;
        labelNodes.add(SceneText(
          text: card,
          bounds: Rect.fromCenter(pos, size.width, size.height),
          style: cardStyle,
          color: Color.black,
        ));
      }

      cardinality(r.cardFrom, startTip, startDir);
      cardinality(r.cardTo, endTip, endDir);
    }

    // Note attachment edges (dashed, no markers).
    for (var i = 0; i < diagram.notes.length; i++) {
      final target = diagram.notes[i].forClass;
      final noteBox = noteBoxes[i]!;
      if (target != null && boxes.containsKey(target)) {
        final to = boxes[target]!;
        final p1 = intersectRect(noteBox.rectAt(noteBox.center), to.center);
        final p2 = intersectRect(to.rectAt(to.center), noteBox.center);
        edgeNodes.add(SceneShape(
          geometry: PathGeometry([MoveTo(p1), LineTo(p2)]),
          stroke: Stroke(color: theme.lineColor, width: 1, dash: const [2, 2]),
        ));
      }
      final rect = noteBox.rectAt(noteBox.center);
      boxNodes.add(SceneGroup(
        id: '__note$i',
        role: SceneGroupRole.annotation,
        children: [
        SceneShape(
          geometry: RectGeometry(rect),
          // Upstream classDb sets `fill: noteBkgColor; stroke: noteBorderColor`.
          fill: Fill(theme.noteBkgColor),
          stroke: Stroke(color: theme.noteBorderColor),
        ),
        SceneText(
          text: diagram.notes[i].text,
          bounds: rect.inflate(-_padding),
          style: baseStyle,
          // Upstream `.noteLabel .nodeLabel { color: noteTextColor }`.
          color: theme.noteTextColor,
        ),
        ],
      ));
    }

    for (final b in boxes.values) {
      boxNodes.add(_buildBox(b));
    }

    var nodes = <SceneNode>[
      ...clusterNodes,
      ...edgeNodes,
      ...labelNodes,
      ...boxNodes,
    ];
    var bounds =
        sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 100);

    final title = diagram.title;
    if (title != null && title.isNotEmpty) {
      final style = baseStyle.copyWith(fontWeight: 700);
      final size = measurer.measure(title, style);
      final node = SceneText(
        text: title,
        bounds: Rect.fromLTWH(bounds.center.x - size.width / 2,
            bounds.top - size.height - 8, size.width, size.height),
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

  // --- boxes -------------------------------------------------------------------

  _Box _measureBox(ClassNode node) {
    final titleStyle = baseStyle.copyWith(fontWeight: 700);
    final lines = <_BoxLine>[];
    var y = _padding / 2 + 2;
    var width = 0.0;

    void add(String text, TextStyleSpec style,
        {bool centered = false, bool separator = false, bool underline = false}) {
      final size = measurer.measure(text, style, maxWidth: 300);
      lines.add(_BoxLine(text, style, size, y,
          centered: centered, separatorAbove: separator, underline: underline));
      y += size.height + _memberGap;
      width = math.max(width, size.width);
    }

    // Upstream `shapeUtil.ts:textHelper` renders only the first annotation,
    // plain (non-italic) at the base class font size, centered.
    if (node.annotations.isNotEmpty) {
      add('«${node.annotations.first}»', baseStyle, centered: true);
    }
    add(node.label, titleStyle, centered: true);
    y += _padding / 2;

    // Upstream `classBox.ts`: with default `hideEmptyMembersBox` (false) and
    // both compartments empty, draw a single extra empty compartment bounded
    // by two divider lines (`renderExtraBox`). Otherwise draw a divider above
    // each present compartment, reserving the methods region when methods are
    // empty but members are present.
    final renderExtraBox = node.attributes.isEmpty && node.methods.isEmpty;

    if (renderExtraBox) {
      // Divider under the label and a second divider closing the extra box.
      lines.add(_BoxLine('', baseStyle, Size.zero, y, separatorAbove: true));
      y += _padding * 2;
      lines.add(_BoxLine('', baseStyle, Size.zero, y, separatorAbove: true));
    } else {
      var first = true;
      for (final m in node.attributes) {
        add(m.text, m.isAbstract ? baseStyle.copyWith(italic: true) : baseStyle,
            separator: first, underline: m.isStatic);
        first = false;
      }
      if (node.attributes.isEmpty) {
        // Members compartment empty but methods present: divider under label.
        lines.add(_BoxLine('', baseStyle, Size.zero, y, separatorAbove: true));
        y += 8;
      } else {
        y += _padding / 2;
      }

      first = true;
      for (final m in node.methods) {
        add(m.text, m.isAbstract ? baseStyle.copyWith(italic: true) : baseStyle,
            separator: first, underline: m.isStatic);
        first = false;
      }
      if (node.methods.isEmpty) {
        // Methods compartment empty but members present: divider + region.
        lines.add(_BoxLine('', baseStyle, Size.zero, y, separatorAbove: true));
        y += 8;
      }
    }

    // Upstream box width is purely content-driven: bbox.width + 2*PADDING.
    return _Box(node, width + 2 * _padding, y + _padding / 2, lines);
  }

  SceneGroup _buildBox(_Box b) {
    final rect = b.rectAt(b.center);
    var fill = theme.mainBkg;
    var stroke = theme.nodeBorder;
    void applyStyles(Map<String, String>? styles) {
      if (styles == null) return;
      fill = Color.tryParse(styles['fill'] ?? '') ?? fill;
      stroke = Color.tryParse(styles['stroke'] ?? '') ?? stroke;
    }

    applyStyles(diagram.classDefs['default']);
    for (final c in b.node.cssClasses) {
      applyStyles(diagram.classDefs[c]);
    }
    applyStyles(b.node.styles);

    final children = <SceneNode>[
      SceneShape(
        geometry: RectGeometry(rect),
        fill: Fill(fill),
        stroke: Stroke(color: stroke),
      ),
    ];
    for (final line in b.lines) {
      if (line.separatorAbove) {
        final sepY = rect.top + line.dy - _memberGap / 2 - 1;
        children.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(rect.left, sepY)),
            LineTo(Point(rect.right, sepY)),
          ]),
          stroke: Stroke(color: stroke),
        ));
      }
      if (line.text.isEmpty) continue;
      children.add(SceneText(
        text: line.text,
        bounds: line.centered
            ? Rect.fromLTWH(rect.center.x - line.size.width / 2,
                rect.top + line.dy, line.size.width, line.size.height)
            : Rect.fromLTWH(rect.left + _padding, rect.top + line.dy,
                line.size.width, line.size.height),
        style: line.style,
        color: theme.textColor,
        align: line.centered ? TextAlignH.center : TextAlignH.left,
        underline: line.underline,
      ));
    }
    return SceneGroup(
        id: b.node.id, semanticLabel: b.node.label, children: children);
  }

  // --- markers -------------------------------------------------------------------

  double _markerInset(RelationEnd end) => switch (end) {
        RelationEnd.extension => _markerSize - 1,
        RelationEnd.composition || RelationEnd.aggregation => _markerSize + 2,
        RelationEnd.lollipop => 11,
        _ => 0,
      };

  List<SceneNode> _marker(RelationEnd end, Point tip, Point dir) {
    final perp = Point(-dir.y, dir.x);
    switch (end) {
      case RelationEnd.none:
        return const [];
      case RelationEnd.extension:
        final base = tip - dir * _markerSize;
        return [
          SceneShape(
            geometry: PolygonGeometry(
                [tip, base + perp * (_markerSize / 2), base - perp * (_markerSize / 2)]),
            fill: Fill(theme.background),
            stroke: Stroke(color: theme.lineColor, width: 1.5),
          ),
        ];
      case RelationEnd.composition || RelationEnd.aggregation:
        final mid = tip - dir * (_markerSize / 2 + 1);
        final back = tip - dir * (_markerSize + 2);
        return [
          SceneShape(
            geometry: PolygonGeometry([
              tip,
              mid + perp * (_markerSize / 2.8),
              back,
              mid - perp * (_markerSize / 2.8),
            ]),
            fill: Fill(end == RelationEnd.composition
                ? theme.lineColor
                : theme.background),
            stroke: Stroke(color: theme.lineColor, width: 1.5),
          ),
        ];
      case RelationEnd.arrow:
        final base = tip - dir * 10;
        return [
          SceneShape(
            geometry: PathGeometry([
              MoveTo(base + perp * 5),
              LineTo(tip),
              LineTo(base - perp * 5),
            ]),
            stroke: Stroke(color: theme.lineColor, width: 1.5),
          ),
        ];
      case RelationEnd.lollipop:
        return [
          SceneShape(
            geometry: CircleGeometry(tip - dir * 6, 6),
            fill: Fill(theme.background),
            stroke: Stroke(color: theme.lineColor, width: 1.5),
          ),
        ];
    }
  }

  final _namespaceTitleSizes = <String, Size>{};

  /// Measured once per namespace label: the separation sweep and the paint
  /// pass both need it, and the sweep can run several times.
  Size _namespaceTitleSize(String label) =>
      _namespaceTitleSizes[label] ??= measurer.measure(label, baseStyle);

  /// The cluster rect a namespace occupies given where its members sit right
  /// now. Null when none of [memberIds] has a box.
  Rect? _namespaceRect(String label, Iterable<String> memberIds) {
    Rect? acc;
    for (final id in memberIds) {
      final b = boxes[id];
      if (b == null) continue;
      final r = b.rectAt(b.center);
      acc = acc == null ? r : acc.union(r);
    }
    if (acc == null) return null;
    final titleSize = _namespaceTitleSize(label);
    return Rect.fromLTRB(
      acc.left - 12,
      acc.top - 16 - titleSize.height,
      acc.right + 12,
      acc.bottom + 12,
    );
  }

  Map<(int, String), double> _extensionPorts() {
    final byEndpoint = <String, List<(int, Point)>>{};
    for (var i = 0; i < diagram.relations.length; i++) {
      final relation = diagram.relations[i];
      if (relation.endFrom == RelationEnd.extension) {
        byEndpoint
            .putIfAbsent(relation.from, () => [])
            .add((i, boxes[relation.to]!.center));
      }
      if (relation.endTo == RelationEnd.extension) {
        byEndpoint
            .putIfAbsent(relation.to, () => [])
            .add((i, boxes[relation.from]!.center));
      }
    }

    final ports = <(int, String), double>{};
    for (final MapEntry(key: endpointId, value: relations)
        in byEndpoint.entries) {
      final endpoint = boxes[endpointId]!;
      final vertical = diagram.direction == FlowDirection.tb ||
          diagram.direction == FlowDirection.bt;
      relations.sort((a, b) {
        final aCross = vertical ? a.$2.x : a.$2.y;
        final bCross = vertical ? b.$2.x : b.$2.y;
        final crossOrder = aCross.compareTo(bCross);
        return crossOrder != 0 ? crossOrder : a.$1.compareTo(b.$1);
      });

      // A single relation lands on the centre of the endpoint's edge, which is
      // what the even spread below yields for a one-element list.
      final extent = vertical ? endpoint.width : endpoint.height;
      final start = (vertical ? endpoint.center.x : endpoint.center.y) -
          extent / 2;
      for (var index = 0; index < relations.length; index++) {
        ports[(relations[index].$1, endpointId)] =
            start + extent * (index + 1) / (relations.length + 1);
      }
    }
    return ports;
  }

  Point _rankApproachPoint(_Box endpoint, Point other, {double? crossAxis}) {
    if (diagram.direction == FlowDirection.tb ||
        diagram.direction == FlowDirection.bt) {
      final sign = other.y < endpoint.center.y ? -1.0 : 1.0;
      return Point(crossAxis ?? endpoint.center.x,
          endpoint.center.y + sign * (endpoint.height / 2 + _rankSpacing / 2));
    }
    final sign = other.x < endpoint.center.x ? -1.0 : 1.0;
    return Point(
        endpoint.center.x +
            sign * (endpoint.width / 2 + _rankSpacing / 2),
        crossAxis ?? endpoint.center.y);
  }
}

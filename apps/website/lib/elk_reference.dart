library;

import 'package:elk/elk.dart';

import 'elk_stress_examples.dart';
import 'generated/elk_reference_data.g.dart';

class ElkReference {
  const ElkReference({
    required this.elkjsVersion,
    required this.input,
    this.result,
    this.error,
  });

  final String elkjsVersion;
  final Map<String, dynamic> input;
  final ElkResult? result;
  final String? error;
}

ElkReference elkReferenceFor(ElkStressExample example) {
  final rawSnapshot = elkReferenceData[example.title];
  if (rawSnapshot is! Map) {
    throw StateError('Missing elkjs reference for ${example.title}');
  }
  final snapshot = rawSnapshot.cast<String, dynamic>();
  final input = (snapshot['input'] as Map).cast<String, dynamic>();
  final current = elkGraphToJson(example.graph);
  if (!_sameJson(input, current)) {
    throw StateError(
      'Stale elkjs reference for ${example.title}; run '
      'dart run tool/generate_elk_reference.dart.',
    );
  }
  final error = snapshot['error'] as String?;
  final output = snapshot['output'];
  return ElkReference(
    elkjsVersion: snapshot['version'] as String,
    input: input,
    result: output is Map
        ? _decodeResult(output.cast<String, dynamic>())
        : null,
    error: error,
  );
}

bool _sameJson(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (index) => index,
        ).every((index) => _sameJson(a[index], b[index]));
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _sameJson(a[key], b[key]));
  }
  return a == b;
}

Map<String, dynamic> elkGraphToJson(ElkGraph graph) => {
  'id': graph.id,
  'layoutOptions': _options(graph.layoutOptions),
  'children': [for (final node in graph.children) _node(node)],
  'edges': [for (final edge in graph.edges) _edge(edge)],
};

Map<String, dynamic> _options(ElkLayoutOptions o) => {
  'elk.algorithm': o.algorithm,
  'elk.direction': o.direction.name.toUpperCase(),
  'elk.edgeRouting': 'ORTHOGONAL',
  'elk.randomSeed': 1,
  'elk.padding':
      '[top=${o.padding.top},left=${o.padding.left},bottom=${o.padding.bottom},right=${o.padding.right}]',
  'elk.hierarchyHandling': switch (o.hierarchyHandling) {
    ElkHierarchyHandling.inherit => 'INHERIT',
    ElkHierarchyHandling.includeChildren => 'INCLUDE_CHILDREN',
    ElkHierarchyHandling.separateChildren => 'SEPARATE_CHILDREN',
  },
  'elk.spacing.nodeNode': o.resolvedNodeNode,
  'elk.spacing.edgeNode': o.resolvedEdgeNode,
  'elk.layered.spacing.nodeNodeBetweenLayers': o.resolvedNodeNodeBetweenLayers,
  'elk.layered.spacing.edgeNodeBetweenLayers': o.resolvedEdgeNode,
  'elk.spacing.edgeEdge': o.spacingEdgeEdge,
  'elk.layered.spacing.edgeEdgeBetweenLayers': o.spacingEdgeEdge,
  'elk.spacing.labelLabel': o.spacingLabelLabel,
  'elk.spacing.edgeLabel': o.spacingEdgeLabel,
  'elk.spacing.labelNode': o.spacingNodeLabel,
  'elk.spacing.labelPortHorizontal': o.spacingPortLabel,
  'elk.spacing.labelPortVertical': o.spacingPortLabel,
  'elk.spacing.portsSurrounding':
      '[top=${o.spacingPortsSurroundingTop},bottom=${o.spacingPortsSurroundingBottom}]',
  'elk.spacing.nodeSelfLoop': o.resolvedNodeSelfLoop,
  'elk.layered.mergeEdges': o.mergeEdges,
  'elk.layered.nodePlacement.bk.fixedAlignment': switch (o.fixedAlignment) {
    ElkFixedAlignment.none => 'NONE',
    ElkFixedAlignment.leftUp => 'LEFTUP',
    ElkFixedAlignment.leftDown => 'LEFTDOWN',
    ElkFixedAlignment.rightUp => 'RIGHTUP',
    ElkFixedAlignment.rightDown => 'RIGHTDOWN',
    ElkFixedAlignment.balanced => 'BALANCED',
  },
  'elk.layered.nodePlacement.bk.edgeStraightening': o.improveStraightness
      ? 'IMPROVE_STRAIGHTNESS'
      : 'NONE',
  'elk.layered.cycleBreaking.strategy': _enumName(o.cycleBreaking.name),
  'elk.layered.considerModelOrder.strategy': _enumName(
    o.considerModelOrder.name,
  ),
  'elk.layered.crossingMinimization.forceNodeModelOrder': o.forceNodeModelOrder,
};

Map<String, dynamic> _node(ElkNode n) => {
  'id': n.id,
  if (n.x != null) 'x': n.x,
  if (n.y != null) 'y': n.y,
  'width': n.width,
  'height': n.height,
  'layoutOptions': {
    // Direction is the only nested graph override implemented by Dart ELK.
    if (n.layoutOptions != null)
      'elk.direction': n.layoutOptions!.direction.name.toUpperCase(),
    if (n.ports.isNotEmpty && n.ports.every((port) => port.side != null))
      'elk.portConstraints': 'FIXED_SIDE',
    if (!n.fixedSize)
      'elk.nodeSize.constraints': [
        if (n.sizeForLabels) 'NODE_LABELS',
        if (n.sizeForPorts) 'PORTS',
        if (n.preserveMinimumSize) 'MINIMUM_SIZE',
      ].join(' '),
    if (n.labels.isNotEmpty)
      'elk.nodeLabels.placement': switch (n.labelPlacement ??
          (n.children.isEmpty
              ? ElkNodeLabelPlacement.topLeft
              : ElkNodeLabelPlacement.topCenter)) {
        ElkNodeLabelPlacement.topLeft => 'INSIDE V_TOP H_LEFT',
        ElkNodeLabelPlacement.topCenter => 'INSIDE V_TOP H_CENTER',
        ElkNodeLabelPlacement.center => 'INSIDE V_CENTER H_CENTER',
        ElkNodeLabelPlacement.bottomCenter => 'INSIDE V_BOTTOM H_CENTER',
      },
  },
  if (n.children.isNotEmpty)
    'children': [for (final child in n.children) _node(child)],
  if (n.edges.isNotEmpty) 'edges': [for (final edge in n.edges) _edge(edge)],
  if (n.labels.isNotEmpty)
    'labels': [for (final label in n.labels) _label(label)],
  if (n.ports.isNotEmpty) 'ports': [for (final port in n.ports) _port(port)],
};

Map<String, dynamic> _port(ElkPort p) => {
  'id': p.id,
  'width': p.width,
  'height': p.height,
  'layoutOptions': {
    if (p.side != null) 'elk.port.side': p.side!.name.toUpperCase(),
  },
  if (p.labels.isNotEmpty)
    'labels': [for (final label in p.labels) _label(label)],
};

Map<String, dynamic> _edge(ElkEdge e) => {
  'id': e.id,
  'sources': e.sources,
  'targets': e.targets,
  'layoutOptions': {'elk.edge.thickness': e.thickness},
  if (e.labels.isNotEmpty)
    'labels': [for (final label in e.labels) _label(label, edge: true)],
};

Map<String, dynamic> _label(ElkLabel l, {bool edge = false}) => {
  'text': l.text,
  'width': l.width,
  'height': l.height,
  if (edge)
    'layoutOptions': {
      'elk.edgeLabels.placement': l.placement.name.toUpperCase(),
      'elk.layered.edgeLabels.sideSelection': l.side == ElkLabelSide.below
          ? 'ALWAYS_DOWN'
          : 'ALWAYS_UP',
    },
};

String _enumName(String value) =>
    value.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();

ElkResult _decodeResult(Map<String, dynamic> root) {
  final edges = <ElkPositionedEdge>[];
  final origins = <String, ElkPoint>{
    '${root['id'] ?? 'root'}': const ElkPoint(0, 0),
  };
  void indexOrigins(Map<String, dynamic> raw, double dx, double dy) {
    for (final item
        in raw['children'] is List ? raw['children'] as List : const []) {
      if (item is! Map) continue;
      final child = item.cast<String, dynamic>();
      final x = dx + _number(child['x']);
      final y = dy + _number(child['y']);
      origins['${child['id']}'] = ElkPoint(x, y);
      indexOrigins(child, x, y);
    }
  }

  indexOrigins(root, 0, 0);
  late void Function(Object?, double, double) collectEdges;

  List<ElkPositionedLabel> labels(Object? raw, double dx, double dy) => [
    for (final item in raw is List ? raw : const [])
      if (item is Map)
        ElkPositionedLabel(
          text: '${item['text'] ?? ''}',
          x: _number(item['x']) + dx,
          y: _number(item['y']) + dy,
          width: _number(item['width']),
          height: _number(item['height']),
        ),
  ];

  ElkPositionedNode node(Map<String, dynamic> raw, double absX, double absY) {
    final x = _number(raw['x']);
    final y = _number(raw['y']);
    final ownX = absX + x;
    final ownY = absY + y;
    collectEdges(raw['edges'], ownX, ownY);
    return ElkPositionedNode(
      id: '${raw['id']}',
      x: x,
      y: y,
      width: _number(raw['width']),
      height: _number(raw['height']),
      labels: labels(raw['labels'], 0, 0),
      ports: [
        for (final item
            in raw['ports'] is List ? raw['ports'] as List : const [])
          if (item is Map)
            ElkPositionedPort(
              id: '${item['id']}',
              x: _number(item['x']),
              y: _number(item['y']),
              width: _number(item['width']),
              height: _number(item['height']),
              labels: labels(item['labels'], 0, 0),
            ),
      ],
      children: [
        for (final item
            in raw['children'] is List ? raw['children'] as List : const [])
          if (item is Map) node(item.cast<String, dynamic>(), ownX, ownY),
      ],
    );
  }

  collectEdges = (Object? rawEdges, double dx, double dy) {
    for (final item in rawEdges is List ? rawEdges : const []) {
      if (item is! Map) continue;
      final raw = item.cast<String, dynamic>();
      final container = origins['${raw['container']}'];
      final edgeDx = container?.x ?? dx;
      final edgeDy = container?.y ?? dy;
      final sections = <ElkEdgeSection>[
        for (final section
            in raw['sections'] is List ? raw['sections'] as List : const [])
          if (section is Map)
            ElkEdgeSection(
              startPoint: _point(section['startPoint'], edgeDx, edgeDy),
              bendPoints: [
                for (final point
                    in section['bendPoints'] is List
                        ? section['bendPoints'] as List
                        : const [])
                  _point(point, edgeDx, edgeDy),
              ],
              endPoint: _point(section['endPoint'], edgeDx, edgeDy),
            ),
      ];
      edges.add(
        ElkPositionedEdge(
          id: '${raw['id']}',
          sections: sections,
          labels: labels(raw['labels'], edgeDx, edgeDy),
          junctionPoints: [
            for (final point
                in raw['junctionPoints'] is List
                    ? raw['junctionPoints'] as List
                    : const [])
              _point(point, edgeDx, edgeDy),
          ],
        ),
      );
    }
  };

  collectEdges(root['edges'], 0, 0);
  final children = [
    for (final item
        in root['children'] is List ? root['children'] as List : const [])
      if (item is Map) node(item.cast<String, dynamic>(), 0, 0),
  ];
  return ElkResult(
    width: _number(root['width']),
    height: _number(root['height']),
    children: children,
    edges: edges,
  );
}

ElkPoint _point(Object? raw, double dx, double dy) {
  final point = (raw as Map).cast<String, dynamic>();
  return ElkPoint(_number(point['x']) + dx, _number(point['y']) + dy);
}

double _number(Object? value) => (value as num?)?.toDouble() ?? 0;

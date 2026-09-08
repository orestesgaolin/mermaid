import '../api/graph.dart';
import '../api/result.dart';

/// Expand public multi-endpoint edges into shared-port branches for the layered
/// pipeline, then restore the public identity and sections in its result.
class HyperedgeExpansion {
  HyperedgeExpansion(ElkGraph input) {
    final nodes = <String, ElkNode>{};
    final declaredPorts = <String>{};
    final used = <String>{};
    void scan(List<ElkNode> values, List<ElkEdge> edges) {
      for (final e in edges) {
        used.add(e.id);
      }
      for (final n in values) {
        nodes[n.id] = n;
        used.add(n.id);
        for (final p in n.ports) {
          declaredPorts.add(p.id);
          used.add(p.id);
        }
        scan(n.children, n.edges);
      }
    }

    scan(input.children, input.edges);
    var next = 0;
    String fresh() {
      String id;
      do {
        id = '__elk_hyper_${next++}';
      } while (used.contains(id));
      used.add(id);
      return id;
    }

    final extraPorts = <String, List<ElkPort>>{};
    final shared = <String, String>{};
    String port(ElkEdge edge, String endpoint, bool source) {
      if (declaredPorts.contains(endpoint) || !nodes.containsKey(endpoint))
        return endpoint;
      final key = '${edge.id}\u0000$endpoint\u0000$source';
      return shared.putIfAbsent(key, () {
        final id = fresh();
        syntheticPorts.add(id);
        (extraPorts[endpoint] ??= []).add(ElkPort(id: id));
        return id;
      });
    }

    List<ElkEdge> expand(List<ElkEdge> edges) => [
      for (final edge in edges)
        if (edge.sources.length <= 1 && edge.targets.length <= 1)
          edge
        else
          ...(() {
            final branches = <ElkEdge>[];
            for (final source in edge.sources) {
              for (final target in edge.targets) {
                final id = fresh();
                originalId[id] = edge.id;
                branches.add(
                  ElkEdge(
                    id: id,
                    sources: [port(edge, source, true)],
                    targets: [port(edge, target, false)],
                    labels: branches.isEmpty ? edge.labels : const [],
                    thickness: edge.thickness,
                  ),
                );
              }
            }
            return branches;
          })(),
    ];
    // Expand all edge scopes before cloning nodes so descendants can receive
    // ports requested by an edge declared at an ancestor or sibling scope.
    final rootEdges = expand(input.edges);
    final nestedEdges = <String, List<ElkEdge>>{};
    for (final n in nodes.values) {
      nestedEdges[n.id] = expand(n.edges);
    }
    List<ElkNode> clone(List<ElkNode> values) => [
      for (final n in values)
        ElkNode(
          id: n.id,
          x: n.x,
          y: n.y,
          width: n.width,
          height: n.height,
          children: clone(n.children),
          edges: nestedEdges[n.id]!,
          labels: n.labels,
          ports: [...n.ports, ...?extraPorts[n.id]],
          layoutOptions: n.layoutOptions,
          labelPlacement: n.labelPlacement,
          fixedSize: n.fixedSize,
          sizeForLabels: n.sizeForLabels,
          sizeForPorts: n.sizeForPorts,
          preserveMinimumSize: n.preserveMinimumSize,
          inLayerSuccessors: n.inLayerSuccessors,
          barycenterAssociates: n.barycenterAssociates,
        ),
    ];
    graph = ElkGraph(
      id: input.id,
      layoutOptions: input.layoutOptions,
      children: clone(input.children),
      edges: rootEdges,
    );
  }
  late final ElkGraph graph;
  final originalId = <String, String>{};
  final syntheticPorts = <String>{};

  ElkResult restore(ElkResult result) {
    if (originalId.isEmpty) return result;
    final groups = <String, List<ElkPositionedEdge>>{};
    for (final edge in result.edges) {
      (groups[originalId[edge.id] ?? edge.id] ??= []).add(edge);
    }
    List<ElkPositionedNode> clean(List<ElkPositionedNode> nodes) => [
      for (final n in nodes)
        ElkPositionedNode(
          id: n.id,
          x: n.x,
          y: n.y,
          width: n.width,
          height: n.height,
          children: clean(n.children),
          labels: n.labels,
          ports: n.ports.where((p) => !syntheticPorts.contains(p.id)).toList(),
        ),
    ];
    return ElkResult(
      width: result.width,
      height: result.height,
      children: clean(result.children),
      edges: [
        for (final entry in groups.entries)
          ElkPositionedEdge(
            id: entry.key,
            sections: [for (final edge in entry.value) ...edge.sections],
            labels: [for (final edge in entry.value) ...edge.labels],
            junctionPoints: uniquePoints([
              for (final edge in entry.value) ...edge.junctionPoints,
            ]),
          ),
      ],
    );
  }
}

List<ElkPoint> uniquePoints(Iterable<ElkPoint> points) {
  final result = <ElkPoint>[];
  for (final p in points) {
    if (!result.any(
      (q) => (q.x - p.x).abs() < 1e-8 && (q.y - p.y).abs() < 1e-8,
    ))
      result.add(p);
  }
  return result;
}

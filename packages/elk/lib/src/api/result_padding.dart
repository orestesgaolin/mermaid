import 'options.dart';
import 'result.dart';

/// Insets the completed geometry after all direction transforms and branch
/// restoration. Only root nodes and absolute edge geometry move; child nodes,
/// node labels and ports retain their coordinates relative to their owner.
ElkResult padRootResult(ElkResult result, ElkPadding padding) {
  if (padding.top == 0 &&
      padding.left == 0 &&
      padding.bottom == 0 &&
      padding.right == 0)
    return result;
  ElkPoint point(ElkPoint value) =>
      ElkPoint(value.x + padding.left, value.y + padding.top);
  return ElkResult(
    width: result.width + padding.left + padding.right,
    height: result.height + padding.top + padding.bottom,
    children: [
      for (final node in result.children)
        ElkPositionedNode(
          id: node.id,
          x: node.x + padding.left,
          y: node.y + padding.top,
          width: node.width,
          height: node.height,
          children: node.children,
          labels: node.labels,
          ports: node.ports,
        ),
    ],
    edges: [
      for (final edge in result.edges)
        ElkPositionedEdge(
          id: edge.id,
          sections: [
            for (final section in edge.sections)
              ElkEdgeSection(
                startPoint: point(section.startPoint),
                endPoint: point(section.endPoint),
                bendPoints: section.bendPoints.map(point).toList(),
              ),
          ],
          junctionPoints: edge.junctionPoints.map(point).toList(),
          labels: [
            for (final label in edge.labels)
              ElkPositionedLabel(
                text: label.text,
                x: label.x + padding.left,
                y: label.y + padding.top,
                width: label.width,
                height: label.height,
              ),
          ],
        ),
    ],
  );
}

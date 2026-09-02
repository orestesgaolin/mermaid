/// Paint-only flowchart updates over an existing render scene.
library;

import '../../color.dart';
import '../../ir/scene.dart';

class FlowNodePaintOverride {
  const FlowNodePaintOverride({
    this.fill,
    this.stroke,
    this.strokeWidth,
    this.strokeDash,
    this.textColor,
  }) : assert(strokeWidth == null || strokeWidth >= 0);

  final Color? fill;
  final Color? stroke;
  final double? strokeWidth;

  /// Replacement dash pattern. An empty list makes the stroke solid; null
  /// keeps the base scene pattern.
  final List<double>? strokeDash;
  final Color? textColor;

  @override
  bool operator ==(Object other) =>
      other is FlowNodePaintOverride &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.strokeWidth == strokeWidth &&
      _listEquals(other.strokeDash, strokeDash) &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(
    fill,
    stroke,
    strokeWidth,
    Object.hashAll(strokeDash ?? const []),
    textColor,
  );
}

class FlowLinkPaintOverride {
  const FlowLinkPaintOverride({this.stroke, this.strokeWidth, this.strokeDash})
    : assert(strokeWidth == null || strokeWidth >= 0);

  final Color? stroke;
  final double? strokeWidth;

  /// Replacement dash pattern. An empty list makes the stroke solid; null
  /// keeps the base scene pattern.
  final List<double>? strokeDash;

  @override
  bool operator ==(Object other) =>
      other is FlowLinkPaintOverride &&
      other.stroke == stroke &&
      other.strokeWidth == strokeWidth &&
      _listEquals(other.strokeDash, strokeDash);

  @override
  int get hashCode =>
      Object.hash(stroke, strokeWidth, Object.hashAll(strokeDash ?? const []));
}

bool _listEquals(List<double>? a, List<double>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Returns a paint-restyled copy of [base] without parsing or laying out.
///
/// Geometry, text metrics, group identity, links, tooltips, and scene size are
/// retained exactly. Unknown node ids and link indices are ignored. These
/// resolved overrides intentionally cannot express layout-affecting changes;
/// source, theme, text, topology, engine, interpolation, and spacing changes
/// must produce a new base scene through the normal renderer.
RenderScene applyFlowchartPaintOverrides(
  RenderScene base, {
  Map<String, FlowNodePaintOverride> nodes = const {},
  Map<int, FlowLinkPaintOverride> links = const {},
}) {
  if (nodes.isEmpty && links.isEmpty) return base;

  SceneNode restyle(
    SceneNode node,
    FlowNodePaintOverride? nodeOverride,
    FlowLinkPaintOverride? linkOverride,
  ) => switch (node) {
    SceneGroup(
      :final id,
      :final role,
      :final semanticLabel,
      :final link,
      :final tooltip,
      :final edge,
      :final children,
    ) =>
      SceneGroup(
        id: id,
        role: role,
        semanticLabel: semanticLabel,
        link: link,
        tooltip: tooltip,
        edge: edge,
        children: [
          for (final child in children)
            restyle(
              child,
              role == SceneGroupRole.node && id != null
                  ? nodes[id]
                  : nodeOverride,
              edge == null ? linkOverride : links[edge.linkIndex],
            ),
        ],
      ),
    SceneShape(
      :final geometry,
      :final fill,
      :final stroke,
      :final blendMode,
      :final paintRole,
    ) =>
      SceneShape(
        geometry: geometry,
        fill: _shapeFill(fill, paintRole, nodeOverride, linkOverride),
        stroke: _shapeStroke(stroke, paintRole, nodeOverride, linkOverride),
        blendMode: blendMode,
        paintRole: paintRole,
      ),
    SceneText(
      :final text,
      :final bounds,
      :final style,
      :final color,
      :final align,
      :final rotation,
      :final underline,
      :final paintRole,
    ) =>
      SceneText(
        text: text,
        bounds: bounds,
        style: style,
        color: paintRole == ScenePaintRole.nodeLabel
            ? nodeOverride?.textColor ?? color
            : color,
        align: align,
        rotation: rotation,
        underline: underline,
        paintRole: paintRole,
      ),
  };

  return RenderScene(
    size: base.size,
    background: base.background,
    nodes: [for (final node in base.nodes) restyle(node, null, null)],
  );
}

Fill? _shapeFill(
  Fill? fill,
  ScenePaintRole role,
  FlowNodePaintOverride? node,
  FlowLinkPaintOverride? link,
) {
  if (fill == null) return null;
  final color = switch (role) {
    ScenePaintRole.nodeBody => node?.fill,
    ScenePaintRole.nodeLabel => node?.textColor,
    ScenePaintRole.edgeMarker => link?.stroke,
    _ => null,
  };
  if (color == null) return fill;
  return Fill(color);
}

Stroke? _shapeStroke(
  Stroke? stroke,
  ScenePaintRole role,
  FlowNodePaintOverride? node,
  FlowLinkPaintOverride? link,
) {
  if (stroke == null) return null;
  return switch (role) {
    ScenePaintRole.nodeBody => _copyStroke(
      stroke,
      color: node?.stroke,
      width: node?.strokeWidth ?? stroke.width,
      dash: node?.strokeDash ?? stroke.dash,
    ),
    ScenePaintRole.nodeFill => _copyStroke(stroke, color: node?.fill),
    ScenePaintRole.nodeStroke => _copyStroke(
      stroke,
      color: node?.stroke,
      width: node?.strokeWidth ?? stroke.width,
      dash: node?.strokeDash ?? stroke.dash,
    ),
    ScenePaintRole.nodeLabel ||
    ScenePaintRole.nodeLabelFill ||
    ScenePaintRole.nodeLabelStroke => _copyStroke(
      stroke,
      color: node?.textColor,
    ),
    ScenePaintRole.edgeStroke => _copyStroke(
      stroke,
      color: link?.stroke,
      width: link?.strokeWidth ?? stroke.width,
      dash: link?.strokeDash ?? stroke.dash,
    ),
    ScenePaintRole.edgeMarker ||
    ScenePaintRole.edgeMarkerFill ||
    ScenePaintRole.edgeMarkerStroke => _copyStroke(stroke, color: link?.stroke),
    ScenePaintRole.none => stroke,
  };
}

Stroke _copyStroke(
  Stroke stroke, {
  Color? color,
  double? width,
  List<double>? dash,
}) => Stroke(
  color: color ?? stroke.color,
  width: width ?? stroke.width,
  dash: dash ?? stroke.dash,
  gradient: color == null ? stroke.gradient : null,
);

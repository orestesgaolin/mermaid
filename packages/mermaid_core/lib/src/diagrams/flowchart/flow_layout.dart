/// Flowchart layout: sizes nodes via the text measurer, runs dagre, routes
/// edges, and emits a fully resolved RenderScene.
library;

import '../../ir/scene.dart';
import '../../text/text_measurer.dart';
import '../../theme/theme.dart';
import 'flow_model.dart';

RenderScene layoutFlowchart(
  FlowGraph graph, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  throw UnimplementedError('flowchart layout not yet implemented');
}

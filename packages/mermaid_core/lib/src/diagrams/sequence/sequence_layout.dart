/// Sequence diagram layout: bespoke column-per-participant positioning,
/// emitting a RenderScene.
library;

import '../../ir/scene.dart';
import '../../text/text_measurer.dart';
import '../../theme/theme.dart';
import 'sequence_model.dart';

RenderScene layoutSequence(
  SequenceDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  throw UnimplementedError('sequence layout not yet implemented');
}

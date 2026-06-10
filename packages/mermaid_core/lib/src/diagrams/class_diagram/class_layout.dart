/// Class diagram layout: dagre-positioned compartment boxes with UML
/// relation markers, emitting a RenderScene.
library;

import '../../ir/scene.dart';
import '../../text/text_measurer.dart';
import '../../theme/theme.dart';
import 'class_model.dart';

RenderScene layoutClassDiagram(
  ClassDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  throw UnimplementedError('class diagram layout not yet implemented');
}

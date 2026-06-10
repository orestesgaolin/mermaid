/// Top-level facade: source text in, render scene out.
library;

import 'detect.dart';
import 'diagrams/class_diagram/class_layout.dart';
import 'diagrams/class_diagram/class_parser.dart';
import 'diagrams/flowchart/flow_layout.dart';
import 'diagrams/flowchart/flow_parser.dart';
import 'diagrams/sequence/sequence_layout.dart';
import 'diagrams/sequence/sequence_parser.dart';
import 'ir/scene.dart';
import 'parse_error.dart';
import 'text/text_measurer.dart';
import 'theme/theme.dart';

class Mermaid {
  const Mermaid({
    required this.measurer,
    this.theme = MermaidTheme.defaultTheme,
  });

  final TextMeasurer measurer;
  final MermaidTheme theme;

  /// Parses [source], lays it out, and returns the scene.
  ///
  /// Throws [MermaidParseException] on syntax errors and
  /// [UnsupportedError] for not-yet-ported diagram types.
  RenderScene render(String source) {
    switch (detectDiagramType(source)) {
      case DiagramType.flowchart:
        return layoutFlowchart(parseFlowchart(source),
            measurer: measurer, theme: theme);
      case DiagramType.sequence:
        return layoutSequence(parseSequence(source),
            measurer: measurer, theme: theme);
      case DiagramType.classDiagram:
        return layoutClassDiagram(parseClassDiagram(source),
            measurer: measurer, theme: theme);
      case DiagramType.unknown:
        throw UnsupportedError(
          'Unrecognized or not-yet-supported diagram type. '
          'Currently supported: flowchart, sequenceDiagram, classDiagram.',
        );
    }
  }
}

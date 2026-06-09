/// Hand-written recursive descent parser for mermaid flowchart syntax.
library;

import 'flow_model.dart';

/// Parses flowchart source (including optional frontmatter, directives and
/// `%%` comments) into a [FlowGraph].
///
/// Throws `MermaidParseException` on syntax errors.
FlowGraph parseFlowchart(String source) {
  throw UnimplementedError('flowchart parser not yet implemented');
}

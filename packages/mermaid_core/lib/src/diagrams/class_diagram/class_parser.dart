/// Hand-written parser for mermaid class diagrams.
library;

import 'class_model.dart';

/// Parses class diagram source (frontmatter/directives/comments included)
/// into a [ClassDiagram].
///
/// Throws `MermaidParseException` on syntax errors.
ClassDiagram parseClassDiagram(String source) {
  throw UnimplementedError('class diagram parser not yet implemented');
}

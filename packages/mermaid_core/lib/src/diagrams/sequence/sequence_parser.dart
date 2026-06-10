/// Hand-written parser for mermaid sequence diagrams.
library;

import 'sequence_model.dart';

/// Parses sequence diagram source (frontmatter/directives/comments included)
/// into a [SequenceDiagram].
///
/// Throws `MermaidParseException` on syntax errors.
SequenceDiagram parseSequence(String source) {
  throw UnimplementedError('sequence parser not yet implemented');
}

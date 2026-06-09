class MermaidParseException implements Exception {
  const MermaidParseException(this.message, {this.line, this.column, this.source});

  final String message;

  /// 1-based position in the diagram source, when known.
  final int? line;
  final int? column;
  final String? source;

  @override
  String toString() {
    final loc = line != null ? ' at line $line${column != null ? ':$column' : ''}' : '';
    return 'MermaidParseException$loc: $message';
  }
}

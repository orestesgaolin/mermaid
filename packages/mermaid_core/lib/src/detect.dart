/// Diagram type detection, mirroring upstream detectType(): strip frontmatter
/// and directives, then match the first meaningful line against per-diagram
/// patterns in priority order.
library;

enum DiagramType {
  flowchart,
  sequence,
  classDiagram,
  stateDiagram,
  er,
  pie,
  gantt,
  unknown,
}

DiagramType detectDiagramType(String source) {
  final text = stripMetadata(source);
  for (final (type, pattern) in _detectors) {
    if (pattern.hasMatch(text)) return type;
  }
  return DiagramType.unknown;
}

/// Priority-ordered, as in upstream diagram-orchestration.ts.
const _detectorSpecs = <(DiagramType, String)>[
  (DiagramType.classDiagram, r'^\s*classDiagram(-v2)?\b'),
  (DiagramType.stateDiagram, r'^\s*stateDiagram(-v2)?\b'),
  (DiagramType.er, r'^\s*erDiagram\b'),
  (DiagramType.pie, r'^\s*pie\b'),
  (DiagramType.gantt, r'^\s*gantt\b'),
  (DiagramType.sequence, r'^\s*sequenceDiagram\b'),
  (DiagramType.flowchart, r'^\s*graph\b'),
  (DiagramType.flowchart, r'^\s*flowchart(-elk)?\b'),
];

final _detectors = [
  for (final (type, src) in _detectorSpecs) (type, RegExp(src)),
];

/// Removes YAML frontmatter (`--- ... ---` at the very top), `%%{init}%%`
/// directives and `%%` comment lines, returning text whose first line is the
/// diagram keyword line.
String stripMetadata(String source) {
  var text = source.replaceAll('\r\n', '\n');
  final fm = RegExp(r'^\s*---\n[\s\S]*?\n---\n').firstMatch(text);
  if (fm != null) text = text.substring(fm.end);
  text = text.replaceAll(RegExp(r'%%\{[\s\S]*?\}%%'), '');
  final lines = text.split('\n').where((l) {
    final t = l.trimLeft();
    return t.isNotEmpty && !(t.startsWith('%%') && !t.startsWith('%%{'));
  });
  return lines.join('\n');
}

/// Extracts `title:` from YAML frontmatter if present.
String? frontmatterTitle(String source) {
  final text = source.replaceAll('\r\n', '\n');
  final fm = RegExp(r'^\s*---\n([\s\S]*?)\n---\n').firstMatch(text);
  if (fm == null) return null;
  final m = RegExp(r'^title:\s*(.+)$', multiLine: true).firstMatch(fm.group(1)!);
  return m?.group(1)?.trim();
}

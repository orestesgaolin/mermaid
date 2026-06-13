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
  quadrant,
  journey,
  timeline,
  xychart,
  mindmap,
  requirement,
  c4,
  gitGraph,
  sankey,
  packet,
  block,
  radar,
  treemap,
  kanban,
  architecture,
  cynefin,
  venn,
  ishikawa,
  wardley,
  eventModeling,
  railroad,
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
  (DiagramType.quadrant, r'^\s*quadrantChart\b'),
  (DiagramType.journey, r'^\s*journey\b'),
  (DiagramType.timeline, r'^\s*timeline\b'),
  (DiagramType.xychart, r'^\s*xychart(-beta)?\b'),
  (DiagramType.mindmap, r'^\s*mindmap\b'),
  (DiagramType.requirement, r'^\s*requirementDiagram\b'),
  (DiagramType.c4, r'^\s*C4(Context|Container|Component|Dynamic|Deployment)\b'),
  (DiagramType.gitGraph, r'^\s*gitGraph\b'),
  (DiagramType.sankey, r'^\s*sankey(-beta)?\b'),
  (DiagramType.packet, r'^\s*packet(-beta)?\b'),
  (DiagramType.block, r'^\s*block(-beta)?\b'),
  (DiagramType.radar, r'^\s*radar(-beta)?\b'),
  (DiagramType.treemap, r'^\s*treemap(-beta)?\b'),
  (DiagramType.kanban, r'^\s*kanban\b'),
  (DiagramType.architecture, r'^\s*architecture(-beta)?\b'),
  (DiagramType.cynefin, r'^\s*cynefin(-beta)?\b'),
  (DiagramType.venn, r'^\s*venn(-beta)?\b'),
  (DiagramType.ishikawa, r'^\s*ishikawa(-beta)?\b'),
  (DiagramType.wardley, r'^\s*wardley(-beta)?\b'),
  (DiagramType.eventModeling, r'^\s*eventmodeling\b'),
  (DiagramType.railroad, r'^\s*railroad(-diagram|-beta)?\b'),
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
  // Frontmatter fences may be indented (common in demo/docs sources).
  final fm =
      RegExp(r'^\s*---[ \t]*\n[\s\S]*?\n[ \t]*---[ \t]*\n').firstMatch(text);
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
  final fm = RegExp(r'^\s*---[ \t]*\n([\s\S]*?)\n[ \t]*---[ \t]*\n')
      .firstMatch(text);
  if (fm == null) return null;
  final m =
      RegExp(r'^\s*title:\s*(.+)$', multiLine: true).firstMatch(fm.group(1)!);
  return m?.group(1)?.trim();
}

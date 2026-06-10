/// Immutable model for a parsed gantt chart. Task dates are fully resolved
/// at parse time (the parser implements `after`/duration sequencing).
library;

class GanttChart {
  const GanttChart({
    required this.sections,
    this.title,
    this.axisFormat,
  });

  /// Tasks outside any `section` land in a section with an empty name.
  final List<GanttSection> sections;
  final String? title;

  /// strftime-style axis label format (subset), e.g. `%m-%d`.
  final String? axisFormat;

  Iterable<GanttTask> get tasks sync* {
    for (final s in sections) {
      yield* s.tasks;
    }
  }
}

class GanttSection {
  const GanttSection({required this.name, required this.tasks});

  final String name;
  final List<GanttTask> tasks;
}

class GanttTask {
  const GanttTask({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.active = false,
    this.done = false,
    this.crit = false,
    this.milestone = false,
  });

  final String id;
  final String name;
  final DateTime start;
  final DateTime end;
  final bool active;
  final bool done;
  final bool crit;
  final bool milestone;
}

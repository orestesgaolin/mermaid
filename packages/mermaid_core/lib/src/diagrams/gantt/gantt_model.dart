/// Immutable model for a parsed gantt chart. Task dates are fully resolved
/// at parse time (the parser implements `after`/duration sequencing).
library;

class GanttChart {
  const GanttChart({
    required this.sections,
    this.title,
    this.axisFormat,
    this.excludeWeekdays = const {},
    this.excludeDates = const {},
    this.todayMarkerOff = false,
  });

  /// Tasks outside any `section` land in a section with an empty name.
  final List<GanttSection> sections;
  final String? title;

  /// strftime-style axis label format (subset), e.g. `%m-%d`.
  final String? axisFormat;

  /// Weekdays excluded via `excludes weekends` / `excludes monday` (1=Mon..7=Sun).
  final Set<int> excludeWeekdays;

  /// Specific `YYYY-MM-DD` dates excluded.
  final Set<DateTime> excludeDates;

  /// `todayMarker off` hides the current-date line.
  final bool todayMarkerOff;

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
    DateTime? renderEnd,
    this.active = false,
    this.done = false,
    this.crit = false,
    this.milestone = false,
  }) : renderEnd = renderEnd ?? end;

  final String id;
  final String name;
  final DateTime start;

  /// Sequencing end: the end used by `after` dependents and the axis domain.
  /// When excluded days (weekends / `excludes <date>`) fall inside a
  /// duration-based task, this is pushed past them so the task keeps its full
  /// count of working days (upstream `checkTaskDates`/`fixTaskDates`).
  final DateTime end;

  /// Drawn end of the bar. Equals [end] for manual-end and milestone tasks and
  /// when there are no excludes; otherwise it is the original (unextended) end,
  /// matching upstream's `renderEndTime`.
  final DateTime renderEnd;
  final bool active;
  final bool done;
  final bool crit;
  final bool milestone;
}

/// Hand-written parser for mermaid gantt charts.
///
/// Grammar reference: upstream `gantt/parser/gantt.jison` + ganttDb.ts task
/// metadata resolution (tags, ids, `after` dependencies, durations).
library;

import '../../detect.dart';
import '../../parse_error.dart';
import 'gantt_dates.dart';
import 'gantt_model.dart';

GanttChart parseGanttChart(String source) {
  final frontTitle = frontmatterTitle(source);
  return _GanttParser(stripMetadata(source), frontTitle).parse();
}

class _GanttParser {
  _GanttParser(this.text, this.frontTitle);

  final String text;
  final String? frontTitle;

  String? title;
  String? axisFormat;
  var dateFormat = 'YYYY-MM-DD';
  final sections = <(String, List<GanttTask>)>[];
  final byId = <String, GanttTask>{};
  GanttTask? lastTask;
  var _autoId = 0;

  GanttChart parse() {
    title = frontTitle;
    final lines = text.split('\n');
    var seenHeader = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      final comment = line.indexOf('%%');
      if (comment >= 0) line = line.substring(0, comment).trim();
      if (line.isEmpty) continue;
      if (!seenHeader) {
        if (!RegExp(r'^gantt\b').hasMatch(line)) {
          throw MermaidParseException('expected "gantt" header', line: i + 1);
        }
        seenHeader = true;
        continue;
      }
      _parseStatement(line, i + 1);
    }
    if (!seenHeader) {
      throw const MermaidParseException('empty gantt source');
    }
    return GanttChart(
      sections: [
        for (final (name, tasks) in sections)
          if (tasks.isNotEmpty) GanttSection(name: name, tasks: tasks),
      ],
      title: title,
      axisFormat: axisFormat,
    );
  }

  void _parseStatement(String line, int n) {
    Match? m;

    m = RegExp(r'^dateFormat\s+(.+)$').firstMatch(line);
    if (m != null) {
      dateFormat = m.group(1)!.trim();
      return;
    }
    m = RegExp(r'^axisFormat\s+(.+)$').firstMatch(line);
    if (m != null) {
      axisFormat = m.group(1)!.trim();
      return;
    }
    m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      return;
    }
    m = RegExp(r'^section\s+(.+)$').firstMatch(line);
    if (m != null) {
      sections.add((m.group(1)!.trim(), []));
      return;
    }
    // Recognized-but-unsupported settings: parsed and ignored.
    if (RegExp(r'^(excludes|includes|todayMarker|inclusiveEndDates|'
            r'topAxis|weekday|tickInterval|displayMode|compact|'
            r'click|link|call|acc(Title|Descr))\b')
        .hasMatch(line)) {
      return;
    }

    final colon = line.indexOf(':');
    if (colon > 0) {
      _parseTask(line.substring(0, colon).trim(),
          line.substring(colon + 1).trim(), n);
      return;
    }

    throw MermaidParseException('unrecognized statement "$line"', line: n);
  }

  /// Metadata: `[tags...,] [id,] [start,] end-or-duration` per ganttDb.
  void _parseTask(String name, String meta, int n) {
    final parts = meta.split(',').map((p) => p.trim()).toList();
    var active = false, done = false, crit = false, milestone = false;
    while (parts.isNotEmpty &&
        RegExp(r'^(active|done|crit|milestone)$').hasMatch(parts.first)) {
      switch (parts.removeAt(0)) {
        case 'active':
          active = true;
        case 'done':
          done = true;
        case 'crit':
          crit = true;
        default:
          milestone = true;
      }
    }

    String? id;
    DateTime? start;
    DateTime? end;
    Duration? duration;

    DateTime? asDate(String s) => parseGanttDate(s, dateFormat);

    // The first remaining part may be an id: it is one when it's neither a
    // date, a duration, nor an `after` clause, and more parts follow.
    if (parts.length > 1 &&
        asDate(parts.first) == null &&
        parseGanttDuration(parts.first) == null &&
        !parts.first.startsWith('after ') &&
        !parts.first.startsWith('until ')) {
      id = parts.removeAt(0);
    }

    for (final part in parts) {
      if (part.isEmpty) continue;
      if (part.startsWith('after ')) {
        // Latest end among the referenced tasks.
        DateTime? latest;
        for (final ref in part.substring(6).split(RegExp(r'\s+'))) {
          final t = byId[ref];
          if (t != null && (latest == null || t.end.isAfter(latest))) {
            latest = t.end;
          }
        }
        start = latest ?? lastTask?.end ?? DateTime(2024);
        continue;
      }
      final date = asDate(part);
      if (date != null) {
        if (start == null) {
          start = date;
        } else {
          end = date;
        }
        continue;
      }
      final dur = parseGanttDuration(part);
      if (dur != null) {
        duration = dur;
        continue;
      }
      // Unparseable metadata (typos, exotic dateFormats) is ignored, like
      // upstream's lenient task resolution; sequencing fallbacks apply.
    }

    start ??= lastTask?.end ?? DateTime(2024);
    end ??= duration != null
        ? start.add(duration)
        : start.add(const Duration(days: 1));
    if (milestone) end = start;

    final task = GanttTask(
      id: id ?? 'task${_autoId++}',
      name: name,
      start: start,
      end: end,
      active: active,
      done: done,
      crit: crit,
      milestone: milestone,
    );
    byId[task.id] = task;
    lastTask = task;
    if (sections.isEmpty) sections.add(('', []));
    sections.last.$2.add(task);
  }
}

/// Minimal date parsing/formatting for gantt charts — covers the dateFormat
/// and axisFormat subsets that real-world mermaid gantt sources use, without
/// a dayjs-equivalent dependency.
library;

/// Parses [text] according to a dayjs-style [format] containing the tokens
/// YYYY, MM, DD, HH, mm, ss with literal separators. Returns null when the
/// text does not match.
DateTime? parseGanttDate(String text, String format) {
  const tokens = ['YYYY', 'MM', 'DD', 'HH', 'mm', 'ss'];
  final values = <String, int>{};
  var ti = 0; // index in text
  var fi = 0; // index in format
  while (fi < format.length) {
    String? token;
    for (final t in tokens) {
      if (format.startsWith(t, fi)) {
        token = t;
        break;
      }
    }
    if (token != null) {
      final len = token == 'YYYY' ? 4 : 2;
      if (ti + len > text.length) return null;
      final v = int.tryParse(text.substring(ti, ti + len));
      if (v == null) return null;
      values[token] = v;
      ti += len;
      fi += token.length;
    } else {
      if (ti >= text.length || text[ti] != format[fi]) return null;
      ti++;
      fi++;
    }
  }
  if (ti != text.length) return null;
  return DateTime(
    values['YYYY'] ?? 1970,
    values['MM'] ?? 1,
    values['DD'] ?? 1,
    values['HH'] ?? 0,
    values['mm'] ?? 0,
    values['ss'] ?? 0,
  );
}

/// Parses durations like `30m`, `4h`, `1d`, `2w` (mermaid taskDuration).
Duration? parseGanttDuration(String text) {
  final m = RegExp(r'^(\d+(?:\.\d+)?)(ms|s|m|h|d|w)$').firstMatch(text.trim());
  if (m == null) return null;
  final v = double.parse(m.group(1)!);
  return switch (m.group(2)!) {
    'ms' => Duration(microseconds: (v * 1000).round()),
    's' => Duration(milliseconds: (v * 1000).round()),
    'm' => Duration(milliseconds: (v * 60 * 1000).round()),
    'h' => Duration(milliseconds: (v * 3600 * 1000).round()),
    'd' => Duration(milliseconds: (v * 24 * 3600 * 1000).round()),
    _ => Duration(milliseconds: (v * 7 * 24 * 3600 * 1000).round()),
  };
}

const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _daysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// strftime-lite used for axis labels: %Y %m %d %e %b %a %H %M plus
/// literal characters.
String formatGanttDate(DateTime d, String format) {
  final out = StringBuffer();
  for (var i = 0; i < format.length; i++) {
    if (format[i] != '%' || i + 1 >= format.length) {
      out.write(format[i]);
      continue;
    }
    i++;
    out.write(switch (format[i]) {
      'Y' => d.year.toString().padLeft(4, '0'),
      'm' => d.month.toString().padLeft(2, '0'),
      'd' => d.day.toString().padLeft(2, '0'),
      'e' => d.day.toString(),
      'b' => _monthsShort[d.month - 1],
      'a' => _daysShort[d.weekday - 1],
      'H' => d.hour.toString().padLeft(2, '0'),
      'M' => d.minute.toString().padLeft(2, '0'),
      '%' => '%',
      _ => format[i],
    });
  }
  return out.toString();
}

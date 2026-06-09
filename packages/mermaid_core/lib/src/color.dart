/// ARGB color value type with CSS color parsing, independent of dart:ui.
library;

class Color {
  const Color(this.value);

  const Color.fromARGB(int a, int r, int g, int b)
      : value = ((a & 0xff) << 24) | ((r & 0xff) << 16) | ((g & 0xff) << 8) | (b & 0xff);

  /// 0xAARRGGBB
  final int value;

  int get alpha => (value >> 24) & 0xff;
  int get red => (value >> 16) & 0xff;
  int get green => (value >> 8) & 0xff;
  int get blue => value & 0xff;

  static const transparent = Color(0x00000000);
  static const black = Color(0xff000000);
  static const white = Color(0xffffffff);

  Color withOpacity(double opacity) =>
      Color.fromARGB((opacity.clamp(0, 1) * 255).round(), red, green, blue);

  /// Parses `#rgb`, `#rrggbb`, `#aarrggbb`, `rgb()/rgba()` and a small set of
  /// CSS color names. Returns null for unsupported input.
  static Color? tryParse(String css) {
    final s = css.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) {
      final hex = s.substring(1);
      if (hex.length == 3) {
        final r = int.tryParse(hex[0] * 2, radix: 16);
        final g = int.tryParse(hex[1] * 2, radix: 16);
        final b = int.tryParse(hex[2] * 2, radix: 16);
        if (r == null || g == null || b == null) return null;
        return Color.fromARGB(0xff, r, g, b);
      }
      if (hex.length == 6) {
        final v = int.tryParse(hex, radix: 16);
        return v == null ? null : Color(0xff000000 | v);
      }
      if (hex.length == 8) {
        // CSS #rrggbbaa
        final v = int.tryParse(hex, radix: 16);
        if (v == null) return null;
        final a = v & 0xff;
        return Color((a << 24) | (v >> 8));
      }
      return null;
    }
    final rgbMatch = RegExp(r'^rgba?\(([^)]+)\)$').firstMatch(s);
    if (rgbMatch != null) {
      final parts = rgbMatch.group(1)!.split(',').map((p) => p.trim()).toList();
      if (parts.length < 3) return null;
      final r = int.tryParse(parts[0]);
      final g = int.tryParse(parts[1]);
      final b = int.tryParse(parts[2]);
      if (r == null || g == null || b == null) return null;
      final a = parts.length > 3 ? ((double.tryParse(parts[3]) ?? 1) * 255).round() : 255;
      return Color.fromARGB(a, r, g, b);
    }
    return _named[s];
  }

  static const _named = <String, Color>{
    'black': Color(0xff000000),
    'white': Color(0xffffffff),
    'red': Color(0xffff0000),
    'green': Color(0xff008000),
    'blue': Color(0xff0000ff),
    'yellow': Color(0xffffff00),
    'orange': Color(0xffffa500),
    'purple': Color(0xff800080),
    'pink': Color(0xffffc0cb),
    'gray': Color(0xff808080),
    'grey': Color(0xff808080),
    'lightgray': Color(0xffd3d3d3),
    'lightgrey': Color(0xffd3d3d3),
    'lightblue': Color(0xffadd8e6),
    'lightgreen': Color(0xff90ee90),
    'lightyellow': Color(0xffffffe0),
    'cyan': Color(0xff00ffff),
    'magenta': Color(0xffff00ff),
    'brown': Color(0xffa52a2a),
    'beige': Color(0xfff5f5dc),
    'ivory': Color(0xfffffff0),
    'silver': Color(0xffc0c0c0),
    'gold': Color(0xffffd700),
    'teal': Color(0xff008080),
    'navy': Color(0xff000080),
    'maroon': Color(0xff800000),
    'olive': Color(0xff808000),
    'lime': Color(0xff00ff00),
    'aqua': Color(0xff00ffff),
    'fuchsia': Color(0xffff00ff),
    'transparent': Color(0x00000000),
    'none': Color(0x00000000),
  };

  @override
  bool operator ==(Object other) => other is Color && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() =>
      'Color(0x${value.toRadixString(16).padLeft(8, '0')})';
}

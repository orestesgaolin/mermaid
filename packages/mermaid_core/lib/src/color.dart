/// ARGB color value type with CSS color parsing, independent of dart:ui.
library;

class Color {
  const Color(this.value);

  const Color.fromARGB(int a, int r, int g, int b)
    : value =
          ((a & 0xff) << 24) |
          ((r & 0xff) << 16) |
          ((g & 0xff) << 8) |
          (b & 0xff);

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

  /// Parses CSS named colors, hex colors, `rgb()`/`rgba()`, and
  /// `hsl()`/`hsla()` colors.
  ///
  /// Eight-digit hex values use the CSS `#rrggbbaa` order. RGB channels and
  /// alpha values are clamped to their CSS ranges. Returns null when the
  /// syntax or a numeric value is invalid. Mermaid source and configuration
  /// consumers treat that null result as an unsupported color and retain the
  /// applicable theme or diagram default; they do not emit a diagnostic.
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
      if (hex.length == 4) {
        final r = int.tryParse(hex[0] * 2, radix: 16);
        final g = int.tryParse(hex[1] * 2, radix: 16);
        final b = int.tryParse(hex[2] * 2, radix: 16);
        final a = int.tryParse(hex[3] * 2, radix: 16);
        if (r == null || g == null || b == null || a == null) return null;
        return Color.fromARGB(a, r, g, b);
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
    final function = RegExp(r'^(rgb|rgba|hsl|hsla)\(([^)]*)\)$').firstMatch(s);
    if (function != null) {
      final name = function.group(1)!;
      final parts = _functionParts(function.group(2)!);
      if (parts == null || (parts.length != 3 && parts.length != 4)) {
        return null;
      }
      if ((name == 'rgba' || name == 'hsla') && parts.length != 4) return null;
      final alpha = parts.length == 4 ? _parseAlpha(parts[3]) : 255;
      if (alpha == null) return null;
      if (name.startsWith('rgb')) {
        final channels = parts.take(3).map(_parseRgbChannel).toList();
        if (channels.any((value) => value == null)) return null;
        return Color.fromARGB(alpha, channels[0]!, channels[1]!, channels[2]!);
      }
      final hue = _parseHue(parts[0]);
      final saturation = _parsePercentage(parts[1]);
      final lightness = _parsePercentage(parts[2]);
      if (hue == null || saturation == null || lightness == null) return null;
      return _fromHsl(hue, saturation, lightness, alpha);
    }
    return _named[s];
  }

  static List<String>? _functionParts(String body) {
    if (body.contains(',')) {
      if (body.contains('/')) return null;
      final parts = body.split(',').map((part) => part.trim()).toList();
      return parts.any((part) => part.isEmpty) ? null : parts;
    }
    final slashParts = body.split('/');
    if (slashParts.length > 2) return null;
    final channels = slashParts.first.trim().split(RegExp(r'\s+'));
    if (channels.length != 3 || channels.any((part) => part.isEmpty)) {
      return null;
    }
    if (slashParts.length == 2) {
      final alpha = slashParts[1].trim();
      if (alpha.isEmpty || alpha.contains(RegExp(r'\s'))) return null;
      channels.add(alpha);
    }
    return channels;
  }

  static int? _parseRgbChannel(String text) {
    final percent = text.endsWith('%');
    final value = double.tryParse(
      percent ? text.substring(0, text.length - 1) : text,
    );
    if (value == null || !value.isFinite) return null;
    return (percent ? value.clamp(0, 100) / 100 * 255 : value.clamp(0, 255))
        .round();
  }

  static int? _parseAlpha(String text) {
    final percent = text.endsWith('%');
    final value = double.tryParse(
      percent ? text.substring(0, text.length - 1) : text,
    );
    if (value == null || !value.isFinite) return null;
    return ((percent ? value.clamp(0, 100) / 100 : value.clamp(0, 1)) * 255)
        .round();
  }

  static double? _parsePercentage(String text) {
    if (!text.endsWith('%')) return null;
    final value = double.tryParse(text.substring(0, text.length - 1));
    if (value == null || !value.isFinite) return null;
    return value.clamp(0, 100) / 100;
  }

  static double? _parseHue(String text) {
    var unit = 'deg';
    var number = text;
    for (final candidate in const ['grad', 'turn', 'rad', 'deg']) {
      if (text.endsWith(candidate)) {
        unit = candidate;
        number = text.substring(0, text.length - candidate.length);
        break;
      }
    }
    final value = double.tryParse(number);
    if (value == null || !value.isFinite) return null;
    final degrees = switch (unit) {
      'grad' => value * 0.9,
      'turn' => value * 360,
      'rad' => value * 180 / 3.141592653589793,
      _ => value,
    };
    return ((degrees % 360) + 360) % 360;
  }

  static Color _fromHsl(
    double hue,
    double saturation,
    double lightness,
    int alpha,
  ) {
    final chroma = (1 - (2 * lightness - 1).abs()) * saturation;
    final segment = hue / 60;
    final x = chroma * (1 - ((segment % 2) - 1).abs());
    final (r1, g1, b1) = switch (segment.floor()) {
      0 => (chroma, x, 0.0),
      1 => (x, chroma, 0.0),
      2 => (0.0, chroma, x),
      3 => (0.0, x, chroma),
      4 => (x, 0.0, chroma),
      _ => (chroma, 0.0, x),
    };
    final m = lightness - chroma / 2;
    return Color.fromARGB(
      alpha,
      ((r1 + m) * 255).round(),
      ((g1 + m) * 255).round(),
      ((b1 + m) * 255).round(),
    );
  }

  static const _named = <String, Color>{
    'aliceblue': Color(0xfff0f8ff), 'antiquewhite': Color(0xfffaebd7),
    'aqua': Color(0xff00ffff), 'aquamarine': Color(0xff7fffd4),
    'azure': Color(0xfff0ffff), 'beige': Color(0xfff5f5dc),
    'bisque': Color(0xffffe4c4), 'black': Color(0xff000000),
    'blanchedalmond': Color(0xffffebcd), 'blue': Color(0xff0000ff),
    'blueviolet': Color(0xff8a2be2), 'brown': Color(0xffa52a2a),
    'burlywood': Color(0xffdeb887), 'cadetblue': Color(0xff5f9ea0),
    'chartreuse': Color(0xff7fff00), 'chocolate': Color(0xffd2691e),
    'coral': Color(0xffff7f50), 'cornflowerblue': Color(0xff6495ed),
    'cornsilk': Color(0xfffff8dc), 'crimson': Color(0xffdc143c),
    'cyan': Color(0xff00ffff), 'darkblue': Color(0xff00008b),
    'darkcyan': Color(0xff008b8b), 'darkgoldenrod': Color(0xffb8860b),
    'darkgray': Color(0xffa9a9a9), 'darkgreen': Color(0xff006400),
    'darkgrey': Color(0xffa9a9a9), 'darkkhaki': Color(0xffbdb76b),
    'darkmagenta': Color(0xff8b008b), 'darkolivegreen': Color(0xff556b2f),
    'darkorange': Color(0xffff8c00), 'darkorchid': Color(0xff9932cc),
    'darkred': Color(0xff8b0000), 'darksalmon': Color(0xffe9967a),
    'darkseagreen': Color(0xff8fbc8f), 'darkslateblue': Color(0xff483d8b),
    'darkslategray': Color(0xff2f4f4f), 'darkslategrey': Color(0xff2f4f4f),
    'darkturquoise': Color(0xff00ced1), 'darkviolet': Color(0xff9400d3),
    'deeppink': Color(0xffff1493), 'deepskyblue': Color(0xff00bfff),
    'dimgray': Color(0xff696969), 'dimgrey': Color(0xff696969),
    'dodgerblue': Color(0xff1e90ff), 'firebrick': Color(0xffb22222),
    'floralwhite': Color(0xfffffaf0), 'forestgreen': Color(0xff228b22),
    'fuchsia': Color(0xffff00ff), 'gainsboro': Color(0xffdcdcdc),
    'ghostwhite': Color(0xfff8f8ff), 'gold': Color(0xffffd700),
    'goldenrod': Color(0xffdaa520), 'gray': Color(0xff808080),
    'green': Color(0xff008000), 'greenyellow': Color(0xffadff2f),
    'grey': Color(0xff808080), 'honeydew': Color(0xfff0fff0),
    'hotpink': Color(0xffff69b4), 'indianred': Color(0xffcd5c5c),
    'indigo': Color(0xff4b0082), 'ivory': Color(0xfffffff0),
    'khaki': Color(0xfff0e68c), 'lavender': Color(0xffe6e6fa),
    'lavenderblush': Color(0xfffff0f5), 'lawngreen': Color(0xff7cfc00),
    'lemonchiffon': Color(0xfffffacd), 'lightblue': Color(0xffadd8e6),
    'lightcoral': Color(0xfff08080), 'lightcyan': Color(0xffe0ffff),
    'lightgoldenrodyellow': Color(0xfffafad2), 'lightgray': Color(0xffd3d3d3),
    'lightgreen': Color(0xff90ee90), 'lightgrey': Color(0xffd3d3d3),
    'lightpink': Color(0xffffb6c1), 'lightsalmon': Color(0xffffa07a),
    'lightseagreen': Color(0xff20b2aa), 'lightskyblue': Color(0xff87cefa),
    'lightslategray': Color(0xff778899), 'lightslategrey': Color(0xff778899),
    'lightsteelblue': Color(0xffb0c4de), 'lightyellow': Color(0xffffffe0),
    'lime': Color(0xff00ff00), 'limegreen': Color(0xff32cd32),
    'linen': Color(0xfffaf0e6), 'magenta': Color(0xffff00ff),
    'maroon': Color(0xff800000), 'mediumaquamarine': Color(0xff66cdaa),
    'mediumblue': Color(0xff0000cd), 'mediumorchid': Color(0xffba55d3),
    'mediumpurple': Color(0xff9370db), 'mediumseagreen': Color(0xff3cb371),
    'mediumslateblue': Color(0xff7b68ee),
    'mediumspringgreen': Color(0xff00fa9a),
    'mediumturquoise': Color(0xff48d1cc), 'mediumvioletred': Color(0xffc71585),
    'midnightblue': Color(0xff191970), 'mintcream': Color(0xfff5fffa),
    'mistyrose': Color(0xffffe4e1), 'moccasin': Color(0xffffe4b5),
    'navajowhite': Color(0xffffdead), 'navy': Color(0xff000080),
    'oldlace': Color(0xfffdf5e6), 'olive': Color(0xff808000),
    'olivedrab': Color(0xff6b8e23), 'orange': Color(0xffffa500),
    'orangered': Color(0xffff4500), 'orchid': Color(0xffda70d6),
    'palegoldenrod': Color(0xffeee8aa), 'palegreen': Color(0xff98fb98),
    'paleturquoise': Color(0xffafeeee), 'palevioletred': Color(0xffdb7093),
    'papayawhip': Color(0xffffefd5), 'peachpuff': Color(0xffffdab9),
    'peru': Color(0xffcd853f), 'pink': Color(0xffffc0cb),
    'plum': Color(0xffdda0dd), 'powderblue': Color(0xffb0e0e6),
    'purple': Color(0xff800080), 'rebeccapurple': Color(0xff663399),
    'red': Color(0xffff0000), 'rosybrown': Color(0xffbc8f8f),
    'royalblue': Color(0xff4169e1), 'saddlebrown': Color(0xff8b4513),
    'salmon': Color(0xfffa8072), 'sandybrown': Color(0xfff4a460),
    'seagreen': Color(0xff2e8b57), 'seashell': Color(0xfffff5ee),
    'sienna': Color(0xffa0522d), 'silver': Color(0xffc0c0c0),
    'skyblue': Color(0xff87ceeb), 'slateblue': Color(0xff6a5acd),
    'slategray': Color(0xff708090), 'slategrey': Color(0xff708090),
    'snow': Color(0xfffffafa), 'springgreen': Color(0xff00ff7f),
    'steelblue': Color(0xff4682b4), 'tan': Color(0xffd2b48c),
    'teal': Color(0xff008080), 'thistle': Color(0xffd8bfd8),
    'tomato': Color(0xffff6347), 'turquoise': Color(0xff40e0d0),
    'violet': Color(0xffee82ee), 'wheat': Color(0xfff5deb3),
    'white': Color(0xffffffff), 'whitesmoke': Color(0xfff5f5f5),
    'yellow': Color(0xffffff00), 'yellowgreen': Color(0xff9acd32),
    'transparent': Color(0x00000000),
    // Mermaid uses `none` as a transparent paint value even though it is not
    // a CSS <color> keyword.
    'none': Color(0x00000000),
  };

  @override
  bool operator ==(Object other) => other is Color && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Color(0x${value.toRadixString(16).padLeft(8, '0')})';
}

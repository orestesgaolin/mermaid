/// Pure-Dart approximate text measurement based on per-character advance
/// tables for a Helvetica/Trebuchet-like proportional font.
///
/// Used for tests and non-Flutter environments. Flutter apps should use the
/// exact TextPainter-backed measurer from mermaid_flutter.
library;

import 'dart:math' as math;

import '../geometry.dart';
import 'text_measurer.dart';
import 'text_style.dart';

class ApproximateTextMeasurer implements TextMeasurer {
  const ApproximateTextMeasurer();

  /// Line height as a multiple of font size, roughly matching browser
  /// rendering of the default mermaid font stack.
  static const double lineHeightFactor = 1.2;

  @override
  Size measure(String text, TextStyleSpec style, {double? maxWidth}) {
    final boldFactor = style.fontWeight >= 600 ? 1.07 : 1.0;
    final lines = <String>[];
    for (final hardLine in text.split('\n')) {
      if (maxWidth == null || _lineWidth(hardLine, style) * boldFactor <= maxWidth) {
        lines.add(hardLine);
        continue;
      }
      lines.addAll(_wrap(hardLine, style, maxWidth / boldFactor));
    }
    var width = 0.0;
    for (final line in lines) {
      width = math.max(width, _lineWidth(line, style) * boldFactor);
    }
    final height = lines.length * style.fontSize * lineHeightFactor;
    return Size(width.ceilToDouble(), height.ceilToDouble());
  }

  List<String> _wrap(String line, TextStyleSpec style, double maxWidth) {
    final words = line.split(RegExp(r'\s+'));
    final out = <String>[];
    var current = StringBuffer();
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (current.isNotEmpty && _lineWidth(candidate, style) > maxWidth) {
        out.add(current.toString());
        current = StringBuffer(word);
      } else {
        current = StringBuffer(candidate);
      }
    }
    if (current.isNotEmpty) out.add(current.toString());
    return out.isEmpty ? [''] : out;
  }

  double _lineWidth(String line, TextStyleSpec style) {
    var w = 0.0;
    for (final unit in line.codeUnits) {
      w += _advance(unit);
    }
    return w * style.fontSize;
  }

  /// Advance width in em for a code unit. Values derived from Helvetica
  /// metrics, which track the mermaid default ("trebuchet ms") closely
  /// enough for layout purposes.
  double _advance(int codeUnit) {
    if (codeUnit >= 32 && codeUnit < 127) {
      return _asciiAdvances[codeUnit - 32];
    }
    // CJK and fullwidth forms.
    if ((codeUnit >= 0x2E80 && codeUnit <= 0x9FFF) ||
        (codeUnit >= 0xAC00 && codeUnit <= 0xD7AF) ||
        (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) ||
        (codeUnit >= 0xFF00 && codeUnit <= 0xFF60)) {
      return 1.0;
    }
    return 0.6;
  }

  // Helvetica AFM advances (per mille of em) for ASCII 32..126, /1000.
  static const List<double> _asciiAdvances = [
    0.278, 0.278, 0.355, 0.556, 0.556, 0.889, 0.667, 0.191, // space ! " # $ % & '
    0.333, 0.333, 0.389, 0.584, 0.278, 0.333, 0.278, 0.278, // ( ) * + , - . /
    0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556, // 0-7
    0.556, 0.556, 0.278, 0.278, 0.584, 0.584, 0.584, 0.556, // 8 9 : ; < = > ?
    1.015, 0.667, 0.667, 0.722, 0.722, 0.667, 0.611, 0.778, // @ A-G
    0.722, 0.278, 0.500, 0.667, 0.556, 0.833, 0.722, 0.778, // H-O
    0.667, 0.778, 0.722, 0.667, 0.611, 0.722, 0.667, 0.944, // P-W
    0.667, 0.667, 0.611, 0.278, 0.278, 0.278, 0.469, 0.556, // X Y Z [ \ ] ^ _
    0.333, 0.556, 0.556, 0.500, 0.556, 0.556, 0.278, 0.556, // ` a-g
    0.556, 0.222, 0.222, 0.500, 0.222, 0.833, 0.556, 0.556, // h-o
    0.556, 0.556, 0.333, 0.500, 0.278, 0.556, 0.500, 0.722, // p-w
    0.500, 0.500, 0.500, 0.334, 0.260, 0.334, 0.584, //        x y z { | } ~
  ];
}

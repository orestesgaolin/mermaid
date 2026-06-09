/// Backend-agnostic text style description used for measurement and painting.
library;

class TextStyleSpec {
  const TextStyleSpec({
    required this.fontFamily,
    required this.fontSize,
    this.fontWeight = 400,
    this.italic = false,
  });

  /// CSS-style family list, e.g. `"trebuchet ms", verdana, arial, sans-serif`.
  /// Backends pick the first family they can resolve.
  final String fontFamily;
  final double fontSize;

  /// 100..900, CSS semantics (400 normal, 700 bold).
  final int fontWeight;
  final bool italic;

  TextStyleSpec copyWith({
    String? fontFamily,
    double? fontSize,
    int? fontWeight,
    bool? italic,
  }) =>
      TextStyleSpec(
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        fontWeight: fontWeight ?? this.fontWeight,
        italic: italic ?? this.italic,
      );

  @override
  bool operator ==(Object other) =>
      other is TextStyleSpec &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(fontFamily, fontSize, fontWeight, italic);
}

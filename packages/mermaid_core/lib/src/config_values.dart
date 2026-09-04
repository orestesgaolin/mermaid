/// Shared readers for resolved `config.<diagram>` maps.
///
/// Every diagram config is built from an untyped map produced by
/// `resolveDiagramConfig` (frontmatter `config:` merged with `%%{init}%%`
/// directives), so the values are whatever the source happened to contain.
/// Mermaid.js validates those against a JSON schema and falls back to the
/// documented default when a value is missing or out of range; these helpers
/// are that fallback for this port. Every numeric reader rejects non-numbers,
/// `NaN` and the infinities before applying its sign constraint, so a hostile
/// or typo'd config can never propagate a non-finite or negative dimension
/// into layout geometry.
library;

/// Reads [key] as a finite, strictly positive double, else [fallback].
///
/// Use for dimensions that must not collapse (canvas width/height, node
/// width, font sizes).
double positiveDouble(
  Map<String, Object?> values,
  String key,
  double fallback,
) {
  final value = values[key];
  if (value is num) {
    final resolved = value.toDouble();
    if (resolved.isFinite && resolved > 0) return resolved;
  }
  return fallback;
}

/// Reads [key] as a finite, non-negative double, else [fallback].
///
/// Use for spacing that may legitimately be zero (padding, gaps).
double nonNegativeDouble(
  Map<String, Object?> values,
  String key,
  double fallback,
) {
  final value = values[key];
  if (value is num) {
    final resolved = value.toDouble();
    if (resolved.isFinite && resolved >= 0) return resolved;
  }
  return fallback;
}

/// Reads [key] as a finite double inside `[min, max]` (inclusive), else
/// [fallback].
double clampedDouble(
  Map<String, Object?> values,
  String key,
  double fallback, {
  required double min,
  required double max,
}) {
  final value = values[key];
  if (value is num) {
    final resolved = value.toDouble();
    if (resolved.isFinite && resolved >= min && resolved <= max) {
      return resolved;
    }
  }
  return fallback;
}

/// Reads [key] as a bool, else [fallback]. Non-bool values (including the
/// strings `"true"`/`"false"`) do not coerce, matching the upstream schema.
bool boolValue(Map<String, Object?> values, String key, bool fallback) {
  final value = values[key];
  return value is bool ? value : fallback;
}

/// Reads [key] as a string, else [fallback].
String stringValue(Map<String, Object?> values, String key, String fallback) {
  final value = values[key];
  return value is String ? value : fallback;
}

/// Reads [key] as one of [supported], else [fallback].
String enumValue(
  Map<String, Object?> values,
  String key,
  Set<String> supported,
  String fallback,
) {
  final value = values[key];
  return value is String && supported.contains(value) ? value : fallback;
}

/// Immutable model for a parsed ER diagram, mirroring upstream erDb.
library;

import '../flowchart/flow_model.dart' show FlowDirection;

class ErDiagram {
  const ErDiagram({
    required this.entities,
    required this.relationships,
    this.direction = FlowDirection.tb,
    this.title,
    this.classDefs = const {},
  });

  /// First-mention order, keyed by id.
  final Map<String, ErEntity> entities;
  final List<ErRelationship> relationships;
  final FlowDirection direction;
  final String? title;

  /// `classDef <name> <css>` declarations, name → raw `k:v` style list.
  final Map<String, List<String>> classDefs;
}

class ErEntity {
  const ErEntity({
    required this.id,
    required this.label,
    this.attributes = const [],
    this.cssStyles = const [],
    this.cssClasses = const [],
  });

  final String id;

  /// Display name (`p[Person]` aliases).
  final String label;
  final List<ErAttribute> attributes;

  /// Inline `style <entity> fill:#f00,stroke:#000` declarations (raw `k:v`).
  final List<String> cssStyles;

  /// Class names attached via `class <entity> <className>`.
  final List<String> cssClasses;

  ErEntity copyWith({
    String? label,
    List<ErAttribute>? attributes,
    List<String>? cssStyles,
    List<String>? cssClasses,
  }) =>
      ErEntity(
        id: id,
        label: label ?? this.label,
        attributes: attributes ?? this.attributes,
        cssStyles: cssStyles ?? this.cssStyles,
        cssClasses: cssClasses ?? this.cssClasses,
      );
}

class ErAttribute {
  const ErAttribute({
    required this.type,
    required this.name,
    this.keys = const [],
    this.comment,
  });

  /// Generics already converted (`type~T~` → `type<T>`).
  final String type;
  final String name;

  /// PK / FK / UK markers.
  final List<String> keys;
  final String? comment;
}

/// Crow's foot cardinality at one relationship end.
enum ErCardinality { zeroOrOne, onlyOne, zeroOrMore, oneOrMore }

class ErRelationship {
  const ErRelationship({
    required this.from,
    required this.to,
    required this.cardFrom,
    required this.cardTo,
    this.identifying = true,
    this.label = '',
  });

  final String from;
  final String to;

  /// Cardinality marker drawn at the [from] end.
  final ErCardinality cardFrom;
  final ErCardinality cardTo;

  /// Solid line (`--`) vs dashed non-identifying (`..`, `.-`, `-.`).
  final bool identifying;
  final String label;
}

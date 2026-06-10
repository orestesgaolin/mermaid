/// Immutable model for a parsed ER diagram, mirroring upstream erDb.
library;

import '../flowchart/flow_model.dart' show FlowDirection;

class ErDiagram {
  const ErDiagram({
    required this.entities,
    required this.relationships,
    this.direction = FlowDirection.tb,
    this.title,
  });

  /// First-mention order, keyed by id.
  final Map<String, ErEntity> entities;
  final List<ErRelationship> relationships;
  final FlowDirection direction;
  final String? title;
}

class ErEntity {
  const ErEntity({
    required this.id,
    required this.label,
    this.attributes = const [],
  });

  final String id;

  /// Display name (`p[Person]` aliases).
  final String label;
  final List<ErAttribute> attributes;

  ErEntity copyWith({String? label, List<ErAttribute>? attributes}) =>
      ErEntity(
        id: id,
        label: label ?? this.label,
        attributes: attributes ?? this.attributes,
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

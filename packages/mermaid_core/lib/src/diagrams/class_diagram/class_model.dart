/// Immutable model for a parsed class diagram, mirroring upstream classDb.
library;

import '../flowchart/flow_model.dart' show FlowDirection;

class ClassDiagram {
  const ClassDiagram({
    required this.classes,
    required this.relations,
    this.namespaces = const [],
    this.notes = const [],
    this.classDefs = const {},
    this.direction = FlowDirection.tb,
    this.title,
  });

  /// Declaration/first-mention order, keyed by id.
  final Map<String, ClassNode> classes;
  final List<ClassRelation> relations;
  final List<ClassNamespace> namespaces;
  final List<ClassNote> notes;

  /// classDef name -> style property map (fill, stroke, ...).
  final Map<String, Map<String, String>> classDefs;
  final FlowDirection direction;
  final String? title;
}

class ClassNode {
  const ClassNode({
    required this.id,
    required this.label,
    this.annotations = const [],
    this.attributes = const [],
    this.methods = const [],
    this.cssClasses = const [],
    this.styles = const {},
    this.link,
  });

  final String id;

  /// Display name; generics already converted (`List~T~` → `List<T>`).
  final String label;

  /// Stereotypes like `interface`, `abstract`, `enumeration` (without `<<>>`).
  final List<String> annotations;
  final List<ClassMember> attributes;
  final List<ClassMember> methods;
  final List<String> cssClasses;
  final Map<String, String> styles;
  final String? link;

  ClassNode copyWith({
    String? label,
    List<String>? annotations,
    List<ClassMember>? attributes,
    List<ClassMember>? methods,
    List<String>? cssClasses,
    Map<String, String>? styles,
    String? link,
  }) =>
      ClassNode(
        id: id,
        label: label ?? this.label,
        annotations: annotations ?? this.annotations,
        attributes: attributes ?? this.attributes,
        methods: methods ?? this.methods,
        cssClasses: cssClasses ?? this.cssClasses,
        styles: styles ?? this.styles,
        link: link ?? this.link,
      );
}

class ClassMember {
  const ClassMember({
    required this.text,
    this.isStatic = false,
    this.isAbstract = false,
  });

  /// Display text with visibility prefix and converted generics,
  /// e.g. `+getTime() DateTime`.
  final String text;

  /// `$` classifier — rendered underlined (upstream) / plain here for now.
  final bool isStatic;

  /// `*` classifier — rendered italic.
  final bool isAbstract;
}

/// Marker at one end of a relation, per upstream relationType.
enum RelationEnd {
  none,

  /// `<|` / `|>` — hollow triangle (inheritance/realization)
  extension,

  /// `*` — filled diamond
  composition,

  /// `o` — hollow diamond
  aggregation,

  /// `<` / `>` — open arrow (dependency/association direction)
  arrow,

  /// `()` — lollipop interface (rendered as a small circle)
  lollipop,
}

class ClassRelation {
  const ClassRelation({
    required this.from,
    required this.to,
    this.endFrom = RelationEnd.none,
    this.endTo = RelationEnd.none,
    this.dotted = false,
    this.label,
    this.cardFrom,
    this.cardTo,
  });

  final String from;
  final String to;

  /// Marker drawn at the [from] end (e.g. `A <|-- B` puts extension at A).
  final RelationEnd endFrom;
  final RelationEnd endTo;
  final bool dotted;
  final String? label;

  /// Cardinality strings like `1`, `0..n` at each end.
  final String? cardFrom;
  final String? cardTo;
}

class ClassNamespace {
  const ClassNamespace({required this.id, required this.classIds, String? label})
      : label = label ?? id;

  final String id;

  /// Display title (`namespace Auth["Authentication Service"]`).
  final String label;
  final List<String> classIds;
}

class ClassNote {
  const ClassNote({required this.text, this.forClass});

  final String text;

  /// Attached to a class (`note for X "..."`) or floating when null.
  final String? forClass;
}

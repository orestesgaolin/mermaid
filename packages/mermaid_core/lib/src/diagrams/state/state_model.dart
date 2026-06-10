/// Immutable model for a parsed state diagram (stateDiagram-v2), mirroring
/// upstream stateDb.
library;

import '../flowchart/flow_model.dart' show FlowDirection;

class StateDiagram {
  const StateDiagram({
    required this.states,
    required this.transitions,
    this.notes = const [],
    this.classDefs = const {},
    this.direction = FlowDirection.tb,
    this.title,
  });

  /// First-mention order, keyed by id. Includes synthesized `[*]` start/end
  /// pseudo-states (ids `__start_<scope>` / `__end_<scope>`).
  final Map<String, StateNode> states;
  final List<StateTransition> transitions;
  final List<StateNote> notes;
  final Map<String, Map<String, String>> classDefs;
  final FlowDirection direction;
  final String? title;
}

enum StateKind { normal, start, end, choice, fork, join, composite }

class StateNode {
  const StateNode({
    required this.id,
    required this.label,
    this.kind = StateKind.normal,
    this.children = const [],
    this.parent,
    this.cssClasses = const [],
    this.styles = const {},
  });

  final String id;

  /// Display label; `state "Long description" as s1` and `s1 : description`
  /// set it. `<br/>` normalized to `\n`.
  final String label;
  final StateKind kind;

  /// Direct child state ids when [kind] is [StateKind.composite].
  final List<String> children;

  /// Enclosing composite state id, if nested.
  final String? parent;
  final List<String> cssClasses;
  final Map<String, String> styles;

  StateNode copyWith({
    String? label,
    StateKind? kind,
    List<String>? children,
    String? parent,
    List<String>? cssClasses,
    Map<String, String>? styles,
  }) =>
      StateNode(
        id: id,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        children: children ?? this.children,
        parent: parent ?? this.parent,
        cssClasses: cssClasses ?? this.cssClasses,
        styles: styles ?? this.styles,
      );
}

class StateTransition {
  const StateTransition({required this.from, required this.to, this.label});

  final String from;
  final String to;
  final String? label;
}

enum StateNotePosition { leftOf, rightOf }

class StateNote {
  const StateNote({
    required this.target,
    required this.text,
    this.position = StateNotePosition.rightOf,
  });

  final String target;
  final String text;
  final StateNotePosition position;
}

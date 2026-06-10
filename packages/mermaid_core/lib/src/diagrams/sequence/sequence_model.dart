/// Immutable model for a parsed sequence diagram, mirroring the facts
/// captured by upstream sequenceDb (participants in declaration order plus a
/// flat, ordered event list).
library;

class SequenceDiagram {
  const SequenceDiagram({
    required this.participants,
    required this.events,
    this.title,
  });

  /// Declaration/first-mention order = column order, keyed by id.
  final Map<String, SeqParticipant> participants;
  final List<SeqEvent> events;
  final String? title;
}

class SeqParticipant {
  const SeqParticipant({
    required this.id,
    required this.label,
    this.isActor = false,
  });

  final String id;

  /// Display name (alias when declared with `as`). `<br/>` normalized to \n.
  final String label;

  /// Declared with the `actor` keyword: drawn as a stick figure.
  final bool isActor;
}

/// Arrow tokens per upstream sequenceDiagram.jison.
enum SeqArrow {
  /// `->` solid line, no head
  solidOpen,

  /// `-->` dotted line, no head
  dottedOpen,

  /// `->>` solid line, filled head
  solidArrow,

  /// `-->>` dotted line, filled head
  dottedArrow,

  /// `<<->>` solid line, filled heads both ends
  bidirectionalSolid,

  /// `<<-->>` dotted line, filled heads both ends
  bidirectionalDotted,

  /// `-x` solid line, cross at end
  solidCross,

  /// `--x` dotted line, cross at end
  dottedCross,

  /// `-)` solid line, open (stick) head — async
  solidPoint,

  /// `--)` dotted line, open head — async
  dottedPoint;

  bool get dotted => switch (this) {
        dottedOpen || dottedArrow || bidirectionalDotted || dottedCross ||
        dottedPoint =>
          true,
        _ => false,
      };

  bool get bidirectional =>
      this == bidirectionalSolid || this == bidirectionalDotted;
}

sealed class SeqEvent {
  const SeqEvent();
}

class SeqMessage extends SeqEvent {
  const SeqMessage({
    required this.from,
    required this.to,
    required this.arrow,
    this.text = '',
  });

  final String from;
  final String to;
  final SeqArrow arrow;
  final String text;
}

/// Activation bar start/end on a participant's lifeline.
class SeqActivation extends SeqEvent {
  const SeqActivation(this.id, {required this.active});

  final String id;
  final bool active;
}

enum NotePlacement { leftOf, rightOf, over }

class SeqNote extends SeqEvent {
  const SeqNote({
    required this.placement,
    required this.target,
    this.target2,
    required this.text,
  });

  final NotePlacement placement;
  final String target;

  /// Second participant for `Note over A,B`.
  final String? target2;
  final String text;
}

enum SeqBlockKind { loop, alt, opt, par, critical, breakBlock, rect }

class SeqBlockStart extends SeqEvent {
  const SeqBlockStart(this.kind, this.label, {this.color});

  final SeqBlockKind kind;
  final String label;

  /// Background for `rect rgb(...)` blocks (CSS color text).
  final String? color;
}

/// `else` / `and` / `option` divider inside the enclosing block.
class SeqBlockDivider extends SeqEvent {
  const SeqBlockDivider(this.label);

  final String label;
}

class SeqBlockEnd extends SeqEvent {
  const SeqBlockEnd();
}

/// `autonumber` toggle; numbering starts/continues at [start] when given.
class SeqAutonumber extends SeqEvent {
  const SeqAutonumber({required this.on, this.start, this.step});

  final bool on;
  final int? start;
  final int? step;
}

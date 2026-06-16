/// The phase / processor interface, mirroring ELK's `ILayoutPhase` and
/// `ILayoutProcessor`: each step mutates the [LGraph] in place. The layered
/// algorithm is a fixed sequence of five phases interleaved with intermediate
/// processors.
library;

import 'lgraph.dart';
import 'property.dart';

/// A step in the layered pipeline (a phase or an intermediate processor).
abstract class ILayoutProcessor {
  void process(LGraph graph);
}

/// Internal/option properties shared across phases (subset of ELK's
/// `InternalProperties` / `LayeredOptions` that the ported phases read).
class LProps {
  /// Per-edge layering priority along the flow direction (ELK
  /// `PRIORITY_DIRECTION`); raises a node's effective in/out degree.
  static const priorityDirection = Property<int>('priorityDirection', 0);

  /// Set on the graph when cycle breaking reversed at least one edge.
  static const cyclic = Property<bool>('cyclic', false);
}

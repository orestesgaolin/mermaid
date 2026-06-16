/// The public layered-layout entry point — a thin wrapper over the **faithful
/// ELK port** in `../layered/`.
///
/// There is **no dagre fallback**. The earlier dagre-substrate engine produced
/// a non-ELK layout under the `elk` label, which was misleading; it has been
/// removed. Graphs that use features the faithful port hasn't implemented yet
/// throw a descriptive [UnsupportedError] (see [unsupportedElkFeature]) instead
/// of silently approximating. Supported features grow until parity — see
/// `../layered/PORTING.md`.
library;

import '../api/graph.dart';
import '../api/result.dart';
import '../layered/elk_layered_engine.dart' as faithful;

/// Lays out [ElkGraph]s using the faithful ELK layered algorithm.
class ElkLayered {
  const ElkLayered();

  /// Computes positions for [graph]. Throws [UnsupportedError] if [graph] uses
  /// a feature the faithful port hasn't implemented yet.
  ElkResult layout(ElkGraph graph) => faithful.layeredLayout(graph);
}

/// A feature of [graph] not yet supported by the faithful engine, or null when
/// it can be laid out. Lets callers (e.g. the mermaid adapter) check up front
/// and surface the limitation rather than catch an error.
String? elkUnsupportedFeature(ElkGraph graph) =>
    faithful.unsupportedElkFeature(graph);

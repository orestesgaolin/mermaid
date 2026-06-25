/// Faithful port of ELK's `p3order.SweepCopy` — saves and restores the node
/// order (per layer) and the port order (per node) computed during a crossing-
/// minimization sweep, so the driver can keep the best-scoring sweep among
/// several randomized restarts and across hierarchy levels.
///
/// Simplification vs ELK: the `transferNodeAndPortOrdersToGraph` north/south
/// port-dummy side-correction (only relevant under the non-default
/// `ALLOW_NON_FLOW_PORTS_TO_SWITCH_SIDES` option) is omitted; we restore node
/// and port order verbatim. This matches our engine, which does not enable that
/// option.
library;

import '../lgraph.dart';

class SweepCopy {
  /// Deep copy of the node order: `nodeOrder[layer][pos]`.
  final List<List<LNode>> nodeOrder;

  /// Deep copy of each node's port order: `portOrders[layer][pos]`.
  final List<List<List<LPort>>> portOrders;

  /// Copies the current node + port order out of [currentOrder].
  SweepCopy(List<List<LNode>> currentOrder)
      : nodeOrder = [
          for (final layer in currentOrder) List<LNode>.from(layer),
        ],
        portOrders = [
          for (final layer in currentOrder)
            [for (final node in layer) List<LPort>.from(node.ports)],
        ];

  /// Copy constructor.
  SweepCopy.from(SweepCopy other)
      : nodeOrder = [for (final layer in other.nodeOrder) List<LNode>.from(layer)],
        portOrders = [
          for (final layer in other.portOrders)
            [for (final ports in layer) List<LPort>.from(ports)],
        ];

  /// Restores this saved order onto [graph]: reorders each [Layer.nodes] list
  /// and each node's port list to the saved order, and re-assigns `node.id` to
  /// the within-layer index (ELK uses `id` to remember the order).
  void transferTo(LGraph graph) {
    final layers = graph.layers;
    for (var i = 0; i < layers.length && i < nodeOrder.length; i++) {
      final nodes = layers[i].nodes;
      final saved = nodeOrder[i];
      for (var j = 0; j < saved.length; j++) {
        final node = saved[j];
        node.id = j;
        if (j < nodes.length) nodes[j] = node;
        // Restore the node's port order.
        node.ports
          ..clear()
          ..addAll(portOrders[i][j]);
      }
    }
  }
}

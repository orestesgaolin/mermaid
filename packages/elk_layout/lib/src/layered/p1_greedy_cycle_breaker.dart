/// Phase 1 — faithful port of ELK's `GreedyCycleBreaker`
/// (`p1cycles/GreedyCycleBreaker.java`): the Eades–Lin–Smyth greedy
/// feedback-arc-set heuristic. It computes a linear node ordering by peeling
/// sinks (to the right) and sources (to the left), breaking ties by maximum
/// out-flow, then reverses every edge that points backward in that order.
///
/// The only deviation: ELK breaks max-outflow ties with a seeded RNG; we take
/// the first such node for deterministic output.
library;

import 'lgraph.dart';
import 'phase.dart';

class GreedyCycleBreaker implements ILayoutProcessor {
  late List<int> _indeg;
  late List<int> _outdeg;
  late List<int> _mark;
  final _sources = <LNode>[];
  final _sinks = <LNode>[];

  @override
  void process(LGraph graph) {
    final nodes = graph.layerlessNodes;
    var unprocessed = nodes.length;
    _indeg = List.filled(unprocessed, 0);
    _outdeg = List.filled(unprocessed, 0);
    _mark = List.filled(unprocessed, 0);

    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      node.id = index;
      for (final port in node.ports) {
        for (final edge in port.incomingEdges) {
          if (edge.source?.node == node) continue; // self-loop
          final p = edge.getProperty(LProps.priorityDirection);
          _indeg[index] += p > 0 ? p + 1 : 1;
        }
        for (final edge in port.outgoingEdges) {
          if (edge.target?.node == node) continue; // self-loop
          final p = edge.getProperty(LProps.priorityDirection);
          _outdeg[index] += p > 0 ? p + 1 : 1;
        }
      }
      if (_outdeg[index] == 0) {
        _sinks.add(node);
      } else if (_indeg[index] == 0) {
        _sources.add(node);
      }
    }

    var nextRight = -1, nextLeft = 1;
    while (unprocessed > 0) {
      while (_sinks.isNotEmpty) {
        final sink = _sinks.removeAt(0);
        _mark[sink.id] = nextRight--;
        _updateNeighbors(sink);
        unprocessed--;
      }
      while (_sources.isNotEmpty) {
        final source = _sources.removeAt(0);
        _mark[source.id] = nextLeft++;
        _updateNeighbors(source);
        unprocessed--;
      }
      if (unprocessed > 0) {
        // Track the unmarked node(s) with the greatest out-flow. Use an
        // empty-first check rather than a `-1 << 31` sentinel: on Dart web
        // (32-bit shifts) `-1 << 31` does not yield a large-negative value, so
        // the comparison would reject every node and leave maxNodes empty.
        var maxOutflow = 0;
        final maxNodes = <LNode>[];
        for (final node in nodes) {
          if (_mark[node.id] == 0) {
            final outflow = _outdeg[node.id] - _indeg[node.id];
            if (maxNodes.isEmpty || outflow > maxOutflow) {
              maxNodes.clear();
              maxOutflow = outflow;
              maxNodes.add(node);
            } else if (outflow == maxOutflow) {
              maxNodes.add(node);
            }
          }
        }
        final maxNode = maxNodes.first; // ELK: random tie-break
        _mark[maxNode.id] = nextLeft++;
        _updateNeighbors(maxNode);
        unprocessed--;
      }
    }

    // Shift the negative (sink-side) marks above the positive ones to get a
    // single increasing order.
    final shiftBase = nodes.length + 1;
    for (var i = 0; i < nodes.length; i++) {
      if (_mark[i] < 0) _mark[i] += shiftBase;
    }

    // Reverse every edge that runs backward in the computed order.
    for (final node in nodes) {
      for (final port in node.ports.toList()) {
        for (final edge in port.outgoingEdges.toList()) {
          final targetIx = edge.target!.node.id;
          if (_mark[node.id] > _mark[targetIx]) {
            edge.reverse();
            graph.setProperty(LProps.cyclic, true);
          }
        }
      }
    }
  }

  void _updateNeighbors(LNode node) {
    for (final port in node.ports) {
      for (final edge in port.connectedEdges) {
        final connectedPort = edge.source == port ? edge.target! : edge.source!;
        final endpoint = connectedPort.node;
        if (node == endpoint) continue;
        var priority = edge.getProperty(LProps.priorityDirection);
        if (priority < 0) priority = 0;
        final index = endpoint.id;
        if (_mark[index] == 0) {
          if (edge.target == connectedPort) {
            _indeg[index] -= priority + 1;
            if (_indeg[index] <= 0 && _outdeg[index] > 0) _sources.add(endpoint);
          } else {
            _outdeg[index] -= priority + 1;
            if (_outdeg[index] <= 0 && _indeg[index] > 0) _sinks.add(endpoint);
          }
        }
      }
    }
  }
}

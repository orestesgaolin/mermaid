/// Additional ELK layered cycle-breaking strategies.
///
/// These implement the ordering contracts of ELK's `DepthFirstCycleBreaker`,
/// `InteractiveCycleBreaker`, `ModelOrderCycleBreaker`, and
/// `GreedyModelOrderCycleBreaker`. Reversed edges are restored after routing by
/// the common `ReversedEdgeRestorer` processor.
library;

import 'dart:math' as math;

import 'intermediate_constraints.dart';
import 'lgraph.dart';
import 'p1_greedy_cycle_breaker.dart';
import 'p3_layer_sweep_crossing_minimizer.dart' show modelOrder;
import 'phase.dart';

/// Reverses DFS back edges. Input node and edge order determine traversal.
class DepthFirstCycleBreaker implements ILayoutProcessor {
  late List<bool> _visited;
  late List<bool> _active;
  final List<LEdge> _toReverse = [];

  @override
  void process(LGraph graph) {
    final nodes = graph.layerlessNodes;
    _visited = List<bool>.filled(nodes.length, false);
    _active = List<bool>.filled(nodes.length, false);
    _toReverse.clear();

    for (var i = 0; i < nodes.length; i++) {
      nodes[i].id = i;
    }
    for (final node in nodes) {
      if (node.incomingEdges.where((edge) => !edge.isSelfLoop).isEmpty) {
        _dfs(node);
      }
    }
    for (final node in nodes) {
      if (!_visited[node.id]) _dfs(node);
    }

    for (final edge in _toReverse) {
      edge.reverse();
      graph.setProperty(LProps.cyclic, true);
    }
  }

  void _dfs(LNode node) {
    if (_visited[node.id]) return;
    _visited[node.id] = true;
    _active[node.id] = true;
    for (final edge in node.outgoingEdges.toList()) {
      if (edge.isSelfLoop) continue;
      final target = edge.target!.node;
      if (_active[target.id]) {
        _toReverse.add(edge);
      } else {
        _dfs(target);
      }
    }
    _active[node.id] = false;
  }
}

/// Preserves the left-to-right direction of the supplied node positions, then
/// reverses DFS back edges when equal positions still leave a cycle.
class InteractiveCycleBreaker implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final toReverse = <LEdge>[];
    for (final source in graph.layerlessNodes) {
      source.id = 1;
      final sourceX = source.position.x + source.size.x / 2;
      for (final edge in source.outgoingEdges) {
        final target = edge.target!.node;
        final targetX = target.position.x + target.size.x / 2;
        if (target != source && targetX < sourceX) {
          toReverse.add(edge);
        }
      }
    }
    for (final edge in toReverse) {
      edge.reverse();
    }

    toReverse.clear();
    for (final node in graph.layerlessNodes) {
      if (node.id > 0) _findCycles(node, toReverse);
    }
    for (final edge in toReverse) {
      edge.reverse();
    }
  }

  void _findCycles(LNode node, List<LEdge> toReverse) {
    node.id = -1;
    for (final edge in node.outgoingEdges.toList()) {
      final target = edge.target!.node;
      if (target == node) continue;
      if (target.id < 0) {
        toReverse.add(edge);
      } else if (target.id > 0) {
        _findCycles(target, toReverse);
      }
    }
    node.id = 0;
  }
}

/// Reverses every edge that runs backward relative to input node order.
class ModelOrderCycleBreaker implements ILayoutProcessor {
  @override
  void process(LGraph graph) {
    final toReverse = <LEdge>[];
    final offset = _modelOrderOffset(graph);
    for (final source in graph.layerlessNodes) {
      final calculator = _ConstraintModelOrderCalculator();
      final sourceOrder = calculator.compute(source, offset);
      for (final edge in source.outgoingEdges) {
        final target = edge.target!.node;
        if (calculator.compute(target, offset) < sourceOrder) {
          toReverse.add(edge);
        }
      }
    }
    for (final edge in toReverse) {
      edge.reverse();
      graph.setProperty(LProps.cyclic, true);
    }
  }
}

/// Uses model order to resolve the greedy algorithm's maximum-outflow ties.
class GreedyModelOrderCycleBreaker extends GreedyCycleBreaker {
  @override
  LNode chooseNodeWithMaxOutflow(List<LNode> nodes) {
    LNode? result;
    var minimumOrder = 0;
    final calculator = _ConstraintModelOrderCalculator();
    final offset = _modelOrderOffset(nodes.first.graph);
    for (final node in nodes) {
      if (!node.hasProperty(modelOrder)) continue;
      final order = calculator.compute(node, offset);
      if (result == null || order < minimumOrder) {
        result = node;
        minimumOrder = order;
      }
    }
    return result ?? super.chooseNodeWithMaxOutflow(nodes);
  }
}

int _modelOrderOffset(LGraph graph) {
  var maximum = graph.layerlessNodes.length;
  for (final node in graph.layerlessNodes) {
    if (node.hasProperty(modelOrder)) {
      maximum = math.max(maximum, node.getProperty(modelOrder) + 1);
    }
  }
  return maximum;
}

/// Constraint-aware portion of ELK's `GroupModelOrderCalculator`.
class _ConstraintModelOrderCalculator {
  var _firstSeparateNodes = 0;
  var _lastSeparateNodes = 0;

  int compute(LNode node, int offset) {
    var order = switch (node.getProperty(layerConstraint)) {
      LayerConstraint.firstSeparate => -2 * offset + _firstSeparateNodes++,
      LayerConstraint.first => -offset,
      LayerConstraint.none => 0,
      LayerConstraint.last => offset,
      LayerConstraint.lastSeparate => 2 * offset + _lastSeparateNodes++,
    };
    if (node.hasProperty(modelOrder)) order += node.getProperty(modelOrder);
    return order;
  }
}

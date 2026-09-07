import 'dart:math' as math;

import '../api/graph.dart';
import 'intermediate_labels.dart';
import 'lgraph.dart';
import 'property.dart';

const nodeLabelPlacement = Property<ElkNodeLabelPlacement>(
  'label.nodePlacement',
  ElkNodeLabelPlacement.topLeft,
);
const labelTranspose = Property<bool>('label.transpose', false);
const labelMirror = Property<bool>('label.mirror', false);
const nodeLabelSpacing = Property<double>('label.nodeSpacing', 5);

const portLabelSpacing = Property<double>('label.portSpacing', 1);

/// Position port labels outside their owning border before margins and BK
/// placement. Coordinates remain port-relative throughout the pipeline.
void placePortLabels(LNode node) {
  final transpose = node.graph.getProperty(labelTranspose);
  final mirror = node.graph.getProperty(labelMirror);
  final width = transpose ? node.size.y : node.size.x;
  final height = transpose ? node.size.x : node.size.y;
  final total =
      node.labels.fold(0.0, (v, l) => v + (transpose ? l.size.x : l.size.y)) +
      math.max(0, node.labels.length - 1) *
          node.graph.getProperty(labelStackSpacing);
  final placement = node.getProperty(nodeLabelPlacement);
  final nodeGap = node.graph.getProperty(nodeLabelSpacing);
  var labelY = switch (placement) {
    ElkNodeLabelPlacement.topLeft => 0.0,
    ElkNodeLabelPlacement.topCenter => nodeGap,
    ElkNodeLabelPlacement.center => (height - total) / 2,
    ElkNodeLabelPlacement.bottomCenter => height - total - nodeGap,
  };
  for (final label in node.labels) {
    final w = transpose ? label.size.y : label.size.x;
    final h = transpose ? label.size.x : label.size.y;
    var x = placement == ElkNodeLabelPlacement.topLeft ? 0.0 : (width - w) / 2;
    var y = labelY;
    if (mirror) {
      if (transpose) {
        y = height - y - h;
      } else {
        x = width - x - w;
      }
    }
    label.position.x = transpose ? y : x;
    label.position.y = transpose ? x : y;
    labelY += h + node.graph.getProperty(labelStackSpacing);
  }
  final gap = node.graph.getProperty(portLabelSpacing);
  final stackGap = node.graph.getProperty(labelStackSpacing);
  for (final port in node.ports) {
    final pw = transpose ? port.size.y : port.size.x;
    final ph = transpose ? port.size.x : port.size.y;
    final height =
        port.labels.fold(0.0, (v, l) => v + (transpose ? l.size.x : l.size.y)) +
        math.max(0, port.labels.length - 1) * stackGap;
    final outputSide = transpose
        ? switch (port.side) {
            PortSide.east => mirror ? PortSide.north : PortSide.south,
            PortSide.west => mirror ? PortSide.south : PortSide.north,
            PortSide.north => PortSide.west,
            PortSide.south => PortSide.east,
            _ => PortSide.undefined,
          }
        : mirror
        ? switch (port.side) {
            PortSide.east => PortSide.west,
            PortSide.west => PortSide.east,
            final value => value,
          }
        : port.side;
    var cursor = 0.0;
    for (final label in port.labels) {
      final w = transpose ? label.size.y : label.size.x;
      final h = transpose ? label.size.x : label.size.y;
      var x = outputSide == PortSide.west ? -gap - w : pw + gap;
      var y =
          (outputSide == PortSide.north ? -gap - height : ph + gap) + cursor;
      if (mirror) {
        if (transpose) {
          y = ph - y - h;
        } else {
          x = pw - x - w;
        }
      }
      label.position.x = transpose ? y : x;
      label.position.y = transpose ? x : y;
      cursor += h + stackGap;
    }
  }
}

/// End labels follow the first/last routed segment, after cycle restoration.
/// Center labels have already reserved space through their layout dummies.
void placeEndLabels(LEdge edge) {
  if (edge.source == null || edge.target == null) return;
  final points = [
    edge.source!.absoluteAnchor,
    ...edge.bendPoints.points,
    edge.target!.absoluteAnchor,
  ];
  final gap =
      edge.source!.node.graph.getProperty(edgeLabelSpacing) +
      edge.getProperty(labelEdgeThickness) / 2;
  final stackGap = edge.source!.node.graph.getProperty(labelStackSpacing);
  if (edge.isSelfLoop && points.length > 1) {
    var best = 0, length = -1.0;
    final node = edge.source!.node;
    for (var i = 0; i < points.length - 1; i++) {
      final mx = (points[i + 1].x + points[i].x) / 2,
          my = (points[i + 1].y + points[i].y) / 2;
      final distance =
          math.max(
            0.0,
            math.max(node.position.x - mx, mx - node.position.x - node.size.x),
          ) +
          math.max(
            0.0,
            math.max(node.position.y - my, my - node.position.y - node.size.y),
          );
      if (distance > length) {
        length = distance;
        best = i;
      }
    }
    final a = points[best], b = points[best + 1];
    final horizontal = (b.x - a.x).abs() >= (b.y - a.y).abs();
    var offset = gap;
    for (final label in edge.labels.where(
      (l) => l.getProperty(labelPlacement) == ElkEdgeLabelPlacement.center,
    )) {
      label.position.x = (a.x + b.x - label.size.x) / 2;
      label.position.y = (a.y + b.y - label.size.y) / 2;
      if (horizontal) {
        label.position.y =
            (a.y + b.y) / 2 +
            ((a.y + b.y) / 2 > node.position.y + node.size.y
                ? offset
                : -offset - label.size.y);
      } else {
        label.position.x =
            (a.x + b.x) / 2 +
            ((a.x + b.x) / 2 > node.position.x + node.size.x
                ? offset
                : -offset - label.size.x);
      }
      offset += (horizontal ? label.size.y : label.size.x) + stackGap;
    }
  }
  for (final placement in [
    ElkEdgeLabelPlacement.tail,
    ElkEdgeLabelPlacement.head,
  ]) {
    final route = placement == ElkEdgeLabelPlacement.head
        ? points.reversed.toList()
        : points;
    final start = route.first;
    final end = route
        .skip(1)
        .firstWhere(
          (p) => p.x != start.x || p.y != start.y,
          orElse: () => route.last,
        );
    final dx = end.x - start.x, dy = end.y - start.y;
    final horizontal = dx.abs() >= dy.abs();
    var above = gap, below = gap;
    final port = placement == ElkEdgeLabelPlacement.head
        ? edge.target!
        : edge.source!;
    for (final label in port.labels) {
      final near = horizontal
          ? label.position.y - port.anchor.y
          : label.position.x - port.anchor.x;
      final extent = horizontal ? label.size.y : label.size.x;
      above = math.max(above, -near + gap);
      below = math.max(below, near + extent + gap);
    }
    for (final label in edge.labels.where(
      (l) => l.getProperty(labelPlacement) == placement,
    )) {
      final isAbove = label.getProperty(labelSide) == ElkLabelSide.above;
      final offset = isAbove ? above : below;
      if (horizontal) {
        label.position.x = start.x + (dx >= 0 ? gap : -gap - label.size.x);
        label.position.y =
            start.y + (isAbove ? -offset - label.size.y : offset);
      } else {
        label.position.x =
            start.x + (isAbove ? -offset - label.size.x : offset);
        label.position.y = start.y + (dy >= 0 ? gap : -gap - label.size.y);
      }
      final node = port.node;
      final intersectsNode =
          label.position.x < node.position.x + node.size.x &&
          label.position.x + label.size.x > node.position.x &&
          label.position.y < node.position.y + node.size.y &&
          label.position.y + label.size.y > node.position.y;
      if (intersectsNode) {
        if (horizontal) {
          label.position.x = dx >= 0
              ? node.position.x + node.size.x + gap
              : node.position.x - gap - label.size.x;
        } else {
          label.position.y = dy >= 0
              ? node.position.y + node.size.y + gap
              : node.position.y - gap - label.size.y;
        }
      }
      final advance = (horizontal ? label.size.y : label.size.x) + stackGap;
      if (isAbove) {
        above += advance;
      } else {
        below += advance;
      }
    }
  }
}

/// Called after routed edges are restored to their original direction.
void placeGraphEndLabels(LGraph graph) {
  final seen = <LEdge>{};
  for (final layer in graph.layers) {
    for (final node in layer.nodes) {
      for (final edge in node.outgoingEdges) {
        if (seen.add(edge)) placeEndLabels(edge);
      }
    }
  }
}

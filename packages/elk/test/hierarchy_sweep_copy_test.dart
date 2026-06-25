// Unit test for the hierarchy-aware crossing-min foundation (C1): SweepCopy
// saves a node+port order and restores it verbatim onto the graph.
import 'package:elk/src/layered/lgraph.dart';
import 'package:elk/src/layered/hierarchy/sweep_copy.dart';
import 'package:test/test.dart';

void main() {
  group('SweepCopy', () {
    test('saves and restores node order and per-node port order', () {
      final g = LGraph();
      final layer = Layer(g)..owner = g;
      g.layers.add(layer);

      final a = LNode(g)..identifier = 'a';
      final b = LNode(g)..identifier = 'b';
      final c = LNode(g)..identifier = 'c';
      // Give `b` two ports whose order we will also scramble.
      final p0 = LPort(b)..identifier = 'p0';
      final p1 = LPort(b)..identifier = 'p1';
      b.ports.addAll([p0, p1]);
      layer.nodes.addAll([a, b, c]);

      // Snapshot the good order.
      final saved = SweepCopy([
        [a, b, c]
      ]);

      // Scramble both node order and b's port order.
      layer.nodes
        ..clear()
        ..addAll([c, a, b]);
      b.ports
        ..clear()
        ..addAll([p1, p0]);

      saved.transferTo(g);

      expect(layer.nodes, [a, b, c]);
      expect(b.ports, [p0, p1]);
      // ids reflect within-layer index.
      expect([a.id, b.id, c.id], [0, 1, 2]);
    });

    test('copy constructor is independent of the original', () {
      final g = LGraph();
      final layer = Layer(g);
      g.layers.add(layer);
      final a = LNode(g)..identifier = 'a';
      final b = LNode(g)..identifier = 'b';
      layer.nodes.addAll([a, b]);

      final original = SweepCopy([
        [a, b]
      ]);
      final copy = SweepCopy.from(original);
      // Mutating the copy's top-level list must not affect the original.
      copy.nodeOrder[0].clear();
      expect(original.nodeOrder[0], [a, b]);
    });
  });
}

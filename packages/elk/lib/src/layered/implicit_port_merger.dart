import 'lgraph.dart';

/// Resolves undeclared node endpoints to implicit ports.
///
/// When edge merging is enabled, all edges that use the same node border share
/// one implicit port. Declared ports keep their explicit identity and are never
/// combined.
class ImplicitPortMerger {
  ImplicitPortMerger({required this.enabled});

  final bool enabled;
  final Map<(LNode, PortSide), LPort> _shared = {};

  LPort resolve(
    LNode node,
    String endpoint,
    PortSide side,
    Map<LNode, Map<String, LPort>> declaredPorts,
  ) {
    final declared = declaredPorts[node]?[endpoint];
    if (declared != null) return declared;
    if (enabled) {
      return _shared.putIfAbsent((node, side), () => _create(node, side));
    }
    return _create(node, side);
  }

  LPort _create(LNode node, PortSide side) {
    final port = LPort(node)..side = side;
    node.ports.add(port);
    return port;
  }
}

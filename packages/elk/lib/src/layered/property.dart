/// Faithful port of ELK's property system (`org.eclipse.elk.graph.properties`).
///
/// ELK's layered algorithm threads state between phases via typed properties on
/// graph elements rather than fields. [Property] mirrors `IProperty<T>` (an
/// identity-keyed, typed handle with a default) and [MapPropertyHolder] mirrors
/// `MapPropertyHolder` (the get/set store every `LGraphElement` extends).
library;

/// A typed, identity-keyed property handle with a default value — the Dart
/// counterpart of ELK's `IProperty<T>` / `Property<T>`.
class Property<T> {
  const Property(this.id, [this.defaultValue]);

  /// Stable identity used as the map key (two `Property` handles with the same
  /// [id] address the same slot, matching ELK's `Property.equals`).
  final String id;
  final T? defaultValue;

  @override
  bool operator ==(Object other) => other is Property && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Property($id)';
}

/// Mixin providing the typed property store (`MapPropertyHolder`).
mixin MapPropertyHolder {
  final Map<Property<Object?>, Object?> _props = {};

  /// Sets [property] to [value]; returns this holder for chaining.
  T setProperty<V, T extends MapPropertyHolder>(Property<V> property, V value) {
    _props[property as Property<Object?>] = value;
    return this as T;
  }

  /// Returns the value of [property], or its [Property.defaultValue] if unset.
  V getProperty<V>(Property<V> property) {
    final v = _props[property as Property<Object?>];
    if (v != null) return v as V;
    return property.defaultValue as V;
  }

  bool hasProperty(Property<Object?> property) => _props.containsKey(property);

  void copyPropertiesFrom(MapPropertyHolder other) =>
      _props.addAll(other._props);
}

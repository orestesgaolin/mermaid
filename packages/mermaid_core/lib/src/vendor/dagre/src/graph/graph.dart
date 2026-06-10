// ignore_for_file: strict_top_level_inference
import 'package:mermaid_core/src/vendor/dagre/src/model/props.dart';
import 'package:mermaid_core/src/vendor/dagre/src/util/list_util.dart';

import '../model/graph_label.dart';

class Graph {
  static const String _defaultEdgeId = "\x00";
  static const String _edgeKeyDelim = "\x01";
  static const String _graphNodeId = "\x00";
  final bool isDirected;
  final bool isMultiGraph;
  final bool isCompound;

  // 图本身的属性
  GraphLabel? _label;

  GraphLabel get label => _label!;

  GraphLabel? get label2 => _label;

  set label(GraphLabel? newLabel) {
    _label = newLabel;
  }

  //v->label
  final Map<String, Props?> _nodes = {};

  // v-> edgeObj
  final Map<String, Map<String, Edge>> _in = {};

  // u -> v -> Number
  final Map<String, Map<String, int>> _preds = {};

  // v -> edgeObj
  final Map<String, Map<String, Edge>> _out = {};

  // v -> w -> Number
  final Map<String, Map<String, int>> _sucs = {};

  // edgeId -> EdgeObj
  final Map<String, Edge> _edgeObjs = {};

  // edgeId -> EdgeValue
  final Map<String, Props?> _edgeLabels = {};

  // nodeId -> edgeObj
  Map<String, String> _parent = {};

  Map<String, Map<String, bool>> _children = {};

  int _nodeCount = 0;
  int _edgeCount = 0;

  Props? Function(String)? _defaultNodeLabelFun;

  Props Function(String, String, String?)? _defaultEdgeLabelFun;

  Graph({
    this.isDirected = true,
    this.isMultiGraph = false,
    this.isCompound = false,
  }) {
    if (isCompound) {
      _parent = {};
      _children = {};
      _children[_graphNodeId] = {};
    }
  }

  Graph setDefaultNodePropsFun(Props? Function(String) newDefault) {
    _defaultNodeLabelFun = newDefault;
    return this;
  }

  Graph setDefaultEdgeLabelFun(Props Function(String, String, String?) newDefault) {
    _defaultEdgeLabelFun = newDefault;
    return this;
  }

  Graph setDefaultNodeLabel(String label) {
    var type = Props()..value = label;
    _defaultNodeLabelFun = (v) => type;
    return this;
  }

  Graph setDefaultEdgeLabel(String newDefault) {
    var type = Props()..value = newDefault;
    _defaultEdgeLabelFun = (a, b, c) => type;
    return this;
  }

  int get nodeCount => _nodeCount;

  List<String> get nodes => List.from(_nodes.keys);

  Iterable<String> get nodesIterable => _nodes.keys;

  List<String> get sources {
    return nodes.filter((v) {
      var t = _in[v];
      return t == null || t.isEmpty;
    });
  }

  List<String> get sinks {
    return nodes.filter((v) {
      var vv=_out[v];
      return vv==null||vv.isEmpty;
    });
  }

  Graph setNodes(List<String> vs, [Props? value]) {
    var self = this;
    vs.each((v, i) {
      self.setNode(v, value);
    });
    return this;
  }

  Graph setNode(String v, [Props? value]) {
    if (_nodes.containsKey(v)) {
      if (value != null) {
        _nodes[v] = value;
      }
      return this;
    }
    _nodes[v] = value ?? _defaultNodeLabelFun?.call(v);
    if (isCompound) {
      _parent[v] = _graphNodeId;
      _children[v] = {};
      Map<String, bool> m = _children[_graphNodeId] ?? {};
      _children[_graphNodeId] = m;
      m[v] = true;
    }
    _in[v] = {};
    _preds[v] = {};
    _out[v] = {};
    _sucs[v] = {};
    ++_nodeCount;
    return this;
  }

  Props node(String nodeId) {
    return _nodes[nodeId]!;
  }

  Props? nodeNull(String nodeId) {
    return _nodes[nodeId];
  }

  Graph setParent(String id, [String? parent]) {
    if (!isCompound) {
      throw StateError("Cannot set parent in a non-compound graph");
    }
    if (parent == null) {
      parent = _graphNodeId;
    } else {
      String? ancestor = parent;
      while (ancestor != null) {
        ancestor = this.parent(ancestor);
        if (ancestor == id) {
          throw StateError('Setting  $parent   as parent of $id  would create a cycle');
        }
      }
      setNode(parent);
    }
    setNode(id);
    _removeFromParentsChildList(id);
    _parent[id] = parent;

    Map<String, bool> m = _children[parent] ?? {};
    _children[parent] = m;
    m[id] = true;
    return this;
  }

  void _removeFromParentsChildList(String? v) {
    _children[_parent[v]]?.remove(v);
  }

  String? parent(String v) {
    if (isCompound) {
      var parent = _parent[v];
      if (parent != _graphNodeId) {
        return parent;
      }
    }
    return null;
  }

  List<String>? predecessors(String v) {
    var predsV = _preds[v];
    if (predsV != null) {
      return List.from(predsV.keys);
    }
    return null;
  }

  List<String>? successors(String v) {
    var sucsV = _sucs[v];
    if (sucsV != null) {
      return List.from(sucsV.keys);
    }
    return null;
  }

  bool isLeaf(v) {
    List<String>? neighborsv;
    if (isDirected) {
      neighborsv = successors(v);
    } else {
      neighborsv = neighbors(v);
    }
    return neighborsv == null || neighborsv.isEmpty;
  }

  ///根据EdgeObj 对象获取对应的Value
  Props edge(String v, String w, [String? name]) {
    return edgeNull(v, w, name)!;
  }

  Props edge2(Edge obj) {
    return edge2Null(obj)!;
  }

  Props? edgeNull(String v, String w, [String? name]) {
    var e = edgeArgsToId(isDirected, v, w, name);
    return _edgeLabels[e];
  }

  Props? edge2Null(Edge obj) {
    return edge(obj.v, obj.w, obj.id);
  }

  int get edgeCount => _edgeCount;

  ///返回所有的EdgeObj对象
  List<Edge> get edges {
    return List.from(_edgeObjs.values);
  }

  Iterable<Edge> get edgesIterable {
    return _edgeObjs.values;
  }

  bool hasEdge(Edge edge) {
    var e = edgeObjToId(isDirected, edge);
    return _edgeObjs[e] != null;
  }

  bool hasEdge2(String v, String w, [String? id]) {
    var e = edgeArgsToId(isDirected, v, w, id);
    return _edgeObjs[e] != null;
  }

  // Vendored fix: graphlib's inEdges returns undefined only when the node
  // does not exist; for an existing node with no incoming edges `_in[v]` is
  // an empty object (truthy), so it returns an empty array. The original
  // port added an `isNotEmpty` check, returning null for source nodes. That
  // made nodeEdges() drop a source node's out-edges entirely, so
  // feasibleTree's tightTree could never expand through the nesting root —
  // an infinite loop on graphs with multiple disconnected components.
  List<Edge>? inEdges(String v, [String? u]) {
    var inV = _in[v];
    if (inV != null) {
      List<Edge> edges = List.from(inV.values);
      if (u == null) {
        return edges;
      }
      return edges.filter((edge) {
        return edge.v == u;
      });
    }
    return null;
  }

  List<Edge>? outEdges(String v, [String? w]) {
    var outV = _out[v];
    if (outV != null) {
      List<Edge> edges = List.from(outV.values);
      if (w == null) {
        return edges;
      }
      return edges.filter((edge) {
        return edge.w == w;
      });
    }
    return null;
  }

  Graph removeEdge(String v, String w, [String? name]) {
    var e = edgeArgsToId(isDirected, v, w, name);
    var edge = _edgeObjs[e];
    if (edge != null) {
      v = edge.v;
      w = edge.w;
      _edgeLabels.remove(e);
      _edgeObjs.remove(e);
      decrementOrRemoveEntry(_preds[w], v);
      decrementOrRemoveEntry(_sucs[v], w);
      _in[w]?.remove(e);
      _out[v]?.remove(e);
      _edgeCount--;
    }
    return this;
  }

  Graph removeEdge2(Edge? v) {
    if (v == null) {
      return this;
    }
    return removeEdge(v.v, v.w, v.id);
  }

  Graph setEdge(Edge edge, [Props? value]) {
    return _setEdgeInner(edge.v, edge.w, edge.id, value);
  }

  Graph setEdge2(String v, String w, {String? name, Props? value}) {
    return _setEdgeInner(v, w, name, value);
  }

  Graph _setEdgeInner(String v, String w, String? name, Props? value) {
    var e = edgeArgsToId(isDirected, v, w, name);
    if (_edgeLabels.containsKey(e)) {
      if (value != null) {
        _edgeLabels[e] = value;
      }
      return this;
    }
    if (!(name == null || name.isEmpty) && !isMultiGraph) {
      throw StateError("Cannot set a named edge when isMultigraph = false");
    }

    setNode(v);
    setNode(w);
    _edgeLabels[e] = value ?? _defaultEdgeLabelFun?.call(v, w, name);
    var edgeObj = edgeArgsToObj(isDirected, v, w, name);
    v = edgeObj.v;
    w = edgeObj.w;
    _edgeObjs[e] = edgeObj;
    incrementOrInitEntry(_preds[w]!, v);
    incrementOrInitEntry(_sucs[v]!, w);

    var map = _in[w] ?? {};
    _in[w] = map;
    map[e] = edgeObj;

    map = _out[v] ?? {};
    _out[v] = map;
    map[e] = edgeObj;
    _edgeCount++;
    return this;
  }

  List<String>? children([String nodeId = _graphNodeId]) {
    if (isCompound) {
      var children = _children[nodeId];
      if (children != null) {
        return List.from(children.keys);
      }
    } else if (nodeId == _graphNodeId) {
      return nodes;
    } else if (hasNode(nodeId)) {
      return [];
    }
    return null;
  }

  bool hasNode(String v) {
    return _nodes.containsKey(v);
  }

  List<String>? neighbors(String v) {
    var preds = predecessors(v);
    if (preds != null) {
      Set<String> ds = Set.from(preds);
      successors(v)?.forEach((e) {
        ds.add(e);
      });
      return List.from(ds);
    }
    return null;
  }

  Graph removeNode(String v) {
    if (_nodes.containsKey(v)) {
      _nodes.remove(v);
      if (isCompound) {
        _removeFromParentsChildList(v);
        _parent.remove(v);
        children(v)?.forEach((child) {
          setParent(child);
        });
        _children.remove(v);
      }

      List<String> kl = List.from((_in[v] ?? {}).keys);
      for (var e in kl) {
        removeEdge2(_edgeObjs[e]);
      }
      _in.remove(v);
      _preds.remove(v);

      kl = List.from((_out[v] ?? {}).keys);
      for (var e in kl) {
        removeEdge2(_edgeObjs[e]);
      }
      _out.remove(v);
      _sucs.remove(v);
      --_nodeCount;
    }
    return this;
  }

  Graph filterNodes(bool Function(String) filter) {
    var copy = Graph(isDirected: isDirected, isMultiGraph: isMultiGraph, isCompound: isCompound);
    copy.label = label;

    _nodes.forEach((v, value) {
      if (filter(v)) {
        copy.setNode(v, value);
      }
    });

    _edgeObjs.forEach((s, e) {
      if (copy.hasNode(e.v) && copy.hasNode(e.w)) {
        copy.setEdge(e, edge(e.v, e.w, e.id));
      }
    });

    Map<String, String?> parents = {};
    findParent(v) {
      var parent = this.parent(v);
      if (parent == null || copy.hasNode(parent)) {
        parents[v] = parent;
        return parent;
      } else if (parents.containsKey(parent)) {
        return parents[parent];
      } else {
        return findParent(parent);
      }
    }

    if (isCompound) {
      for (var v in copy.nodes) {
        copy.setParent(v, findParent(v));
      }
    }
    return copy;
  }

  Graph setPath(List<String> idList, [Props? value]) {
    for (int i = 1; i < idList.length; i++) {
      String v = idList[i - 1];
      String w = idList[i];
      _setEdgeInner(v, w, null, value);
    }
    return this;
  }

  List<Edge>? nodeEdges(String v, [String? w]) {
    var values = inEdges(v, w);
    if (values != null) {
      var list = outEdges(v, w);
      if (list != null) {
        values.addAll(list);
      }
      return values;
    }
    return null;
  }

  void incrementOrInitEntry(Map<String, int> map, String k) {
    int? v = map[k];
    if (v != null) {
      map[k] = v + 1;
    } else {
      map[k] = 1;
    }
  }

  void decrementOrRemoveEntry(Map<String, int>? map, String k) {
    if (map == null) {
      return;
    }
    int? v = map[k];
    if (v != null) {
      v -= 1;
      map[k] = v;
    }
    if (v == null || v == 0) {
      map.remove(k);
    }
  }

  String edgeArgsToId(bool isDirected, String v_, String? w_, [String? edgeId]) {
    String v = v_;
    String w = w_ ?? '';
    int t = v.compareTo(w);
    if (!isDirected && t > 0) {
      var tmp = v;
      v = w;
      w = tmp;
    }
    return v + _edgeKeyDelim + w + _edgeKeyDelim + ((edgeId == null || edgeId.isEmpty) ? _defaultEdgeId : edgeId);
  }

  Edge edgeArgsToObj(bool isDirected, String v_, String w_, [String? edgeId]) {
    var v = v_;
    var w = w_;
    int t = v.compareTo(w);
    if (!isDirected && t > 0) {
      var tmp = v;
      v = w;
      w = tmp;
    }
    return Edge(v: v, w: w, id: edgeId);
  }

  String edgeObjToId(bool isDirected, Edge obj) {
    return edgeArgsToId(isDirected, obj.v, obj.w, obj.id);
  }
}

class Edge {
  final String v;
  final String w;
  final String? id;

  const Edge({required this.v, required this.w, this.id});

  @override
  String toString() {

    return "id:$id,v:$v,w:$w";
  }
}

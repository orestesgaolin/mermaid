// ignore_for_file: unintended_html_in_doc_comment
import 'dart:convert';

import 'package:elk/src/dagre/src/model/enums/dummy.dart';

extension MapExtension on Map<String, dynamic> {
  Props get toProps {
    var p = Props();
    p.putAll(this);
    return p;
  }
}

class Props {
  String? value;

  Map<String, dynamic> _valueMap = {};

  Props put(String key, dynamic data) {
    _valueMap[_format(key)] = data;
    return this;
  }

  Props putAll(Map<String, dynamic>? map) {
    if (map != null) {
      map.forEach((key, value) {
        _valueMap[_format(key)] = value;
      });
    }
    return this;
  }

  dynamic remove(String key) {
    return _valueMap.remove(_format(key));
  }

  void removeAt(Iterable<String> keys) {
    for (var key in keys) {
      _valueMap.remove(_format(key));
    }
  }

  void clean() {
    _valueMap = {};
  }

  T get<T>(String attr, [T? defVal]) {
    T? value = get2(attr);
    if (value != null) {
      return value as T;
    }
    if (defVal != null) {
      put(attr, defVal);
      return defVal as T;
    }
    throw UnsupportedError("not value");
  }

  T? get2<T>(String attr) {
    return _valueMap[_format(attr)] as T?;
  }

  double getD(String attr) {
    return getD2(attr)!;
  }

  double? getD2(String attr) {
    var value=_valueMap[_format(attr)];
    if(value==null){
      return null;
    }
    return value.toDouble();
  }

  int getI(String attr) {
    return getI2(attr)!;
  }

  int? getI2(String attr) {
    var value=_valueMap[_format(attr)];
    if(value==null ||value is! num){
      return null;
    }
    return value.toInt();
  }

  String getS(String attr) {
    return getS2(attr)!;
  }

  String? getS2(String attr) {
    return get2(attr) as String?;
  }

  List<T> getL<T>(String attr, [bool autoFix = true]) {
    var result = getL2(attr) as List<T>?;
    if (result != null) {
      return result;
    }
    if (autoFix) {
      return [];
    }
    throw UnsupportedError("not value");
  }

  List<T>? getL2<T>(String attr) {
    return get(attr) as List<T>?;
  }

  dynamic operator [](String name) {
    return _valueMap[_format(name)];
  }

  void operator []=(String name, dynamic value) {
    _valueMap[_format(name)] = value;
  }

  Map<String, dynamic> pick(Iterable<String> fields) {
    Map<String, dynamic> map = {};
    for (var key in fields) {
      key = _format(key);
      map[key] = _valueMap[key];
    }
    return map;
  }

  Map<String, dynamic> getAll() {
    return _valueMap;
  }

  bool hasOwn(String key) {
    return _valueMap.containsKey(_format(key));
  }

  String _format(String key) {
    return key;
  }

  Props copy(){
    var pp=Props();
    pp.putAll(_valueMap);
    return pp;
  }

  @override
  String toString() {
    Map<String, dynamic> map = {};
    _valueMap.forEach((key, value) {
      map[key] = _convertValue(value);
    });
    return jsonEncode(map);
  }

  dynamic _convertValue(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value.toString();
    }
    if (value is num) {
      return value.toStringAsFixed(2);
    }
    if (value is List) {
      List<dynamic> resultList = [];
      for (var item in value) {
        resultList.add(_convertValue(item));
      }
      return resultList;
    }
    if (value is Map) {
      Map<String, dynamic> resultMap = {};
      for (var item in value.entries) {
        resultMap[item.key.toString()] = _convertValue(item.value);
      }
      return resultMap;
    }
    return value.toString();
  }
}

const xK = 'x';
const yK = 'y';
const eK = "e";
const vK = "v";
const outK = "out";
const innerK = "inner";

const widthK = 'width';
const heightK = 'height';
const weightK = 'weight';
const rankDirK = 'rankDir';
const minLenK = 'minLen';

///type is String
const borderTopK = 'borderTop';

///type is String
const borderBottomK = 'borderBottom';

///type is List<String>
const borderLeftK = 'borderLeft';

///type is List<String>
const borderRightK = 'borderRight';

///type is [Dummy]
const dummyK = 'dummy';

const labelOffsetK = 'labelOffset';

///type is [LabelPosition]
const labelPosK = 'labelPos';

///type is [List<GraphPoint>]
const pointsK = 'points';
const labelRankK = 'labelRank';
const rankK = 'rank';
const minRankK = 'minRank';
const maxRankK = 'maxRank';

///type is bool
const reversedK = 'reversed';
const forwardNameK = "forwardName";
const parentK = "parent";
const cutValueK = "cutValue";

const lowK = "low";
const limK = "lim";
const orderK = "order";
const valueK = "value";
const borderTypeK = "borderType";

///type is String
const rootK = "root";

const nodeRankFactorK = "nodeRankFactor";

///type is List<String>
const dummyChainsK = "dummyChains";

///type is [Edge]
const edgeObjK = "edgeObj";

const edgeLabelK = "edgeLabel";

const nestingRootK = "nestingRoot";

///type is [bool]
const nestingEdgeK = "nestingEdge";

/// type is List<SelfEdgeData>
const selfEdgesK = "selfEdges";

const labelK = "label";

/// elk extension: per-node model (declaration) order index, and a graph
/// label flag that turns on model-order-aware initial ordering in init_order.
/// Both are absent for plain dagre layouts, so default behavior is unchanged.
const modelOrderK = "modelOrder";
const useModelOrderK = "useModelOrder";

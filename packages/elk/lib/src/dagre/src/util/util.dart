import 'dart:math';

class _Unique {
  static final _Unique instance = _Unique._();

  _Unique._();

  final Set<int> _usedSet = {};
  int _now = 0;

  String uniqueId() {
    int t = _now + 1;
    while (_usedSet.contains(t)) {
      t += 1;
    }
    _now = t;
    _usedSet.add(t);
    return '@$t';
  }
}

String uniqueId([String prefix = '']) {
  return "$prefix${_Unique.instance.uniqueId()}";
}

List<int> range(int start, int end, [int step = 1]) {
  int index = -1;
  int length = max(((end - start) / step).ceil(), 0);
  List<int> rl = List.filled(length, 0);
  while ((length--) != 0) {
    rl[++index] = start;
    start += step;
  }
  return rl;
}

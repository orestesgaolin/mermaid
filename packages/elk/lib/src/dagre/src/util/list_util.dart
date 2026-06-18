import 'dart:math' as math;

extension ListExt<T> on List<T> {

  List<T> concat(Iterable<T>? lists) {
    List<T> rl = [...this];
    if(lists!=null){
      rl.addAll(lists);
    }
    return rl;
  }

  List<T> reverse2() {
    return List.from(reversed);
  }

  List<T> reverseSelf() {
    List<T> list = reverse2();
    clear();
    addAll(list);
    return this;
  }

  T? removeLastOrNull() {
    if (isEmpty) {
      return null;
    }
    return removeLast();
  }

  void each(void Function(T, int) call) {
    int i = 0;
    for (var ele in this) {
      call.call(ele, i);
      i++;
    }
  }

  void eachRight(void Function(T, int) call) {
    for(int i=length-1;i>=0;i--){
      call.call(this[i], i);
    }
  }

  List<T> filter(bool Function(T) call) {
    return List.from(where(call));
  }

  O reduce2<O>(O Function(T, O) call, [O? initV]) {
    if (initV != null) {
      var o = initV;
      for (var n in this) {
        o = call.call(n, o);
      }
      return o;
    } else {
      var o = this[0] as O;
      for (int i = 1; i < length; i++) {
        o = call.call(this[i], o);
      }
      return o;
    }
  }

  List<O> map2<O>(O? Function(T, int) call) {
    List<O> rl = [];
    int i = 0;
    for (var n in this) {
      O? r=call.call(n, i);
      if(r!=null){
        rl.add(r);
      }
      i++;
    }
    return rl;
  }

  T? find(bool Function(T) call) {

    for(var item in this){
      if(call.call(item)){
        return item;
      }
    }
    return null;
  }

}

T? max<T extends num>(Iterable<T>? list) {
  if (list == null || list.isEmpty) {
    return null;
  }
  T m = list.first;
  for (var n in list) {
    m = math.max(m, n);
  }
  return m;
}

num? min(Iterable<num>? list) {
  if (list == null || list.isEmpty) {
    return null;
  }
  num m = list.first;
  for (var n in list) {
    m = math.min(m, n);
  }
  return m;
}

T minBy<T>(List<T> list, num? Function(T) by) {
  T v = list.first;
  num p = by.call(v) ?? 0;
  for (var d in list) {
    num t = by.call(d) ?? 0;
    if (t < p) {
      p = t;
      v = d;
    }
  }
  return v;
}


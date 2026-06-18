/// 用于模拟Array
class Array<T> {
  final Map<int, T?> _map = {};

  Array();

  void operator []=(int index, T node) {
    _map[index] = node;
  }

  T? operator [](int index) {
    return _map[index];
  }

  bool has(int index){
    return _map[index]!=null;
  }

  void forEach(void Function(T?,int) call){
    if(_map.isEmpty){return;}
    List<int> keys=List.from(_map.keys);
    keys.sort();
    for(int i=keys[0];i<=keys[keys.length-1];i++){
      call.call(this[i],i);
    }
  }

  List<T> toList(){
    List<int> keys=List.from(_map.keys);
    keys.sort();
    List<T> rl=[];
    for(int i=0;i<keys.length;i++){
      T t=this[keys[i]] as T;
      rl.add(t);
    }
    return rl;
  }
}

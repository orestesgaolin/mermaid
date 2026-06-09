class ConflictInfo {
  num inDegree = 0;
  List<ConflictInfo> inner = [];
  List<ConflictInfo> out = [];

  //node list
  List<String> vs = [];
  int i = -1;
  num? barycenter;
  num weight = 0;
  bool merged = false;
}

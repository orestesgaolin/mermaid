import 'package:mermaid_core/src/vendor/dagre/src/model/props.dart';

import '../../graph/graph.dart';

class SelfEdgeData{
  Edge e;
  Props data;
  SelfEdgeData(this.e,this.data);
}
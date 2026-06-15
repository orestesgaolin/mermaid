class GraphPoint{
  double x;
  double y;
  GraphPoint(this.x,this.y);

  @override
  String toString() {
    return "[x: ${x.toStringAsFixed(2)}, y: ${y.toStringAsFixed(2)}]";
  }
}
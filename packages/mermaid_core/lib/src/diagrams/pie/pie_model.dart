/// Immutable model for a parsed pie chart.
library;

class PieChart {
  const PieChart({
    required this.slices,
    this.title,
    this.showData = false,
  });

  /// Declaration order.
  final List<PieSlice> slices;
  final String? title;

  /// `pie showData` — render values next to legend labels.
  final bool showData;
}

class PieSlice {
  const PieSlice({required this.label, required this.value});

  final String label;
  final double value;
}

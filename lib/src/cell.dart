class Cell {
  /// Formula a ser aplicada (exemplo: "=SUM(A1:B1)")
  List<Object?> value;

  /// Colunas a serem aplicadas (exemplo: "A1:B1")
  String range;

  Cell({required this.value, required this.range});
}

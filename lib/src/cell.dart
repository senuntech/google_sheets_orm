class Cell {
  /// Formula a ser aplicada (exemplo: "=SUM(A1:B1)")
  String formula;

  /// Colunas a serem aplicadas (exemplo: "A1:B1")
  String columns;

  /// Tabela a ser aplicada (exemplo: "Sheet1")
  String sheet;

  Cell({required this.formula, required this.columns, required this.sheet});
}

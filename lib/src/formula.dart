class Formula {
  /// Formula a ser aplicada (exemplo: "=SUM(A1:B1)")
  String formula;

  /// Colunas a serem aplicadas (exemplo: "A1:B1")
  String range;

  /// Tabela a ser aplicada (exemplo: "Sheet1")
  String sheet;

  final bool isProtected;

  Formula({
    required this.formula,
    required this.range,
    required this.sheet,
    this.isProtected = true,
  });
}

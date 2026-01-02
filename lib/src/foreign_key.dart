class ForeignKey {
  /// A tabela/aba onde a fórmula será inserida.
  /// Ex: "Produtos"
  final String sourceTable;

  /// A coluna na tabela de origem que contém o ID para busca.
  /// Ex: "id_categoria"
  final String sourceKeyColumn;

  /// A coluna na tabela de origem que receberá o resultado (o "destino" do nome).
  /// Ex: "nome_categoria_calculado"
  final String sourceTargetColumn;

  /// A tabela/aba de onde os dados serão buscados.
  /// Ex: "Categorias"
  final String lookupTable;

  /// A coluna de ID na tabela de referência.
  /// Ex: "id"
  final String lookupKeyColumn;

  /// A coluna com o valor que queremos retornar (nome, descrição, etc).
  /// Ex: "nome"
  final String lookupResultColumn;

  ForeignKey({
    required this.sourceTable,
    required this.sourceKeyColumn,
    required this.sourceTargetColumn,
    required this.lookupTable,
    required this.lookupKeyColumn,
    required this.lookupResultColumn,
  });
}

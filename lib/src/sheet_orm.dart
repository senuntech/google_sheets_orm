import 'package:googleapis/sheets/v4.dart' as sheets;

class SheetORM {
  final sheets.SheetsApi api;
  final String spreadsheetId;
  final String sheetName;
  int? _cachedGid;

  SheetORM(this.api, this.spreadsheetId, this.sheetName);

  /// Obtém o ID numérico da aba (GID) com cache para evitar chamadas extras
  Future<int> _getGid() async {
    if (_cachedGid != null) return _cachedGid!;
    final ss = await api.spreadsheets.get(spreadsheetId);
    final sheet = ss.sheets?.firstWhere(
      (s) => s.properties?.title == sheetName,
      orElse: () => throw Exception("Aba $sheetName não encontrada."),
    );
    _cachedGid = sheet?.properties?.sheetId ?? 0;
    return _cachedGid!;
  }

  /// Busca todos os dados e retorna como uma lista de Maps
  Future<List<Map<String, dynamic>>> findAll() async {
    final response = await api.spreadsheets.values.get(
      spreadsheetId,
      '$sheetName!A:Z',
    );
    final rows = response.values;
    if (rows == null || rows.isEmpty) return [];

    final headers = List<String>.from(rows[0]);
    return rows.skip(1).map((row) {
      final map = <String, dynamic>{};
      for (var j = 0; j < headers.length; j++) {
        map[headers[j]] = j < row.length ? row[j] : "";
      }
      return map;
    }).toList();
  }

  /// Busca um único registro pelo ID e retorna um Map
  Future<Map<String, dynamic>?> findById(int id) async {
    final results = await findAll();
    try {
      return results.firstWhere((item) => int.tryParse(item['id']) == id);
    } catch (_) {
      return null;
    }
  }

  /// Busca registros que coincidem com um critério em uma coluna específica.
  /// Retorna uma [List<Map<String, dynamic>>]. Caso não encontre nada, retorna uma lista vazia.
  Future<List<Map<String, dynamic>>> find({
    required String column,
    required dynamic value,
  }) async {
    // 1. Obtém todos os registros da aba (utiliza o cache/processamento do findAll)
    final allData = await findAll();

    if (allData.isEmpty) return [];

    // 2. Filtra os dados onde o valor da coluna corresponde ao critério
    // A comparação é feita convertendo para String e ignorando maiúsculas/minúsculas
    final List<Map<String, dynamic>> results = allData.where((row) {
      final cellValue = row[column]?.toString().toLowerCase() ?? "";
      final searchValue = value.toString().toLowerCase();
      return cellValue == searchValue;
    }).toList();

    return results;
  }

  /// Cria um registro com auto-incremento de ID
  Future<int> create(Map<String, dynamic> data) async {
    final response = await api.spreadsheets.values.get(
      spreadsheetId,
      '$sheetName!A:Z',
    );
    final rows = response.values ?? [];
    if (rows.isEmpty) throw Exception("Cabeçalhos não encontrados.");

    final headers = List<String>.from(rows[0]);
    int idColIndex = headers.indexOf("id");

    int maxId = 0;
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].length > idColIndex) {
        maxId = BigInt.parse(rows[i][idColIndex].toString()).toInt() > maxId
            ? int.parse(rows[i][idColIndex].toString())
            : maxId;
      }
    }

    int newId = maxId + 1;
    final newRow = headers
        .map((h) => h == "id" ? newId : (data[h] ?? ""))
        .toList();

    await api.spreadsheets.values.append(
      sheets.ValueRange(values: [newRow]),
      spreadsheetId,
      '$sheetName!A1',
      valueInputOption: "USER_ENTERED",
    );
    return newId;
  }

  /// Atualiza uma linha inteira em uma única chamada de API
  Future<void> updateWhereId(String id, Map<String, dynamic> data) async {
    final response = await api.spreadsheets.values.get(
      spreadsheetId,
      '$sheetName!A:Z',
    );
    final rows = response.values;
    if (rows == null || rows.isEmpty) throw Exception("Planilha vazia.");

    final headers = List<String>.from(rows[0]);
    int rowIndex = rows.indexWhere(
      (row) => row.isNotEmpty && row[0].toString() == id,
    );

    if (rowIndex == -1) throw Exception("ID $id não encontrado.");

    // Mescla dados novos com os existentes na linha
    List<Object?> updatedRow = List<Object?>.generate(headers.length, (j) {
      final header = headers[j];
      if (data.containsKey(header) && header != "id") return data[header];
      return j < rows[rowIndex].length ? rows[rowIndex][j] : "";
    });

    await api.spreadsheets.values.update(
      sheets.ValueRange(values: [updatedRow]),
      spreadsheetId,
      '$sheetName!A${rowIndex + 1}',
      valueInputOption: 'USER_ENTERED',
    );
  }

  /// Deleta fisicamente a linha baseada no ID
  Future<void> delete(String id) async {
    final response = await api.spreadsheets.values.get(
      spreadsheetId,
      '$sheetName!A:A',
    );
    final rows = response.values;
    if (rows == null) return;

    int rowIndex = rows.indexWhere(
      (row) => row.isNotEmpty && row[0].toString() == id,
    );
    if (rowIndex == -1) return;

    final gid = await _getGid();
    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            deleteDimension: sheets.DeleteDimensionRequest(
              range: sheets.DimensionRange(
                sheetId: gid,
                dimension: "ROWS",
                startIndex: rowIndex,
                endIndex: rowIndex + 1,
              ),
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
  }
}

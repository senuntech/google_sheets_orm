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
  Future<int> insert(Map<String, dynamic> data) async {
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

  /// Insere múltiplos registros com auto-incremento de ID
  Future<List<int>> insertAll(List<Map<String, dynamic>> dataList) async {
    if (dataList.isEmpty) return [];

    final response = await api.spreadsheets.values.get(
      spreadsheetId,
      '$sheetName!A:Z',
    );

    final rows = response.values ?? [];
    if (rows.isEmpty) throw Exception("Cabeçalhos não encontrados.");

    final headers = List<String>.from(rows[0]);
    int idColIndex = headers.indexOf("id");
    if (idColIndex == -1) throw Exception("Coluna 'id' não encontrada.");

    int maxId = 0;
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].length > idColIndex) {
        var currentIdValue = rows[i][idColIndex].toString();
        if (currentIdValue.isNotEmpty) {
          int? currentId = int.tryParse(currentIdValue);
          if (currentId != null && currentId > maxId) {
            maxId = currentId;
          }
        }
      }
    }

    List<List<Object>> newRows = [];
    List<int> newIds = [];
    int nextId = maxId + 1;

    for (var data in dataList) {
      final newRow = headers.map((h) {
        if (h == "id") {
          return nextId;
        }
        return data[h] ?? "";
      }).toList();

      newRows.add(List.from(newRow));
      newIds.add(nextId);
      nextId++;
    }

    await api.spreadsheets.values.append(
      sheets.ValueRange(values: newRows),
      spreadsheetId,
      '$sheetName!A1',
      valueInputOption: "USER_ENTERED",
    );

    return newIds;
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

  /// Deleta registros usando uma string de consulta (ex: "id=10" ou "status=inativo")
  Future<void> deleteWhere(String query) async {
    final regExp = RegExp(r"(\w+)\s*(=|!=|>|<)\s*(.+)");
    final match = regExp.firstMatch(query);

    if (match == null) {
      throw Exception("Formato de query inválido. Use 'coluna=valor'.");
    }

    final field = match.group(1);
    final operator = match.group(2);
    final value = match
        .group(3)
        ?.replaceAll("'", "")
        .replaceAll('"', '')
        .trim();

    final response = await api.spreadsheets.values.get(
      spreadsheetId,
      '$sheetName!A:Z',
    );

    final rows = response.values ?? [];
    if (rows.isEmpty) return;

    final headers = List<String>.from(rows[0]);
    int colIndex = headers.indexOf(field!);

    if (colIndex == -1) {
      throw Exception("Coluna '$field' não encontrada na planilha.");
    }

    List<int> indicesToDelete = [];

    for (var i = 1; i < rows.length; i++) {
      if (rows[i].length <= colIndex) continue;

      final cellValue = rows[i][colIndex].toString();
      bool shouldDelete = false;

      switch (operator) {
        case '=':
          shouldDelete = (cellValue == value);
          break;
        case '!=':
          shouldDelete = (cellValue != value);
          break;
      }

      if (shouldDelete) {
        indicesToDelete.add(i);
      }
    }

    if (indicesToDelete.isEmpty) return;

    final gid = await _getGid();
    indicesToDelete.sort((a, b) => b.compareTo(a));

    final requests = indicesToDelete.map((index) {
      return sheets.Request(
        deleteDimension: sheets.DeleteDimensionRequest(
          range: sheets.DimensionRange(
            sheetId: gid,
            dimension: "ROWS",
            startIndex: index,
            endIndex: index + 1,
          ),
        ),
      );
    }).toList();

    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(requests: requests),
      spreadsheetId,
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

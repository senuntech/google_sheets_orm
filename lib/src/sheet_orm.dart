import 'package:google_sheets_orm/orm.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:google_sheets_orm/src/utils.dart';

class SheetORM {
  final sheets.SheetsApi api;
  final String spreadsheetId;
  final String sheetName;
  int? _cachedGid;
  List<ForeignKey>? foreignKeys;
  List<Formula>? formulas;
  final Duration cacheTime;

  List<List<Object?>>? _cachedRawRows;
  DateTime? _lastFetch;

  SheetORM(
    this.api,
    this.spreadsheetId,
    this.sheetName,
    this.foreignKeys, [
    this.formulas,
    this.cacheTime = const Duration(seconds: 0),
  ]);

  /// Obtém o ID numérico da aba (GID) com cache para evitar chamadas extras
  Future<int> getGid() async {
    if (_cachedGid != null) return _cachedGid!;
    final ss = await api.spreadsheets.get(spreadsheetId);
    final sheet = ss.sheets?.firstWhere(
      (s) => s.properties?.title == sheetName,
      orElse: () => throw Exception("Aba $sheetName não encontrada."),
    );
    _cachedGid = sheet?.properties?.sheetId ?? 0;
    return _cachedGid!;
  }

  /// Busca os dados puros (com cabeçalho) da planilha usando cache se configurado
  Future<List<List<Object?>>> getRawRows({bool forceRefresh = false}) async {
    bool isCacheValid =
        _cachedRawRows != null &&
        _lastFetch != null &&
        (cacheTime.inMilliseconds > 0
            ? DateTime.now().difference(_lastFetch!) < cacheTime
            : true);

    if (!forceRefresh && isCacheValid) {
      return _cachedRawRows!;
    }

    final response = await api.spreadsheets.values.get(
      spreadsheetId,
      '$sheetName!A:Z',
    );
    final rows = response.values ?? [];

    _cachedRawRows = rows;
    _lastFetch = DateTime.now();
    return rows;
  }

  /// Busca todos os dados e retorna como uma lista de Maps
  Future<List<Map<String, dynamic>>> findAll({
    bool forceRefresh = false,
  }) async {
    final rows = await getRawRows(forceRefresh: forceRefresh);
    if (rows.isEmpty) return [];

    final headers = List<String>.from(rows[0]);
    return rows
        .skip(1)
        .where((row) {
          if (row.isEmpty) return false;
          int idColIndex = headers.indexOf("id");
          if (idColIndex == -1 || idColIndex >= row.length) return false;
          return row[idColIndex].toString().trim().isNotEmpty;
        })
        .map((row) {
          final map = <String, dynamic>{};
          for (var j = 0; j < headers.length; j++) {
            map[headers[j]] = j < row.length ? row[j] : "";
          }
          return map;
        })
        .toList();
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
    final rows = await getRawRows(forceRefresh: true);
    if (rows.isEmpty) throw Exception("Cabeçalhos não encontrados.");

    final headers = List<String>.from(rows[0]);
    int idColIndex = headers.indexOf("id");

    int maxId = 0;
    int lastPopulatedRow = 1; // 1 is header
    int firstEmptyRow = -1;

    for (var i = 1; i < rows.length; i++) {
      bool isEmptyId = true;
      if (rows[i].length > idColIndex) {
        var val = rows[i][idColIndex];
        var idStr = val == null ? "" : val.toString().trim();
        if (idStr.isNotEmpty && idStr != "null") {
          isEmptyId = false;
          lastPopulatedRow = i + 1;

          var id = double.tryParse(idStr)?.toInt() ?? int.tryParse(idStr);
          if (id != null && id > maxId) {
            maxId = id;
          }
        }
      }
      if (isEmptyId && firstEmptyRow == -1) {
        firstEmptyRow = i + 1;
      }
    }

    int newId = maxId + 1;
    int nextRow = firstEmptyRow != -1 ? firstEmptyRow : lastPopulatedRow + 1;

    final newRow = headers.map((h) => h == "id" ? newId : data[h]).toList();
    List<sheets.ValueRange> updateData = [];

    for (int i = 0; i < headers.length; i++) {
      var val = newRow[i];
      if (val != null && val.toString().isNotEmpty) {
        String colLetter = listAlfabetic(i);
        updateData.add(
          sheets.ValueRange(
            range: '$sheetName!$colLetter$nextRow',
            values: [
              [val],
            ],
          ),
        );
      }
    }

    if (updateData.isNotEmpty) {
      final batchRequest = sheets.BatchUpdateValuesRequest(
        valueInputOption: "USER_ENTERED",
        data: updateData,
      );

      await api.spreadsheets.values.batchUpdate(batchRequest, spreadsheetId);
    }

    _cachedRawRows = null; // Invalida o cache
    return newId;
  }

  /// Insere múltiplos registros com auto-incremento de ID
  Future<List<int>> insertAll(List<Map<String, dynamic>> dataList) async {
    if (dataList.isEmpty) return [];

    final rows = await getRawRows(forceRefresh: true);
    if (rows.isEmpty) throw Exception("Cabeçalhos não encontrados.");

    final headers = List<String>.from(rows[0]);
    int idColIndex = headers.indexOf("id");
    if (idColIndex == -1) throw Exception("Coluna 'id' não encontrada.");

    int maxId = 0;
    int lastPopulatedRow = 1; // 1 is header
    List<int> emptyRows = [];

    for (var i = 1; i < rows.length; i++) {
      bool isEmptyId = true;
      if (rows[i].length > idColIndex) {
        var val = rows[i][idColIndex];
        var idStr = val == null ? "" : val.toString().trim();
        if (idStr.isNotEmpty && idStr != "null") {
          isEmptyId = false;
          lastPopulatedRow = i + 1;

          var currentId =
              double.tryParse(idStr)?.toInt() ?? int.tryParse(idStr);
          if (currentId != null && currentId > maxId) {
            maxId = currentId;
          }
        }
      }
      if (isEmptyId) {
        emptyRows.add(i + 1);
      }
    }

    List<List<Object?>> newRows = [];
    List<int> newIds = [];
    int nextId = maxId + 1;

    for (var data in dataList) {
      final newRow = headers.map((h) {
        if (h == "id") {
          return nextId;
        }
        return data[h];
      }).toList();

      newRows.add(List.from(newRow));
      newIds.add(nextId);
      nextId++;
    }

    List<sheets.ValueRange> updateData = [];
    int nextAppendRow = rows.length + 1;

    for (int r = 0; r < newRows.length; r++) {
      int currentRow;
      if (emptyRows.isNotEmpty) {
        currentRow = emptyRows.removeAt(0);
      } else {
        currentRow = nextAppendRow;
        nextAppendRow++;
      }

      for (int c = 0; c < headers.length; c++) {
        var val = newRows[r][c];
        if (val != null && val.toString().isNotEmpty) {
          String colLetter = listAlfabetic(c);
          updateData.add(
            sheets.ValueRange(
              range: '$sheetName!$colLetter$currentRow',
              values: [
                [val],
              ],
            ),
          );
        }
      }
    }

    if (updateData.isNotEmpty) {
      final batchRequest = sheets.BatchUpdateValuesRequest(
        valueInputOption: "USER_ENTERED",
        data: updateData,
      );

      await api.spreadsheets.values.batchUpdate(batchRequest, spreadsheetId);
    }

    _cachedRawRows = null; // Invalida o cache
    return newIds;
  }

  /// Atualiza uma linha inteira em uma única chamada de API
  Future<void> updateWhereId(String id, Map<String, dynamic> data) async {
    final rows = await getRawRows(forceRefresh: true);
    if (rows.isEmpty) throw Exception("Planilha vazia.");

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

    for (var i = 0; i < headers.length; i++) {
      final header = headers.elementAt(i);
      final isFk =
          foreignKeys?.any((e) => e.sourceTargetColumn == header) ?? false;

      // Checa se a coluna está configurada em alguma Formula (extraindo a coluna da range)
      // O regex captura a letra da coluna. Ex: range "M2:M2" captura "M".
      // Para ser 100% preciso, se a coluna não foi enviada em `data`, evitamos sobrescrever.
      final isFormula =
          formulas?.any(
            (e) => e.sheet == sheetName && e.range.startsWith(listAlfabetic(i)),
          ) ??
          false;

      if (isFk || isFormula) {
        updatedRow[i] = null;
      }
    }

    await api.spreadsheets.values.update(
      sheets.ValueRange(values: [updatedRow]),
      spreadsheetId,
      '$sheetName!A${rowIndex + 1}',
      valueInputOption: 'USER_ENTERED',
    );

    _cachedRawRows = null; // Invalida o cache
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

    final rows = await getRawRows(forceRefresh: true);
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

    final gid = await getGid();

    // Pega os índices da cascata de todas as tabelas afetadas
    final deletedIds = indicesToDelete
        .map((idx) => rows[idx][0].toString())
        .toList();
    final cascadeIndices = await GoogleSheetsDatabase()
        .buildCascadeDeleteIndices(sheetName, deletedIds);

    // Adiciona os índices da tabela atual no mapa de deleção
    cascadeIndices.putIfAbsent(gid, () => {}).addAll(indicesToDelete);

    // Constrói os requests finais
    final List<sheets.Request> requests = [];
    cascadeIndices.forEach((sheetId, indices) {
      // Ordena de forma decrescente para não quebrar a ordem de deleção no Sheets
      final sortedIndices = indices.toList()..sort((a, b) => b.compareTo(a));
      for (final index in sortedIndices) {
        requests.add(
          sheets.Request(
            deleteDimension: sheets.DeleteDimensionRequest(
              range: sheets.DimensionRange(
                sheetId: sheetId,
                dimension: "ROWS",
                startIndex: index,
                endIndex: index + 1,
              ),
            ),
          ),
        );
      }
    });

    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(requests: requests),
      spreadsheetId,
    );

    // Como a deleção pode ter apagado a linha 2 (que contém as fórmulas ARRAYFORMULA),
    // nós reaplicamos as fórmulas para garantir que a planilha continue funcionando.
    await GoogleSheetsDatabase().reapplyFormulas();

    _cachedRawRows = null; // Invalida o cache local
  }

  /// Deleta fisicamente a linha baseada no ID
  Future<void> delete(String id) async {
    final rows = await getRawRows(forceRefresh: true);
    if (rows.isEmpty) return;

    int rowIndex = rows.indexWhere(
      (row) => row.isNotEmpty && row[0].toString() == id,
    );
    if (rowIndex == -1) return;

    final gid = await getGid();

    // Pega os índices da cascata
    final cascadeIndices = await GoogleSheetsDatabase()
        .buildCascadeDeleteIndices(sheetName, [id]);

    // Adiciona o próprio índice
    cascadeIndices.putIfAbsent(gid, () => {}).add(rowIndex);

    // Constrói os requests garantindo unicidade e ordem decrescente
    final List<sheets.Request> requests = [];
    cascadeIndices.forEach((sheetId, indices) {
      final sortedIndices = indices.toList()..sort((a, b) => b.compareTo(a));
      for (final index in sortedIndices) {
        requests.add(
          sheets.Request(
            deleteDimension: sheets.DeleteDimensionRequest(
              range: sheets.DimensionRange(
                sheetId: sheetId,
                dimension: "ROWS",
                startIndex: index,
                endIndex: index + 1,
              ),
            ),
          ),
        );
      }
    });

    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(requests: requests),
      spreadsheetId,
    );

    // Como a deleção pode ter apagado a linha 2 (que contém as fórmulas ARRAYFORMULA),
    // nós reaplicamos as fórmulas para garantir que a planilha continue funcionando.
    await GoogleSheetsDatabase().reapplyFormulas();

    _cachedRawRows = null; // Invalida o cache local
  }

  /// Insere uma formula/valores em uma coluna ou linha exemplo: "A1:B1"
  Future<void> insertByCell(List<Cell> cells) async {
    final List<sheets.ValueRange> updateBatch = [];

    for (final cell in cells) {
      updateBatch.add(
        sheets.ValueRange(
          range: "$sheetName!${cell.range}",
          values: cell.value.map((e) => [e]).toList(),
        ),
      );
    }

    if (updateBatch.isNotEmpty) {
      final batchRequest = sheets.BatchUpdateValuesRequest(
        data: updateBatch,
        valueInputOption: "USER_ENTERED",
      );

      await api.spreadsheets.values.batchUpdate(batchRequest, spreadsheetId);
    }
    _cachedRawRows = null; // Invalida o cache local
  }
}

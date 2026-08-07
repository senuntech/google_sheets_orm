import 'package:google_sheets_orm/orm.dart';
import 'package:google_sheets_orm/src/utils.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;

class GoogleSheetsDatabase {
  static final GoogleSheetsDatabase _instance =
      GoogleSheetsDatabase._internal();

  factory GoogleSheetsDatabase() => _instance;

  GoogleSheetsDatabase._internal();

  String? spreadsheetId;
  String _fileName = "App Database";
  Map<String, List<String>> _structure = {};
  sheets.SheetsApi? api;
  List<ForeignKey>? foreignKeys;
  List<Formula>? formulas;

  SheetORM repo(String sheetName) {
    if (spreadsheetId == null || api == null) {
      throw Exception(
        "Database not initialized. Call initialize() first in splash or login.",
      );
    }
    return SheetORM(api!, spreadsheetId!, sheetName, foreignKeys);
  }

  /// Inicializa a base de dados
  Future<void> initialize({
    dynamic httpClient,
    sheets.SheetsApi? injectedSheetsApi,
    drive.DriveApi? injectedDriveApi,
    required String fileName,
    required Map<String, List<String>> structure,
    List<Formula>? formulas,
    List<ForeignKey>? foreignKeys,
  }) async {
    _fileName = fileName;
    _structure = structure;
    this.foreignKeys = foreignKeys;
    this.formulas = formulas;

    if (injectedDriveApi == null &&
        injectedSheetsApi == null &&
        httpClient == null) {
      throw Exception(
        "You must provide either an httpClient or injected APIs for testing.",
      );
    }

    final driveApi = injectedDriveApi ?? drive.DriveApi(httpClient!);
    final sheetsApi = injectedSheetsApi ?? sheets.SheetsApi(httpClient!);
    api = sheetsApi;

    final search = await driveApi.files.list(
      q: "name = '$_fileName' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
    );

    if (search.files != null && search.files!.isNotEmpty) {
      spreadsheetId = search.files!.first.id;
      if (foreignKeys != null) {
        await updateForeignKey(sheetsApi, foreignKeys);
      }
      if (formulas != null) {
        await _updateFormulas(sheetsApi);
      }

      // Now checks both NEW columns and name CHANGES
      await _synchronizeStructure(sheetsApi);
      await _applyAutomaticProtections(sheetsApi);
      return;
    }

    // Initial creation logic...
    var newSpreadsheet = sheets.Spreadsheet(
      properties: sheets.SpreadsheetProperties(title: _fileName),
      sheets: _structure.keys
          .map(
            (title) =>
                sheets.Sheet(properties: sheets.SheetProperties(title: title)),
          )
          .toList(),
    );

    var sheetResponse = await sheetsApi.spreadsheets.create(newSpreadsheet);
    spreadsheetId = sheetResponse.spreadsheetId;

    if (foreignKeys != null) {
      await updateForeignKey(sheetsApi, foreignKeys);
    }
    if (formulas != null) {
      await _updateFormulas(sheetsApi);
    }

    await _configureHeaders(sheetsApi);
    await _applyAutomaticProtections(sheetsApi);
  }

  /// Atualiza as foreign keys na planilha
  Future<void> updateForeignKey(
    sheets.SheetsApi api,
    List<ForeignKey>? foreignKeyConfigs,
  ) async {
    if (foreignKeyConfigs == null || foreignKeyConfigs.isEmpty) return;

    final List<sheets.ValueRange> updateBatch = [];

    for (final config in foreignKeyConfigs) {
      // Nomes claros: origem (source) vs destino/referência (lookup)
      final sourceSheetHeaders = _structure[config.sourceTable];
      final lookupSheetHeaders = _structure[config.lookupTable];

      if (sourceSheetHeaders == null || lookupSheetHeaders == null) {
        throw Exception("Sheet structure not found for: ${config.sourceTable}");
      }

      // Identificando índices (Column Index)
      final colIdxTrigger = sourceSheetHeaders.indexOf(config.sourceKeyColumn);
      final colIdxLookupKey = lookupSheetHeaders.indexOf(
        config.lookupKeyColumn,
      );
      final colIdxLookupValue = lookupSheetHeaders.indexOf(
        config.lookupResultColumn,
      );
      final colIdxTarget = sourceSheetHeaders.indexOf(
        config.sourceTargetColumn,
      );

      if ([
        colIdxTrigger,
        colIdxLookupKey,
        colIdxLookupValue,
        colIdxTarget,
      ].contains(-1)) {
        throw Exception(
          "One or more columns not found in sheet: ${config.sourceTable}",
        );
      }

      final colLetterTrigger = listAlfabetic(colIdxTrigger);
      final colLetterLookupKey = listAlfabetic(colIdxLookupKey);
      final colLetterLookupValue = listAlfabetic(colIdxLookupValue);
      final colLetterTarget = listAlfabetic(colIdxTarget);

      final xLookupFormula =
          "=ARRAYFORMULA(SE(${colLetterTrigger}2:$colLetterTrigger =\"\"; \"\"; PROCX(${colLetterTrigger}2:$colLetterTrigger; ${config.lookupTable}!$colLetterLookupKey:$colLetterLookupKey; ${config.lookupTable}!$colLetterLookupValue:$colLetterLookupValue; \"not found\")))";

      final targetCellRange = '${config.sourceTable}!${colLetterTarget}2';

      updateBatch.add(
        sheets.ValueRange(
          range: targetCellRange,
          values: [
            [xLookupFormula],
          ],
        ),
      );
    }

    if (updateBatch.isNotEmpty) {
      final batchRequest = sheets.BatchUpdateValuesRequest(
        data: updateBatch,
        valueInputOption: "USER_ENTERED",
      );

      await api.spreadsheets.values.batchUpdate(batchRequest, spreadsheetId!);
    }
  }

  /// Restaura as fórmulas e foreign keys.
  /// Útil para ser chamado após deleção de linhas que podem ter apagado a linha 2 (onde as fórmulas residem).
  Future<void> reapplyFormulas() async {
    if (api == null || spreadsheetId == null) return;

    if (foreignKeys != null && foreignKeys!.isNotEmpty) {
      await updateForeignKey(api!, foreignKeys);
    }
    if (formulas != null && formulas!.isNotEmpty) {
      await _updateFormulas(api!);
    }
  }

  /// Configura os headers na planilha
  Future<void> _configureHeaders(sheets.SheetsApi api) async {
    if (spreadsheetId == null) return;

    for (var entry in _structure.entries) {
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: [entry.value]),
        spreadsheetId!,
        "${entry.key}!A1",
        valueInputOption: "USER_ENTERED",
      );
    }
  }

  /// Sincroniza a estrutura da planilha
  Future<void> _synchronizeStructure(sheets.SheetsApi sheetsApi) async {
    final ss = await sheetsApi.spreadsheets.get(spreadsheetId!);
    final existingSheets =
        ss.sheets?.map((s) => s.properties?.title).toList() ?? [];

    for (var entry in _structure.entries) {
      String sheetName = entry.key;
      List<String> localHeaders = entry.value;

      // 1. If the sheet does not exist in Sheets, create the sheet
      if (!existingSheets.contains(sheetName)) {
        await sheetsApi.spreadsheets.batchUpdate(
          sheets.BatchUpdateSpreadsheetRequest(
            requests: [
              sheets.Request(
                addSheet: sheets.AddSheetRequest(
                  properties: sheets.SheetProperties(title: sheetName),
                ),
              ),
            ],
          ),
          spreadsheetId!,
        );
        await _updateHeader(sheetsApi, sheetName, localHeaders);
        continue;
      }

      // 2. Check if the remote header is equal to the local header
      final response = await sheetsApi.spreadsheets.values.get(
        spreadsheetId!,
        '$sheetName!1:1',
      );
      final remoteHeaders =
          response.values?.first.map((e) => e.toString()).toList() ?? [];

      // Compare if lists are identical in content and order
      bool headersAreEqual = _listEquals(localHeaders, remoteHeaders);

      if (!headersAreEqual) {
        // If you changed "description" to "product_name",
        // or added "price" at the end, it will update here.
        await _updateHeader(sheetsApi, sheetName, localHeaders);
      }
    }
  }

  // Função auxiliar para comparar listas
  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Atualiza os headers na planilha
  Future<void> _updateHeader(
    sheets.SheetsApi api,
    String name,
    List<String> columns,
  ) async {
    await api.spreadsheets.values.update(
      sheets.ValueRange(values: [columns]),
      spreadsheetId!,
      "$name!A1",
      valueInputOption: "USER_ENTERED",
    );
  }

  /// Atualiza as fórmulas na planilha
  Future<void> _updateFormulas(sheets.SheetsApi api) async {
    if (formulas == null || formulas!.isEmpty) return;

    final List<sheets.ValueRange> updateBatch = [];

    for (final formula in formulas!) {
      updateBatch.add(
        sheets.ValueRange(
          range: "${formula.sheet}!${formula.range}",
          values: [
            [formula.formula],
          ],
        ),
      );
    }

    if (updateBatch.isNotEmpty) {
      final batchRequest = sheets.BatchUpdateValuesRequest(
        data: updateBatch,
        valueInputOption: "USER_ENTERED",
      );

      await api.spreadsheets.values.batchUpdate(batchRequest, spreadsheetId!);
    }
  }

  /// Aplica proteção automática em colunas de Fórmula e ForeignKey
  Future<void> _applyAutomaticProtections(sheets.SheetsApi api) async {
    final List<sheets.Request> protectionRequests = [];
    final ss = await api.spreadsheets.get(spreadsheetId!);
    final existingSheets = ss.sheets ?? [];

    // Process Formulas
    if (formulas != null) {
      for (final formula in formulas!.where((f) => f.isProtected)) {
        try {
          final targetSheet = existingSheets.firstWhere(
            (s) => s.properties?.title == formula.sheet,
          );
          final sheetId = targetSheet.properties?.sheetId;
          if (sheetId == null) continue;

          final letter = extractColumnLetter(formula.range);
          final columnIndex = columnLetterToIndex(letter);

          protectionRequests.add(
            _buildProtectionRequest(
              sheetId: sheetId,
              columnIndex: columnIndex,
              description: 'Auto-protected by google_sheets_orm (Formula)',
            ),
          );
        } catch (e) {
          // Skip silently if resolution fails
        }
      }
    }

    // Process Foreign Keys
    if (foreignKeys != null) {
      for (final fk in foreignKeys!.where((f) => f.isProtected)) {
        try {
          final targetSheet = existingSheets.firstWhere(
            (s) => s.properties?.title == fk.sourceTable,
          );
          final sheetId = targetSheet.properties?.sheetId;
          if (sheetId == null) continue;

          final headers = _structure[fk.sourceTable];
          if (headers == null) continue;

          final columnIndex = headers.indexOf(fk.sourceTargetColumn);
          if (columnIndex == -1) continue;

          protectionRequests.add(
            _buildProtectionRequest(
              sheetId: sheetId,
              columnIndex: columnIndex,
              description: 'Auto-protected by google_sheets_orm (ForeignKey)',
            ),
          );
        } catch (e) {
          // Skip silently
        }
      }
    }

    if (protectionRequests.isNotEmpty) {
      final batchRequest = sheets.BatchUpdateSpreadsheetRequest(
        requests: protectionRequests,
      );
      await api.spreadsheets.batchUpdate(batchRequest, spreadsheetId!);
    }
  }

  sheets.Request _buildProtectionRequest({
    required int sheetId,
    required int columnIndex,
    required String description,
  }) {
    return sheets.Request(
      addProtectedRange: sheets.AddProtectedRangeRequest(
        protectedRange: sheets.ProtectedRange(
          range: sheets.GridRange(
            sheetId: sheetId,
            startColumnIndex: columnIndex,
            endColumnIndex: columnIndex + 1,
          ),
          description: description,
          warningOnly: true,
        ),
      ),
    );
  }

  /// Constrói de forma recursiva todas as requisições de deleção para os filhos
  /// (e netos) caso o `onDeleteCascade` esteja ativado no ForeignKey.
  /// Retorna um Map agrupando por sheetId (GID) um Set de índices de linha únicos a deletar.
  Future<Map<int, Set<int>>> buildCascadeDeleteIndices(
    String sheetName,
    List<String> idsToDelete, {
    Set<String>? visited,
  }) async {
    Map<int, Set<int>> indicesBySheet = {};
    if (idsToDelete.isEmpty) return indicesBySheet;

    visited ??= {};
    if (visited.contains(sheetName)) {
      return indicesBySheet; // Evita loop infinito em dependências circulares
    }
    visited.add(sheetName);

    final dependents =
        foreignKeys?.where(
          (fk) => fk.lookupTable == sheetName && fk.onDeleteCascade,
        ) ??
        [];

    for (final fk in dependents) {
      final childRepo = repo(fk.sourceTable);
      final childData = await childRepo.findAll();

      List<String> childIdsToDelete = [];
      Set<int> childRowIndices = {}; // Utiliza Set para garantir índices únicos

      for (int i = 0; i < childData.length; i++) {
        final row = childData[i];
        final fkValue = row[fk.sourceKeyColumn]?.toString();

        if (fkValue != null && idsToDelete.contains(fkValue)) {
          if (row.containsKey('id') && row['id'].toString().isNotEmpty) {
            childIdsToDelete.add(row['id'].toString());
          }
          childRowIndices.add(i + 1);
        }
      }

      if (childRowIndices.isNotEmpty) {
        final childGid = await childRepo.getGid();
        indicesBySheet.putIfAbsent(childGid, () => {}).addAll(childRowIndices);
      }

      if (childIdsToDelete.isNotEmpty) {
        final cascadeIndices = await buildCascadeDeleteIndices(
          fk.sourceTable,
          childIdsToDelete,
          visited: Set.from(visited), // Passa cópia do Set para a ramificação
        );

        // Faz o merge dos resultados
        cascadeIndices.forEach((gid, indices) {
          indicesBySheet.putIfAbsent(gid, () => {}).addAll(indices);
        });
      }
    }
    return indicesBySheet;
  }
}

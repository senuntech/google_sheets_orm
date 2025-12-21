import 'package:google_sheets_orm/src/sheet_orm.dart';
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

  SheetORM repo(String sheetName) {
    if (spreadsheetId == null || api == null) {
      throw Exception(
        "Database not initialized. Call initialize() first in splash or login.",
      );
    }
    return SheetORM(api!, spreadsheetId!, sheetName);
  }

  Future<void> initialize({
    required dynamic httpClient,
    required String fileName,
    required Map<String, List<String>> structure,
  }) async {
    _fileName = fileName;
    _structure = structure;

    final driveApi = drive.DriveApi(httpClient);
    final sheetsApi = sheets.SheetsApi(httpClient);
    api = sheetsApi;

    final search = await driveApi.files.list(
      q: "name = '$_fileName' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
    );

    if (search.files != null && search.files!.isNotEmpty) {
      spreadsheetId = search.files!.first.id;

      // Now checks both NEW columns and name CHANGES
      await _synchronizeStructure(sheetsApi);
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
    await _configureHeaders(sheetsApi);
  }

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
}

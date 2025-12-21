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
        "Base de dados não inicializada. Chame initialize() primeiro no splash ou login.",
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
    api = sheets.SheetsApi(httpClient);

    // 1. Localiza o arquivo no Drive
    final search = await driveApi.files.list(
      q: "name = '$_fileName' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
    );

    if (search.files != null && search.files!.isNotEmpty) {
      spreadsheetId = search.files!.first.id;
      return;
    }

    // 2. Se não existir, cria a estrutura dinâmica
    var novaPlanilha = sheets.Spreadsheet(
      properties: sheets.SpreadsheetProperties(title: _fileName),
      sheets: _structure.keys
          .map(
            (title) =>
                sheets.Sheet(properties: sheets.SheetProperties(title: title)),
          )
          .toList(),
    );

    try {
      var sheetResponse = await sheetsApi.spreadsheets.create(novaPlanilha);
      spreadsheetId = sheetResponse.spreadsheetId;

      // 3. Configura os cabeçalhos nas abas recém-criadas
      await _configurarCabecalhos(sheetsApi);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _configurarCabecalhos(sheets.SheetsApi api) async {
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
}

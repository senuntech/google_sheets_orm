import 'package:mocktail/mocktail.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;

class MockSheetsApi extends Mock implements sheets.SheetsApi {}
class MockSpreadsheetsResource extends Mock implements sheets.SpreadsheetsResource {}
class MockSpreadsheetsValuesResource extends Mock implements sheets.SpreadsheetsValuesResource {}
class MockDriveApi extends Mock implements drive.DriveApi {}
class MockFilesResource extends Mock implements drive.FilesResource {}

class FakeBatchUpdateValuesRequest extends Fake implements sheets.BatchUpdateValuesRequest {}
class FakeBatchUpdateSpreadsheetRequest extends Fake implements sheets.BatchUpdateSpreadsheetRequest {}
class FakeValueRange extends Fake implements sheets.ValueRange {}
class FakeSpreadsheet extends Fake implements sheets.Spreadsheet {}

void registerFallbacks() {
  registerFallbackValue(FakeBatchUpdateValuesRequest());
  registerFallbackValue(FakeBatchUpdateSpreadsheetRequest());
  registerFallbackValue(FakeValueRange());
  registerFallbackValue(FakeSpreadsheet());
}

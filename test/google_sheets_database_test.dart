import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:google_sheets_orm/orm.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'mocks.dart';

void main() {
  late MockDriveApi mockDriveApi;
  late MockFilesResource mockFiles;
  late MockSheetsApi mockSheetsApi;
  late MockSpreadsheetsResource mockSpreadsheets;
  late MockSpreadsheetsValuesResource mockValues;
  late GoogleSheetsDatabase db;

  setUpAll(() {
    registerFallbacks();
  });

  setUp(() {
    mockDriveApi = MockDriveApi();
    mockFiles = MockFilesResource();
    when(() => mockDriveApi.files).thenReturn(mockFiles);

    mockSheetsApi = MockSheetsApi();
    mockSpreadsheets = MockSpreadsheetsResource();
    mockValues = MockSpreadsheetsValuesResource();
    when(() => mockSheetsApi.spreadsheets).thenReturn(mockSpreadsheets);
    when(() => mockSpreadsheets.values).thenReturn(mockValues);

    db = GoogleSheetsDatabase();
    // Reset singleton state
    db.spreadsheetId = null;
    db.api = null;
    db.foreignKeys = null;
    db.formulas = null;
  });

  group('GoogleSheetsDatabase Tests', () {
    test('initialize uses existing spreadsheet if found', () async {
      // Setup mock to return an existing file
      final fileList = drive.FileList(
        files: [drive.File(id: 'existing_id', name: 'TestDB')],
      );
      when(() => mockFiles.list(q: any(named: 'q')))
          .thenAnswer((_) async => fileList);

      // Setup mock to simulate returning the spreadsheet properties
      final existingSpreadsheet = sheets.Spreadsheet(
        sheets: [
          sheets.Sheet(
              properties: sheets.SheetProperties(title: 'Users', sheetId: 1))
        ],
      );
      when(() => mockSpreadsheets.get('existing_id'))
          .thenAnswer((_) async => existingSpreadsheet);

      // Mock value get for header comparison
      when(() => mockValues.get('existing_id', 'Users!1:1'))
          .thenAnswer((_) async => sheets.ValueRange(values: [['id', 'name']]));

      await db.initialize(
        injectedDriveApi: mockDriveApi,
        injectedSheetsApi: mockSheetsApi,
        fileName: 'TestDB',
        structure: {
          'Users': ['id', 'name'],
        },
      );

      expect(db.spreadsheetId, 'existing_id');
      verify(() => mockFiles.list(q: any(named: 'q'))).called(1);
      verify(() => mockSpreadsheets.get('existing_id')).called(2);
    });

    test('initialize applies automatic protections for Formula', () async {
      final fileList = drive.FileList(
        files: [drive.File(id: 'existing_id', name: 'TestDB')],
      );
      when(() => mockFiles.list(q: any(named: 'q')))
          .thenAnswer((_) async => fileList);

      final existingSpreadsheet = sheets.Spreadsheet(
        sheets: [
          sheets.Sheet(
              properties: sheets.SheetProperties(title: 'Users', sheetId: 1))
        ],
      );
      when(() => mockSpreadsheets.get('existing_id'))
          .thenAnswer((_) async => existingSpreadsheet);

      when(() => mockValues.get('existing_id', 'Users!1:1'))
          .thenAnswer((_) async => sheets.ValueRange(values: [['id', 'name', 'calculated']]));
          
      when(() => mockValues.batchUpdate(any(), 'existing_id'))
          .thenAnswer((_) async => sheets.BatchUpdateValuesResponse());

      when(() => mockSpreadsheets.batchUpdate(any(), 'existing_id'))
          .thenAnswer((_) async => sheets.BatchUpdateSpreadsheetResponse());

      await db.initialize(
        injectedDriveApi: mockDriveApi,
        injectedSheetsApi: mockSheetsApi,
        fileName: 'TestDB',
        structure: {
          'Users': ['id', 'name', 'calculated'],
        },
        formulas: [
          Formula(formula: '=SUM(A1)', range: 'C:C', sheet: 'Users', isProtected: true),
        ],
      );

      // Verify batchUpdate was called with AddProtectedRangeRequest
      final captured = verify(() => mockSpreadsheets.batchUpdate(captureAny(), 'existing_id')).captured;
      final batchRequest = captured.first as sheets.BatchUpdateSpreadsheetRequest;
      
      expect(batchRequest.requests, isNotNull);
      final hasProtectedRangeRequest = batchRequest.requests!.any((r) => r.addProtectedRange != null);
      expect(hasProtectedRangeRequest, isTrue);
    });
  });
}

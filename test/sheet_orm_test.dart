import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:google_sheets_orm/orm.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'mocks.dart';

void main() {
  late MockSheetsApi mockApi;
  late MockSpreadsheetsResource mockSpreadsheets;
  late MockSpreadsheetsValuesResource mockValues;
  late SheetORM orm;

  setUpAll(() {
    registerFallbacks();
  });

  setUp(() {
    mockApi = MockSheetsApi();
    mockSpreadsheets = MockSpreadsheetsResource();
    mockValues = MockSpreadsheetsValuesResource();

    when(() => mockApi.spreadsheets).thenReturn(mockSpreadsheets);
    when(() => mockSpreadsheets.values).thenReturn(mockValues);

    orm = SheetORM(mockApi, 'test_spreadsheet_id', 'TestSheet', []);
  });

  group('SheetORM Tests', () {
    test('findAll returns correct data', () async {
      final valueRange = sheets.ValueRange(
        values: [
          ['id', 'name', 'age'],
          ['1', 'John', '30'],
          ['2', 'Jane', '25'],
        ],
      );

      when(() => mockValues.get('test_spreadsheet_id', 'TestSheet!A:Z'))
          .thenAnswer((_) async => valueRange);

      final result = await orm.findAll();

      expect(result.length, 2);
      expect(result[0]['name'], 'John');
      expect(result[1]['age'], '25');
    });

    test('findById returns correct row', () async {
      final valueRange = sheets.ValueRange(
        values: [
          ['id', 'name', 'age'],
          ['1', 'John', '30'],
          ['2', 'Jane', '25'],
        ],
      );

      when(() => mockValues.get('test_spreadsheet_id', 'TestSheet!A:Z'))
          .thenAnswer((_) async => valueRange);

      final result = await orm.findById(2);

      expect(result, isNotNull);
      expect(result!['name'], 'Jane');
    });

    test('insert adds new row with auto-increment id', () async {
      final valueRange = sheets.ValueRange(
        values: [
          ['id', 'name'],
          ['1', 'John'],
        ],
      );

      when(() => mockValues.get('test_spreadsheet_id', 'TestSheet!A:Z'))
          .thenAnswer((_) async => valueRange);

      when(() => mockValues.append(
            any(),
            'test_spreadsheet_id',
            'TestSheet!A1',
            valueInputOption: 'USER_ENTERED',
          )).thenAnswer((_) async => sheets.AppendValuesResponse());

      final newId = await orm.insert({'name': 'Jane'});

      expect(newId, 2);
      verify(() => mockValues.append(
            any(),
            'test_spreadsheet_id',
            'TestSheet!A1',
            valueInputOption: 'USER_ENTERED',
          )).called(1);
    });

    test('updateWhereId updates correct row', () async {
      final valueRange = sheets.ValueRange(
        values: [
          ['id', 'name'],
          ['1', 'John'],
          ['2', 'Jane'],
        ],
      );

      when(() => mockValues.get('test_spreadsheet_id', 'TestSheet!A:Z'))
          .thenAnswer((_) async => valueRange);

      when(() => mockValues.update(
            any(),
            'test_spreadsheet_id',
            'TestSheet!A3', // Row 2 + header (1) = 3
            valueInputOption: 'USER_ENTERED',
          )).thenAnswer((_) async => sheets.UpdateValuesResponse());

      await orm.updateWhereId('2', {'name': 'Janet'});

      verify(() => mockValues.update(
            any(),
            'test_spreadsheet_id',
            'TestSheet!A3',
            valueInputOption: 'USER_ENTERED',
          )).called(1);
    });
  });
}

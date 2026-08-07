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

  setUp(() async {
    mockDriveApi = MockDriveApi();
    mockFiles = MockFilesResource();
    when(() => mockDriveApi.files).thenReturn(mockFiles);

    mockSheetsApi = MockSheetsApi();
    mockSpreadsheets = MockSpreadsheetsResource();
    mockValues = MockSpreadsheetsValuesResource();
    when(() => mockSheetsApi.spreadsheets).thenReturn(mockSpreadsheets);
    when(() => mockSpreadsheets.values).thenReturn(mockValues);

    // Configurando DB Singleton
    db = GoogleSheetsDatabase();
    db.spreadsheetId = null;
    db.api = null;
    db.foreignKeys = null;
    db.formulas = null;

    final fileList = drive.FileList(
      files: [drive.File(id: 'test_db_id', name: 'TestDB')],
    );
    when(() => mockFiles.list(q: any(named: 'q')))
        .thenAnswer((_) async => fileList);

    final existingSpreadsheet = sheets.Spreadsheet(
      sheets: [
        sheets.Sheet(properties: sheets.SheetProperties(title: 'Clientes', sheetId: 100)),
        sheets.Sheet(properties: sheets.SheetProperties(title: 'Debitos', sheetId: 200)),
        sheets.Sheet(properties: sheets.SheetProperties(title: 'Parcelas', sheetId: 300)),
      ],
    );
    when(() => mockSpreadsheets.get('test_db_id'))
        .thenAnswer((_) async => existingSpreadsheet);
        
    when(() => mockValues.get('test_db_id', 'Clientes!1:1'))
        .thenAnswer((_) async => sheets.ValueRange(values: [['id', 'nome']]));
    when(() => mockValues.get('test_db_id', 'Debitos!1:1'))
        .thenAnswer((_) async => sheets.ValueRange(values: [['id', 'id_cliente', 'valor']]));
    when(() => mockValues.get('test_db_id', 'Parcelas!1:1'))
        .thenAnswer((_) async => sheets.ValueRange(values: [['id', 'id_debito', 'vencimento']]));

    when(() => mockSpreadsheets.batchUpdate(any(), 'test_db_id'))
        .thenAnswer((_) async => sheets.BatchUpdateSpreadsheetResponse());
    when(() => mockValues.batchUpdate(any(), 'test_db_id'))
        .thenAnswer((_) async => sheets.BatchUpdateValuesResponse());
    when(() => mockValues.update(
            any(), any(), any(),
            valueInputOption: any(named: 'valueInputOption')))
        .thenAnswer((_) async => sheets.UpdateValuesResponse());
  });

  test('Deve realizar exclusão em cascata (3 níveis)', () async {
    // Definindo Foreign Keys com Cascade ativado
    final fks = [
      ForeignKey(
        sourceTable: 'Debitos',
        sourceKeyColumn: 'id_cliente',
        sourceTargetColumn: 'nome_cliente',
        lookupTable: 'Clientes',
        lookupKeyColumn: 'id',
        lookupResultColumn: 'nome',
        onDeleteCascade: true,
      ),
      ForeignKey(
        sourceTable: 'Parcelas',
        sourceKeyColumn: 'id_debito',
        sourceTargetColumn: 'desc',
        lookupTable: 'Debitos',
        lookupKeyColumn: 'id',
        lookupResultColumn: 'descricao',
        onDeleteCascade: true,
      )
    ];

    await db.initialize(
      injectedDriveApi: mockDriveApi,
      injectedSheetsApi: mockSheetsApi,
      fileName: 'TestDB',
      structure: {
        'Clientes': ['id', 'nome'],
        'Debitos': ['id', 'id_cliente', 'valor', 'nome_cliente', 'descricao'],
        'Parcelas': ['id', 'id_debito', 'vencimento', 'desc'],
      },
      foreignKeys: fks,
    );

    // Mock dados para findAll nas tabelas
    when(() => mockValues.get('test_db_id', 'Clientes!A:A'))
        .thenAnswer((_) async => sheets.ValueRange(values: [
              ['id'],
              ['10'], // Linha 1
            ]));

    when(() => mockValues.get('test_db_id', 'Debitos!A:Z'))
        .thenAnswer((_) async => sheets.ValueRange(values: [
              ['id', 'id_cliente', 'valor', 'nome_cliente', 'descricao'],
              ['100', '10', '50.00', 'João', 'Debito 1'], // Linha 1 (será deletada)
              ['101', '20', '60.00', 'Maria', 'Debito 2'], // Linha 2 (mantida)
            ]));

    when(() => mockValues.get('test_db_id', 'Parcelas!A:Z'))
        .thenAnswer((_) async => sheets.ValueRange(values: [
              ['id', 'id_debito', 'vencimento', 'desc'],
              ['1001', '100', '2026-10-01', 'Desc'], // Linha 1 (será deletada)
              ['1002', '100', '2026-11-01', 'Desc'], // Linha 2 (será deletada)
              ['1003', '101', '2026-12-01', 'Desc'], // Linha 3 (mantida)
            ]));

    final repoClientes = db.repo('Clientes');
    
    // Executa a deleção do cliente ID 10
    await repoClientes.delete('10');

    final captured = verify(() => mockSpreadsheets.batchUpdate(captureAny(), 'test_db_id')).captured;
    
    // O último batchUpdate deve ser o que deleta as dimensões
    final batchRequest = captured.last as sheets.BatchUpdateSpreadsheetRequest;
    
    // O batchRequest deve conter:
    // - 1 request para o cliente (index 1)
    // - 1 request para o débito associado (index 1)
    // - 2 requests para as parcelas associadas (index 2 e 1 - na ordem decrescente)
    expect(batchRequest.requests?.length, 4);

    final requests = batchRequest.requests!;
    
    // Verifica se os GIDs estão corretos
    final clienteRequests = requests.where((r) => r.deleteDimension?.range?.sheetId == 100); // Cliente
    final debitoRequests = requests.where((r) => r.deleteDimension?.range?.sheetId == 200); // Debito
    final parcelaRequests = requests.where((r) => r.deleteDimension?.range?.sheetId == 300); // Parcela

    expect(clienteRequests.length, 1);
    expect(debitoRequests.length, 1);
    expect(parcelaRequests.length, 2);

    // Verifica ordenação decrescente em Parcelas para evitar shifting
    final parcelaIndices = parcelaRequests.map((r) => r.deleteDimension!.range!.startIndex!).toList();
    expect(parcelaIndices[0], 2); // Row 3 in sheets
    expect(parcelaIndices[1], 1); // Row 2 in sheets
  });
}

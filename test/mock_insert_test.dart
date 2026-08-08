import 'dart:convert';
import 'package:test/test.dart';

void main() {
  test('Mock spreadsheet test', () {
    List<List<dynamic>> mockRows = [
      ["id", "descricao", "valor", "id_cliente", "juros", "parcelas", "intervalo", "valor_parcela", "inicio_pagamento", "nome_cliente", "juros_simples", "valor_pago_juros_simples", "status", "data_contratacao"],
      ["", "", "", "", "", "", "", "", "", "", "", "", "", ""],
      ["", "", "", "", "", "", "", "", "", "", "", "", "", ""],
    ];

    int idColIndex = mockRows[0].indexOf("id");
    int maxId = 0;
    int lastPopulatedRow = 1;

    for (var i = 1; i < mockRows.length; i++) {
      if (mockRows[i].length > idColIndex) {
        var idStr = mockRows[i][idColIndex].toString().trim();
        if (idStr.isNotEmpty) {
          lastPopulatedRow = i + 1;
          int currentId = int.tryParse(idStr) ?? 0;
          if (currentId > maxId) maxId = currentId;
        }
      }
    }

    int nextRow = lastPopulatedRow + 1;
    print('Next row to insert: $nextRow');
    expect(nextRow, 2);
  });
}

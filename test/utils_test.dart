import 'package:flutter_test/flutter_test.dart';
import 'package:google_sheets_orm/src/utils.dart';

void main() {
  group('Utils Tests', () {
    test('listAlfabetic returns correct letter', () {
      expect(listAlfabetic(0), 'A');
      expect(listAlfabetic(1), 'B');
      expect(listAlfabetic(25), 'Z');
    });

    test('columnLetterToIndex converts letter to index', () {
      expect(columnLetterToIndex('A'), 0);
      expect(columnLetterToIndex('B'), 1);
      expect(columnLetterToIndex('Z'), 25);
      expect(columnLetterToIndex('AA'), 26);
      expect(columnLetterToIndex('AB'), 27);
    });

    test('extractColumnLetter extracts letter from A1 notation', () {
      expect(extractColumnLetter('A1'), 'A');
      expect(extractColumnLetter('A:A'), 'A');
      expect(extractColumnLetter('AA2:AA'), 'AA');
      expect(extractColumnLetter('B'), 'B');
      expect(extractColumnLetter('123'), 'A'); // Fallback sem letras
    });
  });
}

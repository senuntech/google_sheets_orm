String listAlfabetic(int index) {
  final list = List.generate(
    26,
    (i) => i + 65,
  ).map((i) => String.fromCharCode(i)).toList();

  return list[index];
}

int columnLetterToIndex(String letter) {
  final upperLetter = letter.toUpperCase();
  int index = 0;
  for (int i = 0; i < upperLetter.length; i++) {
    index = index * 26 + (upperLetter.codeUnitAt(i) - 65 + 1);
  }
  return index - 1;
}

String extractColumnLetter(String range) {
  final match = RegExp(r'[A-Za-z]+').firstMatch(range);
  if (match != null) {
    return match.group(0)!.toUpperCase();
  }
  return 'A'; // Fallback
}

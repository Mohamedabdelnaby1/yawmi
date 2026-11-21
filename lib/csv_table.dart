List<List<String>> parseCsvTable(String text) {
  final data = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final table = <List<String>>[];
  var row = <String>[], field = StringBuffer();
  var quoted = false, closed = false;
  void cell() {
    final value = field.toString();
    final escaped =
        value.startsWith("'") &&
        RegExp(r'^\s*[=+@\-\t\r]').hasMatch(value.substring(1));
    row.add(escaped ? value.substring(1) : value);
    field = StringBuffer();
    closed = false;
  }

  for (var i = 0; i < data.length; i++) {
    final ch = data[i];
    if (quoted) {
      if (ch == '"' && i + 1 < data.length && data[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (ch == '"') {
        closed = true;
        quoted = false;
      } else {
        field.write(ch);
      }
    } else if (ch == ',' || ch == '\r' || ch == '\n') {
      cell();
      if (ch != ',') {
        if (row.any((value) => value.isNotEmpty)) table.add(row);
        row = [];
        if (ch == '\r' && i + 1 < data.length && data[i + 1] == '\n') i++;
      }
    } else if (ch == '"' && field.isEmpty && !closed) {
      quoted = true;
    } else if (!closed && ch != '"') {
      field.write(ch);
    } else {
      throw const FormatException('Invalid CSV quoting');
    }
  }
  if (quoted) throw const FormatException('Unclosed CSV quote');
  if (closed || field.isNotEmpty || row.isNotEmpty) {
    cell();
    table.add(row);
  }
  return table;
}

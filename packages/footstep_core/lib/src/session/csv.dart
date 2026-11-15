/// 따옴표로 감싼 필드(쉼표·이중 따옴표 포함)를 처리하는 CSV 한 줄 분리. [formatCsvField]의 서식과 짝이다.
List<String> splitCsvLine(String line) {
  final fields = <String>[];
  final current = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        current.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      fields.add(current.toString());
      current.clear();
    } else {
      current.write(c);
    }
  }
  fields.add(current.toString());
  return fields;
}

/// 물리적 줄 목록을 논리적 CSV 행으로 합친다. 따옴표 안의 줄바꿈(메모 등)이 readAsLines에서 두 줄로
/// 쪼개지므로, 따옴표가 닫히지 않은 줄은 다음 줄과 줄바꿈으로 이어 붙인다. 이미 합쳐진 행을 넣어도 같다.
List<String> csvRecords(List<String> lines) {
  final records = <String>[];
  StringBuffer? open;
  var openQuotes = 0;
  for (final line in lines) {
    final pending = open;
    if (pending == null) {
      final quotes = '"'.allMatches(line).length;
      if (quotes.isEven) {
        records.add(line);
      } else {
        open = StringBuffer(line);
        openQuotes = quotes;
      }
    } else {
      pending.write('\n');
      pending.write(line);
      openQuotes += '"'.allMatches(line).length;
      if (openQuotes.isEven) {
        records.add(pending.toString());
        open = null;
      }
    }
  }
  // 따옴표가 끝내 안 닫힌 꼬리는 깨진 행으로 그대로 남겨, 호출하는 쪽이 건너뛰게 한다.
  if (open != null) records.add(open.toString());
  return records;
}

/// CSV 필드 하나의 문자열. 값이 없거나 유한한 숫자가 아니면(NaN 등) 빈칸으로 둔다 —
/// 분석 쪽(pandas)이 빈칸을 결측치로 읽는다.
String formatCsvField(Object? value) {
  if (value == null) return '';
  if (value is double && !value.isFinite) return '';
  if (value is bool) return value ? '1' : '0';
  final text = value.toString();
  final needsQuote =
      text.contains(',') || text.contains('"') || text.contains('\n') || text.contains('\r');
  return needsQuote ? '"${text.replaceAll('"', '""')}"' : text;
}

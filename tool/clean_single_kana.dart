// ignore_for_file: avoid_print
import 'dart:io';

bool isSingleKana(String key) {
  if (key.length != 1) return false;
  final cp = key.codeUnitAt(0);
  // Hiragana
  if (cp >= 0x3040 && cp <= 0x309F) return true;
  // Katakana (gồm cả U+30FC ー)
  if (cp >= 0x30A0 && cp <= 0x30FF) return true;
  // Katakana Phonetic Extensions
  if (cp >= 0x31F0 && cp <= 0x31FF) return true;
  // Halfwidth Katakana
  if (cp >= 0xFF65 && cp <= 0xFF9F) return true;
  return false;
}

void main() {
  final file = File('data/jp/JaViDict.txt');
  if (!file.existsSync()) {
    print('Không tìm thấy file: ${file.path}');
    return;
  }

  final lines = file.readAsLinesSync();
  print('Tổng số dòng ban đầu: ${lines.length}');

  final removed = <String>[];
  final keptLines = <String>[];

  for (final line in lines) {
    if (line.isEmpty) {
      keptLines.add(line);
      continue;
    }
    final index = line.indexOf('=');
    if (index == -1) {
      keptLines.add(line);
      continue;
    }

    final key = line.substring(0, index);
    if (isSingleKana(key)) {
      removed.add(line);
    } else {
      keptLines.add(line);
    }
  }

  print('Số dòng bị loại bỏ: ${removed.length}');
  print('Một số dòng bị loại bỏ tiêu biểu:');
  for (var i = 0; i < removed.length && i < 20; i++) {
    print('  ${removed[i]}');
  }

  // Viết lại file
  // Thêm BOM \uFEFF ở đầu file
  final buffer = StringBuffer();
  buffer.write('\uFEFF');
  buffer.write(keptLines.join('\r\n')); // Dùng CRLF vì QuickTranslator thường dùng CRLF

  file.writeAsStringSync(buffer.toString());
  print('Đã ghi lại file ${file.path}. Tổng số dòng mới: ${keptLines.length}');
}

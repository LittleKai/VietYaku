// Sinh assets/mappings/trad2simp.tsv từ data/cn/cedict_ts.u8 (không cần mạng).
//
//   dart run tool/build_trad2simp.dart
//
// CC-CEDICT mỗi dòng là `繁體 简体 [pin1 yin1] /nghĩa/`. Hai cột phồn/giản của
// cùng một mục luôn cùng số ký tự nên ghép được từng cặp ký tự một; ký tự nào
// khác nhau là một cặp phồn→giản. Đếm trên toàn bộ 120k mục rồi chọn giản thể
// hay gặp nhất cho mỗi ký tự phồn thể — chữ đa xạ ảnh (乾 → 干/乾) lấy bản phổ
// biến hơn.
//
// Chỉ nhận cặp mà cả hai ký tự đều nằm trong BMP (1 UTF-16 code unit): app quy
// phồn→giản ngay trước khi tra nhưng token vẫn trỏ ngược về offset của văn bản
// gốc, nên độ dài chuỗi phải giữ nguyên tuyệt đối.

import 'dart:io';

void main(List<String> args) {
  final cedict = File('data/cn/cedict_ts.u8');
  if (!cedict.existsSync()) {
    stderr.writeln('Không thấy ${cedict.path} — chạy từ thư mục gốc dự án.');
    exit(1);
  }

  // trad -> {simp: số lần gặp}
  final counts = <String, Map<String, int>>{};
  var entries = 0;
  var skippedLength = 0;

  for (final line in cedict.readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final space = line.indexOf(' ');
    if (space <= 0) continue;
    final second = line.indexOf(' ', space + 1);
    if (second <= space) continue;
    final trad = line.substring(0, space);
    final simp = line.substring(space + 1, second);
    if (trad.length != simp.length) {
      skippedLength++;
      continue;
    }
    entries++;
    for (var i = 0; i < trad.length; i++) {
      final t = trad.codeUnitAt(i);
      final s = simp.codeUnitAt(i);
      if (t == s) continue;
      // Bỏ surrogate: ký tự ngoài BMP ghép theo code unit là vô nghĩa.
      if (_isSurrogate(t) || _isSurrogate(s)) continue;
      counts
          .putIfAbsent(String.fromCharCode(t), () => <String, int>{})
          .update(
            String.fromCharCode(s),
            (value) => value + 1,
            ifAbsent: () => 1,
          );
    }
  }

  final table = <String, String>{};
  final weight = <String, int>{};
  var ambiguous = 0;
  for (final entry in counts.entries) {
    final byCount = entry.value.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (byCount.length > 1) ambiguous++;
    table[entry.key] = byCount.first.key;
    weight[entry.key] = byCount.first.value;
  }

  // Bảng đúng thì đích không bao giờ là nguồn của cặp khác: đã là giản thể thì
  // không còn gì để quy nữa. Còn `a→b` mà `b→c` nghĩa là một trong hai mắt xích
  // là rác — sinh ra từ vài mục cedict bị đảo cột (`提尔 提爾`) hoặc lệch ký tự,
  // cho ra cặp ngược chiều (`尔→爾`) lẫn cặp bậy (`辛→緬`). Chiều đúng đến từ
  // hàng nghìn mục, chiều sai chỉ vài mục, nên bỏ mắt xích nhẹ ký hơn cho tới
  // khi hết chuỗi.
  final dropped = <String>[];
  while (true) {
    String? drop;
    for (final key in table.keys) {
      final mid = table[key]!;
      if (!table.containsKey(mid)) continue;
      drop = weight[key]! <= weight[mid]! ? key : mid;
      break;
    }
    if (drop == null) break;
    table.remove(drop);
    weight.remove(drop);
    dropped.add(drop);
  }

  final keys = table.keys.toList()..sort();
  final out = StringBuffer()
    ..writeln('# trad<TAB>simp — sinh bởi tool/build_trad2simp.dart')
    ..writeln('# nguồn: data/cn/cedict_ts.u8, ${keys.length} ký tự');
  for (final key in keys) {
    out.writeln('$key\t${table[key]}');
  }
  File('assets/mappings/trad2simp.tsv').writeAsStringSync(out.toString());

  stdout
    ..writeln(
      'Mục cedict dùng được : $entries (bỏ $skippedLength mục lệch độ dài)',
    )
    ..writeln('Ký tự phồn thể       : ${keys.length}')
    ..writeln('Có nhiều giản thể    : $ambiguous (lấy bản hay gặp nhất)')
    ..writeln('Bỏ mắt xích rác      : ${dropped.length} (${dropped.join()})')
    ..writeln('Đã ghi assets/mappings/trad2simp.tsv');
}

bool _isSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDFFF;

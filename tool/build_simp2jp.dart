// Sinh assets/mappings/simp2jp.tsv + jp_valid_kanji.txt (chạy OFFLINE lúc dev,
// cần mạng; runtime app KHÔNG cần mạng — asset đã commit).
//
// Nguồn:
// - OpenCC STCharacters.txt        (giản → phồn, có thể nhiều candidate)
// - OpenCC JPShinjitaiCharacters.txt (kyūjitai → shinjitai ~360 cặp)
// - Himeyama/joyo-kanji joyo2021.txt (2136 jōyō, cột 2 = kyūjitai nếu có)
// - aknm21/jinmeiyo-kanji index.js   (~863 jinmeiyō)
//
// Thuật toán: compose simp → trad → shinjitai.
// QUY TẮC VÀNG: simp đã nằm trong jp_valid_kanji → KHÔNG sinh mapping
// (芸/后/叶/国/学 giữ nguyên). Identity sau compose → bỏ.
// Nhiều candidate → ghi `simp\tc1|c2` (runtime coi là ambiguous, không convert;
// simp2jp_overrides.tsv — file soạn tay, commit — resolve các case này).
//
// Chạy: dart run tool/build_simp2jp.dart

import 'dart:convert';
import 'dart:io';

const stUrl =
    'https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/STCharacters.txt';
const jpShinUrl =
    'https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/JPShinjitaiCharacters.txt';
const joyoUrl =
    'https://raw.githubusercontent.com/Himeyama/joyo-kanji/master/joyo2021.txt';
const jinmeiyoUrl =
    'https://raw.githubusercontent.com/aknm21/jinmeiyo-kanji/master/index.js';

/// Hyōgai kanji bổ sung (表外漢字 phổ biến trong tiểu thuyết — không thuộc
/// jōyō/jinmeiyō nhưng là chữ Nhật hợp lệ, không được convert).
/// Danh sách tay, mở rộng khi phát hiện case sai.
const hyogaiSupplement = '嘘噂頷顎躱睨呟騙撫囁揶揄弄嗤嘲蹲踞頬杖梯襖'
    '拗縋憑咄嗟躊躇逡巡朦朧瞭曖昧痙攣蠢煌燦爛絢誂餞囃噺辻凪笹峠榊畑辷込匂';

Future<String> download(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }
    return response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

void main() async {
  stdout.writeln('Downloading sources...');
  final st = await download(stUrl);
  final jpShin = await download(jpShinUrl);
  final joyo = await download(joyoUrl);
  final jinmeiyo = await download(jinmeiyoUrl);

  // --- jp_valid_kanji ---
  final valid = <String>{};
  for (final line in const LineSplitter().convert(joyo)) {
    final cols = line.split(',');
    if (cols.isNotEmpty && cols[0].trim().isNotEmpty) {
      final ch = cols[0].trim();
      if (ch.runes.length == 1 && ch.runes.first > 0x3000) valid.add(ch);
    }
  }
  final joyoCount = valid.length;
  final cjkChar = RegExp(r'"([㐀-鿿豈-﫿])"');
  for (final m in cjkChar.allMatches(jinmeiyo)) {
    valid.add(m.group(1)!);
  }
  final jinmeiyoCount = valid.length - joyoCount;
  for (final rune in hyogaiSupplement.runes) {
    if (rune > 0x3000) valid.add(String.fromCharCode(rune));
  }
  stdout.writeln('jp_valid: joyo=$joyoCount jinmeiyo≈$jinmeiyoCount '
      'total=${valid.length}');

  // --- shinjitai map: kyūjitai/phồn → shinjitai ---
  // LƯU Ý: JPShinjitaiCharacters.txt của OpenCC map shinjitai → kyūjitai
  // (`暦\t曆`), phải ĐẢO CHIỀU khi dùng.
  final shinjitai = <String, String>{};
  for (final line in const LineSplitter().convert(jpShin)) {
    if (line.startsWith('#')) continue;
    final parts = line.split('\t');
    if (parts.length >= 2 && parts[0].trim().isNotEmpty) {
      final shin = parts[0].trim();
      for (final old in parts[1].split(' ')) {
        final o = old.trim();
        if (o.isNotEmpty) shinjitai.putIfAbsent(o, () => shin);
      }
    }
  }
  // Bổ sung kyūjitai từ bảng jōyō (cột 2 → cột 1).
  for (final line in const LineSplitter().convert(joyo)) {
    final cols = line.split(',');
    if (cols.length >= 2 && cols[1].trim().isNotEmpty) {
      shinjitai.putIfAbsent(cols[1].trim(), () => cols[0].trim());
    }
  }
  stdout.writeln('shinjitai map: ${shinjitai.length} pairs');

  // --- compose simp → trad → shinjitai ---
  final table = <String, Set<String>>{};

  void addEntry(String from, String to) {
    if (from == to) return;
    if (valid.contains(from)) return; // quy tắc vàng
    table.putIfAbsent(from, () => <String>{}).add(to);
  }

  for (final line in const LineSplitter().convert(st)) {
    final parts = line.split('\t');
    if (parts.length < 2) continue;
    final simp = parts[0].trim();
    if (simp.runes.length != 1) continue;
    for (final trad in parts[1].split(' ')) {
      final t = trad.trim();
      if (t.isEmpty) continue;
      addEntry(simp, shinjitai[t] ?? t);
    }
  }
  // Phồn thể lẫn trong dữ liệu (trộn giản/phồn): thêm luôn kyūjitai→shinjitai.
  for (final entry in shinjitai.entries) {
    addEntry(entry.key, entry.value);
  }

  final resolved = <String, String>{};
  final ambiguous = <String, Set<String>>{};
  for (final entry in table.entries) {
    if (entry.value.length == 1) {
      resolved[entry.key] = entry.value.first;
    } else {
      ambiguous[entry.key] = entry.value;
    }
  }
  stdout.writeln('table: ${resolved.length} resolved, '
      '${ambiguous.length} ambiguous');

  // --- write assets ---
  final outDir = Directory('assets/mappings');
  outDir.createSync(recursive: true);

  final tsv = StringBuffer();
  final sortedKeys = [...resolved.keys, ...ambiguous.keys]..sort();
  for (final key in sortedKeys) {
    final value =
        resolved[key] ?? (ambiguous[key]!.toList()..sort()).join('|');
    tsv.writeln('$key\t$value');
  }
  File('${outDir.path}/simp2jp.tsv').writeAsStringSync(tsv.toString());

  final validSorted = valid.toList()..sort();
  File('${outDir.path}/jp_valid_kanji.txt')
      .writeAsStringSync('${validSorted.join('\n')}\n');

  stdout.writeln('Wrote ${outDir.path}/simp2jp.tsv '
      'and jp_valid_kanji.txt');
  stdout.writeln('\nAmbiguous cần cân nhắc override:');
  final sample = ambiguous.entries.take(40);
  for (final e in sample) {
    stdout.writeln('  ${e.key} → ${e.value.join("|")}');
  }
}

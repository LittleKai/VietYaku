// Sinh data/jp/SudachiVariants.txt + data/jp/SudachiReadings.txt từ
// SudachiDict raw lexicon (docs/NGHIEN_CUU_SUDACHI.md §2.6). Chạy lúc dev,
// CẦN MẠNG lần đầu (tải zip về build/sudachi_raw, các lần sau dùng lại):
//
//   dart run tool/build_sudachi_assets.dart [--version=20260428]
//       [--lex=small,core] [--data=data/jp]
//
// Nguồn: http://sudachi.s3-website-ap-northeast-1.amazonaws.com/sudachidict-raw/
// (SudachiDict, Works Applications — Apache-2.0; chỉ HTTP, không có HTTPS).
//
// - SudachiVariants.txt: `biến_thể=<value VietPhrase của dạng chuẩn>` khi
//   trường 12 (正規化表記) khác trường 0 (見出し), dạng chuẩn CÓ trong
//   VietPhrase còn biến thể thì KHÔNG (và không có trong Names).
//   Value copy nguyên byte từ VietPhrase.
// - SudachiReadings.txt: `từ=katakana` (trường 11, tối đa 3 cách đọc, nối
//   `/`) cho các key có trong VietPhrase/Names/LacViet chứa ít nhất 1 chữ
//   Hán (key thuần kana tự đọc được, bỏ cho nhẹ file).
//
// Cả hai file ghi UTF-8 BOM CRLF, sort theo key để diff ổn định.
import 'dart:convert';
import 'dart:io';

import 'package:vietyaku/core/cjk.dart';
import 'package:vietyaku/features/dictionary/data/dict_parser.dart';

const _baseUrl =
    'http://sudachi.s3-website-ap-northeast-1.amazonaws.com/sudachidict-raw';
const _defaultVersion = '20260428';

Future<void> main(List<String> args) async {
  var version = _defaultVersion;
  var lexParts = ['small', 'core'];
  var dataDir = 'data/jp';
  for (final arg in args) {
    if (arg.startsWith('--version=')) {
      version = arg.substring('--version='.length);
    } else if (arg.startsWith('--lex=')) {
      lexParts = arg.substring('--lex='.length).split(',');
    } else if (arg.startsWith('--data=')) {
      dataDir = arg.substring('--data='.length);
    } else {
      stderr.writeln('Tham số không hiểu: $arg');
      exit(2);
    }
  }

  final cacheDir = Directory('build/sudachi_raw/$version')
    ..createSync(recursive: true);

  // 1. Tải + giải nén các lex CSV còn thiếu.
  final csvFiles = <File>[];
  for (final part in lexParts) {
    final csv = File('${cacheDir.path}/${part}_lex.csv');
    if (!csv.existsSync()) {
      final zip = File('${cacheDir.path}/${part}_lex.zip');
      if (!zip.existsSync()) {
        final url = '$_baseUrl/$version/${part}_lex.zip';
        stdout.writeln('Tải $url ...');
        await _download(url, zip);
      }
      stdout.writeln('Giải nén ${zip.path} ...');
      final r = Process.runSync('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -LiteralPath "${zip.absolute.path}" '
            '-DestinationPath "${cacheDir.absolute.path}" -Force',
      ]);
      if (r.exitCode != 0) {
        stderr.writeln('Expand-Archive lỗi: ${r.stderr}');
        exit(1);
      }
      if (!csv.existsSync()) {
        stderr.writeln('Không thấy ${csv.path} sau khi giải nén.');
        exit(1);
      }
    }
    csvFiles.add(csv);
  }

  // 2. Đọc từ điển app hiện có làm bộ lọc.
  Map<String, String> loadDict(String name) {
    final f = File('$dataDir/$name');
    if (!f.existsSync()) {
      stderr.writeln('Thiếu $dataDir/$name — chạy từ thư mục gốc dự án.');
      exit(1);
    }
    return parseEntries(
      const Utf8Codec(allowMalformed: true).decode(f.readAsBytesSync()),
    );
  }

  final vietPhrase = loadDict('VietPhrase.txt');
  final names = loadDict('Names.txt');
  final lacViet = loadDict('LacViet.txt');
  stdout.writeln(
    'VietPhrase ${vietPhrase.length} · Names ${names.length} · '
    'LacViet ${lacViet.length}',
  );

  bool hasHan(String s) {
    for (var i = 0; i < s.length; i += runeLengthAt(s, i)) {
      if (isHanCodePoint(codePointAt(s, i))) return true;
    }
    return false;
  }

  bool knownKey(String s) =>
      vietPhrase.containsKey(s) ||
      names.containsKey(s) ||
      lacViet.containsKey(s);

  // Biến thể an toàn cho greedy match: chứa ≥1 chữ Hán (okurigana/chữ khác),
  // hoặc thuần katakana ≥2 code unit (từ vựng thật). Biến thể thuần hiragana
  // (し→四, く→九...) trùng ngữ pháp — Sudachi phân giải bằng lattice theo
  // ngữ cảnh, VietYaku greedy thì không → PHẢI loại (bug してくれ).
  bool safeVariant(String s) {
    if (hasHan(s)) return true;
    if (s.length < 2) return false;
    for (var i = 0; i < s.length; i += runeLengthAt(s, i)) {
      if (charCategoryOf(codePointAt(s, i)) != CjkCharCategory.katakana) {
        return false;
      }
    }
    return true;
  }

  // 3. Quét lexicon: biến thể (0 ≠ 12) + cách đọc (11).
  final variants = <String, String>{}; // biến_thể → value VietPhrase
  final readings = <String, List<String>>{}; // từ → các cách đọc katakana
  var rows = 0;
  for (final csv in csvFiles) {
    final lines = const Utf8Codec(
      allowMalformed: true,
    ).decode(csv.readAsBytesSync()).split('\n');
    for (var line in lines) {
      line = line.trimRight();
      if (line.isEmpty) continue;
      final fields = _parseCsvLine(line);
      if (fields.length < 13) continue;
      rows++;
      final surface = fields[0];
      final reading = fields[11];
      final normalized = fields[12];
      if (surface.isEmpty) continue;

      if (normalized.isNotEmpty &&
          normalized != '*' &&
          normalized != surface &&
          safeVariant(surface) &&
          !variants.containsKey(surface) &&
          !vietPhrase.containsKey(surface) &&
          !names.containsKey(surface)) {
        final value = vietPhrase[normalized];
        if (value != null) variants[surface] = value;
      }

      if (reading.isNotEmpty &&
          reading != '*' &&
          hasHan(surface) &&
          knownKey(surface)) {
        final list = readings.putIfAbsent(surface, () => []);
        if (list.length < 3 && !list.contains(reading)) list.add(reading);
      }
    }
  }
  stdout.writeln('Đã quét $rows dòng lexicon (${lexParts.join('+')}).');

  // Biến thể cũng đáng có cách đọc — key sẽ match được sau khi merge.
  // (Không quét lại: reading của biến thể nằm cùng dòng đã xử lý ở trên,
  // nhưng biến thể không phải knownKey — bổ sung bằng lượt quét thứ hai.)
  for (final csv in csvFiles) {
    final lines = const Utf8Codec(
      allowMalformed: true,
    ).decode(csv.readAsBytesSync()).split('\n');
    for (var line in lines) {
      line = line.trimRight();
      if (line.isEmpty) continue;
      final fields = _parseCsvLine(line);
      if (fields.length < 13) continue;
      final surface = fields[0];
      final reading = fields[11];
      if (reading.isEmpty || reading == '*') continue;
      if (!variants.containsKey(surface) || !hasHan(surface)) continue;
      final list = readings.putIfAbsent(surface, () => []);
      if (list.length < 3 && !list.contains(reading)) list.add(reading);
    }
  }

  // 4. Ghi file UTF-8 BOM CRLF, sort key.
  void writeDict(String name, Map<String, String> entries) {
    final keys = entries.keys.toList()..sort();
    final sb = StringBuffer('﻿'); // BOM
    for (final k in keys) {
      sb.write(k);
      sb.write('=');
      sb.write(entries[k]);
      sb.write('\r\n');
    }
    File('$dataDir/$name').writeAsStringSync(sb.toString());
    stdout.writeln('Ghi $dataDir/$name: ${keys.length} mục.');
  }

  writeDict('SudachiVariants.txt', variants);
  writeDict('SudachiReadings.txt', {
    for (final e in readings.entries) e.key: e.value.join('/'),
  });
}

Future<void> _download(String url, File dest) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode} cho $url');
    }
    final sink = dest.openWrite();
    await sink.addStream(res);
    await sink.close();
  } finally {
    client.close();
  }
}

/// Tách 1 dòng CSV RFC 4180 (field có thể bọc `"..."`, `""` là dấu nháy).
List<String> _parseCsvLine(String line) {
  final fields = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        sb.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      fields.add(sb.toString());
      sb.clear();
    } else {
      sb.write(c);
    }
  }
  fields.add(sb.toString());
  return fields;
}

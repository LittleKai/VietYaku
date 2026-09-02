// Bù overlay VietPhrase cho các mục OnlineDict/AiDict đã lưu TRƯỚC khi app biết
// tự thêm chúng vào VietPhrase.
//
// Vì sao cần: từ được tra online/AI gần như luôn là từ VietPhrase chưa có (không
// có mới phải tra). Engine greedy longest-match vì thế cắt nó thành từng chữ,
// token sinh ra không bao giờ bằng key đã lưu, nên click lại không tra ra mục đã
// lưu. Thêm key vào overlay VietPhrase là engine cắt đúng cụm trở lại.
//
//   dart run tool/backfill_lookup_overlay.dart            # dry-run, chỉ báo cáo
//   dart run tool/backfill_lookup_overlay.dart --apply    # ghi thật
//
// Mặc định đọc/ghi `data/userdata/dictionaries`; truyền --dir=<path> để trỏ chỗ
// khác (VD thư mục `data/jp/generated` của phiên admin), --mode=japanese để chỉ
// xử lý một ngôn ngữ.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vietyaku/features/ai_translation/domain/ai_lookup_result.dart';
import 'package:vietyaku/features/translation/domain/dict_entry_filter.dart';

const _defaultDir = 'data/userdata/dictionaries';

void main(List<String> args) {
  final apply = args.contains('--apply');
  final dirArg = args.firstWhere(
    (a) => a.startsWith('--dir='),
    orElse: () => '',
  );
  final dir = dirArg.isEmpty ? _defaultDir : dirArg.substring('--dir='.length);
  final modeArg = args.firstWhere(
    (a) => a.startsWith('--mode='),
    orElse: () => '',
  );
  final only = modeArg.isEmpty ? '' : modeArg.substring('--mode='.length);

  for (final mode in ['japanese', 'chinese']) {
    if (only.isNotEmpty && only != mode) continue;
    _backfillMode(dir, mode, apply: apply);
  }

  if (!apply) {
    stdout.writeln('\n(dry-run — thêm --apply để ghi thật)');
  }
}

void _backfillMode(String dir, String mode, {required bool apply}) {
  final online = _readDict(p.join(dir, 'OnlineDict_$mode.txt'));
  final ai = _readDict(p.join(dir, 'AiDict_$mode.txt'));
  if (online.isEmpty && ai.isEmpty) return;

  final overlayFile = File(p.join(dir, 'VietPhrase_$mode.txt'));
  final existing = _readDict(overlayFile.path);

  final additions = <String, String>{};
  var skippedNotWord = 0;
  var skippedNoMeaning = 0;
  var skippedMismatch = 0;

  void consider(String key, String meaning) {
    if (existing.containsKey(key) || additions.containsKey(key)) return;
    if (!isWordLikeEntry(key)) {
      skippedNotWord++;
      return;
    }
    if (meaning.isEmpty) {
      skippedNoMeaning++;
      return;
    }
    additions[key] = meaning;
  }

  for (final entry in online.entries) {
    // Value OnlineDict là các mục `<<Nguồn>>` ghép lại, escape `\n`. Chỉ lấy
    // mục tiếng Việt, và nguồn online tra mờ nên nghĩa có thể thuộc về một
    // headword KHÁC — chỉ nhận khi headword trả về đúng bằng key đã lưu.
    final usable = _sections(_unescape(entry.value)).entries.where(
      (s) =>
          vietnameseLookupLabels.contains(s.key) &&
          meaningMatchesWord(entry.key, s.value),
    );
    if (usable.isEmpty) {
      skippedMismatch++;
      continue;
    }
    consider(entry.key, shortMeaningOf(usable.first.value));
  }
  for (final entry in ai.entries) {
    final body = _unescape(entry.value);
    final parsed = AiLookupResult.tryParse(entry.key, body);
    // Mục AI cũ lưu Markdown thô thì không rút được nghĩa ngắn tin cậy → bỏ.
    consider(entry.key, parsed?.shortMeaning ?? '');
  }

  stdout.writeln(
    '[$mode] online ${online.length} · ai ${ai.length} → '
    'thêm ${additions.length} mục vào VietPhrase_$mode.txt '
    '(bỏ $skippedNotWord vì là cả câu, $skippedMismatch vì nghĩa thuộc từ khác, '
    '$skippedNoMeaning vì không rút được nghĩa)',
  );
  for (final e in additions.entries.take(10)) {
    stdout.writeln('    + ${e.key} = ${e.value}');
  }
  if (additions.length > 10) {
    stdout.writeln('    … và ${additions.length - 10} mục nữa');
  }

  if (!apply || additions.isEmpty) return;

  final merged = {...existing, ...additions};
  final sb = StringBuffer('﻿');
  for (final e in merged.entries) {
    sb.write('${e.key}=${e.value}\r\n');
  }
  overlayFile.parent.createSync(recursive: true);
  overlayFile.writeAsStringSync(sb.toString());
  stdout.writeln('    → đã ghi ${overlayFile.path}');
}

Map<String, String> _readDict(String path) {
  final file = File(path);
  if (!file.existsSync()) return const {};
  var text = file.readAsStringSync();
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);

  final out = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.isEmpty) continue;
    final i = line.indexOf('=');
    if (i <= 0) continue;
    out[line.substring(0, i)] = line.substring(i + 1);
  }
  return out;
}

String _unescape(String value) =>
    value.replaceAll(r'\n', '\n').replaceAll(r'\t', '\t');

/// Tách value OnlineDict đã unescape thành `{nhãn nguồn: thân}`.
///
/// Bản rút gọn của `decodeOnlineSections` — tool là CLI Dart thuần nên không
/// import được lookup_controller (file đó kéo theo Flutter).
Map<String, String> _sections(String body) {
  final out = <String, String>{};
  String? label;
  final buffer = StringBuffer();

  void flush() {
    if (label == null) return;
    final text = buffer.toString().trim();
    if (text.isNotEmpty) out[label] = text;
    buffer.clear();
  }

  for (final line in body.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('<<') && trimmed.endsWith('>>')) {
      flush();
      label = trimmed.substring(2, trimmed.length - 2);
    } else if (label != null) {
      buffer.writeln(line);
    }
  }
  flush();
  return out;
}

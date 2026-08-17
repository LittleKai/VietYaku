import 'dart:convert';
import 'dart:io';

import 'package:vietyaku/features/translation/domain/vietphrase_value.dart';

const _defaultPaths = ['data/jp/VietPhrase.txt', 'data/cn/VietPhrase.txt'];

void main(List<String> arguments) {
  final mutableArguments = arguments.toList();
  final write = mutableArguments.remove('--write');
  final paths = mutableArguments.isEmpty ? _defaultPaths : mutableArguments;

  var totalChanged = 0;
  var filesMissingBom = 0;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('Không tìm thấy: $path');
      exitCode = 2;
      continue;
    }

    final originalBytes = file.readAsBytesSync();
    final hasBom = _hasUtf8Bom(originalBytes);
    final decoded = utf8.decode(originalBytes);
    final original = decoded.startsWith('\uFEFF') ? decoded : '\uFEFF$decoded';
    final result = normalizeVietPhraseDictionaryContent(original);
    totalChanged += result.changed;
    if (!hasBom) filesMissingBom++;
    stdout.writeln(
      '$path: ${result.changed}/${result.entries} entry cần chuẩn hóa'
      '${hasBom ? '' : ' · thiếu UTF-8 BOM'}',
    );

    if (write && (result.changed > 0 || !hasBom)) {
      _writeAndVerify(file, result.content);
      stdout.writeln('  Đã ghi và verify canonical: OK');
    }
  }

  if (!write && (totalChanged > 0 || filesMissingBom > 0)) {
    stdout.writeln('Dry-run: thêm --write để ghi thay đổi.');
  }
}

({String content, int entries, int changed})
normalizeVietPhraseDictionaryContent(String content) {
  final lines = content.split('\n');
  var entries = 0;
  var changed = 0;

  for (var i = 0; i < lines.length; i++) {
    final hasCr = lines[i].endsWith('\r');
    final line = hasCr ? lines[i].substring(0, lines[i].length - 1) : lines[i];
    final equals = line.indexOf('=');
    if (equals <= 0) continue;
    entries++;

    final value = line.substring(equals + 1);
    final normalized = normalizeVietPhraseValue(value);
    if (normalized == value) continue;
    changed++;
    lines[i] =
        '${line.substring(0, equals + 1)}$normalized${hasCr ? '\r' : ''}';
  }

  return (content: lines.join('\n'), entries: entries, changed: changed);
}

void _writeAndVerify(File file, String normalized) {
  if (normalized.isEmpty || normalized.codeUnitAt(0) != 0xFEFF) {
    throw StateError('Kết quả thiếu UTF-8 BOM: ${file.path}');
  }

  final secondPass = normalizeVietPhraseDictionaryContent(normalized);
  if (secondPass.changed != 0 || secondPass.content != normalized) {
    throw StateError('Kết quả chưa idempotent: ${file.path}');
  }

  final temp = File('${file.path}.vietyaku-normalize.tmp');
  final normalizedBytes = utf8.encode(normalized);
  temp.writeAsBytesSync(normalizedBytes, flush: true);
  final readBackBytes = temp.readAsBytesSync();
  if (!_hasUtf8Bom(readBackBytes) ||
      !_sameBytes(readBackBytes, normalizedBytes)) {
    temp.deleteSync();
    throw StateError('Verify file tạm thất bại: ${file.path}');
  }

  file.writeAsBytesSync(readBackBytes, flush: true);
  temp.deleteSync();
}

bool _hasUtf8Bom(List<int> bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xEF &&
    bytes[1] == 0xBB &&
    bytes[2] == 0xBF;

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

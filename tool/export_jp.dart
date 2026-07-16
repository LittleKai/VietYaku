// Xuất VietPhrase_JP.txt / LacViet_JP.txt cạnh file gốc từ CLI (không cần
// mở app) + verify: hết key hỏng, value nguyên vẹn, dịch thử Nhật/Trung.
//
// Chạy: dart run tool/export_jp.dart [thư mục QuickTranslator_Jap]

import 'dart:io';

import 'package:vietyaku/features/dictionary/data/dict_parser.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/repair/domain/jp_repair_pipeline.dart';
import 'package:vietyaku/features/repair/domain/simp2jp_table.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main(List<String> args) {
  final dir = args.isNotEmpty
      ? args.first
      : r'C:\Users\XEON\My Drive\JP CN Tool\QuickTranslator_Jap';

  final table = Simp2JpTable.parse(
    File('assets/mappings/simp2jp.tsv').readAsStringSync(),
    overridesTsv:
        File('assets/mappings/simp2jp_overrides.tsv').readAsStringSync(),
  );

  final engines = <String, TranslationEngine>{};
  for (final name in ['VietPhrase', 'LacViet']) {
    final src = File('$dir\\$name.txt');
    if (!src.existsSync()) {
      stderr.writeln('Không thấy ${src.path}');
      exitCode = 1;
      return;
    }
    final content = src.readAsStringSync();
    final sw = Stopwatch()..start();
    final result = repairFile(content, table, RepairPolicy.addVariant);
    final out = File('$dir\\${name}_JP.txt')
      ..writeAsStringSync('﻿${result.content}');
    stdout.writeln('$name: ${sw.elapsedMilliseconds}ms → ${out.path}');
    stdout.writeln('  ${result.report}');

    // Verify: hết key hỏng + value nguyên vẹn.
    final original = parseEntries(content);
    final repaired = parseEntries(result.content);
    final brokenKeys = repaired.keys
        .where((k) => k.contains('覚 悟') || (containsKana(k) && k.contains('军')))
        .toList();
    if (brokenKeys.isNotEmpty) {
      stderr.writeln('  LỖI: còn key hỏng: ${brokenKeys.take(5)}');
      exitCode = 1;
    }
    final originalValues = original.values.toSet();
    final mutated =
        repaired.entries.where((e) => !originalValues.contains(e.value));
    if (mutated.isNotEmpty) {
      stderr.writeln('  LỖI: value bị biến đổi: ${mutated.take(3)}');
      exitCode = 1;
    }
    stdout.writeln('  verify OK: key sạch, value nguyên vẹn '
        '(${repaired.length} entries)');

    engines[name] = TranslationEngine(dicts: [
      parseDictionary(result.content, DictType.vietPhrase),
    ]);
  }

  final phienAm = parseDictionary(
      File('$dir\\ChinesePhienAmWords.txt').readAsStringSync(),
      DictType.chinesePhienAm);
  final engine = TranslationEngine(
    dicts: engines['VietPhrase']!.dicts,
    hanVietFallback: phienAm,
  );

  String render(String text, TranslationMode mode) => engine
      .translate(text, mode: mode)
      .map((t) => t.display)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  stdout.writeln('\nDịch thử tiếng Nhật:');
  stdout.writeln('  骸骨騎士様は覚悟を決めて異世界へ出掛けた');
  stdout.writeln('  → ${render('骸骨騎士様は覚悟を決めて異世界へ出掛けた', TranslationMode.japanese)}');
  stdout.writeln('Dịch thử tiếng Trung:');
  stdout.writeln('  第一次翻译这本小说');
  stdout.writeln('  → ${render('第一次翻译这本小说', TranslationMode.chinese)}');
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/data/dict_parser.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/repair/domain/jp_repair_pipeline.dart';
import 'package:vietyaku/features/repair/domain/simp2jp_table.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

const sourceDir = r'C:\Users\XEON\My Drive\JP CN Tool\QuickTranslator_Jap';

void main() {
  final vietPhraseFile = File('$sourceDir\\VietPhrase.txt');
  final lacVietFile = File('$sourceDir\\LacViet.txt');
  final available = vietPhraseFile.existsSync() && lacVietFile.existsSync();

  late Simp2JpTable table;
  setUpAll(() {
    table = Simp2JpTable.parse(
      File('assets/mappings/simp2jp.tsv').readAsStringSync(),
      overridesTsv: File(
        'assets/mappings/simp2jp_overrides.tsv',
      ).readAsStringSync(),
    );
  });

  group('repair trên dữ liệu thật', () {
    test(
      'LacViet.txt: hết key kana bị chèn space, value nguyên vẹn',
      () async {
        final content = await lacVietFile.readAsString();
        final sw = Stopwatch()..start();
        final result = repairFile(content, table, RepairPolicy.addVariant);
        sw.stop();
        // ignore: avoid_print
        print(
          'LacViet repair: ${sw.elapsedMilliseconds}ms — '
          '${result.report}',
        );

        final repaired = parseEntries(result.content);
        // Các key hỏng nguyên văn phải được sửa đúng.
        expect(repaired.containsKey('覚悟'), isTrue);
        expect(repaired.containsKey('覚 悟'), isFalse);
        expect(repaired.containsKey('持ち歩'), isTrue);
        expect(repaired.containsKey('目を奪'), isTrue);
        // Value của key sửa xong = value gốc, không đổi 1 byte.
        final original = parseEntries(content);
        expect(repaired['覚悟'], original['覚 悟']);
        expect(repaired['翻译'], original['翻译']);

        // VALUE KHÔNG ĐỔI 1 BYTE: mọi value trong output phải tồn tại
        // nguyên văn trong file gốc. (Key trùng sau repair có thể đổi value
        // gán cho key đó — giữ dòng đầu theo thứ tự file, log conflict —
        // nhưng bản thân value không bao giờ bị biến đổi.)
        final originalValues = original.values.toSet();
        for (final entry in repaired.entries) {
          expect(
            originalValues.contains(entry.value),
            isTrue,
            reason: 'value lạ (bị biến đổi) ở key ${entry.key}',
          );
        }
      },
      skip: available ? false : 'thiếu dữ liệu thật',
    );

    test(
      'VietPhrase.txt: repair + nạp lại → match dài hơn',
      () async {
        final content = await vietPhraseFile.readAsString();
        final result = repairFile(content, table, RepairPolicy.addVariant);
        // ignore: avoid_print
        print('VietPhrase repair: ${result.report}');

        final before = parseDictionary(content, DictType.vietPhrase);
        final after = parseDictionary(result.content, DictType.vietPhrase);

        final engineBefore = TranslationEngine(dicts: [before]);
        final engineAfter = TranslationEngine(dicts: [after]);

        const passage = 'ワイトの率いるスケルトン軍団が現れ、骸骨騎士様は覚悟を決めた。';
        int matchedUnits(List<Token> tokens) => tokens
            .where((t) => t.kind == TokenKind.matched)
            .fold(0, (sum, t) => sum + t.source.length);

        final unitsBefore = matchedUnits(engineBefore.translate(passage));
        final unitsAfter = matchedUnits(engineAfter.translate(passage));
        // ignore: avoid_print
        print(
          'matched units: before=$unitsBefore after=$unitsAfter '
          '(entries ${before.length} → ${after.length})',
        );
        expect(unitsAfter, greaterThan(unitsBefore));
      },
      skip: available ? false : 'thiếu dữ liệu thật',
    );
  });
}

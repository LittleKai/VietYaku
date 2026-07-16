import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/data/dict_parser.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_loader.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

const sourceDir = r'C:\Users\XEON\My Drive\JP CN Tool\QuickTranslator_Jap';

void main() {
  final vietPhraseFile = File('$sourceDir\\VietPhrase.txt');
  final namesFile = File('$sourceDir\\Names.txt');
  final phienAmFile = File('$sourceDir\\ChinesePhienAmWords.txt');

  final available = vietPhraseFile.existsSync() &&
      namesFile.existsSync() &&
      phienAmFile.existsSync();

  group('real data integration', () {
    test('parses real dictionaries and translates a Japanese passage',
        () async {
      final sw = Stopwatch()..start();
      final vietPhrase = parseDictionary(
          await vietPhraseFile.readAsString(), DictType.vietPhrase);
      final names =
          parseDictionary(await namesFile.readAsString(), DictType.names);
      final phienAm = parseDictionary(
          await phienAmFile.readAsString(), DictType.chinesePhienAm);
      sw.stop();

      expect(vietPhrase.length, greaterThan(100000));
      expect(names.length, greaterThan(1000));
      expect(phienAm.length, greaterThan(10000));

      final engine = TranslationEngine(
        dicts: [names, vietPhrase],
        hanVietFallback: phienAm,
      );
      final tokens = engine.translate('第一の目標は覚悟を決めることだ。');
      expect(tokens, isNotEmpty);
      // Toàn bộ source ghép lại phải bằng input (không mất ký tự).
      expect(tokens.map((t) => t.source).join(), '第一の目標は覚悟を決めることだ。');
      // Có ít nhất một token match từ điển thật.
      expect(tokens.any((t) => t.kind == TokenKind.matched), isTrue);

      // ignore: avoid_print
      print('parse 3 dicts: ${sw.elapsedMilliseconds}ms; '
          'vietPhrase=${vietPhrase.length} names=${names.length} '
          'phienAm=${phienAm.length}');
    }, skip: available ? false : 'QuickTranslator_Jap data not found');

    test('translate 10k characters in under 200ms', () async {
      final vietPhrase = parseDictionary(
          await vietPhraseFile.readAsString(), DictType.vietPhrase);
      final names =
          parseDictionary(await namesFile.readAsString(), DictType.names);
      final phienAm = parseDictionary(
          await phienAmFile.readAsString(), DictType.chinesePhienAm);
      final engine = TranslationEngine(
        dicts: [names, vietPhrase],
        hanVietFallback: phienAm,
      );

      const passage = '骸骨騎士様は覇権を握る覚悟を決めて、異世界へ出掛けた。'
          '第一の目標は仲間を集めることだ。ワイトの率いるスケルトン軍団が現れた。\n';
      final buffer = StringBuffer();
      while (buffer.length < 10000) {
        buffer.write(passage);
      }
      final text = buffer.toString();

      engine.translate(text); // warm-up JIT
      final sw = Stopwatch()..start();
      final tokens = engine.translate(text);
      sw.stop();

      expect(tokens, isNotEmpty);
      // ignore: avoid_print
      print('translate ${text.length} chars: ${sw.elapsedMilliseconds}ms, '
          '${tokens.length} tokens');
      expect(sw.elapsedMilliseconds, lessThan(200));
    }, skip: available ? false : 'QuickTranslator_Jap data not found');

    test('.vydc cache: cold parse vs warm load on all 5 real files', () {
      final temp = Directory.systemTemp.createTempSync('vydc_real');
      addTearDown(() => temp.deleteSync(recursive: true));

      const files = <DictType, String>{
        DictType.vietPhrase: 'VietPhrase.txt',
        DictType.lacViet: 'LacViet.txt',
        DictType.names: 'Names.txt',
        DictType.chinesePhienAm: 'ChinesePhienAmWords.txt',
        DictType.pronouns: 'Pronouns.txt',
      };

      var coldTotal = 0;
      var warmTotal = 0;
      for (final entry in files.entries) {
        final src = '$sourceDir\\${entry.value}';
        final cache = '${temp.path}\\${entry.key.name}.vydc';

        final cold = loadDictionarySync(
            sourcePath: src, cachePath: cache, type: entry.key);
        final warm = loadDictionarySync(
            sourcePath: src, cachePath: cache, type: entry.key);

        expect(cold.fromCache, isFalse);
        expect(warm.fromCache, isTrue);
        expect(warm.dictionary.length, cold.dictionary.length);
        coldTotal += cold.elapsedMs;
        warmTotal += warm.elapsedMs;
        // ignore: avoid_print
        print('${entry.value}: cold=${cold.elapsedMs}ms '
            'warm=${warm.elapsedMs}ms entries=${cold.dictionary.length}');
      }
      // ignore: avoid_print
      print('TOTAL cold=${coldTotal}ms warm=${warmTotal}ms');
    }, skip: available ? false : 'QuickTranslator_Jap data not found');
  });
}

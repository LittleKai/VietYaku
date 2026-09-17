import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';
import 'package:vietyaku/features/translation/domain/trad2simp_table.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

LoadedDictionaries _createTestDicts({
  Map<String, String>? lacViet,
  Map<String, String>? jaVi,
  Map<String, String>? mazii,
  Map<String, String>? cedict,
  Map<String, String>? sudachiReadings,
}) {
  final empty = PhraseDictionary(DictType.vietPhrase, const {});
  return LoadedDictionaries(
    userDict: empty,
    names: empty,
    vietPhrase: empty,
    lacViet: lacViet != null
        ? PhraseDictionary(DictType.lacViet, lacViet)
        : empty,
    mazii: mazii != null
        ? PhraseDictionary(DictType.mazii, mazii)
        : empty,
    chinesePhienAm: empty,
    pronouns: empty,
    babylon: empty,
    thieuChuu: empty,
    cedict: cedict != null
        ? PhraseDictionary(DictType.cedict, cedict)
        : empty,
    chinesePhienAmEnglish: empty,
    jaVi: jaVi != null
        ? PhraseDictionary(DictType.jaVi, jaVi)
        : empty,
    zhVi: empty,
    sudachiReadings: sudachiReadings != null
        ? PhraseDictionary(DictType.jaVi, sudachiReadings)
        : empty,
    searchLayers: const [],
    stats: const {},
  );
}

void main() {
  group('entryPronunciationOf - Japanese mode', () {
    test('ưu tiên Sudachi khi sudachiMode là sudachiFirst', () {
      final dicts = _createTestDicts(
        sudachiReadings: {'学校': 'がっこう'},
        jaVi: {'学校': '{がっこう}\\n\\t trường học'},
      );
      final reading = entryPronunciationOf(
        dicts,
        '学校',
        TranslationMode.japanese,
        sudachiMode: SudachiReadingsMode.sudachiFirst,
      );
      expect(reading, 'がっこう');
    });

    test('bỏ qua Sudachi khi sudachiMode là disabled và fallback sang JaVi', () {
      final dicts = _createTestDicts(
        sudachiReadings: {'学校': 'がっこう_sudachi'},
        jaVi: {'学校': '{がっこう}\\n\\t trường học'},
      );
      final reading = entryPronunciationOf(
        dicts,
        '学校',
        TranslationMode.japanese,
        sudachiMode: SudachiReadingsMode.disabled,
      );
      expect(reading, 'がっこう');
    });

    test('fallback sang LacViet (romaji/reading) khi JaVi không có', () {
      final dicts = _createTestDicts(
        lacViet: {'猫': '(neko) con mèo'},
      );
      final reading = entryPronunciationOf(
        dicts,
        '猫',
        TranslationMode.japanese,
        sudachiMode: SudachiReadingsMode.sudachiFirst,
      );
      expect(reading, 'neko');
    });

    test('fallback sang Mazii khi JaVi và LacViet không có', () {
      final dicts = _createTestDicts(
        mazii: {'桜': '「さくら」\\n\\t hoa anh đào'},
      );
      final reading = entryPronunciationOf(
        dicts,
        '桜',
        TranslationMode.japanese,
        sudachiMode: SudachiReadingsMode.sudachiFirst,
      );
      expect(reading, 'さくら');
    });

    test('chuỗi thuần kana tự trả về chính nó khi từ điển không có', () {
      final dicts = _createTestDicts();
      final reading = entryPronunciationOf(
        dicts,
        'ありがとう',
        TranslationMode.japanese,
      );
      expect(reading, 'ありがとう');

      final katakana = entryPronunciationOf(
        dicts,
        'コーヒー',
        TranslationMode.japanese,
      );
      expect(katakana, 'コーヒー');
    });

    test('kanji không có trong từ điển trả về null', () {
      final dicts = _createTestDicts();
      final reading = entryPronunciationOf(
        dicts,
        '未知漢字',
        TranslationMode.japanese,
      );
      expect(reading, isNull);
    });
  });

  group('entryPronunciationOf - Chinese mode', () {
    test('lấy phrase reading từ LacViet', () {
      final dicts = _createTestDicts(
        lacViet: {'中国': '[zhōng guó]\\n\\t nước Trung Quốc'},
      );
      final reading = entryPronunciationOf(
        dicts,
        '中国',
        TranslationMode.chinese,
      );
      expect(reading, 'zhōng guó');
    });

    test('ghép phát âm từ từng chữ khi cả cụm không có trong từ điển', () {
      final dicts = _createTestDicts(
        lacViet: {
          '美': '[měi]\\n\\t đẹp',
          '丽': '[lì]\\n\\t đẹp',
        },
      );
      final reading = entryPronunciationOf(
        dicts,
        '美丽',
        TranslationMode.chinese,
      );
      expect(reading, 'měi lì');
    });

    test('hiển thị phrase reading và ghép char reading nếu khác nhau', () {
      final dicts = _createTestDicts(
        lacViet: {
          '重大': '[zhòngdà]\\n\\t trọng đại',
          '重': '[chóng]\\n\\t trùng, lặp',
          '大': '[dà]\\n\\t to lớn',
        },
      );
      final reading = entryPronunciationOf(
        dicts,
        '重大',
        TranslationMode.chinese,
      );
      expect(reading, 'zhòngdà (ghép: chóng dà)');
    });

    test('chỉ hiển thị phrase reading nếu ghép char reading giống nhau', () {
      final dicts = _createTestDicts(
        lacViet: {
          '中国': '[zhōng guó]\\n\\t nước Trung Quốc',
          '中': '[zhōng]\\n\\t giữa, trung',
          '国': '[guó]\\n\\t nước, quốc',
        },
      );
      final reading = entryPronunciationOf(
        dicts,
        '中国',
        TranslationMode.chinese,
      );
      expect(reading, 'zhōng guó');
    });

    test('cụm có quá nhiều từ (> 10 chữ) thì bỏ qua ghép từng chữ', () {
      const longPhrase = '一二三四五六七八九十一';
      final dicts = _createTestDicts(
        lacViet: {
          '一': '[yī]',
          '二': '[èr]',
          '三': '[sān]',
          '四': '[sì]',
          '五': '[wǔ]',
          '六': '[liù]',
          '七': '[qī]',
          '八': '[bā]',
          '九': '[jiǔ]',
          '十': '[shí]',
        },
      );
      final reading = entryPronunciationOf(
        dicts,
        longPhrase,
        TranslationMode.chinese,
      );
      expect(reading, isNull);
    });

    test('cụm 10 chữ trở xuống vẫn được ghép từ từng chữ', () {
      const tenCharPhrase = '一二三四五六七八九十';
      final dicts = _createTestDicts(
        lacViet: {
          '一': '[yī]',
          '二': '[èr]',
          '三': '[sān]',
          '四': '[sì]',
          '五': '[wǔ]',
          '六': '[liù]',
          '七': '[qī]',
          '八': '[bā]',
          '九': '[jiǔ]',
          '十': '[shí]',
        },
      );
      final reading = entryPronunciationOf(
        dicts,
        tenCharPhrase,
        TranslationMode.chinese,
      );
      expect(reading, 'yī èr sān sì wǔ liù qī bā jiǔ shí');
    });

    test('hỗ trợ chuyển đổi phồn thể sang giản thể qua trad2simp', () {
      final dicts = _createTestDicts(
        lacViet: {
          '美丽': '[měi lì]\\n\\t đẹp',
          '美': '[měi]',
          '丽': '[lì]',
        },
      );
      final trad2simp = Trad2SimpTable.parse('麗\t丽');
      final reading = entryPronunciationOf(
        dicts,
        '美麗',
        TranslationMode.chinese,
        trad2simp: trad2simp,
      );
      expect(reading, 'měi lì');
    });
  });
}

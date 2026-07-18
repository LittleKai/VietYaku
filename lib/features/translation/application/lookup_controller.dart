import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cjk.dart';
import '../../../core/google_translate.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/data/dictionary_repository.dart';
import '../data/mazii_api.dart';
import '../domain/reading_extractor.dart';
import '../domain/translation_engine.dart';
import 'translation_controller.dart';

final maziiApiProvider = Provider<MaziiApi>((ref) => MaziiApi());
final googleTranslateProvider = Provider<GoogleTranslateClient>(
  (ref) => GoogleTranslateClient(),
);

/// Một mục trong ô Nghĩa: `từ <<Từ điển>> nội dung` kiểu QuickTranslator.
class LookupSection {
  final String word;
  final String label;
  final String body;

  const LookupSection(this.word, this.label, this.body);

  /// Body 1 dòng → cùng dòng header; nhiều dòng → xuống dòng.
  String get displayText => body.contains('\n')
      ? '$word <<$label>>\n$body'
      : '$word <<$label>> $body';
}

class LookupResult {
  /// Từ được yêu cầu tra (cụm được chọn).
  final String word;

  /// Key thực sự match trong LacViet (có thể là prefix của [word]).
  final String? matchedKey;
  final String? reading;
  final ReadingKind? readingKind;

  /// Âm Hán Việt (chỉ khi [word] là 1 chữ Hán đơn).
  final String? hanViet;

  /// Nội dung LacViet đã unescape \n\t. Null nếu không tìm thấy.
  final String? body;

  /// Các mục đa từ điển hiển thị trong ô Nghĩa (VietPhrase/LacViet/Cedict…).
  final List<LookupSection> sections;

  const LookupResult({
    required this.word,
    this.matchedKey,
    this.reading,
    this.readingKind,
    this.hanViet,
    this.body,
    this.sections = const [],
  });

  bool get found => body != null || sections.isNotEmpty;

  LookupResult withExtraSection(LookupSection section) => LookupResult(
    word: word,
    matchedKey: matchedKey,
    reading: reading,
    readingKind: readingKind,
    hanViet: hanViet,
    body: body,
    sections: [...sections, section],
  );
}

class LookupController extends Notifier<LookupResult?> {
  @override
  LookupResult? build() => null;

  /// Tra đa từ điển cho [word]; [sentence] là đoạn nguồn quanh vị trí chọn
  /// (dùng cho mục Phiên Âm).
  void lookup(String word, {String sentence = ''}) {
    final dicts = ref.read(dictionariesProvider).valueOrNull;
    if (dicts == null || word.isEmpty) return;
    final mode = ref.read(currentModeProvider);

    final sections = <LookupSection>[];
    final firstChar = word.substring(0, runeLengthAt(word, 0));

    // Nhật Việt tra sẵn: dùng cho vị trí hiển thị + fallback phát âm.
    final jaVi = dicts.jaVi.entries[word] ?? dicts.jaVi.entries[firstChar];
    final jaViKey = dicts.jaVi.entries.containsKey(word) ? word : firstChar;

    // Thứ tự hiển thị: VietPhrase → Lạc Việt → (Nhật) Nhật Việt →
    // Cedict/Babylon → Thiều Chửu → Trung Việt/(Trung) Nhật Việt → Phiên Âm.

    // 0. VietPhrase (UserDict/Names/VietPhrase) — lên trước Lạc Việt.
    void addPhraseSection(String w) {
      final hit = _phraseValue(dicts, w);
      if (hit != null) {
        sections.add(LookupSection(w, hit.label, _joinMeanings(hit.value)));
      }
    }

    addPhraseSection(word);
    if (firstChar != word) addPhraseSection(firstChar);

    // 1. Lạc Việt: exact trước, miss thì prefix ngắn dần (theo rune).
    String? matchedKey;
    String? lacVietValue;
    var end = word.length;
    while (end > 0) {
      final candidate = word.substring(0, end);
      final v = dicts.lacViet.entries[candidate];
      if (v != null) {
        matchedKey = candidate;
        lacVietValue = v;
        break;
      }
      end -= 1;
      if (end > 0) {
        final unit = word.codeUnitAt(end);
        if (unit >= 0xDC00 && unit <= 0xDFFF) end -= 1;
      }
    }
    if (lacVietValue != null) {
      sections.add(
        LookupSection(matchedKey!, 'Lạc Việt', unescapeLacViet(lacVietValue)),
      );
    }

    // 1b. Nhật Việt ngay sau Lạc Việt (chỉ mode Nhật).
    if (mode == TranslationMode.japanese && jaVi != null) {
      sections.add(LookupSection(jaViKey, 'Nhật Việt', unescapeLacViet(jaVi)));
    }

    // 2. Cedict (ưu tiên) / Babylon cho cụm và chữ đầu.
    void addCedictBabylon(String w) {
      final cedict = dicts.cedict.entries[w];
      if (cedict != null) {
        sections.add(LookupSection(w, 'Cedict', cedict));
        return;
      }
      final babylon = dicts.babylon.entries[w];
      if (babylon != null) {
        sections.add(LookupSection(w, 'Babylon', babylon));
      }
    }

    addCedictBabylon(word);
    if (firstChar != word) addCedictBabylon(firstChar);

    // 3. Thiều Chửu: cụm, miss thì chữ đầu.
    final thieuChuu =
        dicts.thieuChuu.entries[word] ?? dicts.thieuChuu.entries[firstChar];
    if (thieuChuu != null) {
      final key = dicts.thieuChuu.entries.containsKey(word) ? word : firstChar;
      sections.add(
        LookupSection(key, 'Thiều Chửu', unescapeLacViet(thieuChuu)),
      );
    }

    // 5. Nhật Việt (mode khác Nhật) / Trung Việt (StarDict từ VocabFlip).
    if (mode != TranslationMode.japanese && jaVi != null) {
      sections.add(LookupSection(jaViKey, 'Nhật Việt', unescapeLacViet(jaVi)));
    }
    final zhVi = dicts.zhVi.entries[word] ?? dicts.zhVi.entries[firstChar];
    if (zhVi != null) {
      final key = dicts.zhVi.entries.containsKey(word) ? word : firstChar;
      sections.add(LookupSection(key, 'Trung Việt', unescapeLacViet(zhVi)));
    }

    // 6. Phiên âm Hán Việt đoạn nguồn quanh vị trí chọn.
    if (sentence.isNotEmpty) {
      final phienAm = _phienAm(dicts, sentence);
      if (phienAm.isNotEmpty) {
        sections.add(LookupSection(sentence, 'Phiên Âm English', phienAm));
      }
    }

    String? hanViet;
    if (word.length == runeLengthAt(word, 0) &&
        isHanCodePoint(codePointAt(word, 0))) {
      final v = dicts.chinesePhienAm.entries[word];
      if (v != null) hanViet = v.split('/').first.trim();
    }

    // Phát âm: mode Nhật → ưu tiên kana `{...}` từ Nhật Việt; mode khác →
    // LacViet trước, kana Nhật Việt là fallback.
    ({String text, ReadingKind kind})? reading;
    if (mode == TranslationMode.japanese) {
      reading = jaVi == null ? null : extractKanaReading(jaVi);
      reading ??= lacVietValue == null ? null : extractReading(lacVietValue);
    } else {
      reading = lacVietValue == null ? null : extractReading(lacVietValue);
      reading ??= jaVi == null ? null : extractKanaReading(jaVi);
    }
    state = LookupResult(
      word: word,
      matchedKey: matchedKey,
      reading: reading?.text,
      readingKind: reading?.kind,
      hanViet: hanViet,
      body: lacVietValue == null ? null : unescapeLacViet(lacVietValue),
      sections: sections,
    );
  }

  void clearResult() => state = null;

  /// Tra thêm nghĩa online cho từ đang hiển thị: Nhật → Mazii (miss thì
  /// Google Dịch), Trung → Google Dịch. Trả false khi không lấy được.
  Future<bool> fetchOnlineMeaning() async {
    final r = state;
    if (r == null || r.word.isEmpty) return false;
    final mode = ref.read(currentModeProvider);

    String label;
    String? body;
    if (mode == TranslationMode.japanese) {
      label = 'Mazii';
      body = await ref.read(maziiApiProvider).lookup(r.word);
      if (body == null) {
        label = 'Google Dịch';
        body = await ref
            .read(googleTranslateProvider)
            .translate(r.word, sourceLang: 'ja');
      }
    } else {
      label = 'Google Dịch';
      body = await ref
          .read(googleTranslateProvider)
          .translate(r.word, sourceLang: 'zh-CN');
    }
    if (body == null) return false;
    // Người dùng đã tra từ khác trong lúc chờ mạng → bỏ kết quả cũ.
    if (state?.word != r.word) return false;
    state = state!.withExtraSection(LookupSection(r.word, label, body));
    return true;
  }

  /// Value cụm trong UserDict > Names > VietPhrase kèm nhãn từ điển.
  static ({String label, String value})? _phraseValue(
    LoadedDictionaries dicts,
    String w,
  ) {
    final user = dicts.userDict.entries[w];
    if (user != null) return (label: 'UserDict', value: user);
    final name = dicts.names.entries[w];
    if (name != null) return (label: 'Names', value: name);
    final vp = dicts.vietPhrase.entries[w];
    if (vp != null) return (label: 'VietPhrase', value: vp);
    return null;
  }

  /// `nghĩa1/nghĩa2` → `nghĩa1; nghĩa2`.
  static String _joinMeanings(String value) => value
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join('; ');

  /// Phiên âm từng chữ Hán: ChinesePhienAmWords → Hán Việt;
  /// miss → ChinesePhienAmEnglishWords trong `[]`; khác giữ nguyên.
  static String _phienAm(LoadedDictionaries dicts, String text) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final len = runeLengthAt(text, i);
      final ch = text.substring(i, i + len);
      if (isHanCodePoint(codePointAt(text, i))) {
        final hanViet = dicts.chinesePhienAm.entries[ch];
        final english = dicts.chinesePhienAmEnglish.entries[ch];
        if (buffer.isNotEmpty) buffer.write(' ');
        if (hanViet != null) {
          buffer.write(hanViet.split('/').first.trim());
        } else if (english != null && english.trim().isNotEmpty) {
          buffer.write('[${english.trim().split(' ').first}]');
        } else {
          buffer.write(ch);
        }
      } else {
        buffer.write(ch);
      }
      i += len;
    }
    return buffer.toString();
  }
}

final lookupControllerProvider =
    NotifierProvider<LookupController, LookupResult?>(LookupController.new);

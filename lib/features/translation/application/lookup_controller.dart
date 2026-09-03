import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cjk.dart';
import '../../../core/google_translate.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/data/dictionary_repository.dart';
import '../../settings/settings_provider.dart';
import '../data/jisho_api.dart';
import '../data/mazii_api.dart';
import '../data/weblio_api.dart';
import '../data/youdao_api.dart';
import '../domain/reading_extractor.dart';
import '../domain/lookup_dictionary_type.dart';
import '../domain/trad2simp_table.dart';
import '../domain/translation_engine.dart';
import '../domain/vietphrase_value.dart';
import 'trad2simp_provider.dart';
import 'translation_controller.dart';

/// Key thật sự dùng để tra/lưu từ điển cho [rawWord] người dùng bôi đen: mode
/// Trung có bật quy đổi thì phải về giản thể trước, y như `lookup()` làm, nếu
/// không sẽ so nhầm với key đã lưu trong OnlineDict/AiDict.
String lookupKeyOf(WidgetRef ref, String rawWord) {
  if (ref.read(currentModeProvider) != TranslationMode.chinese) return rawWord;
  if (!ref.read(settingsProvider).convertTraditionalToSimplified) {
    return rawWord;
  }
  final table =
      ref.read(trad2SimpTableProvider).valueOrNull ?? Trad2SimpTable.empty;
  return table.convert(rawWord);
}

final maziiApiProvider = Provider<MaziiApi>((ref) => MaziiApi());
final jishoApiProvider = Provider<JishoApi>((ref) => JishoApi());
final weblioApiProvider = Provider<WeblioApi>((ref) => WeblioApi());
final youdaoApiProvider = Provider<YoudaoApi>((ref) => YoudaoApi());
final googleTranslateProvider = Provider<GoogleTranslateClient>(
  (ref) => GoogleTranslateClient(),
);

/// Một mục trong ô Nghĩa: `từ <<Từ điển>> nội dung` kiểu QuickTranslator.
class LookupSection {
  final String word;
  final String label;
  final String body;

  const LookupSection(this.word, this.label, this.body);

  LookupDictionaryType? get dictionaryType {
    for (final type in LookupDictionaryType.values) {
      if (type.matchesLabel(label)) return type;
    }
    return null;
  }

  /// Body 1 dòng → cùng dòng header; nhiều dòng → xuống dòng.
  String get displayText => body.contains('\n')
      ? '$word <<$label>>\n$body'
      : '$word <<$label>> $body';
}

final _onlineLabelPattern = RegExp(r'^<<(.+)>>$');

/// Ghép các mục tra online thành 1 dòng value dict: mỗi mục mở đầu bằng
/// `<<Nguồn>>`, xuống dòng escape `\n` như LacViet.
String encodeOnlineSections(List<LookupSection> sections) => sections
    .map((s) => '<<${s.label}>>\n${s.body.trim()}')
    .join('\n')
    .replaceAll('\r\n', '\n')
    .replaceAll('\n', r'\n')
    .replaceAll('\t', r'\t');

/// Tách value OnlineDict ngược lại thành các mục theo nhãn `<<Nguồn>>`.
List<LookupSection> decodeOnlineSections(String word, String value) {
  final sections = <LookupSection>[];
  final body = StringBuffer();
  String? label;

  void flush() {
    if (label == null) return;
    final text = body.toString().trim();
    if (text.isNotEmpty) sections.add(LookupSection(word, label, text));
    body.clear();
  }

  for (final line in unescapeLacViet(value).split('\n')) {
    final match = _onlineLabelPattern.firstMatch(line.trim());
    if (match != null) {
      flush();
      label = match.group(1);
    } else if (label != null) {
      body.writeln(line);
    }
  }
  flush();
  return sections;
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
}

class LookupController extends Notifier<LookupResult?> {
  /// Tham số của lần `lookup()` gần nhất, để [refreshCurrent] tra lại y hệt.
  String _lastRawWord = '';
  String _lastRawSentence = '';

  /// Các mục chèn thêm bằng [addOnlineSections] cho từ đang hiển thị.
  ///
  /// [refreshCurrent] chỉ được phép ghép lại mục từ danh sách NÀY, không phải
  /// mọi mục cũ đang hiển: mục do `lookup()` sinh ra mà tra lại không còn
  /// (vừa xóa khỏi từ điển) phải biến mất thật.
  final List<LookupSection> _sessionSections = [];

  @override
  LookupResult? build() => null;

  /// Tra đa từ điển cho [word]; [sentence] là đoạn nguồn quanh vị trí chọn
  /// (dùng cho mục Phiên Âm).
  void lookup(String rawWord, {String rawSentence = ''}) {
    final result = _buildResult(rawWord, rawSentence);
    if (result == null) return;
    _lastRawWord = rawWord;
    _lastRawSentence = rawSentence;
    _sessionSections.clear();
    state = result;
  }

  LookupResult? _buildResult(String rawWord, String rawSentence) {
    final dicts = ref.read(dictionariesProvider).valueOrNull;
    if (dicts == null || rawWord.isEmpty) return null;
    final mode = ref.read(currentModeProvider);

    // Mode Trung: quy phồn→giản trước khi tra, y như lúc dịch cả văn bản. Chọn
    // chữ trong ô Nguồn (vẫn là bản gốc phồn thể) thì mới tra trúng key dict.
    final trad2Simp =
        mode == TranslationMode.chinese &&
            ref.read(settingsProvider).convertTraditionalToSimplified
        ? trad2SimpOf(ref)
        : Trad2SimpTable.empty;
    final word = trad2Simp.convert(rawWord);
    final sentence = trad2Simp.convert(rawSentence);

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

    // 1a. Mazii (offline) — ngay sau Lạc Việt: exact trước, miss thì chữ đầu.
    final mazii = dicts.mazii.entries[word] ?? dicts.mazii.entries[firstChar];
    if (mazii != null) {
      final key = dicts.mazii.entries.containsKey(word) ? word : firstChar;
      sections.add(LookupSection(key, 'Mazii', unescapeLacViet(mazii)));
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

    // 5a. Kết quả tra online đã lưu (OnlineDict_<mode>.txt) — chỉ khớp đúng cụm.
    final online = dicts.onlineDict.entries[word];
    if (online != null) {
      sections.addAll(decodeOnlineSections(word, online));
    }

    // 5b. Kết quả tra AI đã lưu (AiDict_<mode>.txt) — chỉ khớp đúng cụm.
    final ai = dicts.aiDict.entries[word];
    if (ai != null) {
      sections.addAll(decodeOnlineSections(word, ai));
    }

    // 5c. Từ/cụm con AI đã tách (AiEntries_<mode>.txt): tra được như một mục
    // từ điển bình thường chứ không chỉ nằm im phục vụ engine dịch.
    final aiEntry = dicts.aiEntries.entries[word];
    if (aiEntry != null) {
      sections.add(
        LookupSection(word, 'AI tách từ', _joinMeanings(aiEntry)),
      );
    }

    // 6. Phiên âm Hán Việt đoạn nguồn quanh vị trí chọn.
    if (sentence.isNotEmpty) {
      final phienAm = _phienAm(dicts, sentence);
      if (phienAm.isNotEmpty) {
        sections.add(LookupSection(sentence, 'Phiên Âm English', phienAm));
      }
    }

    final hanViet = hanVietReadingOf(dicts, word);

    // Phát âm: mode Nhật → ưu tiên theo cài đặt sudachiReadings; mode khác →
    // LacViet trước, kana Nhật Việt là fallback.
    ({String text, ReadingKind kind})? reading;
    if (mode == TranslationMode.japanese) {
      final sReadings = ref.read(settingsProvider).sudachiReadings;
      if (sReadings == SudachiReadingsMode.sudachiFirst) {
        final sudachi = dicts.sudachiReadings.entries[word];
        if (sudachi != null) {
          reading = (text: sudachi, kind: ReadingKind.kana);
        }
        reading ??= jaVi == null ? null : extractKanaReading(jaVi);
        reading ??= lacVietValue == null ? null : extractReading(lacVietValue);
      } else if (sReadings == SudachiReadingsMode.jaViFirst) {
        reading = jaVi == null ? null : extractKanaReading(jaVi);
        if (reading == null) {
          final sudachi = dicts.sudachiReadings.entries[word];
          if (sudachi != null) {
            reading = (text: sudachi, kind: ReadingKind.kana);
          }
        }
        reading ??= lacVietValue == null ? null : extractReading(lacVietValue);
      } else {
        // SudachiReadingsMode.disabled
        reading = jaVi == null ? null : extractKanaReading(jaVi);
        reading ??= lacVietValue == null ? null : extractReading(lacVietValue);
      }
    } else {
      reading = lacVietValue == null ? null : extractReading(lacVietValue);
      reading ??= jaVi == null ? null : extractKanaReading(jaVi);
    }
    return LookupResult(
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

  /// Tra lại từ đang hiển thị sau khi từ điển vừa đổi (mục AI/online vừa được
  /// ghi vào AiDict/OnlineDict/AiEntries/overlay VietPhrase, hoặc người dùng vừa
  /// sửa/xóa một mục), để ô Nghĩa đổi theo ngay thay vì bắt bấm lại đúng từ đó.
  void refreshCurrent() {
    if (state == null || _lastRawWord.isEmpty) return;
    final refreshed = _buildResult(_lastRawWord, _lastRawSentence);
    if (refreshed == null) return;
    state = _withSessionSections(refreshed);
  }

  /// Ghép lại các mục chỉ tồn tại trong phiên: nghĩa máy dịch (Google) cố ý
  /// không được lưu vào từ điển nên tra lại sẽ không sinh lại được.
  LookupResult _withSessionSections(LookupResult result) {
    final labels = result.sections.map((s) => s.label).toSet();
    final extra = _sessionSections
        .where((s) => !labels.contains(s.label))
        .toList();
    if (extra.isEmpty) return result;
    return LookupResult(
      word: result.word,
      matchedKey: result.matchedKey,
      reading: result.reading,
      readingKind: result.readingKind,
      hanViet: result.hanViet,
      body: result.body,
      sections: [...result.sections, ...extra],
    );
  }

  /// Chèn kết quả tra online vào cuối ô Nghĩa (bỏ mục cũ cùng nhãn khi tra lại).
  /// Bỏ qua nếu người dùng đã chọn từ khác trong lúc chờ mạng.
  void addOnlineSections(String word, List<LookupSection> online) {
    final current = state;
    if (current == null || current.word != word || online.isEmpty) return;
    final labels = online.map((s) => s.label).toSet();
    _sessionSections
      ..removeWhere((s) => labels.contains(s.label))
      ..addAll(online);
    state = LookupResult(
      word: current.word,
      matchedKey: current.matchedKey,
      reading: current.reading,
      readingKind: current.readingKind,
      hanViet: current.hanViet,
      body: current.body,
      sections: [
        ...current.sections.where((s) => !labels.contains(s.label)),
        ...online,
      ],
    );
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
  static String _joinMeanings(String value) => formatVietPhraseForLookup(value);


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

/// Hán Việt của [text] (1 chữ hoặc cả cụm): mỗi chữ Hán tra
/// ChinesePhienAmWords, miss → giữ nguyên chữ gốc; ký tự không phải Hán
/// (hiragana, katakana, dấu câu...) bị lọc bỏ hoàn toàn. Null khi không có
/// chữ Hán nào tra được (VD chọn thuần kana).
String? hanVietReadingOf(LoadedDictionaries dicts, String text) {
  final buffer = StringBuffer();
  var hasHit = false;
  var i = 0;
  while (i < text.length) {
    final len = runeLengthAt(text, i);
    final ch = text.substring(i, i + len);
    if (isHanCodePoint(codePointAt(text, i))) {
      if (buffer.isNotEmpty) buffer.write(' ');
      final v = dicts.chinesePhienAm.entries[ch];
      if (v != null) {
        buffer.write(_capitalizeFirst(v.split('/').first.trim()));
        hasHit = true;
      } else {
        buffer.write(ch);
      }
    }
    i += len;
  }
  return hasHit ? buffer.toString() : null;
}

/// Viết hoa chữ cái đầu (âm Hán Việt hiển thị kiểu tên riêng).
String _capitalizeFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

final lookupControllerProvider =
    NotifierProvider<LookupController, LookupResult?>(LookupController.new);

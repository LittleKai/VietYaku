import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_paths.dart';
import '../../../core/google_translate.dart';
import '../../ai_translation/application/ai_settings_controller.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/data/user_dict_service.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../settings/settings_provider.dart';
import '../data/weblio_api.dart';
import '../domain/dict_entry_filter.dart';
import '../domain/online_lookup_source.dart';
import '../domain/trad2simp_table.dart';
import '../domain/translation_engine.dart';
import 'lookup_controller.dart';
import 'trad2simp_provider.dart';
import 'translation_controller.dart';

/// Một nguồn đang tra: dialog dựng FutureBuilder riêng cho từng cái.
/// [label] là nhãn `<<Từ điển>>` khi hiện trong ô Nghĩa và khi lưu từ điển.
/// [saved] = true khi nguồn là từ điển thật (Mazii, Jisho, Weblio, Youdao) —
/// chỉ nguồn này mới được ghi vào OnlineDict; kết quả máy dịch (Google) chỉ
/// hiện tạm.
typedef OnlineLookupTask = ({
  OnlineLookupSource source,
  String label,
  bool saved,
  Future<String?> body,
});

/// Chạy song song các nguồn tra online đang bật trong Cài đặt cho [word].
///
/// Trả về danh sách task để dialog hiện từng kết quả ngay khi xong. Khi tất cả
/// đã xong: chèn các mục có nội dung vào ô Nghĩa và lưu vào
/// `OnlineDict_<mode>.txt` rồi nạp lại từ điển (lần tra sau có sẵn offline).
/// Phần lưu chạy độc lập với dialog — đóng dialog sớm vẫn lưu được.
List<OnlineLookupTask> startOnlineLookup(WidgetRef ref, String rawWord) {
  final settings = ref.read(settingsProvider);
  final sources = settings.onlineLookupSources;
  final mode = ref.read(currentModeProvider);
  final isJa = mode == TranslationMode.japanese;
  // Mode Trung: tra và lưu bằng bản giản thể, khớp với key mà lookup_controller
  // dùng khi đọc lại OnlineDict.
  final word = !isJa && settings.convertTraditionalToSimplified
      ? (ref.read(trad2SimpTableProvider).valueOrNull ?? Trad2SimpTable.empty)
            .convert(rawWord)
      : rawWord;
  final mazii = ref.read(maziiApiProvider);
  final google = ref.read(googleTranslateProvider);
  final jisho = ref.read(jishoApiProvider);
  final weblio = ref.read(weblioApiProvider);
  final youdao = ref.read(youdaoApiProvider);
  final sourceLang = isJa ? 'ja' : 'zh-CN';

  final tasks = <OnlineLookupTask>[];
  for (final source in OnlineLookupSource.values) {
    if (!sources.contains(source)) continue;
    switch (source) {
      case OnlineLookupSource.mazii:
        tasks.add((
          source: source,
          label: 'Mazii Online',
          saved: true,
          body: mazii.lookup(word, dict: isJa ? 'javi' : 'cnvi'),
        ));
      case OnlineLookupSource.googleVi:
        tasks.add((
          source: source,
          label: 'Google Dịch',
          saved: false,
          body: google.translate(word, sourceLang: sourceLang),
        ));
      // Cả hai chiều đều là từ điển thật: Nhật→Anh dùng Jisho (JMdict),
      // Trung→Anh dùng 有道词典 (endpoint jsonapi, không cần key).
      case OnlineLookupSource.english:
        tasks.add(
          isJa
              ? (
                  source: source,
                  label: 'Jisho',
                  saved: true,
                  body: jisho.lookup(word),
                )
              : (
                  source: source,
                  label: 'Youdao 中英',
                  saved: true,
                  body: youdao.lookup(word),
                ),
        );
      // Weblio 日中中日辞典 là từ điển thật (~1.6 triệu mục, có cả pinyin) nên
      // dùng thay máy dịch; chỉ có chiều Nhật nên mode Trung bỏ qua.
      // Ban đầu tự động dịch nội dung sang tiếng Việt bằng Google Dịch.
      case OnlineLookupSource.chinese:
        if (!isJa) continue; // Trung→Trung vô nghĩa.
        tasks.add((
          source: source,
          label: 'Weblio 日中',
          saved: true,
          body: lookupWeblioWithGoogle(weblio, google, word),
        ));
    }
  }
  if (tasks.isEmpty) return tasks;

  // Đọc trước các notifier/service: dialog có thể đóng trước khi mạng trả về.
  final lookup = ref.read(lookupControllerProvider.notifier);
  final dictionaries = ref.read(dictionariesProvider.notifier);
  final translation = ref.read(translationControllerProvider.notifier);
  final appPaths = ref.read(appPathsProvider.future);
  // Admin ghi vào bộ dict dùng chung của ngôn ngữ để đóng gói theo bản phát
  // hành; người dùng thường ghi vào userdata cá nhân.
  final targetDir = ref.read(dictionarySyncProvider).isAdmin
      ? generatedDictDir(mode)
      : null;
  final dicts = ref.read(dictionariesProvider).valueOrNull;
  final knownToVietPhrase =
      dicts?.vietPhrase.entries.containsKey(word) ?? true;
  final knownToLacViet =
      dicts?.lacViet.entries.containsKey(word) ?? false;

  unawaited(
    _persist(
      tasks,
      word,
      mode,
      lookup,
      dictionaries,
      translation,
      appPaths,
      targetDir,
      knownToVietPhrase,
      knownToLacViet,
    ),
  );
  return tasks;
}

Future<void> _persist(
  List<OnlineLookupTask> tasks,
  String word,
  TranslationMode mode,
  LookupController lookup,
  DictionariesNotifier dictionaries,
  TranslationController translation,
  Future<AppPaths> appPaths,
  String? targetDir,
  bool knownToVietPhrase,
  bool knownToLacViet,
) async {
  try {
    final bodies = await Future.wait(tasks.map((task) => task.body));
    final sections = <LookupSection>[];
    final toSave = <LookupSection>[];
    for (var i = 0; i < tasks.length; i++) {
      final body = bodies[i]?.trim();
      if (body == null || body.isEmpty) continue;
      final section = LookupSection(word, tasks[i].label, body);
      sections.add(section);
      if (tasks[i].saved) toSave.add(section);
    }
    if (sections.isEmpty) return;
    lookup.addOnlineSections(word, sections);
    // Máy dịch trả nghĩa theo ngữ cảnh, lưu lại dễ sai → chỉ lưu từ điển thật.
    if (toSave.isEmpty) return;
    final service = UserDictService(await appPaths);
    final isWord = isWordLikeEntry(word);
    final encoded = encodeOnlineSections(toSave);
    await service.upsertOnlineDict(
      mode,
      word,
      encoded,
      inDir: isWord ? targetDir : null,
    );
    if (targetDir != null && isWord) {
      await service.upsertOnlineDict(mode, word, encoded);
    }

    // Từ tra online thường KHÔNG có trong VietPhrase (không có mới phải tra) →
    // engine cắt nó thành từng chữ và click lại không bao giờ khớp nguyên cụm,
    // nên mục vừa lưu sẽ không hiện ra được. Thêm vào overlay VietPhrase để
    // engine tách đúng cụm; chỉ nhận từ/cụm từ, không nhận cả câu.
    // Nguồn online tra mờ: gõ 再入荷 có thể trả mục của 再入 — đọc thì người
    // dùng tự nhận ra lệch, nhưng đưa vào VietPhrase là nhét bản dịch SAI vào
    // từ điển dịch. Chỉ promote khi headword nguồn trả về đúng bằng từ đã tra.
    if (!knownToVietPhrase && !knownToLacViet && isWord) {
      final exact = toSave
          .where(
            (s) =>
                vietnameseLookupLabels.contains(s.label) &&
                meaningMatchesWord(word, s.body),
          )
          .toList();
      final short = exact.isEmpty ? '' : shortMeaningOf(exact.first.body);
      if (short.isNotEmpty) {
        await service.upsertVietPhraseOverlay(mode, {
          word: short,
        }, inDir: targetDir);
        if (targetDir != null) {
          await service.upsertVietPhraseOverlay(mode, {word: short});
        }
      }
    }

    await dictionaries.reload();
    translation.retranslate();
    // Từ điển vừa có thêm mục online → tra lại ngay để ô Nghĩa hiện chúng,
    // thay vì bắt người dùng bấm lại đúng từ đó.
    lookup.refreshCurrent();
  } catch (_) {
    // Mất mạng / lỗi ghi file: kết quả đã hiện trên dialog là đủ.
  }
}

final _rawWeblioLabels = RegExp(
  r'(読み方|中国語訳|ピンイン|中国語品詞|対訳の関係|日本語での説明|用例)',
);
final _embeddedWeblioLabels = RegExp(
  r'(?<!^)(?<!\n)(読み方|中国語訳|ピンイン|中国語品詞|対訳の関係|日本語での説明|中国語での説明|英語での説明|解説|用例)',
);
final _pinyinThenCjk = RegExp(
  r'(ピンイン\s+[^\u3000-\u9fff\uff00-\uffef\n]+)([\u3000-\u9fff\uff00-\uffef])',
);

/// Lưu bản gốc Weblio 日中 trong phiên để khi bấm `Dịch AI` có thể dịch lại
/// chuẩn từ bản gốc thay vì dịch chồng lên bản Google Dịch.
final _rawWeblioCache = <String, String>{};
final _aiTranslatedWeblioWords = <String>{};

/// Nội dung mục `Weblio 日中` còn nguyên nhãn tiếng Nhật/Trung chưa qua dịch.
bool isRawWeblioBody(String body) => _rawWeblioLabels.hasMatch(body);

/// Tra `Weblio 日中` rồi tự động dịch sang tiếng Việt bằng Google Dịch.
Future<String?> lookupWeblioWithGoogle(
  WeblioApi weblio,
  GoogleTranslateClient google,
  String word,
) async {
  _aiTranslatedWeblioWords.remove(word);
  final raw = await weblio.lookup(word);
  if (raw == null || raw.trim().isEmpty) return null;
  _rawWeblioCache[word] = raw;
  return await translateWeblioWithGoogle(google, raw) ?? raw;
}

/// Dịch nội dung gốc `Weblio 日中` sang tiếng Việt bằng Google Dịch:
/// tách phần nghĩa tiếng Trung (`zh-CN`) và phần giải thích tiếng Nhật (`ja`)
/// để Google không nhận nhầm ngôn ngữ.
Future<String?> translateWeblioWithGoogle(
  GoogleTranslateClient google,
  String raw,
) async {
  final normalized = raw
      .replaceAllMapped(_embeddedWeblioLabels, (m) => '\n${m[1]} ')
      .replaceAllMapped(_pinyinThenCjk, (m) => '${m[1]}\n${m[2]}');
  final lines = [
    for (final l in normalized.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isEmpty) return null;

  final out = List<String?>.filled(lines.length, null);
  final zhItems = <(int, String)>[];
  final zhTexts = <String>[];
  final jaItems = <(int, String)>[];
  final jaTexts = <String>[];

  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.startsWith('読み方')) {
      out[i] = 'Cách đọc: ${l.substring(3).trim()}';
    } else if (l.startsWith('ピンイン')) {
      out[i] = 'Pinyin: ${l.substring(4).trim()}';
    } else if (l.startsWith('中国語訳')) {
      zhItems.add((i, 'Nghĩa: '));
      zhTexts.add(l.substring(4).trim());
    } else if (l.startsWith('中国語での説明')) {
      zhItems.add((i, 'Giải thích (Trung): '));
      zhTexts.add(l.substring(7).trim());
    } else if (l.startsWith('中国語品詞')) {
      jaItems.add((i, 'Từ loại: '));
      jaTexts.add(l.substring(5).trim());
    } else if (l.startsWith('対訳の関係')) {
      jaItems.add((i, 'Quan hệ đối dịch: '));
      jaTexts.add(l.substring(5).trim());
    } else if (l.startsWith('日本語での説明')) {
      jaItems.add((i, 'Giải thích: '));
      jaTexts.add(l.substring(7).trim());
    } else if (l.startsWith('用例')) {
      jaItems.add((i, 'Ví dụ: '));
      jaTexts.add(l.substring(2).trim());
    } else if (l.startsWith('解説')) {
      jaItems.add((i, 'Giải thích: '));
      jaTexts.add(l.substring(2).trim());
    } else {
      jaItems.add((i, ''));
      jaTexts.add(l);
    }
  }

  final results = await Future.wait([
    zhTexts.isEmpty
        ? Future<String?>.value('')
        : google.translate(zhTexts.join('\n'), sourceLang: 'zh-CN'),
    jaTexts.isEmpty
        ? Future<String?>.value('')
        : google.translate(jaTexts.join('\n'), sourceLang: 'ja'),
  ]);
  final zhTranslated = results[0];
  final jaTranslated = results[1];
  if ((zhTexts.isNotEmpty && zhTranslated == null) ||
      (jaTexts.isNotEmpty && jaTranslated == null)) {
    return null;
  }

  if (zhTexts.isNotEmpty && zhTranslated != null) {
    final parts = zhTranslated.split('\n');
    for (var k = 0; k < zhItems.length; k++) {
      final (idx, prefix) = zhItems[k];
      final text = k < parts.length ? parts[k].trim() : zhTexts[k];
      out[idx] = '$prefix$text';
    }
  }
  if (jaTexts.isNotEmpty && jaTranslated != null) {
    final parts = jaTranslated.split('\n');
    for (var k = 0; k < jaItems.length; k++) {
      final (idx, prefix) = jaItems[k];
      final text = k < parts.length ? parts[k].trim() : jaTexts[k];
      out[idx] = '$prefix$text';
    }
  }
  final joined = out.whereType<String>().join('\n').trim();
  return joined.isEmpty ? null : joined;
}

/// Tự động dịch mục `Weblio 日中` còn nguyên bản sang tiếng Việt bằng Google Dịch
/// và cập nhật vào `OnlineDict_<mode>.txt`.
Future<void> translateWeblioSectionWithGoogle(
  WidgetRef ref, {
  required String word,
  required String body,
}) async {
  if (!isRawWeblioBody(body)) return;
  final mode = ref.read(currentModeProvider);
  final isJa = mode == TranslationMode.japanese;
  final settings = ref.read(settingsProvider);
  final normWord = !isJa && settings.convertTraditionalToSimplified
      ? (ref.read(trad2SimpTableProvider).valueOrNull ?? Trad2SimpTable.empty)
            .convert(word)
      : word;
  _rawWeblioCache[normWord] = body;
  final google = ref.read(googleTranslateProvider);
  final lookup = ref.read(lookupControllerProvider.notifier);
  final dictionaries = ref.read(dictionariesProvider.notifier);
  final appPathsFuture = ref.read(appPathsProvider.future);
  final targetDir = ref.read(dictionarySyncProvider).isAdmin
      ? generatedDictDir(mode)
      : null;
  final dicts = ref.read(dictionariesProvider).valueOrNull;
  final existingRaw =
      dicts?.onlineDict.entries[normWord] ?? dicts?.onlineDict.entries[word];
  final currentSections =
      ref.read(lookupControllerProvider)?.sections ?? const [];

  final translated = await translateWeblioWithGoogle(google, body);
  if (translated == null ||
      translated.trim().isEmpty ||
      _aiTranslatedWeblioWords.contains(normWord)) {
    return;
  }
  await _replaceWeblioSection(
    normWord: normWord,
    translatedBody: translated.trim(),
    mode: mode,
    lookup: lookup,
    dictionaries: dictionaries,
    appPathsFuture: appPathsFuture,
    targetDir: targetDir,
    existingRaw: existingRaw,
    currentSections: currentSections,
  );
}

String buildWeblioAiTranslatePrompt(String word, String body) =>
    'Dịch nội dung mục từ điển Weblio 日中 của từ "$word" dưới đây sang tiếng Việt '
    'ngắn gọn, chuẩn xác (giữ nguyên cách đọc kana/pinyin nếu có, chỉ trả về nội dung '
    'đã dịch, không giải thích thêm, không dùng markdown code block):\n\n$body';

/// Dịch nội dung mục `Weblio 日中` của [word] sang tiếng Việt bằng AI, thay thế
/// bản Google Dịch trong `OnlineDict_<mode>.txt` (giữ nguyên các mục online khác).
/// Trả về `null` nếu thành công, hoặc chuỗi thông báo lỗi nếu thất bại.
Future<String?> translateWeblioSectionWithAi(
  WidgetRef ref, {
  required String word,
  required String body,
}) async {
  final mode = ref.read(currentModeProvider);
  final isJa = mode == TranslationMode.japanese;
  final settings = ref.read(settingsProvider);
  final normWord = !isJa && settings.convertTraditionalToSimplified
      ? (ref.read(trad2SimpTableProvider).valueOrNull ?? Trad2SimpTable.empty)
            .convert(word)
      : word;
  if (isRawWeblioBody(body)) {
    _rawWeblioCache[normWord] = body;
  }
  final weblio = ref.read(weblioApiProvider);
  final lookup = ref.read(lookupControllerProvider.notifier);
  final dictionaries = ref.read(dictionariesProvider.notifier);
  final appPathsFuture = ref.read(appPathsProvider.future);
  final targetDir = ref.read(dictionarySyncProvider).isAdmin
      ? generatedDictDir(mode)
      : null;
  final dicts = ref.read(dictionariesProvider).valueOrNull;
  final existingRaw =
      dicts?.onlineDict.entries[normWord] ?? dicts?.onlineDict.entries[word];
  final currentSections =
      ref.read(lookupControllerProvider)?.sections ?? const [];
  final apiClient = ref.read(aiApiClientProvider);
  final aiSettings = await ref.read(aiSettingsControllerProvider.future);
  if (!aiSettings.hasConfiguredKey) {
    return 'Chưa cấu hình API Key trong phần Dịch AI.';
  }

  final sourceBody = isRawWeblioBody(body)
      ? body
      : (_rawWeblioCache[normWord] ?? await weblio.lookup(normWord) ?? body);
  final response = await apiClient.callAi(
    prompt: buildWeblioAiTranslatePrompt(normWord, sourceBody),
    serviceType: aiSettings.activeService,
    config: aiSettings.activeConfig,
  );
  if (!response.isSuccess) {
    return response.error ?? 'Lỗi không xác định khi gọi AI.';
  }
  _aiTranslatedWeblioWords.add(normWord);
  await _replaceWeblioSection(
    normWord: normWord,
    translatedBody: response.text!.trim(),
    mode: mode,
    lookup: lookup,
    dictionaries: dictionaries,
    appPathsFuture: appPathsFuture,
    targetDir: targetDir,
    existingRaw: existingRaw,
    currentSections: currentSections,
  );
  return null;
}

Future<void> _replaceWeblioSection({
  required String normWord,
  required String translatedBody,
  required TranslationMode mode,
  required LookupController lookup,
  required DictionariesNotifier dictionaries,
  required Future<AppPaths> appPathsFuture,
  required String? targetDir,
  required String? existingRaw,
  required List<LookupSection> currentSections,
}) async {
  final updatedSection = LookupSection(normWord, 'Weblio 日中', translatedBody);
  final existingSections = existingRaw != null
      ? decodeOnlineSections(normWord, existingRaw)
      : [
          for (final s in currentSections)
            if (s.word == normWord &&
                const {
                  'Mazii Online',
                  'Jisho',
                  'Youdao 中英',
                  'Weblio 日中',
                }.contains(s.label))
              s,
        ];
  final updatedList = <LookupSection>[];
  var replaced = false;
  for (final s in existingSections) {
    if (s.label == 'Weblio 日中') {
      if (!replaced) {
        updatedList.add(updatedSection);
        replaced = true;
      }
    } else {
      updatedList.add(s);
    }
  }
  if (!replaced) updatedList.add(updatedSection);

  final encoded = encodeOnlineSections(updatedList);
  final service = UserDictService(await appPathsFuture);
  final isWord = isWordLikeEntry(normWord);
  await service.upsertOnlineDict(
    mode,
    normWord,
    encoded,
    inDir: isWord ? targetDir : null,
  );
  if (targetDir != null && isWord) {
    await service.upsertOnlineDict(mode, normWord, encoded);
  }

  await dictionaries.reload();
  lookup.refreshCurrent();
  lookup.addOnlineSections(normWord, [updatedSection]);
}

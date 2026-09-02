import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_paths.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/data/user_dict_service.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../settings/settings_provider.dart';
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
      case OnlineLookupSource.chinese:
        if (!isJa) continue; // Trung→Trung vô nghĩa.
        tasks.add((
          source: source,
          label: 'Weblio 日中',
          saved: true,
          body: weblio.lookup(word),
        ));
    }
  }
  if (tasks.isEmpty) return tasks;

  // Đọc trước các notifier/service: dialog có thể đóng trước khi mạng trả về.
  final lookup = ref.read(lookupControllerProvider.notifier);
  final dictionaries = ref.read(dictionariesProvider.notifier);
  final appPaths = ref.read(appPathsProvider.future);
  // Admin ghi vào bộ dict dùng chung của ngôn ngữ để đóng gói theo bản phát
  // hành; người dùng thường ghi vào userdata cá nhân.
  final targetDir = ref.read(dictionarySyncProvider).isAdmin
      ? generatedDictDir(mode)
      : null;
  final knownToVietPhrase =
      ref.read(dictionariesProvider).valueOrNull?.vietPhrase.entries.containsKey(
        word,
      ) ??
      true;

  unawaited(
    _persist(
      tasks,
      word,
      mode,
      lookup,
      dictionaries,
      appPaths,
      targetDir,
      knownToVietPhrase,
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
  Future<AppPaths> appPaths,
  String? targetDir,
  bool knownToVietPhrase,
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
    await service.upsertOnlineDict(
      mode,
      word,
      encodeOnlineSections(toSave),
      inDir: targetDir,
    );

    // Từ tra online thường KHÔNG có trong VietPhrase (không có mới phải tra) →
    // engine cắt nó thành từng chữ và click lại không bao giờ khớp nguyên cụm,
    // nên mục vừa lưu sẽ không hiện ra được. Thêm vào overlay VietPhrase để
    // engine tách đúng cụm; chỉ nhận từ/cụm từ, không nhận cả câu.
    // Nguồn online tra mờ: gõ 再入荷 có thể trả mục của 再入 — đọc thì người
    // dùng tự nhận ra lệch, nhưng đưa vào VietPhrase là nhét bản dịch SAI vào
    // từ điển dịch. Chỉ promote khi headword nguồn trả về đúng bằng từ đã tra.
    if (!knownToVietPhrase && isWordLikeEntry(word)) {
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
      }
    }

    await dictionaries.reload();
  } catch (_) {
    // Mất mạng / lỗi ghi file: kết quả đã hiện trên dialog là đủ.
  }
}

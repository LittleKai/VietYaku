import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/data/user_dict_service.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/lookup_controller.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/domain/dict_entry_filter.dart';
import '../../translation/domain/translation_engine.dart';
import '../data/ai_api_client.dart';
import '../domain/ai_lookup_result.dart';
import '../domain/ai_service_config.dart';
import 'ai_settings_controller.dart';

/// Prompt trả về JSON thay vì Markdown: ngắn hơn nhiều token, không có phần
/// thừa (ví dụ sử dụng, lời dẫn), và app tự render nên bố cục luôn ổn định.
String buildAiLookupPrompt(String word, {required TranslationMode mode}) {
  final isJa = mode == TranslationMode.japanese;
  final langName = isJa ? 'tiếng Nhật' : 'tiếng Trung';
  final stemRule = isJa
      ? '- Đưa về THÂN TỪ ngắn nhất còn giữ nghĩa: tính từ đuôi い bỏ い '
            '(チャラい → チャラ), động từ về thân từ (食べた → 食べ).'
      : '- Bỏ các hư từ/tiếp vĩ ngữ bám quanh, giữ phần mang nghĩa.';

  return '''
Bạn là chuyên gia ngôn ngữ học $langName sang tiếng Việt.
Phân tích cụm sau: "$word"

CHỈ trả về một object JSON, không lời dẫn, không bọc trong ```:
{
  "meaning": "nghĩa tiếng Việt, các nét nghĩa cách nhau bằng /",
  "pos": "từ loại",
  "parts": [{"part": "thành phần", "base": "dạng gốc nếu bị chia", "meaning": "nghĩa ngắn"}],
  "sub_entries": [{"word": "từ tách ra", "meaning": "nghĩa ngắn"}]
}

KHÔNG đưa phiên âm, cách đọc, romaji, pinyin hay âm Hán Việt vào bất kỳ trường nào.

Quy tắc "sub_entries" — đây là các mục sẽ được thêm thẳng vào từ điển:
- Tách những từ/cụm có nghĩa độc lập nằm trong cụm trên.
$stemRule
- BỎ trợ từ và đuôi ngữ pháp đứng một mình (は, を, ました, です, 的, 了...).
- "meaning" viết kiểu từ điển, ngắn, các nét nghĩa cách nhau bằng /.
- Không lặp lại nguyên cụm "$word".

Không đưa câu ví dụ vào bất kỳ trường nào.
''';
}

/// Chạy tác vụ tra cứu AI cho [rawWord].
///
/// Mọi thứ lấy từ [ref] phải đọc TRƯỚC lần `await` đầu tiên: người dùng có thể
/// đóng hộp thoại trong lúc chờ AI (timeout tới 240s), lúc đó widget đã dispose
/// và `ref` không dùng được nữa — kết quả sẽ mất trắng dù đã tốn lượt gọi API.
Future<AiApiResponse> executeAiLookup(WidgetRef ref, String rawWord) async {
  final mode = ref.read(currentModeProvider);
  final word = lookupKeyOf(ref, rawWord);

  final aiSettings =
      ref.read(aiSettingsControllerProvider).valueOrNull ??
      AiSettings.defaults();

  final activeService = aiSettings.activeService;
  final activeConfig = aiSettings.activeConfig;

  if (activeConfig.keys.isEmpty) {
    return AiApiResponse(
      error:
          'Chưa cấu hình API Key cho ${activeService.label}. Vui lòng mở Cài đặt → Dịch AI để nhập key.',
    );
  }

  final prompt = buildAiLookupPrompt(word, mode: mode);
  final apiClient = ref.read(aiApiClientProvider);
  final lookup = ref.read(lookupControllerProvider.notifier);
  final dictionaries = ref.read(dictionariesProvider.notifier);
  final appPaths = ref.read(appPathsProvider.future);
  final vietPhrase = ref.read(dictionariesProvider).valueOrNull?.vietPhrase;
  // Admin ghi vào bộ dict dùng chung của ngôn ngữ để đóng gói theo bản phát
  // hành; người dùng thường ghi vào userdata cá nhân.
  final targetDir = ref.read(dictionarySyncProvider).isAdmin
      ? generatedDictDir(mode)
      : null;

  final response = await apiClient.callAi(
    prompt: prompt,
    serviceType: activeService,
    config: activeConfig,
  );

  if (!response.isSuccess) return response;

  final parsed = AiLookupResult.tryParse(word, response.text!);
  // Model không chịu trả JSON → vẫn giữ nguyên văn để không mất kết quả.
  final body = parsed?.toStorageValue() ?? response.text!.trim();
  final section = LookupSection(word, 'AI Dịch', body);

  // Cập nhật ngay vào ô Nghĩa hiện tại (tự bỏ qua nếu người dùng đã chọn từ
  // khác trong lúc chờ).
  lookup.addOnlineSections(word, [section]);

  try {
    final service = UserDictService(await appPaths);
    await service.upsertAiDict(
      mode,
      word,
      encodeOnlineSections([section]),
      inDir: targetDir,
    );

    if (parsed != null) {
      // Các từ/cụm con tách ra thành mục từ điển riêng để engine greedy
      // longest-match nhận ra chúng ở văn bản khác.
      final subEntries = {
        for (final e in parsed.subEntries) e.word: e.meaning,
      };
      if (subEntries.isNotEmpty) {
        await service.upsertAiEntries(mode, subEntries, inDir: targetDir);
      }

      // Từ nào VietPhrase chưa có thì thêm luôn vào overlay VietPhrase — có
      // vậy engine mới cắt ra đúng cụm đó và click lại mới tra được.
      // CHỈ nhận từ/cụm từ: value VietPhrase được chèn thẳng vào bản dịch nên
      // một mệnh đề lọt vào sẽ nuốt trọn cả đoạn.
      final missing = {
        for (final e in {word: parsed.shortMeaning, ...subEntries}.entries)
          if (isWordLikeEntry(e.key) &&
              (vietPhrase == null || !vietPhrase.entries.containsKey(e.key)))
            e.key: e.value,
      };
      if (missing.isNotEmpty) {
        await service.upsertVietPhraseOverlay(mode, missing, inDir: targetDir);
      }
    }

    await dictionaries.reload();
  } catch (_) {
    // Lỗi ghi file: kết quả đã hiện trên dialog + ô Nghĩa là đủ.
  }

  return response;
}

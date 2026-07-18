# Project Summary — VietYaku

**Last Updated:** 2026-07-18
**Session:** #8 — Đồng bộ VietPhrase/Lạc Việt chung qua LittleKai-server: public delta pull, admin JWT publish, overlay/cursor theo mode, nút sync cuối menu bar

---

## 1. Project Overview

- **Type:** Desktop app (Windows) — dịch Nhật/Trung→Việt kiểu VietPhrase + công cụ sửa từ điển JP, thay thế QuickTranslator_Jap (WinForms). Dịch chính offline; có thêm tính năng online tùy chọn: tra nghĩa Mazii/Google Dịch và tab Google Translate (endpoint gtx + fallback crawl translate.google.com/m).
- **Tech Stack:** Flutter 3.44.2, Dart ^3.12, Material 3
- **Package Manager:** pub (flutter pub)
- **i18n:** None (UI tiếng Việt cố định)
- **State Management:** Riverpod 2 — manual providers (Notifier/AsyncNotifier), KHÔNG codegen
- **Styling:** Material 3, hệ thiết kế tập trung `lib/core/theme/app_theme.dart` (`AppTheme.light`/`.dark`, seed indigo `0xFF4F46E5`, font chrome Segoe UI, ~15 component theme cho dialog/ô nhập/dropdown/tab/nút/rail/card/tooltip/snackbar/slider/menu). Theme tối tự theo hệ điều hành (`ThemeMode.system`). Màu tô nổi + token Names qua `ThemeExtension AppSemanticColors` (sáng/tối riêng).
- **Deployment:** `flutter build windows --release` → exe độc lập tại `build\windows\x64\runner\Release\vietyaku.exe` (đã verify chạy standalone)

Dữ liệu từ điển bundle trong dự án (commit git), mỗi ngôn ngữ một bộ tại `data/jp/` và `data/cn/` — đường dẫn hardcode (`defaultDataDir` trong settings_provider), không còn UI chọn file trong Cài đặt:
- `data/jp/` (nguồn Drive QuickTranslator_Jap, đã repair simp→JP): VietPhrase.txt (187.419 — bản `_JP` repair), LacViet.txt (103.632 — bản `_JP`), Names.txt, JaViDict.txt (172.321), + ThieuChuu/Babylon/cedict_ts.u8/ChinesePhienAm*/Pronouns.
- `data/cn/` (nguồn `D:\Software\QuickTranslator\Quick Translator Chinese\Data`): VietPhrase.txt (690.007), LacViet.txt (66.450), Names.txt, ZhViDict.txt (161.194), + bộ chung như trên.
- JaViDict/ZhViDict generate từ SQLite của VocabFlip bằng `tool/export_vocabflip_dicts.py` (chạy 1 lần, conda py312), value escape `\n\t` như LacViet.
- Nguồn gốc (KHÔNG ghi đè): Drive `JP CN Tool\QuickTranslator_Jap` và `D:\Software\QuickTranslator\`.

---

## 2. File Structure

### Key Directories
```
VietYaku/
├── CLAUDE.md, .claude/             # docs hệ thống (summary, conventions, fixed bugs, setup report)
├── data/jp/, data/cn/              # bộ từ điển bundle theo ngôn ngữ (commit git, ~123MB)
├── assets/mappings/                # simp2jp.tsv (3.932 + 69 ambiguous), jp_valid_kanji.txt (3.030), simp2jp_overrides.tsv (soạn tay)
├── tool/                           # build_simp2jp.dart (sinh assets, cần mạng), export_jp.dart (CLI repair + verify), export_vocabflip_dicts.py (sinh JaViDict/ZhViDict.txt từ DB VocabFlip)
├── lib/
│   ├── main.dart                   # window_manager (1200×760, min 1000×640), SharedPreferences override, ProviderScope
│   ├── app.dart                    # MaterialApp M3 + HomeShell (NavigationRail + IndexedStack 3 tab)
│   ├── core/                       # cjk.dart, app_paths.dart, fnv_hash.dart, tts_service.dart, google_translate.dart (gtx + fallback crawl /m), theme/app_theme.dart (design system + AppSemanticColors)
│   ├── features/
│   │   ├── dictionary/             # domain (dict_type, phrase_dictionary) · data (dict_parser, binary_cache, dictionary_loader, dictionary_repository, user_dict_service) · application (dictionaries_provider)
│   │   ├── dictionary_sync/        # domain shared entry · typed HTTP API · merge overlay · Riverpod admin session/sync controller
│   │   ├── translation/            # domain (translation_engine, token, reading_extractor) · data (mazii_api) · application (translation_controller + currentModeProvider, lookup_controller, token_selection) · presentation (translate_screen + menu bar, source_pane, result_pane + tab Google Dịch, han_viet_pane, token_text_view, lacviet_panel + nút tra online)
│   │   ├── repair/                 # domain (jp_repair_pipeline, simp2jp_table, repair_report) · application (repair_controller) · presentation (repair_screen, repair_preview)
│   │   └── settings/               # settings_provider, settings_screen
│   └── shared/widgets/             # tts_button, entry_edit_dialog
└── test/                           # 85 tests (10 file; integration dữ liệu thật tự skip nếu thiếu path)
```

### Critical Files
| File | Purpose | Notes |
|------|---------|-------|
| `lib/features/translation/domain/translation_engine.dart` | Engine greedy longest-match | Chữ ký `translate()` chừa sẵn cho AiTranslationEngine v2 |
| `lib/features/dictionary/data/binary_cache.dart` | Format cache `.vydc` | Header: magic/version/FNV-1a/size/mtime/count |
| `lib/features/dictionary/data/dictionary_loader.dart` | Load qua `Isolate.run` | Invalidation: so size trước, lệch mtime mới hash |
| `lib/features/repair/domain/jp_repair_pipeline.dart` | Sửa key: space + simp→JP, dedupe | VALUE KHÔNG ĐỔI 1 BYTE |
| `lib/features/dictionary/data/dictionary_repository.dart` | Load 12 dict + overlay, theo mode | `*_JP.txt` trong appdata chỉ ưu tiên ở mode Nhật (bộ CN dùng thẳng file cấu hình) |
| `tool/build_simp2jp.dart` | Sinh assets mapping | OpenCC JPShinjitaiCharacters map NGƯỢC chiều — đã đảo (xem IMPORTANT_FIXED_BUGS.md) |

---

## 3. Architecture & Patterns

### Component Structure
Feature-first: mỗi feature chia `domain/` (thuần Dart, không Flutter) · `data/` (IO, parse, cache) · `application/` (Riverpod providers/controllers) · `presentation/` (widgets). Widget dùng `ConsumerWidget`/`ConsumerStatefulWidget`.

### State Management
- Riverpod manual: `NotifierProvider` (settings, translation, lookup, repair, recent files), `AsyncNotifierProvider` (dictionaries, saved words), `FutureProvider` (appPaths, ttsService, simp2jpTable).
- `sharedPreferencesProvider` override trong `main()` sau `SharedPreferences.getInstance()`.
- Đồng bộ từ điển chung chỉ áp dụng cho VietPhrase/Lạc Việt: `GET /api/glossary/sync` kéo các trang delta bằng opaque cursor (public); `POST` publish entry qua JWT admin giữ trong RAM. Cursor lưu riêng cho Nhật/Trung; delta merge vào `SharedVietPhrase_<mode>.txt` / `SharedLacViet_<mode>.txt`, sau đó reload cache và dịch lại văn bản hiện tại. UserDict/UserNames luôn local, không upload.
- Engine: `HashMap<String,String>` + `maxLenByFirstUnit: Map<int,int>` per dict (key = UTF-16 code unit đầu). Tie-break UserDict > Names > VietPhrase. Fallback chữ Hán đơn → ChinesePhienAmWords; kana/lạ → passthrough.
- Engine options (constructor, chữ ký `translate()` không đổi): `TranslationAlgorithm` — `leftToRight` (mặc định) / `longestPhrase` (cụm dài toàn văn đặt trước, khe trống dịch trái→phải chặn biên) / `longestPhrase4` (chỉ cụm ≥4 code unit vào vòng global); `prioritizeNames` — tiered: dict đứng trước có match (bất kỳ độ dài) thắng dict sau (UserDict ngắn vẫn thắng cụm dài — cố ý). Settings áp dụng ở lần Dịch kế tiếp.
- Token giữ `rawValue` (value dict nguyên bản); `meaning`/`display`/`displayAll` là getter — đổi tab một nghĩa/đa nghĩa chỉ đổi render, không re-translate.
- `dictionariesProvider` watch `currentModeProvider` (đổi Nhật/Trung → nạp lại bộ dict của mode, cache .vydc giữ nhanh) + `settingsProvider.select(dictPathsFor(mode))` — đổi thuật toán không reload dict. LƯU Ý: không được watch `translationControllerProvider` từ dictionariesProvider (vòng phụ thuộc Riverpod — xem IMPORTANT_FIXED_BUGS.md); mode tách riêng ở `currentModeProvider`.

### Data Flow
settings (paths) → dictionaries_provider → DictionaryRepository.loadAll (12 dict chính + UserNames local + 2 shared overlay, tải song song qua `Isolate.run`; cache `.vydc` hợp lệ → decode, không thì parse text + ghi cache) → shared VietPhrase/Lạc Việt đè entry cùng key trong file bundle → LoadedDictionaries.engineWith(algorithm, prioritizeNames) → translation_controller.translate → tokens + hanVietTokens → TokenTextView: nháy chuột → lookup; chuột phải → sửa UserDict/Names local hoặc, khi đã login admin, cập nhật VietPhrase/Lạc Việt chung.

### Layout màn hình Dịch (kiểu QuickTranslator, tham khảo .claude/image.png)
Menu bar trên cùng (chọn Nhật/Trung + Dán & Dịch). Trái (flex 2): tabs [Nguồn | Hán Việt] qua TabBar + IndexedStack (giữ state SourcePane) trên, LacVietPanel ("Nghĩa", có nút tra online) dưới. Phải (flex 3): ResultPane với tabs [VietPhrase một nghĩa | VietPhrase (đa nghĩa) — mặc định | Google Dịch (tab tạo khi bấm nút, dịch online cả đoạn)] — 1 TokenTextView duy nhất, đổi tab chỉ đổi `textOf` (display/displayAll). Nút chỉnh cỡ chữ + font các ô nằm ở NavigationRail trái.

### Repair Flow
RepairScreen → pick file → preview per-line (Isolate.run, 50 dòng đổi đầu tiên) → Run (`Isolate.spawn` + progress SendPort, kết quả qua `Isolate.exit`) → RepairReport → export `*_JP.txt` (UTF-8 BOM CRLF cạnh gốc + copy appdata + xóa .vydc cũ) → reload providers.

### Storage (appdata = `getApplicationSupportDirectory()`)
`cache/` (.vydc) · `dictionaries/` (*_JP.txt, UserDict.txt, UserNames.txt, SharedVietPhrase_*.txt, SharedLacViet_*.txt) · `saved_words.json`.

---

## 4. Active Features & Status

| Feature | Status | Files Involved | Notes |
|---------|--------|----------------|-------|
| Core engine + parser | ✅ Done | translation_engine, dict_parser, phrase_dictionary | Dịch 10k ký tự ~60ms |
| Binary cache .vydc + isolate loader | ✅ Done | binary_cache, dictionary_loader | Cold 1,28s → warm 0,45s (5 file thật) |
| Màn hình Dịch 3 cột + click-lookup + reading + TTS | ✅ Done | translate_screen, source_pane, result_pane, lacviet_panel, reading_extractor, tts_service | TTS thiếu voice → disable + tooltip |
| JP repair pipeline + RepairScreen | ✅ Done | jp_repair_pipeline, simp2jp_table, repair_controller, repair_screen | VietPhrase: 13.317 space, 81.299 chữ converted |
| UserDict/UserNames overlay | ✅ Done | user_dict_service, entry_edit_dialog, dictionary_repository | Sửa nghĩa áp dụng ngay, không đụng file gốc |
| Đồng bộ VietPhrase/Lạc Việt chung | ✅ Done | dictionary_sync/*, dictionary_repository, entry_edit_dialog, token_text_view, translate_screen, settings_screen | Mọi app pull delta; chỉ admin publish từ menu chuột phải; UserDict/Names luôn local; mật khẩu/JWT không lưu xuống đĩa |
| Bộ dict theo ngôn ngữ (data/jp, data/cn) | ✅ Done | settings_provider, dictionary_repository, dictionaries_provider, currentModeProvider | Đổi mode → reload bộ dict tương ứng |
| Menu bar Nhật/Trung + Dịch + Dán & Dịch | ✅ Done | translate_screen (_MenuBar), translation_controller.translate/pasteAndTranslate, source_pane.sourceDraftProvider | Nút Dịch dịch nội dung ô Nguồn (đọc sourceDraftProvider); ô Nguồn không còn toolbar riêng |
| Chỉnh cỡ chữ + font các ô | ✅ Done | settings_screen, settings_provider.paneTextStyle | Trong tab Cài đặt; áp cho Nguồn/Kết quả/Nghĩa/ô Việt, lưu prefs |
| Tra nghĩa online trong ô Nghĩa | ✅ Done | mazii_api, google_translate, lookup_controller.fetchOnlineMeaning, lacviet_panel | Nhật: Mazii (miss → Google); Trung: Google Dịch (Hanzii v2 mã hóa response nên không dùng) |
| Tab Google Dịch cả đoạn | ✅ Done | result_pane, core/google_translate | gtx endpoint; fallback crawl translate.google.com/m |
| Lưu từ + export vocabflip | ❌ Removed (session #3) | — | saved_words_provider.dart còn trên đĩa nhưng không được import (user tự xóa nếu muốn) |
| Settings + copy kết quả + release build | ✅ Done | settings_screen, result_pane | exe standalone verified |
| Layout tabs kiểu QT + VietPhrase đa nghĩa | ✅ Done | translate_screen, result_pane, token_text_view | Đổi tab không re-translate; hàng chọn Nhật/Trung nằm TRÊN tabs Nguồn/Hán Việt |
| Tab Hán Việt toàn văn | ✅ Done | han_viet_pane, translation_controller | Tính cùng lượt dịch |
| Thuật toán dịch (Trái→phải / Cụm dài / Cụm dài ≥4) + Ưu tiên Name | ✅ Done | translation_engine, settings_provider, settings_screen | Áp dụng lần Dịch kế |
| Chọn kiểu caret + tô nổi đỏ đồng bộ 3 pane | ✅ Done | token_selection, source_pane (_HighlightTextEditingController), token_text_view (SelectableText.rich) | Nháy chuột ô Nguồn/kết quả → chọn cụm, highlight 2 chiều |
| Ô Nghĩa đa từ điển kiểu QT | ✅ Done | lookup_controller (LookupSection), lacviet_panel | VietPhrase cụm+chữ đầu / Lạc Việt / Nhật Việt / Cedict-Babylon / Thiều Chửu / Trung Việt / Phiên Âm, ngăn bằng ----------------- |
| Sửa từ điển từ toolbar chuột phải | ✅ Done | token_text_view (contextMenuBuilder), entry_edit_dialog | Verify tay (không có widget test secondary-tap) |
| Hệ thiết kế tập trung (theme sáng/tối) | ✅ Done | core/theme/app_theme.dart, app.dart, token_text_view, source_pane, settings_screen (DropdownMenu) | Component theme cho dialog/ô nhập/dropdown/tab/nút/rail/card/tooltip/snackbar/slider; dark tự theo OS; font dropdown nâng lên DropdownMenu M3 |

**Verify end-to-end:** `dart run tool/export_jp.dart` → VietPhrase_JP.txt (187.419 entries) + LacViet_JP.txt (103.632) cạnh file gốc; hết key `覚 悟`/`军`, value nguyên vẹn từng byte; dịch Nhật match dài, dịch Trung có fallback phiên âm. `flutter test` 91 pass + `flutter analyze` sạch + Windows release build thành công.

---

## 5. Known Issues & TODOs

### 🔴 High Priority
- (không có)

### 🟡 Medium Priority
- [ ] Chuột phải token (menu edit) chưa có widget test (hit-test TextSpan với kSecondaryButton phức tạp) — verify tay.

### 🟢 Low Priority / Nice to Have (Backlog v2 — KHÔNG làm v1)
- [ ] Furigana per-token cho kanji ngoài từ điển (cần MeCab, không có port Dart thuần).
- [ ] AiTranslationEngine (chữ ký `translate()` đã chừa sẵn).
- [ ] Fuzzy match / gợi ý sửa key còn sót.
- [ ] Luật Nhân (LuatNhan.txt — pattern `把{0}挡住=ngăn cản {0}`, 211 rule trong QuickTranslator_Jap) + 4 tùy chọn sử dụng — user đã chốt để đợt sau.
- [ ] Batch dịch cả thư mục + xuất file (QuickConverter) — chưa có nhu cầu, đã loại khỏi scope đợt này.

### Giới hạn đã biết (by design)
- Quy tắc vàng: ký tự đã hợp lệ JP không convert → không sửa được `后→後`, `干→幹` theo ngữ cảnh; ghi vào RepairReport.ambiguous.
- Ambiguous cố ý không resolve: 复(復/複/覆), 舍(舎/捨), 获(獲/穫), 泛(氾/汎) + ~30 chữ hiếm.
- Screenshot GDI CopyFromScreen không chụp được surface DirectX của Flutter (trắng) — không phải bug app.

---

## 6. Dependencies & External Resources

### Key Dependencies
- flutter_riverpod ^2.6.1 — state management (manual providers)
- window_manager ^0.4.3 — kích thước/min size cửa sổ
- file_selector ^1.0.3 · desktop_drop ^0.5.0 — mở file / kéo-thả
- path_provider ^2.1.5 · path ^1.9.0 — appdata paths
- shared_preferences ^2.3.4 — settings + recent files
- flutter_tts ^4.2.0 — WinRT SpeechSynthesizer (ja-JP / zh-CN, offline)
- collection ^1.19.0

### External APIs / Services
- LittleKai-server (tùy chọn): đăng nhập admin + publish/pull delta từ điển chung. URL lưu trong Cài đặt; mặc định local `http://localhost:5000`, build production có thể đặt `--dart-define=LITTLEKAI_SERVER_URL=...`.
- Chỉ lúc dev (`dart run tool/build_simp2jp.dart`): OpenCC STCharacters.txt + JPShinjitaiCharacters.txt (GitHub raw), Himeyama/joyo-kanji joyo2021.txt, aknm21/jinmeiyo-kanji — kết quả đã commit vào assets.
- vocabflip (format export): `D:\Dev\NodeJS\alpha-studio\tools\vocabflip` — validate cần `version`, `decks[].name`, `decks[].source_language`; card cần `front`+`back`, reading → `front_phonetic`.

---

## 7. Important Notes for Claude

### When making changes to:
- **Repair pipeline / dict_parser:** VALUE KHÔNG ĐỔI 1 BYTE là bất biến tuyệt đối; mọi thay đổi phải chạy `flutter test test/repair_pipeline_test.dart` + `dart run tool/export_jp.dart` để verify trên dữ liệu thật.
- **Binary cache:** đổi format → tăng `BinaryCache.version` (cache cũ tự invalid).
- **Engine:** giữ chữ ký `translate(String, {TranslationMode mode})` — v2 sẽ cắm AiTranslationEngine cùng interface.
- **Assets mappings:** không sửa `simp2jp.tsv` tay — sửa build script hoặc `simp2jp_overrides.tsv` rồi chạy lại `dart run tool/build_simp2jp.dart`.
- **File gốc QuickTranslator_Jap:** tuyệt đối không ghi đè; chỉ xuất `*_JP.txt`.

### Testing checklist:
- [ ] `flutter analyze` sạch
- [ ] `flutter test` pass (91 tests; integration tự skip nếu thiếu dữ liệu thật)
- [ ] Nếu đụng repair/parser: `dart run tool/export_jp.dart` verify OK

### Don't forget to:
- Update this file's timestamp and session number
- Follow CONVENTIONS.md

---

## 9. Quick Commands

```bash
# Development
flutter run -d windows             # chạy debug
flutter analyze                    # lint — phải sạch

# Build
flutter build windows --release    # exe tại build\windows\x64\runner\Release\

# Test
flutter test                       # toàn bộ 85 tests

# Tools (dev)
dart run tool/build_simp2jp.dart   # sinh lại assets mapping (cần mạng)
dart run tool/export_jp.dart       # repair + xuất *_JP.txt + verify dữ liệu thật
```

---

**📌 CRITICAL:** Read this entire file before making any changes to the project.

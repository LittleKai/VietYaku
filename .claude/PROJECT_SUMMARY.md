# Project Summary — VietYaku

**Last Updated:** 2026-07-15
**Session:** #1 — Initial build (7 phases) + documentation setup

---

## 1. Project Overview

- **Type:** Desktop app (Windows) — dịch Nhật/Trung→Việt kiểu VietPhrase + công cụ sửa từ điển JP, thay thế QuickTranslator_Jap (WinForms). Offline thuần, không AI ở v1.
- **Tech Stack:** Flutter 3.44.2, Dart ^3.12, Material 3
- **Package Manager:** pub (flutter pub)
- **i18n:** None (UI tiếng Việt cố định)
- **State Management:** Riverpod 2 — manual providers (Notifier/AsyncNotifier), KHÔNG codegen
- **Styling:** Material 3, `ColorScheme.fromSeed(indigo)`
- **Deployment:** `flutter build windows --release` → exe độc lập tại `build\windows\x64\runner\Release\vietyaku.exe` (đã verify chạy standalone)

Dữ liệu nguồn (KHÔNG ghi đè): `C:\Users\XEON\My Drive\JP CN Tool\QuickTranslator_Jap\` — VietPhrase.txt (131.556 dòng), LacViet.txt (69.527), Names.txt (1.960), ChinesePhienAmWords.txt (11.501), Pronouns.txt (30). UTF-8 BOM, format `key=nghĩa1/nghĩa2`.

---

## 2. File Structure

### Key Directories
```
VietYaku/
├── CLAUDE.md, .claude/             # docs hệ thống (summary, conventions, fixed bugs, setup report)
├── assets/mappings/                # simp2jp.tsv (3.932 + 69 ambiguous), jp_valid_kanji.txt (3.030), simp2jp_overrides.tsv (soạn tay)
├── tool/                           # build_simp2jp.dart (sinh assets, cần mạng), export_jp.dart (CLI repair + verify)
├── lib/
│   ├── main.dart                   # window_manager (1200×760, min 1000×640), SharedPreferences override, ProviderScope
│   ├── app.dart                    # MaterialApp M3 + HomeShell (NavigationRail + IndexedStack 3 tab)
│   ├── core/                       # cjk.dart, app_paths.dart, fnv_hash.dart, tts_service.dart
│   ├── features/
│   │   ├── dictionary/             # domain (dict_type, phrase_dictionary) · data (dict_parser, binary_cache, dictionary_loader, dictionary_repository, user_dict_service) · application (dictionaries_provider)
│   │   ├── translation/            # domain (translation_engine, token, reading_extractor) · application (translation_controller, lookup_controller, saved_words_provider, recent_files_provider) · presentation (translate_screen, source_pane, result_pane, lacviet_panel)
│   │   ├── repair/                 # domain (jp_repair_pipeline, simp2jp_table, repair_report) · application (repair_controller) · presentation (repair_screen, repair_preview)
│   │   └── settings/               # settings_provider, settings_screen
│   └── shared/widgets/             # tts_button, entry_edit_dialog
└── test/                           # 71 tests (10 file; integration dữ liệu thật tự skip nếu thiếu path)
```

### Critical Files
| File | Purpose | Notes |
|------|---------|-------|
| `lib/features/translation/domain/translation_engine.dart` | Engine greedy longest-match | Chữ ký `translate()` chừa sẵn cho AiTranslationEngine v2 |
| `lib/features/dictionary/data/binary_cache.dart` | Format cache `.vydc` | Header: magic/version/FNV-1a/size/mtime/count |
| `lib/features/dictionary/data/dictionary_loader.dart` | Load qua `Isolate.run` | Invalidation: so size trước, lệch mtime mới hash |
| `lib/features/repair/domain/jp_repair_pipeline.dart` | Sửa key: space + simp→JP, dedupe | VALUE KHÔNG ĐỔI 1 BYTE |
| `lib/features/dictionary/data/dictionary_repository.dart` | Load 6 dict + overlay | `*_JP.txt` trong appdata tự ưu tiên hơn file nguồn |
| `tool/build_simp2jp.dart` | Sinh assets mapping | OpenCC JPShinjitaiCharacters map NGƯỢC chiều — đã đảo (xem IMPORTANT_FIXED_BUGS.md) |

---

## 3. Architecture & Patterns

### Component Structure
Feature-first: mỗi feature chia `domain/` (thuần Dart, không Flutter) · `data/` (IO, parse, cache) · `application/` (Riverpod providers/controllers) · `presentation/` (widgets). Widget dùng `ConsumerWidget`/`ConsumerStatefulWidget`.

### State Management
- Riverpod manual: `NotifierProvider` (settings, translation, lookup, repair, recent files), `AsyncNotifierProvider` (dictionaries, saved words), `FutureProvider` (appPaths, ttsService, simp2jpTable).
- `sharedPreferencesProvider` override trong `main()` sau `SharedPreferences.getInstance()`.
- Engine: `HashMap<String,String>` + `maxLenByFirstUnit: Map<int,int>` per dict (key = UTF-16 code unit đầu). Tie-break UserDict > Names > VietPhrase. Fallback chữ Hán đơn → ChinesePhienAmWords; kana/lạ → passthrough.

### Data Flow
settings (paths) → dictionaries_provider → DictionaryRepository.loadAll (6 file song song, mỗi file 1 `Isolate.run`: cache `.vydc` hợp lệ → decode, không thì parse text + ghi cache) → LoadedDictionaries.engine → translation_controller.translate → tokens → ResultPane RichText (TapGestureRecognizer per token) → lookup_controller → LacVietPanel.

### Repair Flow
RepairScreen → pick file → preview per-line (Isolate.run, 50 dòng đổi đầu tiên) → Run (`Isolate.spawn` + progress SendPort, kết quả qua `Isolate.exit`) → RepairReport → export `*_JP.txt` (UTF-8 BOM CRLF cạnh gốc + copy appdata + xóa .vydc cũ) → reload providers.

### Storage (appdata = `getApplicationSupportDirectory()`)
`cache/` (.vydc) · `dictionaries/` (*_JP.txt, UserDict.txt, UserNames.txt) · `saved_words.json`.

---

## 4. Active Features & Status

| Feature | Status | Files Involved | Notes |
|---------|--------|----------------|-------|
| Core engine + parser | ✅ Done | translation_engine, dict_parser, phrase_dictionary | Dịch 10k ký tự ~60ms |
| Binary cache .vydc + isolate loader | ✅ Done | binary_cache, dictionary_loader | Cold 1,28s → warm 0,45s (5 file thật) |
| Màn hình Dịch 3 cột + click-lookup + reading + TTS | ✅ Done | translate_screen, source_pane, result_pane, lacviet_panel, reading_extractor, tts_service | TTS thiếu voice → disable + tooltip |
| JP repair pipeline + RepairScreen | ✅ Done | jp_repair_pipeline, simp2jp_table, repair_controller, repair_screen | VietPhrase: 13.317 space, 81.299 chữ converted |
| UserDict/UserNames overlay | ✅ Done | user_dict_service, entry_edit_dialog, dictionary_repository | Sửa nghĩa áp dụng ngay, không đụng file gốc |
| Clipboard watcher | ✅ Done | source_pane | Poll 1s; verify tay (không có test tự động) |
| Recent files | ✅ Done | recent_files_provider, source_pane | Tối đa 10 |
| Lưu từ + export vocabflip | ✅ Done | saved_words_provider, lacviet_panel | JSON deck v1.0, đã test khớp validateImportData |
| Settings + copy kết quả + release build | ✅ Done | settings_screen, result_pane | exe standalone verified |

**Verify end-to-end:** `dart run tool/export_jp.dart` → VietPhrase_JP.txt (187.419 entries) + LacViet_JP.txt (103.632) cạnh file gốc; hết key `覚 悟`/`军`, value nguyên vẹn từng byte; dịch Nhật match dài, dịch Trung có fallback phiên âm. `flutter test` 71 pass + `flutter analyze` sạch.

---

## 5. Known Issues & TODOs

### 🔴 High Priority
- (không có)

### 🟡 Medium Priority
- [ ] Clipboard watcher chỉ verify tay — cân nhắc test với TestDefaultBinaryMessenger nếu sửa vùng này.

### 🟢 Low Priority / Nice to Have (Backlog v2 — KHÔNG làm v1)
- [ ] Furigana per-token cho kanji ngoài từ điển (cần MeCab, không có port Dart thuần).
- [ ] AiTranslationEngine (chữ ký `translate()` đã chừa sẵn).
- [ ] Fuzzy match / gợi ý sửa key còn sót.

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
- Không có ở runtime (offline thuần).
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
- [ ] `flutter test` pass (71 tests; integration tự skip nếu thiếu dữ liệu thật)
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
flutter test                       # toàn bộ 71 tests

# Tools (dev)
dart run tool/build_simp2jp.dart   # sinh lại assets mapping (cần mạng)
dart run tool/export_jp.dart       # repair + xuất *_JP.txt + verify dữ liệu thật
```

---

**📌 CRITICAL:** Read this entire file before making any changes to the project.

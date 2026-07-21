# Project Summary — VietYaku

**Last Updated:** 2026-07-21
**Session #24:** Giải quyết lỗi chạy codegraph index bị treo/chặn: (1) Thêm `.codegraph/` vào `.gitignore` để ngăn chặn việc quét các file nhị phân của SQLite (`codegraph.db`, `codegraph.db-shm`, `codegraph.db-wal`) gây ra lỗi encoding "bytes are not valid utf8"; (2) Tạo cấu hình `codegraph.json` loại trừ (`exclude`) thư mục từ điển `data/` chứa hơn 1.2 triệu dòng text để tăng tốc độ indexer.
**Session #23:** Tùy chọn auto-sync + gom nút "Cập nhật từ điển" vào Cài đặt: (1) thêm setting `autoSyncDictionary` (bool, mặc định TẮT, key `dictionarySync.autoSync`) trong `settings_provider.dart` + setter `setAutoSyncDictionary`; (2) khi bật, `app.dart` initState kéo `sync()` cả hai ngôn ngữ JP+CN tuần tự lúc khởi động (sync() chặn chạy song song nên phải await lần lượt; lỗi mạng mỗi mode nuốt qua try/catch rồi kéo mode tiếp theo); (3) section "Từ điển chung" trong Settings giờ hiện trên MỌI nền tảng (bỏ gate `!Platform.isAndroid`), thêm hàng switch auto-sync + nút "Cập nhật từ điển" (gọi `sync(currentMode)`); (4) gỡ nút "Cập nhật từ điển" khỏi menu bar tab Dịch (`translate_screen.dart`) — dọn `dictionarySyncProvider` import, `LayoutBuilder`/`Spacer` thừa. `flutter analyze` sạch, tests liên quan pass.
**Session #22:** Đồng bộ từ điển tự động khi đủ 10 sửa đổi: `DictionarySyncController.stageLocalEdit` đếm tổng pending entries (cả 2 mode JP/CN, cả 2 kind VietPhrase/LạcViệt) sau mỗi lần lưu; đạt ngưỡng `_autoPublishThreshold = 10` thì tự gọi `publishPending()` (không cần bấm nút Update thủ công); ngưỡng tự reset về 0 mỗi lần publish thành công nên tính theo "mỗi 10 sửa đổi mới". Nút Update thủ công vẫn hoạt động như cũ để gửi sớm hơn ngưỡng. `flutter analyze` sạch, `flutter test test/dictionary_sync_test.dart` 9 pass.
**Session #21:** Thiết kế và thay thế icon ứng dụng mới (Minimalist Origami): (1) Thay thế logo hiển thị trong ứng dụng `assets/branding/app_icon.png` (1024x1024); (2) Tạo file Windows `.ico` đa kích thước (16x16 đến 256x256) tại `windows/runner/resources/app_icon.ico`; (3) Sinh và thay thế các launcher icon Android trong thư mục `android/app/src/main/res/mipmap-*` (từ 48x48 đến 192x192). `flutter analyze` sạch.
**Session #20:** Tự động kiểm tra cập nhật qua GitHub Releases: (1) module `features/update/` (domain/data/application/presentation) — `AppVersion` parse/so sánh semver, `GitHubReleaseApi.fetchLatestRelease()` (404 → chưa có release), `UpdateController` (Notifier) tự kiểm tra lúc khởi động (cache 24h, không chặn UI), nút "Kiểm tra ngay" + toggle `autoCheckUpdates` trong Cài đặt, "bỏ qua bản này"; (2) Windows: tải ZIP → giải nén → sinh script `.bat` chờ app thoát, thay thế thư mục cài đặt, khởi động lại, spawn detached rồi `exit(0)`; (3) Android: tải `.apk` → `open_filex`, fallback mở trang GitHub Release nếu chưa có asset `.apk` (thực trạng hiện tại — build Android đang tắt); thêm quyền `REQUEST_INSTALL_PACKAGES`. Test mới `app_version_test.dart`, `github_release_api_test.dart`. `flutter test` 157 pass, `flutter analyze` sạch. Chưa test được luồng tải/cài thật vì repo chưa có release nào.
**Session #19:** Hoàn thiện tương tác và EPUB theo AI Translation Bridge: (1) popup tra nhanh bám dòng active, tự nằm dưới dòng gần đầu panel hoặc trên dòng gần cuối để không che nội dung; (2) dialog sửa từ giữ chiều cao khung tự nhiên nhưng ô Nghĩa cao 6–10 dòng, Hủy/Lưu dùng context của route nên không còn lỗi deactivated ancestor; (3) EPUB nằm dưới Cài đặt, parse/export dùng entry-point top-level qua `compute` nên không capture State/ScrollController; tự nhận diện JP/CN/KR/VI/EN và sách Nhật có đủ ba chế độ furigana giống dự án tham chiếu; (4) chuột phải cụm VietPhrase chỉ chèn nghĩa, không active/tô đỏ. `flutter test` 139 pass, `flutter analyze --no-pub` sạch.
**Session #18:** Menu tra/sửa + popup từ điển + EPUB converter: (1) ô Nguồn và vùng chọn VietPhrase dùng menu riêng có icon; ô Nguồn chỉ hiện các lệnh sửa theo quyền, Names và tra online, không còn Copy/Cut/Paste/Select all; dialog sửa từ cao hơn; (2) active cụm từ ô Nguồn hiện popup tối đa 2 loại từ điển (mặc định Lạc Việt, cho phép tắt), mục đã hiện trong popup được ẩn khỏi ô Nghĩa; (3) thêm tab EPUB, đọc spine/OPF, bỏ furigana và xuất CSV/XLSX `id,text`, MD/DOCX/TXT trong isolate; (4) sửa crash `Scrollbar has no ScrollPosition` bằng controller dùng chung; thêm test parser/export/settings/scrollbar. `flutter test` 133 pass, `flutter analyze --no-pub` sạch.
**Session #17:** Quyền sửa từ điển theo admin + Update thủ công: (1) chuột phải cụm VietPhrase chỉ chèn nghĩa vào ô Bản dịch, không active/tô đỏ cụm; (2) phiên admin lưu `username + JWT` trong SharedPreferences (không lưu mật khẩu), tự khôi phục khi mở app và xóa khi logout/401; (3) admin sửa trực tiếp lớp VietPhrase/Lạc Việt cục bộ, non-admin dùng UserDict, Names vẫn local; (4) sửa admin vào hàng đợi `PendingVietPhrase/PendingLacViet_<mode>.txt`, chỉ upload cả hai ngôn ngữ khi bấm `Update` trong Cài đặt; pull server không ghi đè mục đang chờ. Test sync tăng thêm 2 case; `flutter test` 126 pass, analyze sạch.
**Session #16:** Dropdown setting cho phát âm kana từ SudachiDict & loại bỏ hiển thị đường dẫn trong từ điển chung. (1) Đổi `sudachiReadings` từ bool sang enum `SudachiReadingsMode` (lựa chọn: `sudachiFirst` (mặc định), `jaViFirst` (như hiện tại), `disabled` (không dùng)), đổi UI từ switch sang DropdownMenu; (2) Loại bỏ `(data/jp, data/cn trong dự án)` khỏi phần mô tả phần Từ điển trong Cài đặt; (3) Thêm unit test `test/sudachi_readings_settings_test.dart` verify cả 3 chế độ.
**Session #15:** Sudachi P2/P3 (nghiên cứu: `docs/NGHIEN_CUU_SUDACHI.md`, trạng thái §5): (1) chuẩn hoá halfwidth katakana ｱｲｳ/ｶﾞ→fullwidth trước khi tra + offset map về văn bản gốc (`translation/domain/jp_input_normalizer.dart`, gọi trong TranslationController); (2) gộp run số kanji không match → số Ả Rập 三百二十五→325 (`translation/domain/kanji_numeral.dart`, run ≥2 token hanViet/unmatched liền kề); (3) `tool/build_sudachi_assets.dart` (cần mạng, zip cache `build/sudachi_raw/`) sinh `data/jp/SudachiVariants.txt` (~13,7k biến thể okurigana — chỉ nhận key chứa chữ Hán hoặc thuần katakana ≥2, xem IMPORTANT_FIXED_BUGS 2026-07-19; merge DƯỚI VietPhrase trong loadAll) + `data/jp/SudachiReadings.txt` (~44k phát âm kana, fallback ô Nghĩa sau Nhật Việt; field `LoadedDictionaries.sudachiReadings`). 4 setting mới trong Cài đặt (mặc định bật, chỉ mode Nhật): `normalizeHalfwidthKana`, `joinKanjiNumerals`, `sudachiVariants` (đổi → nạp lại dict qua dictionariesProvider watch), `sudachiReadings`. (4) Category ký tự kiểu char.def (mục 2.7): `lib/core/cjk.dart` thêm enum `CjkCharCategory` + `charCategoryOf(cp)` + `categoryRunsOf(text)` + `kanjiNumericCodeUnits`; `kanji_numeral.dart` dùng làm membership — nền cho P1 2.3 (gộp katakana OOV). Test mới `test/sudachi_p2_test.dart`, `test/cjk_category_test.dart` (122 tests tổng, analyze sạch). P1 Sudachi (gộp katakana OOV, trường âm, yomigana) chưa làm.
**Session #14:** Tách giao diện khỏi Cài đặt: tạo tab "Giao diện" (appearance_screen.dart) nằm giữa Dịch và Cài đặt, chuyển cỡ chữ/font, màu Katakana, hiển thị (bracketSingleMeaning, keepSpecialQuotes) sang đó. Bỏ chọn ngôn ngữ mặc định trong Cài đặt — mode tự nhớ lần cuối qua setMode persist prefs. NavigationRail 3 tab: Dịch | Giao diện | Cài đặt.
**Session #12:** Ô VietPhrase: chuột phải (không tô đen) vào cụm MATCHED → paste nghĩa DƯỚI CON TRỎ vào ô Bản dịch (đa nghĩa "[a/b/c]" lấy đúng nghĩa bị nhấn; chữ ngoài cụm/hán-kanji ngoài từ điển → không paste; không menu khi không tô đen; bỏ auto-paste click trái). Vị trí nhấn từ Listener + `renderEditable.getPositionForPoint` (Windows chuột phải không dời caret khi đã focus — xem IMPORTANT_FIXED_BUGS); tiêu thụ vị trí sau xử lý + luôn ẩn toolbar (chống paste lặp / bị toggleToolbar nuốt). Chuột phải khi tô đen → menu gọn 3 mục "Thêm/Sửa (VietPhrase/Lạc Việt/Names)" — nhãn theo key có sẵn hay chưa, key = source CJK của token trong vùng tô đen; dialog nhận `title`/`initialMeaning`; mục admin publish giữ khi đăng nhập. Ngoặc kép CJK: 「」﹁﹂｢｣ luôn → `"`; 『』《》〈〉〝〞〟﹃﹄ GIỮ NGUYÊN theo setting `keepSpecialQuotes` (mặc định bật, tắt → chuyển `"`); ngoặc giữ nguyên được tính là dấu mở/đóng (không chèn space) và "trong suốt" khi xét viết hoa. Viết hoa xuyên qua nháy/ngoặc mở (`『[hành/đi]` đầu hàng → `『[Hành/đi]`). Setting `bracketSingleMeaning` (mặc định bật): tab đa nghĩa bọc `[ ]` cả cụm 1 nghĩa (`Token.displayAllWith`). TokenTextView → ConsumerStatefulWidget; test mới test/token_display_rules_test.dart (98 tests).

---

## 1. Project Overview

- **Type:** App đa nền tảng (Windows desktop + Android) — dịch Nhật/Trung→Việt kiểu VietPhrase + công cụ sửa từ điển JP, thay thế QuickTranslator_Jap (WinForms). Dịch chính offline; có thêm tính năng online tùy chọn: tra nghĩa Mazii/Google Dịch và tab Google Translate (endpoint gtx + fallback crawl translate.google.com/m). Android: chỉ dịch + TTS; ẩn Sửa từ điển/đồng bộ file (desktop-only).
- **Tech Stack:** Flutter 3.44.2, Dart ^3.12, Material 3
- **Package Manager:** pub (flutter pub)
- **i18n:** None (UI tiếng Việt cố định)
- **State Management:** Riverpod 2 — manual providers (Notifier/AsyncNotifier), KHÔNG codegen
- **Styling:** Material 3, hệ thiết kế tập trung `lib/core/theme/app_theme.dart` (`AppTheme.light`/`.dark`, seed indigo `0xFF4F46E5`, font chrome Segoe UI, ~15 component theme cho dialog/ô nhập/dropdown/tab/nút/rail/card/tooltip/snackbar/slider/menu). Theme tối tự theo hệ điều hành (`ThemeMode.system`). Màu tô nổi + token Names qua `ThemeExtension AppSemanticColors` (sáng/tối riêng).
- **Deployment:** Windows: `flutter build windows --release` → exe độc lập tại `build\windows\x64\runner\Release\vietyaku.exe`. Android: `flutter build apk --release` (org `com.littlekai.vietyaku`) — từ điển đi kèm dạng assets nên APK/exe lớn thêm ~130MB.

Dữ liệu từ điển bundle trong dự án (commit git), mỗi ngôn ngữ một bộ tại `data/jp/` và `data/cn/` — đường dẫn hardcode (`defaultDataDir` trong settings_provider), không còn UI chọn file trong Cài đặt:
- `data/jp/` (nguồn Drive QuickTranslator_Jap, đã repair simp→JP): VietPhrase.txt (187.419 — bản `_JP` repair), LacViet.txt (103.632 — bản `_JP`), Names.txt, JaViDict.txt (172.321), + ThieuChuu/Babylon/cedict_ts.u8/ChinesePhienAm*/Pronouns, SudachiVariants.txt (13.677 — biến thể→value VietPhrase, sinh bởi tool/build_sudachi_assets.dart), SudachiReadings.txt (43.996 — từ=kana đọc).
- `data/cn/` (nguồn `D:\Software\QuickTranslator\Quick Translator Chinese\Data`): VietPhrase.txt (690.007), LacViet.txt (66.450), Names.txt, ZhViDict.txt (161.194), + bộ chung như trên.
- JaViDict/ZhViDict generate từ SQLite của VocabFlip bằng `tool/export_vocabflip_dicts.py` (chạy 1 lần, conda py312), value escape `\n\t` như LacViet.
- Nguồn gốc (KHÔNG ghi đè): Drive `JP CN Tool\QuickTranslator_Jap` và `D:\Software\QuickTranslator\`.

---

## 2. File Structure

### Key Directories
```
VietYaku/
├── CLAUDE.md, .claude/             # docs hệ thống (summary, conventions, fixed bugs, setup report)
├── codegraph.json                  # cấu hình loại trừ file/folder khỏi CodeGraph indexer
├── docs/                            # nghiên cứu/roadmap; NGHIEN_CUU_DINH_HUONG_PHAT_TRIEN.md, NGHIEN_CUU_SUDACHI.md
├── data/jp/, data/cn/              # bộ từ điển bundle theo ngôn ngữ (commit git, ~123MB)
├── assets/mappings/                # simp2jp.tsv (3.932 + 69 ambiguous), jp_valid_kanji.txt (3.030), simp2jp_overrides.tsv (soạn tay)
├── tool/                           # build_simp2jp.dart (sinh assets, cần mạng), export_jp.dart (CLI repair + verify), export_vocabflip_dicts.py (sinh JaViDict/ZhViDict.txt từ DB VocabFlip), build_sudachi_assets.dart (sinh data/jp/SudachiVariants+SudachiReadings từ SudachiDict raw, cần mạng)
├── lib/
│   ├── main.dart                   # window_manager (1200×760, min 1000×640), SharedPreferences override, ProviderScope
│   ├── app.dart                    # MaterialApp M3 + HomeShell (NavigationRail + IndexedStack 4 tab: Dịch, EPUB, Giao diện, Cài đặt)
│   ├── core/                       # cjk.dart, app_paths.dart, fnv_hash.dart, tts_service.dart, google_translate.dart (gtx + fallback crawl /m), theme/app_theme.dart (design system + AppSemanticColors)
│   ├── features/
│   │   ├── dictionary/             # domain (dict_type, phrase_dictionary) · data (dict_parser, binary_cache, dictionary_loader, dictionary_repository, user_dict_service) · application (dictionaries_provider)
│   │   ├── dictionary_sync/        # domain shared entry · typed HTTP API · merge overlay · Riverpod admin session/sync controller
│   │   ├── epub_converter/         # đọc EPUB spine/OPF + xuất CSV/XLSX/MD/DOCX/TXT; UI chọn file/xem trước/lưu
│   │   ├── translation/            # domain (translation_engine, token, reading_extractor) · data (mazii_api) · application (translation_controller + currentModeProvider, lookup_controller, token_selection, viet_draft — controller dùng chung ô Bản dịch) · presentation (translate_screen: 2 cột kéo được + lưu tỷ lệ, menu bar, source_pane + hover tô đỏ, result_pane chỉ VietPhrase + tab Google Dịch, viet_pane — ô Bản dịch Việt luôn trống, han_viet_pane, token_text_view — chuẩn hoá dấu câu/toàn-hình + menu chèn nghĩa, lacviet_panel + nhãn từ điển có màu + nút tra online)
│   │   ├── repair/                 # domain (jp_repair_pipeline, simp2jp_table, repair_report) · application (repair_controller) · presentation (repair_screen, repair_preview)
│   │   └── settings/               # settings_provider, settings_screen (thuật toán/TTS/repair/sync/dict), appearance_screen (cỡ chữ+font/màu kana/hiển thị)
│   └── shared/widgets/             # tts_button, entry_edit_dialog
└── test/                           # 139 tests (21 file; integration dữ liệu thật tự skip nếu thiếu path)
```

### Critical Files
| File | Purpose | Notes |
|------|---------|-------|
| `lib/features/translation/domain/translation_engine.dart` | Engine greedy longest-match | Chữ ký `translate()` chừa sẵn cho AiTranslationEngine v2 |
| `lib/features/translation/domain/jp_input_normalizer.dart` | Halfwidth katakana → fullwidth trước khi tra (mode Nhật) | BẮT BUỘC remap token về offset gốc bằng `toOriginal` |
| `lib/features/translation/domain/kanji_numeral.dart` | Gộp run số kanji không match → số Ả Rập | Chỉ run ≥2 token hanViet/unmatched liền kề; parse fail giữ nguyên |
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
- Đồng bộ từ điển chung chỉ áp dụng cho VietPhrase/Lạc Việt: `GET /api/glossary/sync` kéo các trang delta bằng opaque cursor (public); `POST` publish entry qua JWT admin. `username + JWT` lưu SharedPreferences để khôi phục phiên (không lưu mật khẩu; logout/401 xóa phiên). Admin sửa cục bộ vào `SharedVietPhrase/SharedLacViet_<mode>.txt` và hàng đợi `PendingVietPhrase/PendingLacViet_<mode>.txt`; chỉ bấm `Update` mới upload các mục chờ của cả Nhật/Trung. Cursor lưu riêng theo mode; pull delta xong re-apply pending để không mất sửa đổi chưa upload. Non-admin dùng UserDict; UserNames luôn local.
- Engine: `HashMap<String,String>` + `maxLenByFirstUnit: Map<int,int>` per dict (key = UTF-16 code unit đầu). Tie-break UserDict > Names > VietPhrase. Fallback chữ Hán đơn → ChinesePhienAmWords; kana/lạ → passthrough.
- Engine options (constructor, chữ ký `translate()` không đổi): `TranslationAlgorithm` — `leftToRight` (mặc định) / `longestPhrase` (cụm dài toàn văn đặt trước, khe trống dịch trái→phải chặn biên) / `longestPhrase4` (chỉ cụm ≥4 code unit vào vòng global); `prioritizeNames` — tiered: dict đứng trước có match (bất kỳ độ dài) thắng dict sau (UserDict ngắn vẫn thắng cụm dài — cố ý). Settings áp dụng ở lần Dịch kế tiếp.
- Token giữ `rawValue` (value dict nguyên bản); `meaning`/`display`/`displayAll` là getter — đổi tab một nghĩa/đa nghĩa chỉ đổi render, không re-translate.
- `dictionariesProvider` watch `currentModeProvider` (đổi Nhật/Trung → nạp lại bộ dict của mode, cache .vydc giữ nhanh) + `settingsProvider.select(dictPathsFor(mode))` — đổi thuật toán không reload dict. LƯU Ý: không được watch `translationControllerProvider` từ dictionariesProvider (vòng phụ thuộc Riverpod — xem IMPORTANT_FIXED_BUGS.md); mode tách riêng ở `currentModeProvider`.

### Data Flow
settings (paths) → dictionaries_provider → DictionaryRepository.loadAll (12 dict chính + UserNames local + 2 shared overlay, tải song song qua `Isolate.run`; cache `.vydc` hợp lệ → decode, không thì parse text + ghi cache) → shared VietPhrase/Lạc Việt đè entry cùng key trong file bundle → LoadedDictionaries.engineWith(algorithm, prioritizeNames) → translation_controller.translate → tokens + hanVietTokens → TokenTextView: nháy chuột → lookup; chuột phải không tô đen → paste nghĩa vào ô Bản dịch nhưng không đổi active/highlight; chuột phải khi tô đen → admin sửa VietPhrase/Lạc Việt cục bộ và xếp hàng Update, non-admin sửa UserDict, Names luôn local.

### Layout màn hình Dịch (kiểu QuickTranslator, tham khảo .claude/image.png)
Menu bar trên cùng (chọn Nhật/Trung + Dán & Dịch). Trái (flex 2): tabs [Nguồn | Hán Việt] qua TabBar + IndexedStack (giữ state SourcePane) trên, LacVietPanel ("Nghĩa", có nút tra online) dưới. Phải (flex 3): ResultPane với tabs [VietPhrase một nghĩa | VietPhrase (đa nghĩa) — mặc định | Google Dịch (tab tạo khi bấm nút, dịch online cả đoạn)] — 1 TokenTextView duy nhất, đổi tab chỉ đổi `textOf` (display/displayAll). Nút chỉnh cỡ chữ + font các ô nằm ở NavigationRail trái.

### Repair Flow
RepairScreen → pick file → preview per-line (Isolate.run, 50 dòng đổi đầu tiên) → Run (`Isolate.spawn` + progress SendPort, kết quả qua `Isolate.exit`) → RepairReport → export `*_JP.txt` (UTF-8 BOM CRLF cạnh gốc + copy appdata + xóa .vydc cũ) → reload providers.

### Storage (appdata = `getApplicationSupportDirectory()`)
`cache/` (.vydc) · `dictionaries/` (*_JP.txt, UserDict.txt, UserNames.txt, SharedVietPhrase_*.txt, SharedLacViet_*.txt, PendingVietPhrase_*.txt, PendingLacViet_*.txt) · `saved_words.json`.

---

## 4. Active Features & Status

| Feature | Status | Files Involved | Notes |
|---------|--------|----------------|-------|
| Core engine + parser | ✅ Done | translation_engine, dict_parser, phrase_dictionary | Dịch 10k ký tự ~60ms |
| Binary cache .vydc + isolate loader | ✅ Done | binary_cache, dictionary_loader | Cold 1,28s → warm 0,45s (5 file thật) |
| Màn hình Dịch 3 cột + click-lookup + reading + TTS | ✅ Done | translate_screen, source_pane, result_pane, lacviet_panel, reading_extractor, tts_service | TTS thiếu voice → disable + tooltip |
| Chọn giọng đọc + tốc độ TTS | ✅ Done | tts_service (voicesFor/speak voiceKey+rate), settings_provider (ttsVoiceJa/Zh, ttsSpeechRate), settings_screen (_TtsSettings), tts_button | Giọng theo ngôn ngữ (Nhật/Trung, '' = tự động) + tốc độ 0.1–1.0, lưu prefs, "Nghe thử" |
| Nền tảng Android | ✅ Done | android/*, main.dart (guard window_manager + seed), app_paths (seedBundledData), pubspec (assets data/jp,cn), settings_screen (ẩn repair/sync) | Từ điển seed từ assets → app storage lần đầu; AndroidManifest queries TTS_SERVICE |
| JP repair pipeline + RepairScreen | ✅ Done | jp_repair_pipeline, simp2jp_table, repair_controller, repair_screen | VietPhrase: 13.317 space, 81.299 chữ converted |
| UserDict/UserNames overlay | ✅ Done | user_dict_service, entry_edit_dialog, dictionary_repository | Sửa nghĩa áp dụng ngay, không đụng file gốc |
| Đồng bộ VietPhrase/Lạc Việt chung | ✅ Done | dictionary_sync/*, dictionary_repository, entry_edit_dialog, token_text_view, translate_screen, settings_screen | Mọi app pull delta; phiên admin persist username+JWT (không lưu mật khẩu); admin sửa local + pending, nút Update thủ công HOẶC tự động khi đủ 10 sửa đổi pending (cả 2 mode+kind gộp lại, `_autoPublishThreshold` trong dictionary_sync_controller); auto-sync khi mở app (setting `autoSyncDictionary`, mặc định tắt) + nút "Cập nhật từ điển" gom trong section Settings (không còn ở menu bar tab Dịch); non-admin dùng UserDict, Names local |
| Bộ dict theo ngôn ngữ (data/jp, data/cn) | ✅ Done | settings_provider, dictionary_repository, dictionaries_provider, currentModeProvider | Đổi mode → reload bộ dict tương ứng |
| Menu bar Nhật/Trung + Dịch + Dán & Dịch | ✅ Done | translate_screen (_MenuBar), translation_controller.translate/pasteAndTranslate, source_pane.sourceDraftProvider | Nút Dịch dịch nội dung ô Nguồn (đọc sourceDraftProvider) |
| Chỉnh cỡ chữ + font các ô | ✅ Done | appearance_screen, settings_provider.paneTextStyle | Trong tab Giao diện; áp cho Nguồn/Kết quả/Nghĩa/ô Việt, lưu prefs |
| Tra nghĩa online trong ô Nghĩa | ✅ Done | mazii_api, google_translate, lookup_controller.fetchOnlineMeaning, lacviet_panel | Nhật: Mazii (miss → Google); Trung: Google Dịch (Hanzii v2 mã hóa response nên không dùng) |
| Tab Google Dịch cả đoạn | ✅ Done | result_pane, core/google_translate | gtx endpoint; fallback crawl translate.google.com/m |
| Lưu từ + export vocabflip | ❌ Removed (session #3) | — | saved_words_provider.dart còn trên đĩa nhưng không được import (user tự xóa nếu muốn) |
| Settings + copy kết quả + release build | ✅ Done | settings_screen, appearance_screen, result_pane | exe standalone verified |
| Layout tabs kiểu QT + VietPhrase đa nghĩa | ✅ Done | translate_screen, result_pane, token_text_view | Đổi tab không re-translate; hàng chọn Nhật/Trung nằm TRÊN tabs Nguồn/Hán Việt |
| Tab Hán Việt toàn văn | ✅ Done | han_viet_pane, translation_controller | Tính cùng lượt dịch |
| Thuật toán dịch (Trái→phải / Cụm dài / Cụm dài ≥4) + Ưu tiên Name | ✅ Done | translation_engine, settings_provider, settings_screen | Áp dụng lần Dịch kế |
| Chọn kiểu caret + tô nổi đỏ đồng bộ 3 pane | ✅ Done | token_selection, source_pane (_HighlightTextEditingController), token_text_view (SelectableText.rich) | Nháy chuột ô Nguồn/kết quả → chọn cụm, highlight 2 chiều |
| Ô Nghĩa đa từ điển + popup tra nhanh | ✅ Done | lookup_controller (LookupSection), lacviet_panel, source_pane, settings_provider | Popup ở Nguồn tối đa 2 loại, mặc định Lạc Việt; tự đặt trên/dưới dòng active để không che nội dung; mục popup không lặp trong ô Nghĩa |
| Sửa từ điển từ toolbar chuột phải | ✅ Done | source_pane, token_text_view, icon_context_menu, entry_edit_dialog, lacviet_panel | Menu có icon; admin sửa VietPhrase/Lạc Việt, non-admin UserDict, Names local; ô Nguồn có thêm tra online; secondary-tap chèn nghĩa không active |
| Chuyển đổi EPUB | ✅ Done | epub_converter/*, app.dart | Đọc OPF/spine qua `compute` top-level; nhận diện JP/CN/KR/VI/EN; sách Nhật có giữ hết/bỏ hết/chỉ bỏ Hiragana; xuất CSV/XLSX `id,text`, Markdown, DOCX, TXT |
| Scrollbar settings có controller | ✅ Done | settings_layout.dart, settings_scrollbar_test.dart | Scrollbar/ListView dùng chung controller, không còn lỗi thiếu ScrollPosition |
| Hệ thiết kế tập trung (theme sáng/tối) | ✅ Done | core/theme/app_theme.dart, app.dart, token_text_view, source_pane, settings_screen (DropdownMenu) | Component theme cho dialog/ô nhập/dropdown/tab/nút/rail/card/tooltip/snackbar/slider; dark tự theo OS; font dropdown nâng lên DropdownMenu M3 |
| Tự động kiểm tra cập nhật (GitHub Releases) | ✅ Done | features/update/* (app_version, github_release_api, download_file, update_controller, update_dialog), app.dart, settings_provider, settings_screen | Windows: tải ZIP → giải nén → `.bat` tự thay thư mục cài đặt + khởi động lại; Android: tải `.apk` → open_filex, fallback mở trang GitHub Release nếu chưa có asset `.apk` (thực trạng hiện tại); silent check lúc khởi động (cache 24h) + nút "Kiểm tra ngay" + toggle + bỏ qua bản này |

**Verify end-to-end:** `dart run tool/export_jp.dart` → VietPhrase_JP.txt (187.419 entries) + LacViet_JP.txt (103.632) cạnh file gốc; hết key `覚 悟`/`军`, value nguyên vẹn từng byte; dịch Nhật match dài, dịch Trung có fallback phiên âm. `flutter test` 139 pass + `flutter analyze --no-pub` sạch; Windows release build gần nhất thành công.

---

## 5. Known Issues & TODOs

### 🔴 High Priority
- (không có)

### 🟡 Medium Priority
- [ ] Chuột phải token (chèn nghĩa không active + menu edit theo quyền) chưa có widget test (hit-test TextSpan với kSecondaryButton phức tạp) — verify tay.
- [ ] Từ điển bundle dạng assets (`data/jp`, `data/cn`) áp cho MỌI nền tảng → APK Android + build Windows đều +~130MB; mobile copy sang app storage lần đầu tốn thêm ~130MB đĩa. pubspec không cho khai báo assets theo nền tảng nên chấp nhận (đổi lại Windows portable hơn). Nếu cần giảm: seed data cho Android bằng cơ chế riêng (asset pack / tải server).
- [ ] Luồng tải + tự cài đặt bản cập nhật (Windows `.bat` self-update, Android `open_filex`) mới chỉ verify qua unit test (`app_version_test.dart`, `github_release_api_test.dart`) + `flutter analyze`/`flutter test` sạch — CHƯA test được với release thật vì repo chưa có release nào (`GET .../releases/latest` trả 404). Cần verify tay lần release đầu tiên.

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
- archive ^4.0.9 · xml ^7.0.1 · html ^0.15.6 — đọc EPUB và tạo/kiểm tra OOXML DOCX/XLSX
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
- [ ] `flutter test` pass (139 tests; integration tự skip nếu thiếu dữ liệu thật)
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
flutter test                       # toàn bộ 139 tests

# Tools (dev)
dart run tool/build_simp2jp.dart   # sinh lại assets mapping (cần mạng)
dart run tool/export_jp.dart       # repair + xuất *_JP.txt + verify dữ liệu thật
```

---

**📌 CRITICAL:** Read this entire file before making any changes to the project.

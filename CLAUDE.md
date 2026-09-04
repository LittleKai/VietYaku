# Instructions for Claude Code — VietYaku

Flutter Windows desktop app: dịch Nhật/Trung → Việt kiểu VietPhrase (greedy longest-match) + công cụ sửa từ điển tiếng Nhật bị hỏng của QuickTranslator_Jap. Dịch chính offline, KHÔNG dùng AI. Tính năng online tùy chọn: tra nghĩa Mazii/Google Dịch trong ô Nghĩa, tab Google Translate (gtx + fallback crawl `/m`), và tra cứu/phân tích một từ bằng AI (người dùng tự nhập API key) — AI chỉ tra từ, không tham gia dịch cả văn bản.

---

## 🎯 CORE PRINCIPLE

Read PROJECT_SUMMARY.md FIRST, not the entire codebase.
Update documentation AFTER every change.

---

## BEFORE ANY TASK

### 1. Read (in order):
```
.claude/PROJECT_SUMMARY.md     → Project state, architecture, active features
Specific files user mentioned  → Only if needed for implementation
```

### 2. DON'T Read:
- ❌ Entire `lib/` folder
- ❌ All features to "understand project"
- ❌ Files already summarized in PROJECT_SUMMARY.md

### 3. Context cần biết:
- Flutter 3.44.2 tại `D:\3.Flutter\flutter\bin\flutter.bat` (có trong PATH).
- Từ điển app dùng: `data/jp/` và `data/cn/` trong dự án (mỗi ngôn ngữ một bộ; UTF-8 BOM, format `key=nghĩa1/nghĩa2`). **KHÔNG commit git** — `.gitignore` có `data/*`, chỉ chừa `data/cn/LuatNhan.txt`; chúng đi theo bản phát hành qua `assets:` trong pubspec (release → `<exe>/data/flutter_assets/data/`).
- Nguồn gốc (KHÔNG ghi đè): `C:\Users\XEON\My Drive\JP CN Tool\QuickTranslator_Jap\` và `D:\Software\QuickTranslator\` (bộ Quick Translator Chinese/for Japanese).

---

## Quyết định thiết kế đã chốt (không bàn lại)

- Engine tra: `HashMap<String,String>` + index `maxLenByFirstUnit: Map<int,int>` per dict (key = UTF-16 code unit đầu). Không trie, không DB.
- Cache: binary snapshot custom `.vydc` (không SQLite/Isar/Hive). Load qua `Isolate.run()`, transfer bằng `Isolate.exit`.
- State: Riverpod manual providers (không codegen), `AsyncNotifier` cho dict load.
- Navigation: NavigationRail + IndexedStack 3 tab. Không GoRouter, không Dio, không codegen.
- Độ dài đo bằng UTF-16 code unit; surrogate pair advance theo rune.
- Ưu tiên dict cùng độ dài match: UserDict > Names > VietPhrase.
- Repair: VALUE KHÔNG ĐỔI 1 BYTE, chỉ sửa key; xuất `*_JP.txt` UTF-8 BOM CRLF cạnh file gốc + copy vào appdata. KHÔNG ghi đè file gốc.
- Xóa space trong key: khi CẢ HAI ký tự liền kề đều KHÔNG phải ASCII alphanumeric `[A-Za-z0-9]` (không phải quy tắc "hai phía là CJK").
- Phồn→giản CHỈ mode Trung (mode Nhật quy giản thể là phá kanji Nhật). Chuyển ngầm ngay trước khi tra — `translate()`, `LookupController.lookup()`, `startOnlineLookup()` — ô Nguồn giữ nguyên chữ người dùng dán vào. Bảng `assets/mappings/trad2simp.tsv` sinh từ `data/cn/cedict_ts.u8` bằng `tool/build_trad2simp.dart` (không cần mạng), CHỈ nhận cặp 1 UTF-16 code unit → 1 code unit để `sourceStart` của token còn khớp văn bản gốc. Generator áp invariant "đích không bao giờ là nguồn của cặp khác" — cedict có mục đảo cột/lệch ký tự sinh ra cặp ngược chiều (`尔→爾`) và chuỗi (`託→托` mà `托→度`), bỏ mắt xích nhẹ ký hơn. Setting `convertTraditionalToSimplified`, mặc định bật.
- Cùng setting đó, mode Trung còn quy luôn KEY của mọi dict CN về giản thể lúc nạp (`normalizeKeysToSimplified` trong `dictionary_loader`, chạy trong isolate trước khi ghi cache). Key giản thể có sẵn LUÔN thắng; key phồn thể bị bỏ vì mọi đường tra đều đã quy văn bản về giản thể nên chúng không bao giờ khớp được. Cache `.vydc` của bộ đã quy giản mang `Trad2SimpTable.signature` trong tên file → sinh lại tsv thì cache cũ tự bị bỏ qua. KHÔNG ghi đè `data/cn/`.
- Bộ dict theo ngôn ngữ: mode Nhật → `data/jp`, mode Trung → `data/cn`; đổi mode reload qua `currentModeProvider` (KHÔNG watch translationController từ dictionariesProvider — vòng phụ thuộc). Override `*_JP.txt` appdata chỉ áp dụng mode Nhật.
- Online: không key/API trả phí — Mazii (**chỉ dùng được cho Nhật**: `/api/search` bỏ qua tham số `dict`, hỏi `cnvi` vẫn trả mục của từ điển Nhật với `phonetic` là kana và `pinyin` rỗng → `MaziiApi` loại kết quả có cách đọc kana khi `dict != 'javi'`, coi như miss. Đã kiểm chứng bằng gọi API trực tiếp, không phải dữ liệu cũ), Jisho (Nhật→Anh, JMdict), Weblio 日中中日辞典 (Nhật→Trung, crawl thẻ `<meta name="description">` của `cjjc.weblio.jp/content/<từ>` — thân trang đầy quảng cáo và đổi layout liên tục), 有道词典 (Trung→Anh, `dict.youdao.com/jsonapi?q=<từ>&dicts=[["ce"]]` — không key, tự quy phồn→giản, có pinyin + từ loại. KHÔNG dùng `/suggest`: đó là gợi ý ô tìm kiếm, chỉ hiểu giản thể và thiếu phần lớn mục từ), Google gtx + fallback crawl `translate.google.com/m`. Hanzii v2 mã hóa response → không dùng. Đã loại: MOJi辞書 (Parse API nội bộ, `search_v3` đã bỏ, không auth thì trả rỗng), 沪江小D (chặn request), Baidu/Tencent + API dịch trả phí của Youdao (bắt đăng ký key, mà vẫn là máy dịch), 金山词霸 `dict-co.iciba.com` (bắt key).
- **Chỗ ghi dữ liệu (`AppPaths`) — KHÔNG dùng AppData/Application Support trên desktop:**
  - release → `<thư mục chứa .exe>/userdata/` (`cache/` + `dictionaries/`), app chạy kiểu portable
  - debug/profile → `<repo>/data/userdata/` (đã nằm trong `.gitignore` vì `data/` bị ignore)
  - Android/iOS là ngoại lệ duy nhất: không có thư mục cạnh exe ghi được → vẫn `getApplicationSupportDirectory()`
  - `AppPaths.init()` tự chép `dictionaries/` từ AppData cũ sang chỗ mới một lần, chỉ khi thư mục mới còn trống
  - File từ điển nguồn (`VietPhrase.txt`, `LacViet.txt`, … trong `data/jp`, `data/cn`) vẫn chỉ đọc, KHÔNG ghi đè
  - **Ngoại lệ duy nhất — `data/<lang>/generated/`:** phiên admin ghi `AiDict`, `AiEntries`, `OnlineDict`, `VietPhrase_<mode>` vào đây để chúng được đóng gói theo bản phát hành (assets `data/<lang>/**`). Thư mục con riêng nên không lẫn với file nguồn; an toàn khi cập nhật vì self-update Windows dùng `xcopy /E /Y` (ghi đè, không xoá file thừa) và `seedLanguagePack` trên mobile cũng chép đè chứ không dọn thư mục. Chưa đăng nhập admin thì vẫn ghi vào `userdata/dictionaries/`; app nạp cả hai, mục cá nhân đè mục dùng chung.
- Ô Nghĩa hiện loại nào và theo thứ tự nào do người dùng đặt trong Cài đặt, **riêng JP và CN** (`MeaningPanelLayout` — `order` đầy đủ + tập `hidden` tách rời để tắt/bật không mất vị trí; lưu `lookup.meaningPanel.<mode>` dạng `name:0|1`). `orderMeaningSections` sắp xếp ỔN ĐỊNH theo vị trí loại nên nhiều mục cùng loại giữ nguyên thứ tự `lookup()` sinh ra; nhãn lạ vẫn hiện, xếp cuối. Thứ tự mặc định = `LookupDictionaryType.defaultPanelOrder`, khớp đúng thứ tự `lookup()` sinh section.
- `AiEntries` là từ điển tra được, không chỉ phục vụ engine dịch: `lookup()` sinh section `AI tách từ`, và nó có mặt trong Search Center lẫn danh sách bật/tắt của ô Nghĩa.
- **Mọi chỗ GHI `Global Glossary.json` phải đi qua `glossaryServiceProvider`, không tự `GlossaryService(dir)`.** Provider gắn sẵn hook xếp hàng `PendingGlossary_<mode>.txt` để sửa đổi glossary của phiên admin lên được `POST /api/glossary/terms/sync` (kind riêng `glossaryTerm`, không lẫn từ điển dịch) — AI_Translation_Bridge trên máy khác kéo delta công khai về merge vào `Glossary/<JP|CN>/Global Glossary.json` của nó. Tự dựng service là mất đường đồng bộ, im lặng. Chỗ chỉ ĐỌC (`find`, `readAll`, `hasGlossaryFor`) dựng trực tiếp vẫn được. Chiều đẩy là một chiều: VietYaku publish, không kéo về. Ngưỡng auto-publish (`maybeAutoPublish`, 10 mục) đếm CHUNG hàng đợi từ điển và glossary, nhưng chỉ kích hoạt khi ghi **lẻ một mục** — ghi hàng loạt vẫn chờ admin bấm Update, đúng quy ước `stageLocalEditsBulk`.
- **Xóa từ phải gỡ cả overlay AI/online, không chỉ SharedVietPhrase.** `stageLocalDelete` gọi `UserDictService.removeGeneratedEntry` để bỏ key khỏi `VietPhrase_<mode>.txt` + `AiEntries_<mode>.txt` (cả userdata lẫn `generated/` nếu là admin) TRƯỚC khi xếp hàng xóa ở dict chung; chạy cho cả người dùng thường vì overlay cá nhân của họ nằm trong userdata. KHÔNG đụng `AiDict`/`OnlineDict` — xóa mục dịch không có nghĩa là vứt luôn kết quả đã tra.
- Tra AI trả **JSON** (`AiLookupResult`), không phải Markdown: ngắn token, không có ví dụ sử dụng, KHÔNG có phiên âm/romaji/pinyin/âm Hán Việt, và `sub_entries` không được lưu vào `AiDict` (đã thành mục từ điển riêng rồi, giữ lại chỉ làm ô Nghĩa hiện thừa mục "Đã thêm vào từ điển"). App tự render nên bố cục ổn định. `AiDict_<mode>.txt` lưu JSON compact một dòng; mục cũ dạng Markdown vẫn đọc được (`aiBodyToMarkdown` trả nguyên văn). Hiển thị bằng `flutter_markdown_plus` (bản gốc `flutter_markdown` đã discontinued, API giống hệt).
- `sub_entries` AI trả về được ghi thành mục từ điển riêng: `AiEntries_<mode>.txt` (vào engine dịch, xếp SAU VietPhrase nên không đè từ điển gốc), và những key VietPhrase chưa có thì thêm luôn vào overlay `VietPhrase_<mode>.txt`. Prompt bắt AI đưa về thân từ ngắn nhất (`チャラい` → `チャラ`) để greedy longest-match nhận ra được, và bỏ trợ từ/đuôi ngữ pháp đứng một mình.
- **Tra online/AI xong PHẢI thêm key vào overlay VietPhrase, nếu không mục vừa lưu không bao giờ tra lại được.** Từ phải tra online chính là từ VietPhrase chưa có → engine cắt nó thành từng chữ (`再入荷` → `[再, 入荷]`) → token sinh ra không bằng key đã lưu → `onlineDict.entries[word]` luôn trượt. Có mục trong VietPhrase thì engine mới cắt đúng cụm. `tool/backfill_lookup_overlay.dart` bù cho dữ liệu lưu trước khi có cơ chế này.
- Ba rào chắn BẮT BUỘC trước khi đưa nghĩa tra được vào VietPhrase (`dict_entry_filter.dart`) — value VietPhrase chèn thẳng vào bản dịch nên sai là hỏng cả đoạn:
  1. `isWordLikeEntry` — chỉ từ/cụm từ (≤10 rune, không dấu câu, không khoảng trắng). Cả câu/mệnh đề bị loại.
  2. `meaningMatchesWord` — nguồn online tra MỜ: gõ `再入荷` trả mục của `再入`, gõ `一愣` trả `eleven; 11`. Chỉ nhận khi headword nguồn trả về đúng bằng từ đã tra.
  3. `vietnameseLookupLabels` — chỉ Mazii trả nghĩa Việt; Jisho/Youdao (Anh) và Weblio (Trung) không được vào từ điển dịch tiếng Việt.
- OnlineDict CHỈ lưu nghĩa từ từ điển thật (Mazii, Jisho, Weblio, Youdao) — cờ `saved` trong `OnlineLookupTask`. Kết quả máy dịch (Google Việt) chỉ hiện trên dialog + ô Nghĩa của lần tra đó, không ghi vào file — nghĩa máy dịch theo ngữ cảnh, lưu lại sẽ làm bẩn từ điển.

## Giới hạn đã biết

- Không sửa được biến thể cần ngữ cảnh: `后→後` khi 后 là ký tự hợp lệ tiếng Nhật (quy tắc vàng: ký tự đã nằm trong jp_valid_kanji thì không convert — 芸/后/叶/国/学 giữ nguyên). Các case này ghi vào RepairReport.ambiguous.
- Furigana per-token cho kanji ngoài từ điển cần MeCab — không có port Dart thuần → backlog v2.

---

## AFTER ANY TASK

### Update PROJECT_SUMMARY.md

**Always update:**
- `Active Features & Status`: update feature status (⏳→🚧→✅) if changed
- `Known Issues & TODOs`: mark [x] completed TODOs, add new current TODOs/issues

**Update if changed:**
- `File Structure` / `Dependencies & External Resources`: update new files, folders, or dependencies

> PROJECT_SUMMARY.md chỉ phản ánh **trạng thái hiện tại** của dự án. Không dùng PROJECT_SUMMARY.md để ghi lịch sử thay đổi, changelog, recent changes, hoặc bug-fix log. Nếu đã fix một bug quan trọng, khó phát hiện, hoặc dễ tái phát, ghi lại ngắn gọn trong `.claude/IMPORTANT_FIXED_BUGS.md` để tránh tái phạm; không ghi bug fix thông thường và không cập nhật file này sau mọi task.

---

## READING PRIORITY

```
1. ALWAYS  → PROJECT_SUMMARY.md
2. IF NEEDED → Files mentioned in user request
3. RARELY  → Other source files
```

---

## SPECIAL CASES

**"Review entire project"** → Exception: read all files, create/update full summary
**Summary outdated?** → Ask user before proceeding
**Major refactor** → Update `File Structure` and `Architecture & Patterns` completely
**PROJECT_SUMMARY.md không tồn tại?** → Treat như "Review entire project" — đọc toàn bộ, tạo mới

---

## 🔒 SECURITY RULES

- Tuyệt đối **không** ghi mật khẩu, JWT admin, hay bất kỳ credential thật nào vào file bị Git theo dõi — kể cả `lib/`, `test/`, fixture, comment, hay `.md`. Trong code/docs chỉ dùng placeholder (`<JWT>`, `admin@example`).
- Phiên admin (`dictionary_sync`): SharedPreferences chỉ lưu `username + JWT`, **không bao giờ lưu mật khẩu**; logout/401 phải xóa phiên. Giữ nguyên hợp đồng này khi sửa `dictionary_sync_controller`.
- Không `debugPrint`/log token, header `Authorization`, hay response đăng nhập — kể cả khi debug tạm; xóa log trước khi kết thúc task.
- URL server đặt qua `--dart-define=LITTLEKAI_SERVER_URL=...`, không hardcode URL production vào source.
- `.env` và `data/userdata/` đã nằm trong `.gitignore` — không gỡ, không commit dữ liệu người dùng thật (từ điển cá nhân, OnlineDict, cache `.vydc`).
- Giữ nguyên quyết định đã chốt: **không dùng API trả phí / API cần key**. Nếu một nguồn online mới bắt đăng ký key → loại, đừng nhúng key vào app.

---

## 🧪 TEST POLICY

- Mọi tính năng mới hoặc sửa lỗi **logic** trong `lib/features/*/domain/`, `lib/features/*/data/`, hoặc `lib/core/` bắt buộc phải có unit test tương ứng trong `test/` phủ case đó trước khi kết thúc session.
- Với bug fix: viết test tái hiện bug **trước**, rồi mới sửa.
- Đụng repair/parser: ngoài `flutter test`, phải chạy `dart run tool/export_jp.dart` để verify trên dữ liệu thật (bất biến VALUE KHÔNG ĐỔI 1 BYTE).
- Đụng `app_theme.dart`: invariant đang được khoá bởi `test/app_theme_test.dart` — sửa theme phải cập nhật/không phá test này.
- Thay đổi thuần `presentation/` (bố cục, màu, cỡ chữ) không bắt buộc test; verify tay và ghi vào SMOKE_TEST_CHECKLIST nếu là luồng chính.
- `flutter analyze` phải sạch trước khi kết thúc task.

---

## 📦 PHÁT HÀNH — HAI KÊNH SONG SONG

Mỗi bản release đi ra **hai nơi cùng lúc**, do skill `.claude/skills/build-and-release` lo:

| Kênh | Phục vụ | Nguồn |
|------|---------|-------|
| **GitHub Release** (`LittleKai/VietYaku`) | **Cập nhật trong app** — `lib/features/update/` gọi `releases/latest`, tự tìm asset chứa `windows` + đuôi `.zip` | Asset đính kèm release |
| **Backblaze B2** (bucket `alpha-studio`) | **Link tải trên web** — tool `giaiphapsangtao.com/studio/vietyaku` | `vietyaku-app/version.json` + `vietyaku-app/releases/VietYaku-windows-x64-v<version>.zip` |

- Cùng một file ZIP đi lên cả hai nơi; B2 thêm version vào tên object vì mọi bản nằm chung một prefix.
- `version.json` mang shape giống payload GitHub release (`tag_name`, `body`, `html_url`, `assets[]`) để backend Alpha Studio parse chung một kiểu.
- Phía web: `alpha-studio-backend` có `GET /api/vietyaku/releases/latest` fetch `version.json` rồi cache vào `SystemSetting` (key `vietyaku_latest_release`). Ra bản mới **không cần deploy lại** frontend hay backend.
- Đổi cấu trúc `version.json` hoặc tên object trên B2 → phải sửa cả `alpha-studio-backend/server/routes/vietyaku.js` và `alpha-studio/src/services/vietyakuReleaseService.ts` (repo `D:\Dev\NodeJS\alpha-studio`).
- Credential B2 (`B2_ACCESS_KEY_ID`, `B2_SECRET_ACCESS_KEY`, `B2_BUCKET_NAME`, `CDN_BASE_URL`) đọc từ `.env` — cùng giá trị với `alpha-studio-backend/.env`. **Không hardcode, không log, không commit.**

---

## 🗂️ Project Quick Reference

**Tech Stack:** Flutter 3.44.2 (Dart ^3.12) · Windows desktop · Riverpod 2 (manual providers) · Material 3 · flutter_markdown_plus (render nghĩa AI)

**Key Files:**
- `lib/features/translation/domain/translation_engine.dart` — engine greedy longest-match (chữ ký `translate()` chừa sẵn cho AiTranslationEngine v2)
- `lib/features/dictionary/data/binary_cache.dart` — format `.vydc` (magic/version/hash/size/mtime/count)
- `lib/features/dictionary/data/dictionary_loader.dart` — load qua `Isolate.run`, cache invalidation
- `lib/features/repair/domain/jp_repair_pipeline.dart` — sửa key (space + simp→JP), dedupe, report
- `tool/build_simp2jp.dart` — sinh lại assets/mappings (cần mạng, chỉ lúc dev)
- `tool/build_trad2simp.dart` — sinh `assets/mappings/trad2simp.tsv` từ `data/cn/cedict_ts.u8`
- `tool/export_jp.dart` — CLI repair + verify end-to-end trên dữ liệu thật

**Dev Commands:**
```bash
flutter analyze                    # phải sạch trước khi kết thúc task
flutter test                       # 487 tests (integration tự skip nếu thiếu dữ liệu thật)
flutter run -d windows             # chạy debug
flutter build windows --release    # build exe độc lập
dart run tool/build_simp2jp.dart   # sinh lại assets mapping (dev, cần mạng)
dart run tool/export_jp.dart       # xuất *_JP.txt + verify với dữ liệu thật
```

---

## 📝 Documentation Structure

```
VietYaku/
├── CLAUDE.md (this file)          # Instructions for Claude
└── .claude/
    ├── PROJECT_SUMMARY.md          # Detailed project state & architecture
    ├── CONVENTIONS.md              # Coding standards & patterns
    ├── IMPORTANT_FIXED_BUGS.md     # Important fixed bugs to avoid repeating
    ├── SMOKE_TEST_CHECKLIST.md     # Kiểm tra tay trên exe/APK trước khi release
    └── SETUP_REPORT.md             # Initial setup snapshot
```

---

## 💡 Notes for Claude

- Project dùng Riverpod manual providers + feature folders (domain/data/application/presentation) — theo đúng pattern sẵn có, không thêm codegen/GoRouter/DB.
- Ưu tiên: tính đúng của dữ liệu từ điển (value không đổi 1 byte, không ghi đè file gốc) > tốc độ > UI.
- When in doubt, ask before making structural changes.

---

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**📌 Remember:** Documentation = Single Source of Truth

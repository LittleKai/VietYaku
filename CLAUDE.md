# Instructions for Claude Code — VietYaku

Flutter Windows desktop app: dịch Nhật/Trung → Việt kiểu VietPhrase (greedy longest-match) + công cụ sửa từ điển tiếng Nhật bị hỏng của QuickTranslator_Jap. Dịch chính offline; tính năng online tùy chọn: tra nghĩa Mazii/Google Dịch trong ô Nghĩa, tab Google Translate (gtx + fallback crawl `/m`). Không AI.

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
- Từ điển app dùng: bundle trong dự án `data/jp/` và `data/cn/` (commit git, mỗi ngôn ngữ một bộ; UTF-8 BOM, format `key=nghĩa1/nghĩa2`).
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
- Phồn→giản CHỈ mode Trung (mode Nhật quy giản thể là phá kanji Nhật). Chuyển ngầm ngay trước khi tra — `translate()`, `LookupController.lookup()`, `startOnlineLookup()` — ô Nguồn giữ nguyên chữ người dùng dán vào. Bảng `assets/mappings/trad2simp.tsv` sinh từ `data/cn/cedict_ts.u8` bằng `tool/build_trad2simp.dart` (không cần mạng), CHỈ nhận cặp 1 UTF-16 code unit → 1 code unit để `sourceStart` của token còn khớp văn bản gốc. Setting `convertTraditionalToSimplified`, mặc định bật.
- Bộ dict theo ngôn ngữ: mode Nhật → `data/jp`, mode Trung → `data/cn`; đổi mode reload qua `currentModeProvider` (KHÔNG watch translationController từ dictionariesProvider — vòng phụ thuộc). Override `*_JP.txt` appdata chỉ áp dụng mode Nhật.
- Online: không key/API trả phí — Mazii (Nhật/Trung), Jisho (Nhật→Anh, JMdict), Weblio 日中中日辞典 (Nhật→Trung, crawl thẻ `<meta name="description">` của `cjjc.weblio.jp/content/<từ>` — thân trang đầy quảng cáo và đổi layout liên tục), 有道词典 (Trung→Anh, `dict.youdao.com/jsonapi?q=<từ>&dicts=[["ce"]]` — không key, tự quy phồn→giản, có pinyin + từ loại. KHÔNG dùng `/suggest`: đó là gợi ý ô tìm kiếm, chỉ hiểu giản thể và thiếu phần lớn mục từ), Google gtx + fallback crawl `translate.google.com/m`. Hanzii v2 mã hóa response → không dùng. Đã loại: MOJi辞書 (Parse API nội bộ, `search_v3` đã bỏ, không auth thì trả rỗng), 沪江小D (chặn request), Baidu/Tencent + API dịch trả phí của Youdao (bắt đăng ký key, mà vẫn là máy dịch), 金山词霸 `dict-co.iciba.com` (bắt key).
- **Chỗ ghi dữ liệu (`AppPaths`) — KHÔNG dùng AppData/Application Support trên desktop:**
  - release → `<thư mục chứa .exe>/userdata/` (`cache/` + `dictionaries/`), app chạy kiểu portable
  - debug/profile → `<repo>/data/userdata/` (đã nằm trong `.gitignore` vì `data/` bị ignore)
  - Android/iOS là ngoại lệ duy nhất: không có thư mục cạnh exe ghi được → vẫn `getApplicationSupportDirectory()`
  - `AppPaths.init()` tự chép `dictionaries/` từ AppData cũ sang chỗ mới một lần, chỉ khi thư mục mới còn trống
  - Bộ từ điển nguồn (`data/jp`, `data/cn`) vẫn chỉ đọc, không ghi đè
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

## 🗂️ Project Quick Reference

**Tech Stack:** Flutter 3.44.2 (Dart ^3.12) · Windows desktop · Riverpod 2 (manual providers) · Material 3

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
flutter test                       # 196 tests (integration tự skip nếu thiếu dữ liệu thật)
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

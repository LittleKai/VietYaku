# Instructions for Claude Code — VietYaku

Flutter Windows desktop app: dịch Nhật/Trung → Việt kiểu VietPhrase (greedy longest-match) + công cụ sửa từ điển tiếng Nhật bị hỏng của QuickTranslator_Jap. Offline thuần, không AI ở v1.

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
- Dữ liệu nguồn (KHÔNG ghi đè): `C:\Users\XEON\My Drive\JP CN Tool\QuickTranslator_Jap\` — VietPhrase.txt, LacViet.txt, Names.txt, ChinesePhienAmWords.txt, Pronouns.txt (UTF-8 BOM, format `key=nghĩa1/nghĩa2`).

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

## Giới hạn đã biết

- Không sửa được biến thể cần ngữ cảnh: `后→後` khi 后 là ký tự hợp lệ tiếng Nhật (quy tắc vàng: ký tự đã nằm trong jp_valid_kanji thì không convert — 芸/后/叶/国/学 giữ nguyên). Các case này ghi vào RepairReport.ambiguous.
- Furigana per-token cho kanji ngoài từ điển cần MeCab — không có port Dart thuần → backlog v2.

---

## AFTER ANY TASK

### Update PROJECT_SUMMARY.md

**Always update:**
- Top: `Last Updated` timestamp + session number
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
- `tool/export_jp.dart` — CLI repair + verify end-to-end trên dữ liệu thật

**Dev Commands:**
```bash
flutter analyze                    # phải sạch trước khi kết thúc task
flutter test                       # 83 tests (integration tự skip nếu thiếu dữ liệu thật)
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

# Initial Setup Report

**Generated:** 2026-07-15

---

## ✅ Setup Completed

### Files Created/Updated
- [x] CLAUDE.md (updated with comprehensive instructions)
- [x] .claude/PROJECT_SUMMARY.md
- [x] .claude/CONVENTIONS.md
- [x] .claude/IMPORTANT_FIXED_BUGS.md
- [x] .claude/SETUP_REPORT.md (this file)


## 📊 Project Analysis Summary

### Project Type
Desktop App (Windows) — dịch Nhật/Trung→Việt kiểu VietPhrase + công cụ sửa từ điển JP, thay thế QuickTranslator_Jap. Offline thuần.

### Tech Stack
**Primary:**
- Flutter 3.44.2 / Dart ^3.12 (Windows desktop)
- Riverpod 2 — manual providers, không codegen
- Material 3

**Supporting:**
- window_manager, file_selector, desktop_drop, path_provider, shared_preferences
- flutter_tts (WinRT SpeechSynthesizer offline)
- flutter_lints ^6

### Project Size
- Dart Source Files: 47 (lib: 35, test: 10, tool: 2)
- Lines of Code (Dart): ~3.619
- Tests: 71 (10 test files, gồm integration với dữ liệu thật tự skip nếu thiếu)
- Assets: 3 file mapping (simp2jp.tsv, jp_valid_kanji.txt, simp2jp_overrides.tsv)
- Configuration: pubspec.yaml, analysis_options.yaml, windows/ runner


## 🏗️ Architecture Overview

### Project Structure
Feature-first (`lib/features/{dictionary, translation, repair, settings}`), mỗi feature chia 4 layer: `domain/` (thuần Dart), `data/` (IO/parse/cache), `application/` (Riverpod), `presentation/` (widgets). `lib/core/` cho tiện ích chung, `lib/shared/widgets/` cho widget chéo feature, `tool/` cho script CLI dev.

### Key Patterns
- Engine tra: HashMap + index `maxLenByFirstUnit` per dict, greedy longest-match theo UTF-16 code unit, tie-break UserDict > Names > VietPhrase.
- Binary cache custom `.vydc` (FNV-1a + size/mtime invalidation) load qua `Isolate.run`.
- Repair pipeline pure-function (`repairFile`) chạy trong `Isolate.spawn` với progress qua SendPort.
- Overlay không phá hủy: `*_JP.txt`/UserDict/UserNames trong appdata tự ưu tiên hơn file nguồn.

### Data Flow
settings → dictionaries_provider (AsyncNotifier, load 6 dict song song trong isolates) → engine → translation_controller → tokens → ResultPane (RichText + tap) → lookup_controller → LacVietPanel (reading + TTS + Lưu từ).

## 📋 Key Patterns & Conventions Found

### Component Pattern
ConsumerWidget / ConsumerStatefulWidget, const constructors, dispose đầy đủ (controllers, timers, gesture recognizers), private widget prefix `_`.

### State Management
Riverpod manual: Notifier/AsyncNotifier + immutable state với copyWith; `select()` cho rebuild chọn lọc; SharedPreferences inject qua provider override trong main().

### Styling Approach
Material 3 mặc định (`ColorScheme.fromSeed(indigo)`), không CSS/theme custom; màu token theo dictType trong ResultPane.

### File Organization
By feature, trong feature by layer (domain/data/application/presentation). Chi tiết trong CONVENTIONS.md.


## 💡 Observations & Recommendations

### Strengths Identified
1. Domain logic thuần Dart tách hoàn toàn khỏi Flutter → 71 tests chạy nhanh, có cả integration với dữ liệu thật (tự skip khi thiếu).
2. Bất biến dữ liệu được bảo vệ nghiêm (value không đổi 1 byte, không ghi đè file gốc) và có test khóa lại.
3. Hiệu năng đạt yêu cầu có số đo: dịch 10k ký tự ~60ms, cache warm nhanh gấp ~2,8 lần cold.

### Areas for Potential Improvement
1. Clipboard watcher chưa có test tự động (poll 1s trong SourcePane) — có thể mock qua TestDefaultBinaryMessenger nếu vùng này thay đổi.
2. `_rebuildPreview` chạy `repairFile` từng dòng trên toàn file để tìm 50 diff — đủ nhanh hiện tại, nhưng nếu file lớn hơn nhiều lần thì nên early-exit theo block.

### High Priority Items (if any)
1. Không có — v1 hoàn chỉnh, test + analyze sạch, release exe đã verify.

### Consider for Future
1. Backlog v2 (đã ghi trong PROJECT_SUMMARY.md): furigana MeCab, AiTranslationEngine, fuzzy match key.

## 🎯 Next Steps

### Immediate Actions
1. Review all documentation for accuracy
2. Verify that all patterns in CONVENTIONS.md are correct
3. Test the workflow defined in CLAUDE.md

### For Next Development Session
1. Người dùng verify tay: TTS nghe thực tế (hoặc tooltip cài voice), clipboard watcher, import file export vào vocabflip.
2. Nếu phát hiện case convert sai khi dùng thật → thêm vào `simp2jp_overrides.tsv` rồi `dart run tool/build_simp2jp.dart`.

## 📝 Important Notes

### Project-Specific Context
- Dữ liệu nguồn nằm trong Google Drive folder (`C:\Users\XEON\My Drive\JP CN Tool\QuickTranslator_Jap\`) — sync có thể đổi mtime mà không đổi nội dung; cache .vydc đã xử lý (so hash khi mtime lệch). TUYỆT ĐỐI không ghi đè file gốc.
- OpenCC `JPShinjitaiCharacters.txt` map shinjitai→kyūjitai (ngược tên gọi) — xem IMPORTANT_FIXED_BUGS.md.
- Screenshot GDI (CopyFromScreen) không chụp được surface DirectX của Flutter — cửa sổ trắng là giả, không phải bug.

### Dependencies to Watch
- flutter_tts (WinRT): phụ thuộc voice cài trong Windows Settings; app đã xử lý disable + tooltip.
- Nguồn regenerate assets (GitHub raw của OpenCC/joyo/jinmeiyo) chỉ cần lúc dev.

### Known Limitations
- Quy tắc vàng: không convert ký tự đã hợp lệ JP → `后→後`/`干→幹` không sửa được theo ngữ cảnh (ghi vào RepairReport.ambiguous).
- ~34 ký tự ambiguous cố ý không resolve (复/舍/获/泛 + chữ hiếm).

## 🔄 Workflow Established

From now on, every Claude Code session should:

1. **Start:** Read `.claude/PROJECT_SUMMARY.md` — NOT the entire codebase
2. **Check:** `.claude/CONVENTIONS.md` for standards (if needed)
3. **Work:** Make requested changes
4. **Update:** PROJECT_SUMMARY.md (timestamp, `Active Features & Status`, `Known Issues & TODOs`)
5. **Record:** Add to `.claude/IMPORTANT_FIXED_BUGS.md` only when an important, hard-to-detect, or likely-to-recur bug should not be repeated


## 📚 Documentation System Ready

```
VietYaku/
├── CLAUDE.md                           # ← Main instructions (read first)
└── .claude/
    ├── PROJECT_SUMMARY.md              # ← Current state & architecture
    ├── CONVENTIONS.md                  # ← Coding standards
    ├── IMPORTANT_FIXED_BUGS.md         # ← Important fixed bugs
    └── SETUP_REPORT.md                 # ← This file
```

**Documentation system is ready to use! 🚀**

**Remember:**
- Read PROJECT_SUMMARY.md first, not the entire codebase
- Update PROJECT_SUMMARY.md after every change
- Follow conventions for consistency

**Setup completed on:** 2026-07-15
**Ready for development!** ✅

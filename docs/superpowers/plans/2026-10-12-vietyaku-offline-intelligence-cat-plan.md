# VietYaku Offline Intelligence & CAT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm phím tắt chọn nghĩa, project TXT với exact Translation Memory,
deinflector Nhật dạng prototype, và các rule hậu xử lý Trung có kiểm thử.

**Architecture:** Giữ translation engine HashMap và pipeline token hiện tại.
Phím tắt dùng `tokenSelectionProvider` + `vietDraftControllerProvider`; project
và TM là feature mới với JSON/JSONL IO; deinflector chỉ là fallback sau static
lookup; rule Trung chạy trong `TranslationRuleEngine` hiện có.

**Tech Stack:** Flutter 3.44.2, Dart 3.12, Riverpod manual providers,
`file_selector`, `dart:convert`, `dart:io`, không thêm package.

**Spec:** `docs/superpowers/specs/2026-10-12-vietyaku-offline-intelligence-cat-design.md`

## Global Constraints

- Không làm autosave phiên làm việc.
- Không nhúng Sudachi/MeCab runtime hoặc native dependency.
- Không đưa AI vào đường dịch mặc định.
- Không đổi format `.vydc` hoặc HashMap hot path.
- Không ghi đè file nguồn; mọi file project/overlay ghi atomic.
- Logic domain thuần Dart; IO ở `data/`; Riverpod ở `application/`; UI ở `presentation/`.
- Mọi logic mới/sửa phải có test và cuối task chạy `flutter analyze` + `flutter test`.

## Review Focus

- Phím số khi ô Bản dịch đang giữ caret nhưng token active nằm ở pane khác: phải chèn đúng caret, không làm mất selection.
- Token chỉ có một nghĩa, token unmatched, hoặc index > 9: không chèn nhầm nghĩa.
- Project có newline/UTF-8/BOM và target chứa ký tự JSON đặc biệt: mở/lưu không đổi dữ liệu.
- TM có duplicate source và source trùng nhưng target đang có chỉnh sửa: chỉ gợi ý bản reviewed, không ghi đè.
- Deinflector tạo candidate sai hoặc làm lệch UTF-16 span: fallback nguyên trạng và không crash.

### Task 1: Quick meaning switch

**Files:**
- Create: `lib/features/translation/domain/meaning_choice.dart`
- Create: `lib/features/translation/application/meaning_choice_controller.dart`
- Modify: `lib/features/translation/presentation/translate_screen.dart`
- Modify: `lib/features/translation/presentation/result_pane.dart`
- Modify: `lib/features/translation/presentation/token_text_view.dart`
- Test: `test/meaning_choice_test.dart`
- Test: `test/meaning_choice_widget_test.dart`

**Interfaces:**
- Consumes: `tokenSelectionProvider`, `translationControllerProvider`,
  `vietDraftControllerProvider`, `parseVietPhraseValue`.
- Produces: `MeaningChoiceController.choose(int index)`, and a scoped
  `Shortcuts`/`Actions` binding for `LogicalKeyboardKey.digit1` … `digit9`.

- [ ] **Step 1: Write failing domain tests** for extracting alternatives from a
  tiered VietPhrase value, including one meaning, multiple tiers, empty value,
  and index outside 1..9.
- [ ] **Step 2: Run** `flutter test test/meaning_choice_test.dart` and verify
  failure because the domain/controller does not exist.
- [ ] **Step 3: Implement** `MeaningChoice` and `MeaningChoiceController`.
  `choose(index)` must read the active token, select the flattened display text
  for that 1-based alternative, and call `insertIntoVietDraft` only when the
  index exists. It must not mutate `TranslationState` or dictionaries.
- [ ] **Step 4: Add keyboard bindings** around the translation screen. Bind only
  when a result token is active; let TextField editing keep priority when the
  draft field itself has focus.
- [ ] **Step 5: Add widget tests** for desktop keyboard focus, no-op cases, and
  insertion at a non-end caret.
- [ ] **Step 6: Run** `flutter test test/meaning_choice_test.dart test/meaning_choice_widget_test.dart`.
- [ ] **Step 7: Commit** `feat: add keyboard meaning selection`.

### Task 2: Project TXT and exact Translation Memory domain/data

**Files:**
- Create: `lib/features/project/domain/project_segment.dart`
- Create: `lib/features/project/domain/project_document.dart`
- Create: `lib/features/project/domain/sentence_segmenter.dart`
- Create: `lib/features/project/data/project_store.dart`
- Create: `lib/features/project/data/translation_memory_store.dart`
- Test: `test/project_segment_test.dart`
- Test: `test/sentence_segmenter_test.dart`
- Test: `test/project_store_test.dart`
- Test: `test/translation_memory_store_test.dart`

**Interfaces:**
- Produces `ProjectSegment` fields `segmentId`, `source`, `machineOutput`,
  `editedTarget`, `status`, `updatedAt`, `sourceHash`.
- Produces `SentenceSegmenter.split(String) -> List<String>`.
- Produces `ProjectStore.open(Directory)`, `save(ProjectDocument)`, and
  `TranslationMemoryStore.upsertReviewed(ProjectSegment)` /
  `lookupExact(String) -> String?`.

- [ ] **Step 1: Write failing model/segment tests** covering Japanese/Chinese
  punctuation, newline boundaries, empty text, and stable segment IDs.
- [ ] **Step 2: Run** the four new test files and verify they fail.
- [ ] **Step 3: Implement** immutable models and deterministic UTF-8 sentence
  segmentation without adding a dependency. Preserve source order and text.
- [ ] **Step 4: Write failing store tests** using a temp directory for JSON,
  JSONL, duplicate TM sources, escaped newlines, and atomic replacement.
- [ ] **Step 5: Implement** `ProjectStore` and `TranslationMemoryStore` using
  temp-file + flush + rename; reject malformed records with a typed error while
  leaving existing files intact.
- [ ] **Step 6: Run** all Task 2 tests and verify PASS.
- [ ] **Step 7: Commit** `feat: add project segments and exact translation memory`.

### Task 3: Project editor UI and TM suggestions

**Files:**
- Create: `lib/features/project/application/project_controller.dart`
- Create: `lib/features/project/presentation/project_screen.dart`
- Create: `lib/features/project/presentation/project_segment_editor.dart`
- Modify: `lib/app.dart`
- Modify: `lib/features/translation/presentation/translate_screen.dart`
- Modify: `lib/core/app_paths.dart`
- Test: `test/project_controller_test.dart`
- Test: `test/project_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 stores and `translationControllerProvider`.
- Produces: project open/save actions, segment review action, exact TM suggestion
  that never overwrites a non-empty edited target.

- [ ] **Step 1: Write failing controller tests** for opening a TXT source,
  creating segments with machine output, marking one segment reviewed, saving
  target TXT, and showing an exact TM suggestion.
- [ ] **Step 2: Run** `flutter test test/project_controller_test.dart` and verify
  failure.
- [ ] **Step 3: Implement** controller/provider state with explicit `open`,
  `save`, `setTarget`, `markReviewed`, and `applyTmSuggestion` actions.
- [ ] **Step 4: Add desktop project screen** using existing `file_selector`; keep
  mobile route hidden through `PlatformFeatures` if a folder picker is not
  available. Use a three-column segment editor and a reviewed status control.
- [ ] **Step 5: Add navigation entry and paths** without changing existing
  translation pane behavior.
- [ ] **Step 6: Add widget tests** for open/save controls, target preservation,
  and reviewed state.
- [ ] **Step 7: Run** Task 3 tests and `flutter analyze`.
- [ ] **Step 8: Commit** `feat: add TXT project editor and exact TM suggestions`.

### Task 4: Japanese deinflector fallback prototype

**Files:**
- Create: `lib/features/translation/domain/jp_deinflector.dart`
- Modify: `lib/features/translation/domain/translation_engine.dart`
- Modify: `lib/features/translation/domain/token.dart`
- Test: `test/jp_deinflector_test.dart`
- Modify: `test/engine_test.dart`

**Interfaces:**
- Produces `JapaneseDeinflectionCandidate` with `lemma`, `surfaceLength`, and
  immutable `rules` metadata.
- Produces `JapaneseDeinflector.deinflect(String) -> List<JapaneseDeinflectionCandidate>`.

- [ ] **Step 1: Write failing fixture tests** for common `た`, `ない`, `て`,
  passive, and causative forms plus UTF-16 span length.
- [ ] **Step 2: Run** `flutter test test/jp_deinflector_test.dart` and verify
  failure.
- [ ] **Step 3: Implement** a table-driven domain-only candidate generator with
  bounded candidate count and no Vietnamese grammar injection.
- [ ] **Step 4: Add optional fallback** to `TranslationEngine` after static
  lookup fails. Accept a candidate only when the lemma exists in the same
  dictionary priority chain; create a matched token whose source is the full
  inflected surface and whose raw value is the lemma entry.
- [ ] **Step 5: Add regression tests** proving static matches still win, unknown
  forms remain unmatched, and UTF-16 offsets remain source offsets.
- [ ] **Step 6: Run** deinflector and engine tests; record fixture precision in
  the task notes without enabling automatic grammar prefixes.
- [ ] **Step 7: Commit** `feat: add Japanese deinflection fallback prototype`.

### Task 5: Curated Chinese grammar rules

**Files:**
- Modify: `data/cn/LuatNhan.txt`
- Modify: `test/translation_rule_test.dart`
- Modify: `.claude/PROJECT_SUMMARY.md`
- Modify: `.claude/DESIGN_DECISIONS.md` only if a new invariant is introduced

- [ ] **Step 1: Add failing regression fixtures** for each proposed `的`, `把`,
  `被`, `了`, and `着` rule, including a negative example where the rewrite
  must not run.
- [ ] **Step 2: Run** `flutter test test/translation_rule_test.dart` and verify
  the new examples fail.
- [ ] **Step 3: Add the smallest rule set** to the existing rule file, keeping
  group names, ordering, and the current tester/trace behavior.
- [ ] **Step 4: Run** rule tests and verify no existing rule count/behavior
  regresses.
- [ ] **Step 5: Commit** `feat: refine Chinese post-processing rules`.

### Task 6: Full verification and documentation

- [ ] **Step 1:** Update `.claude/PROJECT_SUMMARY.md` status/details for each
  shipped chặng and keep autosave explicitly out of scope.
- [ ] **Step 2:** Run `flutter analyze`.
- [ ] **Step 3:** Run `flutter test`.
- [ ] **Step 4:** Run `D:/Dev/conda-envs/py312/python.exe .claude/guard_check.py`.
- [ ] **Step 5:** Review `git diff` to confirm unrelated working-tree edits were
  not changed.
- [ ] **Step 6:** Commit documentation/verification changes separately.

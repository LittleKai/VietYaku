# Important Fixed Bugs

**Last Updated:** 2026-07-17

---

## Purpose

This file records important bugs that were fixed and should not be repeated. Keep entries concise and actionable.

Record only high-impact, hard-to-detect, or likely-to-recur bugs. Do not record ordinary bug fixes, do not append entries after every task, and do not use this file as a changelog.

---

## Fixed Bugs

### 2026-07-15 - OpenCC JPShinjitaiCharacters.txt map NGƯỢC chiều tên gọi
- **Symptom:** Bảng simp2jp sinh ra sai — `历` compose ra `歷|曆` (kyūjitai) thay vì `歴|暦` (shinjitai); dict sửa xong vẫn chứa chữ cũ, khó phát hiện vì đa số cặp không qua stage shinjitai vẫn đúng (军→軍 vẫn OK).
- **Root Cause:** File OpenCC `JPShinjitaiCharacters.txt` có format `shinjitai<TAB>kyūjitai` (vd `暦\t曆`) — chiều key→value NGƯỢC với tên file gợi ý. Build script ban đầu đọc xuôi.
- **Fix:** `tool/build_simp2jp.dart` đảo chiều khi parse: `shinjitai[old] = shin` cho từng value; bổ sung cột kyūjitai của bảng jōyō (col2→col1) qua `putIfAbsent`.
- **Do Not Repeat:** Khi dùng bất kỳ dictionary file nào của OpenCC, kiểm chứng chiều mapping bằng vài entry cụ thể (vd 歴/歷, 暦/曆) trước khi compose — đừng tin tên file. Sau khi regenerate assets phải chạy `flutter test test/repair_pipeline_test.dart` (có test 骸骨骑士様… → 騎/異/掛).
- **Related Files:** `tool/build_simp2jp.dart`, `assets/mappings/simp2jp.tsv`

### 2026-07-17 - Riverpod CircularDependencyError khi dictionariesProvider watch translationController
- **Symptom:** Click token để tra nghĩa ném `CircularDependencyError` (bắt bởi gesture handler, debug mode) — app chạy bình thường cho tới khi lookup.
- **Root Cause:** `dictionariesProvider` watch `translationControllerProvider` (để lấy mode), trong khi `TranslationController.translate()` lại `ref.read(dictionariesProvider)` → Riverpod debug assert phát hiện vòng phụ thuộc (kể cả `read` cũng tính).
- **Fix:** Tách mode đang dịch ra `currentModeProvider` (Notifier riêng, chỉ đọc settings). `dictionariesProvider` watch provider này; `setMode` cập nhật cả hai.
- **Do Not Repeat:** Provider A đã bị B `read/watch` thì A không được watch B, kể cả qua `select`. Cần một phần state của B → tách phần đó ra provider riêng.
- **Related Files:** `translation_controller.dart` (currentModeProvider), `dictionaries_provider.dart`

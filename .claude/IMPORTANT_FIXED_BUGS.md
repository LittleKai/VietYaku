# Important Fixed Bugs

**Last Updated:** 2026-07-20

---

## Purpose

This file records important bugs that were fixed and should not be repeated. Keep entries concise and actionable.

Record only high-impact, hard-to-detect, or likely-to-recur bugs. Do not record ordinary bug fixes, do not append entries after every task, and do not use this file as a changelog.

---

## Fixed Bugs

### 2026-07-20 - `Isolate.run` trong State capture cả cây widget khi chuyển EPUB
- **Symptom:** Chọn EPUB ném `Illegal argument in isolate message`, thông báo lần theo `_EpubConverterScreenState`, `SettingsPage` và `ScrollController` dù dữ liệu đầu vào chỉ là bytes.
- **Root Cause:** Closure khai báo trong phương thức của `State` có thể capture ngầm `this`; isolate cố gửi toàn bộ object graph của widget, trong đó có các object native không sendable.
- **Fix:** Dùng entry-point top-level `parseEpubRequest`/`exportEpubRequest` với `compute` và request thuần dữ liệu; thêm test parse lẫn export thật qua isolate.
- **Do Not Repeat:** Tác vụ isolate từ widget phải truyền hàm top-level/static và payload thuần dữ liệu. Không đưa closure của `State`, `BuildContext`, controller hay notifier qua isolate.
- **Related Files:** `lib/features/epub_converter/domain/epub_converter.dart`, `lib/features/epub_converter/presentation/epub_converter_screen.dart`, `test/epub_converter_test.dart`

### 2026-07-20 - Dialog action dùng context của widget gọi đã bị deactive
- **Symptom:** Nút Hủy/Lưu trong dialog mở từ context menu báo `Looking up a deactivated widget's ancestor is unsafe` và không đóng dialog.
- **Root Cause:** Callback action giữ `BuildContext` của menu/widget gọi. Overlay context đó bị gỡ ngay sau khi mở dialog, nên `Navigator.of(context)` không còn hợp lệ.
- **Fix:** `showAppDialog` nhận `actionsBuilder(dialogContext)` và mọi action đóng bằng context thuộc chính route dialog; có widget test gỡ launcher trước khi bấm Hủy.
- **Do Not Repeat:** Callback sống lâu hơn overlay/menu mở nó phải dùng context của route/widget còn mounted, không capture context tạm của launcher.
- **Related Files:** `lib/shared/widgets/app_dialog.dart`, `lib/shared/widgets/entry_edit_dialog.dart`, `test/app_dialog_test.dart`

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

### 2026-07-18 - Flutter Windows accessibility_bridge AXTree crash (app tự tắt)
- **Symptom:** Log spam `[ERROR:...accessibility_bridge.cc(114)] Failed to update ui::AXTree, error: N will not be in the tree...` / `Nodes left pending by the update: ...` rồi `Lost connection to device` → app crash. Xuất hiện lúc khởi động và khi tra nghĩa online; số node đổi mỗi lần chạy.
- **Root Cause:** Bug engine Flutter Windows ở accessibility bridge — reconciliation cây semantics fail khi Windows AT poll (SelectableText.rich, SegmentedButton, NavigationRail, Tooltip đều có thể kích). KHÔNG sửa được bằng Dart, không phải lỗi widget cụ thể.
- **Fix:** Tắt cây semantics app-wide: `MaterialApp.builder: (c, child) => ExcludeSemantics(child: child ?? SizedBox.shrink())` trong `app.dart`. (Trước đó đã giữ `_OnlineLookupButton` không đổi loại widget khi loading — cần nhưng chưa đủ.)
- **Do Not Repeat:** Đừng đi tìm widget "thủ phạm" — đây là bug engine, blanket ExcludeSemantics là fix chuẩn. Đánh đổi: mất hỗ trợ screen-reader (chấp nhận cho desktop tool); chọn/copy text vẫn chạy. Nếu cần bật lại accessibility, phải nâng Flutter và test kỹ trên Windows.
- **Related Files:** `lib/app.dart` (MaterialApp.builder), `lacviet_panel.dart` (_OnlineLookupButton)


### 2026-07-18 - Android APK build fail: "Could not close incremental caches" (Kotlin/Windows)
- **Symptom:** `flutter build apk` fail exit 1, 3 plugin (flutter_tts, file_selector_android, shared_preferences_android) cùng lỗi `compileDebugKotlin` → `java.lang.Exception: Could not close incremental caches in ...\build\<plugin>\kotlin\compileDebugKotlin\...\class-fq-name-to-source.tab`. Code compile được — lỗi ở bước ĐÓNG incremental cache, không phải lỗi biên dịch.
- **Root Cause:** Bug Kotlin incremental compilation trên Windows (file `.tab` bị khoá / cache hỏng, thường do antivirus quét `build/` giữa chừng). Không phải lỗi code app.
- **Fix:** Thêm `kotlin.incremental=false` vào `android/gradle.properties` (bỏ bước incremental cache) + `flutter clean` để xoá cache hỏng, rồi build lại → OK (app-debug.apk 191MB).
- **Do Not Repeat:** Nếu lỗi tái diễn: đừng sửa code — chạy `flutter clean` rồi build lại; giữ `kotlin.incremental=false`. Cân nhắc loại trừ thư mục `build/` khỏi Windows Defender real-time scan.
- **Related Files:** `android/gradle.properties`

### 2026-07-19 - Chuột phải trong SelectableText trên Windows KHÔNG dời caret khi đã focus
- **Symptom:** Chuột phải vào từ trong ô VietPhrase để paste nghĩa: lần đầu đúng, các lần sau paste sai từ hoặc không làm gì (dùng caret/selection để xác định từ bị nhấn).
- **Root Cause:** Framework Flutter (`text_selection.dart`, `onSecondaryTap`): trên Windows/Linux chỉ gọi `selectPosition` khi field CHƯA có focus; đã focus thì chuột phải giữ nguyên selection cũ rồi `toggleToolbar()`. → selection lúc contextMenuBuilder chạy là vị trí click TRÁI trước đó, không phải chỗ chuột phải.
- **Fix:** `token_text_view.dart`: bọc `Listener.onPointerDown` ghi `event.position` khi `(event.buttons & kSecondaryMouseButton) != 0` vào state (`_secondaryTapPosition`, phải là StatefulWidget vì rebuild xảy ra giữa pointer-down và mở toolbar), rồi trong `contextMenuBuilder` map điểm nhấn → offset bằng `editableTextState.renderEditable.getPositionForPoint(...)`.
- **Do Not Repeat:** Muốn biết "từ nào bị chuột phải" trong SelectableText/TextField: KHÔNG đọc `textEditingValue.selection` — dùng vị trí pointer + `renderEditable.getPositionForPoint`. Lưu ý `&` với `!=` trong Dart: phải viết `(a & b) != 0`.
- **Related Files:** `lib/features/translation/presentation/token_text_view.dart`
### 2026-07-19 - SudachiVariants sinh key thuần hiragana → してくれ dịch thành [tứ/bốn] て [chín] れ
- **Symptom:** Sau khi merge `data/jp/SudachiVariants.txt`, chuỗi ngữ pháp kana bị dịch bậy: `してくれ` → `し`=[tứ/bốn], `く`=[chín] (trước đó kana không match giữ nguyên).
- **Root Cause:** SudachiDict chuẩn hoá cả CÁCH ĐỌC kana về kanji (surface `し` normalized `四`, `く` → `九`...). Tool build chỉ lọc "canonical có trong VietPhrase, variant chưa có" nên sinh 6.285 key thuần hiragana; engine greedy match kana đơn giữa chuỗi ngữ pháp — Sudachi phân giải case này bằng lattice theo ngữ cảnh, VietYaku greedy thì không.
- **Fix:** `tool/build_sudachi_assets.dart` thêm `safeVariant()`: biến thể phải chứa ≥1 chữ Hán (okurigana 打込む→打ち込む) hoặc thuần katakana ≥2 code unit (ヴァイオリン→バイオリン); regenerate (20.465 → 13.677 mục). Test chốt chặn: `test/sudachi_data_test.dart`.
- **Do Not Repeat:** Mọi nguồn sinh key MỚI cho dict tham gia greedy match (VietPhrase/Names/UserDict) TUYỆT ĐỐI không được thêm key thuần hiragana — hiragana là vùng ngữ pháp. Chuẩn hoá cần ngữ cảnh thì không đưa vào dict tra thẳng (cùng nguyên tắc với quy tắc vàng jp_valid_kanji của repair).
- **Related Files:** `tool/build_sudachi_assets.dart`, `data/jp/SudachiVariants.txt`, `test/sudachi_data_test.dart`

### 2026-07-20 - Click giữa 1 cụm đã ghép trong ô Nguồn luôn tra từ đầu cụm, không tra từ ký tự bị click
- **Symptom:** Cụm `少女達` được engine ghép thành 1 token (VD match VietPhrase/Names dài nhất tại vị trí 少). Click vào 女 (giữa cụm) vẫn tra nghĩa của cả `少女達` thay vì tra lại từ 女.
- **Root Cause:** `selectAtSourceOffset` (`token_selection.dart`) chỉ tìm token CHỨA offset rồi luôn dùng `t.sourceStart`/`t.source` (biên đã ghép lúc dịch cả đoạn) — không phân biệt click đúng đầu token hay click giữa token.
- **Fix:** Thêm `TranslationEngine.matchAt(text, offset)` (tái dùng `_longestMatchAt`/`_fallbackToken`) để tra lại đúng 1 match bắt đầu CHÍNH XÁC tại offset. `selectAtSourceOffset`: click đúng đầu token → giữ nguyên (đường nhanh); click giữa token → gọi `matchAt` với `sourceText` gốc để lấy cụm/ký tự đúng vị trí click.
- **Do Not Repeat:** Token list từ `translate()` là kết quả ghép của CẢ đoạn văn — không được coi biên token đó là bất biến khi xử lý tương tác theo TỪNG vị trí click (giống nguyên tắc "đo lại theo pointer thật" ở bug 2026-07-19, không suy diễn từ state đã tính sẵn cho mục đích khác).
- **Related Files:** `lib/features/translation/domain/translation_engine.dart` (`matchAt`), `lib/features/translation/application/token_selection.dart`, `test/engine_test.dart`

### 2026-07-20 - Hover tô đỏ trong ô Nguồn lệch vài ký tự so với vị trí chuột
- **Symptom:** Rê chuột trong ô Nguồn (`source_pane.dart`), cụm được tô đỏ thường không phải cụm dưới con trỏ mà là cụm phía sau vài ký tự.
- **Root Cause:** `_onHover` tự dựng một `TextPainter` riêng (`textDirection: TextDirection.ltr`, `maxWidth` tính tay từ `contentWidth`) rồi trừ tay padding/scroll để suy ra offset — không đảm bảo khớp pixel-cho-pixel với `RenderEditable` thật của `TextField` (theme merge style, cursor width, v.v. có thể khiến metrics lệch), cùng gốc với bug 2026-07-19 bên dưới.
- **Fix:** Bỏ `TextPainter` tự dựng; gắn `GlobalKey` vào `TextField`, duyệt render tree tìm `RenderEditable` thật (`_findRenderEditable`), rồi gọi `renderEditable.getPositionForPoint(event.position)` (toạ độ global từ `MouseRegion.onHover`) để suy offset — chính xác tuyệt đối vì dùng đúng render object đang hiển thị.
- **Do Not Repeat:** KHÔNG tự dựng `TextPainter`/layout riêng để suy vị trí con trỏ trong `TextField`/`SelectableText` đang hiển thị — luôn lấy `RenderEditable` thật (qua `EditableTextState` nếu callback có sẵn, hoặc duyệt render tree qua `GlobalKey` nếu không) và gọi `getPositionForPoint`.
- **Related Files:** `lib/features/translation/presentation/source_pane.dart`

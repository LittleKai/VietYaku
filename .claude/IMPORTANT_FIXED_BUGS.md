# Important Fixed Bugs — VietYaku

**Last Updated:** 2026-09-14

## Mục đích

Lỗi **quan trọng, khó phát hiện, hoặc dễ tái phát**, kèm quy tắc để không lặp lại.
Đặc điểm chung: **không ném exception, không báo lỗi** — chỉ lặng lẽ cho ra kết quả
sai. Đó là lý do chúng đáng được ghi riêng.

Chỉ ghi bẫy khi thoả ít nhất một điều: tác động cao (dữ liệu / build / deploy /
security) · khó phát hiện bằng review thường · dễ tái phát · liên quan tới quyết
định kiến trúc, migration, hay API contract. **Không** ghi lỗi vặt, không dùng làm
changelog, không thêm entry sau mọi task.

---

## 🚪 CỬA RA — file này KHÔNG chỉ được phép dài thêm

Một bẫy chỉ cần nằm ở đây **chừng nào chưa có gì trong code chặn nó**. Khi đã viết
được rào chắn thì văn xuôi hết việc:

> **Bẫy đã có rào chắn ⇒ chuyển phần kể chuyện xuống
> `archive/FIXED_BUGS_guarded.md`, ở lại đúng một dòng trong Bảng bẫy + tên hàm
> rào chắn.**

Vì sao: một luật phải nhắc lại bằng văn xuôi là một luật **không có gì cưỡng chế**.
Chép nó ra nhiều chỗ không làm nó được tuân thủ hơn — viết được cái hàm khiến bỏ
qua nó là không thể mới làm được điều đó.

| Mức | Nghĩa là gì | Văn xuôi ở đâu |
|---|---|---|
| ✅ | **mọi** Do-Not-Repeat của bẫy đã bị một hàm cưỡng chế | `archive/` |
| 🔶 | rào chắn lo được một phần, phần còn lại là phán đoán của người | ở lại, rút gọn |
| ❌ | chưa có gì chặn | ở lại, **đủ dài** |

Đừng rút một bẫy chỉ vì code có hàm *liên quan* — phải là hàm **làm cho lỗi đó
không xảy ra được nữa**, và đã chạy thật thấy nó bắt được lỗi.

Ngược lại: thấy một bẫy ❌ mà **viết được** rào chắn thì viết luôn trong task đó rồi
hạ xuống ✅. Đó là cách file này ngắn đi thay vì dài ra.

`.claude/guard_check.py` kiểm mọi hàm nêu ở cột "Rào chắn" còn tồn tại thật — rào
chắn bị xoá mà văn xuôi đã nằm dưới `archive/` là **mất kiến thức lặng lẽ**, nên
phép kiểm này là điều kiện để cửa ra an toàn. Chạy:
`"D:/Dev/conda-envs/py312/python.exe" .claude/guard_check.py`

---

## Bảng bẫy

| # | Bẫy | Rào chắn trong code | Văn xuôi ở đâu |
|---|---|---|---|
| 1 | Alias biến thể Sudachi dựng ngược kanji từ phiên âm katakana (`細工`→`Zaik`) | ✅ `japanese_variant_index.dart::_isAllowedVariant` + `build_sudachi_assets.dart::safeVariant` | `archive/FIXED_BUGS_guarded.md` |
| 2 | Android release mất sạch tính năng mạng — `src/main/AndroidManifest.xml` thiếu `INTERNET` | ✅ `android_manifest_test.dart::manifestPath` | `archive/FIXED_BUGS_guarded.md` |
| 3 | Bôi đen ở ô kết quả sinh key THIẾU token có nghĩa rỗng | ✅ `token_text_view.dart::selectionSourceKey` | `archive/FIXED_BUGS_guarded.md` |
| 4 | Dispose `TextEditingController` ngay sau `await showAppDialog` ⇒ crash | 🔶 một phần: `entry_edit_dialog.dart::disposeAfterRouteAnimation` — chỉ lo `ValueNotifier` | dưới đây |
| 5 | `trad2simp.tsv` quy nhầm chữ VỐN ĐÃ giản thể (子→自, 三→叁…) | ✅ `build_trad2simp.dart::selfCounts` | `archive/FIXED_BUGS_guarded.md` |
| 6 | `trad2simp.tsv` chứa cặp ngược chiều ⇒ dịch Trung tự biến giản thành phồn | ✅ `trad2simp_test.dart::Trad2SimpTable` — chốt `convert(convert(x)) == convert(x)` | `archive/FIXED_BUGS_guarded.md` |
| 7 | `WidgetStateTextStyle` trong `ChipThemeData.labelStyle` làm nhãn chip tàng hình | ✅ `app_theme_test.dart::chipTheme` | `archive/FIXED_BUGS_guarded.md` |
| 8 | `Isolate.run` trong `State` capture cả cây widget | 🔶 một phần: `epub_converter.dart::parseEpubRequest` — chỉ cho EPUB, chỗ khác vẫn tự lo | dưới đây |
| 9 | Dialog action dùng context của widget gọi đã bị deactive | ✅ `app_dialog.dart::actionsBuilder` — API bắt nhận `dialogContext` | `archive/FIXED_BUGS_guarded.md` |
| 10 | OpenCC `JPShinjitaiCharacters.txt` map NGƯỢC chiều tên gọi | 🔶 một phần: `build_simp2jp.dart::shinjitai` — đã đảo, nhưng file OpenCC khác vẫn phải tự kiểm | dưới đây |
| 11 | Riverpod `CircularDependencyError` khi `dictionariesProvider` watch translationController | 🔶 một phần: `translation_controller.dart::currentModeProvider` — Riverpod chỉ assert ở debug | dưới đây |
| 12 | Flutter Windows accessibility_bridge AXTree crash (app tự tắt) | ✅ `app.dart::ExcludeSemantics` | `archive/FIXED_BUGS_guarded.md` |
| 13 | Android APK build fail "Could not close incremental caches" (Kotlin/Windows) | ❌ chưa có — `kotlin.incremental=false` trong `android/gradle.properties`, không phải code app | dưới đây |
| 14 | Chuột phải trong `SelectableText` trên Windows KHÔNG dời caret khi đã focus | 🔶 một phần: `token_text_view.dart::_secondaryTapPosition` — chỉ ở widget này | dưới đây |
| 15 | `SudachiVariants` sinh key thuần hiragana ⇒ chuỗi ngữ pháp bị dịch bậy | ✅ `build_sudachi_assets.dart::safeVariant` + `sudachi_data_test.dart` chốt trên file đã sinh | `archive/FIXED_BUGS_guarded.md` |
| 16 | Click giữa một cụm đã ghép luôn tra từ đầu cụm | 🔶 một phần: `translation_engine.dart::matchAt` — đã TÁI PHẠM một lần (bẫy #18) | dưới đây |
| 17 | Hover tô đỏ trong ô Nguồn lệch vài ký tự so với vị trí chuột | 🔶 một phần: `source_pane.dart::_findRenderEditable` — chỉ ở widget này | dưới đây |
| 18 | Cụm từ điển phụ TÁI PHẠM bẫy "click giữa cụm tra từ đầu cụm" | 🔶 một phần: `secondary_phrase.dart::secondaryPhraseStartingAt` — lớp ghép mới vẫn phải tự áp lại | dưới đây |
| 19 | Tab "VietPhrase một nghĩa" render cả tầng nghĩa ⇒ click active cụm lệch dần | 🔶 một phần: `token_text_view.dart::multiMeaning` — span mới vẫn phải tự đo lại | dưới đây |
| 20 | Alias động Sudachi im lặng không sinh gì cho entry dạng thân từ | 🔶 một phần: `japanese_variant_index.dart::_normalizeGroups` | dưới đây |
| 21 | Từ tra online/AI lưu rồi nhưng click lại không hiện | ✅ `user_dict_service.dart::upsertVietPhraseOverlay` | `archive/FIXED_BUGS_guarded.md` |
| 22 | Xóa từ do AI tạo không mất, người dùng thường xóa gì cũng no-op | ✅ `user_dict_service.dart::removeGeneratedEntry` | `archive/FIXED_BUGS_guarded.md` |
| 23 | Promote nghĩa tra online vào VietPhrase làm bẩn từ điển dịch | ✅ `dict_entry_filter.dart::meaningMatchesWord` + `dict_entry_filter.dart::isWordLikeEntry` + `dict_entry_filter.dart::vietnameseLookupLabels` | `archive/FIXED_BUGS_guarded.md` |
| 24 | Mazii mode Trung trả kết quả từ điển Nhật | ✅ `mazii_api.dart::_hasKanaReading` | `archive/FIXED_BUGS_guarded.md` |
| 25 | Khởi động: nút title bar hiện icon Restore nhưng cửa sổ không maximize | ✅ `window_maximize.dart::ensureWindowMaximized` + `win32_window.cpp::IsZoomed` | `archive/FIXED_BUGS_guarded.md` |
| 26 | Xóa từ khỏi VietPhrase/Lạc Việt không mất từ trong từ điển nạp | ✅ `shared_dictionary_service.dart::deleteSentinel` + `shared_dictionary_service.dart::replayPending` | `archive/FIXED_BUGS_guarded.md` |
| 27 | Sửa từ cùng độ dài trong vòng 1 giây ⇒ cache `.vydc` trả nghĩa CŨ (mtime Windows làm tròn giây) | ✅ `binary_cache.dart::trustsMtime` | `archive/FIXED_BUGS_guarded.md` |
| 28 | Cụm mở đầu bằng ký tự KHÔNG-CJK không bao giờ ghép dù từ điển có đủ (`ＨＢＴＮシリーズ`, `【誓約の魔物】会議`) ⇒ dịch không hiện + dialog sửa nhận sai key | ✅ `translation_engine.dart::_startableMatchAt` | `archive/FIXED_BUGS_guarded.md` |

> Cột 1 phải là **số**, cột 3 phải bắt đầu bằng ✅/🔶/❌ và bọc tên hàm trong dấu
> backtick — `guard_check.py` parse đúng định dạng này.

---

## Fixed Bugs

> Chỉ còn các bẫy mức 🔶 và ❌. Mức ✅ xem `archive/FIXED_BUGS_guarded.md`.

### 2026-08-10 - Disposing `TextEditingController` or `ValueNotifier` in dialog method after `await showAppDialog` causes crash
- **Symptom:** Exception thrown when interacting with dialogs in `glossary_sync_screen.dart`: `A TextEditingController was used after being disposed. Once you have called dispose() on a TextEditingController, it can no longer be used. The relevant error-causing widget was: TextField at glossary_sync_screen.dart:326:15`.
- **Root Cause:** Local `TextEditingController`s and `ValueNotifier`s were created in a helper method, passed into `StatefulBuilder`/`TextField` inside `showAppDialog`, and `.dispose()` was called immediately after `await showAppDialog` returned. Because `showAppDialog` resolves as soon as `Navigator.pop` is invoked, the dialog widget tree (`TextField`) is STILL mounted and rebuilding during the route exit animation. Disposing controllers before element unmount causes `TextField` to access disposed controllers during transition frames.
- **Fix:** Refactored dialog content into `StatefulWidget` classes (`_SingleEditDialogContent`, `_BulkEditDialogContent`, `_ConfirmDeleteDialogContent`) that own `TextEditingController`s in `initState()` and dispose them in `State.dispose()`. `State.dispose()` is executed automatically by Flutter AFTER element unmount and pop animation finish. `ValueNotifier`s are safely disposed via `.disposeAfterRouteAnimation()`.
- **Do Not Repeat:** Never instantiate local `TextEditingController`s outside of a `State` class for dialogs, and never call `.dispose()` on them immediately after `await showAppDialog`. Always let a `StatefulWidget` own and dispose its controllers in `State.dispose()`, or delay disposal until route unmount.
- **Related Files:** `lib/features/glossary/presentation/glossary_sync_screen.dart`, `lib/shared/widgets/entry_edit_dialog.dart`

### 2026-07-20 - `Isolate.run` trong State capture cả cây widget khi chuyển EPUB
- **Symptom:** Chọn EPUB ném `Illegal argument in isolate message`, thông báo lần theo `_EpubConverterScreenState`, `SettingsPage` và `ScrollController` dù dữ liệu đầu vào chỉ là bytes.
- **Root Cause:** Closure khai báo trong phương thức của `State` có thể capture ngầm `this`; isolate cố gửi toàn bộ object graph của widget, trong đó có các object native không sendable.
- **Fix:** Dùng entry-point top-level `parseEpubRequest`/`exportEpubRequest` với `compute` và request thuần dữ liệu; thêm test parse lẫn export thật qua isolate.
- **Do Not Repeat:** Tác vụ isolate từ widget phải truyền hàm top-level/static và payload thuần dữ liệu. Không đưa closure của `State`, `BuildContext`, controller hay notifier qua isolate.
- **Related Files:** `lib/features/epub_converter/domain/epub_converter.dart`, `lib/features/epub_converter/presentation/epub_converter_screen.dart`, `test/epub_converter_test.dart`

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

### 2026-07-25 - Cụm từ điển phụ TÁI PHẠM bug "click giữa cụm tra từ đầu cụm" (2026-07-20)
- **Symptom:** `はやめて` — `はや` có trong Nhật Việt (cụm phụ greedy chiếm 0..2), `やめ` có trong Lạc Việt. Click vào `や` vẫn tra `はや`, không tra `やめ`; nếu không có cụm nào bắt đầu tại `や` thì cũng không chọn riêng `や`.
- **Root Cause:** Nhánh cụm từ điển phụ thêm sau bản fix 2026-07-20 lại chặn TRƯỚC vòng token: `selectAtSourceOffset` lấy `_secondaryPhraseAt(offset)` (chỉ cần CHỨA offset) rồi return ngay — lặp đúng lỗi cũ trên `secondaryPhrasesProvider` (danh sách cụm greedy tính sẵn cho cả đoạn).
- **Fix:** `secondary_phrase.dart` tách `_matchAt` khỏi `_matchRun` + hàm public `secondaryPhraseStartingAt(...)` (greedy longest-match bắt đầu ĐÚNG tại offset, giới hạn trong run token unmatched chứa offset). Áp cho CẢ 2 lối vào: `selectAtSourceOffset` (ô Nguồn) và `selectToken` (ô VietPhrase + Hán Việt, cùng đi qua `TokenTextView`) — click đúng đầu cụm → dùng cả cụm; click giữa cụm → `secondaryPhraseStartingAt`; không có → chọn đúng ký tự/token bị click.
- **Do Not Repeat:** Mọi danh sách cụm tính sẵn cho CẢ đoạn (tokens, secondaryPhrases, và các lớp ghép thêm sau này) chỉ được dùng khi click đúng ĐẦU cụm; click giữa cụm phải tra lại tại đúng offset. Thêm lớp ghép mới thì phải áp lại quy tắc này ở CẢ `selectAtSourceOffset` lẫn `selectToken`, đừng chèn nhánh return sớm lên trước.
- **Related Files:** `lib/features/translation/domain/secondary_phrase.dart`, `lib/features/translation/application/token_selection.dart`, `test/secondary_phrase_test.dart`

### 2026-08-18 - Tab "VietPhrase một nghĩa" render cả các tầng nghĩa → click active cụm lệch dần (rõ từ dòng thứ 3)
- **Symptom:** Tab "VietPhrase một nghĩa": click đúng vào một từ thì active nhầm cụm phía sau, phải click lệch về TRƯỚC từ đó một chút mới trúng. Dòng 1–2 gần như không thấy, càng xuống dưới càng lệch nhiều; cuối đoạn click không ăn gì.
- **Root Cause:** Hai lỗi cùng gốc, đều từ 569734f. (1) `_buildTokenSpan` chỉ kiểm tra `paneId == PaneId.vietPhrase`, không biết đang ở tab nào → với mode hiển thị `visualHierarchy`/`tieredNumbered` nó DỰNG LẠI span từ `token.rawValue`, nên tab "một nghĩa" hiện đủ mọi tầng nghĩa thay vì chỉ nghĩa đầu của `displayWithPartOfSpeech`. (2) Bảng `ranges` map caret→cụm lại cộng dồn `text.length` (chuỗi của `widget.textOf`) trong khi span render dài hơn (thêm tầng nghĩa, nhãn `(n) `, `①`, `‖`, `/`) → sai số cộng dồn theo từng cụm, biểu hiện ra là lệch tăng dần theo dòng.
- **Fix:** (1) Thêm cờ `TokenTextView.multiMeaning` (ResultPane truyền `isMultiMeaning`); tab một nghĩa giữ nguyên chuỗi `textOf`, chỉ tô màu nhãn từ loại qua helper `_posLabelSpan` (dùng chung với nhánh 1-nghĩa của tab đa nghĩa). (2) Đo range bằng chính text sẽ render: `tokenSpan.toPlainText(includeSemanticsLabels: false).length` (đúng cách `SelectableText` dựng controller text) thay cho `text.length`, cho cả `ranges` lẫn biến `offset`.
- **Do Not Repeat:** Widget dựng lại nội dung hiển thị từ dữ liệu gốc thay vì dùng chuỗi được truyền vào thì PHẢI biết ngữ cảnh gọi (tab/chế độ), đừng suy từ `paneId`. Và bất cứ khi nào span hiển thị KHÔNG phải chính chuỗi `textOf(token)` (thêm nhãn, ký hiệu, WidgetSpan…), offset dùng để map caret/`getPositionForPoint` phải đo trên text render thật. Cùng họ với các bug "đo lại theo pointer/render object thật" 2026-07-19 và 2026-07-20.
- **Related Files:** `lib/features/translation/presentation/token_text_view.dart`, `lib/features/translation/presentation/result_pane.dart`, `test/token_text_view_caret_test.dart`

### 2026-09-01 - Alias động Sudachi im lặng không sinh gì cho entry dạng thân từ
- **Symptom:** Bật Sudachi variants, mode Nhật, nhưng `吞み込=nuốt chửng` trong SharedVietPhrase không hề bắt `呑み込ま`/`吞みこま`; kết quả dịch y hệt lúc chưa có tính năng, không lỗi, không log.
- **Root Cause:** `SudachiVariantGroups.txt` chỉ chứa thể chia ĐẦY ĐỦ (`吞み込ま`, `吞み込む`), không bao giờ có thân từ `吞み込`. `_aliasesFor` yêu cầu mọi mảnh của key phải là surface nguyên vẹn của một nhóm hoặc kana, gặp `吞` (Hán, không nhóm nào có) là `return` → 0 alias. Test cũ chỉ dùng key dạng đầy đủ nên xanh hết.
- **Fix:** `_normalizeGroups` cắt dần đuôi kana chung của cả nhóm để sinh thêm nhóm thân từ; mảnh không thuộc nhóm nào thì giữ nguyên thay vì bỏ cả key. Kèm hai chốt chặn nhiễu + tốc độ: mảnh phụ chỉ được kana hoá (chặn `切れ`→`斬れ` và `きれ`→`訊れ` — cùng nhóm Sudachi vì chung dạng chuẩn + cách đọc), và segmentation đi greedy longest-match + cache biến thể theo surface (expand 2.034 entry: 56s → 0,12s).
- **Do Not Repeat:** Dữ liệu Sudachi là surface của TỪ, còn entry người dùng thường là thân từ hoặc cụm ghép — test tính năng dựa trên nhóm Sudachi phải có case thân từ (`吞み込`) và case ghép mảnh (`扱い切`), đừng chỉ test dạng từ điển chuẩn. Nhóm Sudachi gộp theo dạng chuẩn + cách đọc nên KHÔNG được coi mọi thành viên là thay thế được cho nhau khi chỉ khớp một mảnh.
- **Related Files:** `lib/features/dictionary/domain/japanese_variant_index.dart`, `lib/features/dictionary/data/dictionary_repository.dart`, `test/japanese_variant_index_test.dart`, `test/dictionary_repository_variant_test.dart`

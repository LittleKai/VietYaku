# Important Fixed Bugs

**Last Updated:** 2026-08-22

---

## Purpose

This file records important bugs that were fixed and should not be repeated. Keep entries concise and actionable.

Record only high-impact, hard-to-detect, or likely-to-recur bugs. Do not record ordinary bug fixes, do not append entries after every task, and do not use this file as a changelog.

---

## Fixed Bugs

### 2026-08-22 - Android release mất sạch tính năng mạng vì `AndroidManifest.xml` (main) thiếu `INTERNET`
- **Symptom:** Trên bản release APK, tra online (Mazii/Jisho/Weblio/Youdao), tab Google Dịch, kiểm tra cập nhật và đồng bộ từ điển chung đều thất bại im lặng hoặc báo lỗi mạng chung chung. **Chạy `flutter run` (debug) thì mọi thứ bình thường** nên lỗi không bao giờ lộ ra trong lúc phát triển.
- **Root Cause:** Flutter tự sinh `android/app/src/debug/AndroidManifest.xml` và `src/profile/AndroidManifest.xml` có sẵn `<uses-permission android:name="android.permission.INTERNET"/>` để hot reload chạy được, nhưng **`src/main/AndroidManifest.xml` thì không**. Manifest merger chỉ gộp `debug`/`profile` vào đúng build type tương ứng, nên quyền này biến mất khỏi bản release.
- **Fix:** Khai báo `INTERNET` trong `src/main/AndroidManifest.xml`. Kèm theo: `android:largeHeap="true"` (bộ dict ~700k entry vượt heap mặc định) và `android:networkSecurityConfig` mở cleartext riêng cho `localhost`/`127.0.0.1`/`10.0.2.2` để test server dev.
- **Do Not Repeat:** Đừng bao giờ suy ra quyền Android từ việc chạy debug. Sau khi build release, verify bằng `aapt2 dump permissions <apk>` — phải thấy đủ `INTERNET` + `REQUEST_INSTALL_PACKAGES`.
- **Related Files:** `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/network_security_config.xml`

### 2026-08-13 - Bôi đen ở ô kết quả cho key THIẾU token có nghĩa rỗng (`激出了火气` → `激出火气`)
- **Symptom:** Ô VietPhrase bôi đen "kích động ra hỏa khí" rồi chuột phải → "Sửa vào VietPhrase": ô Từ nguồn chỉ hiện `激出火气`, trong khi ô Nguồn là `激出了火气`. Không lỗi, không cảnh báo — key sai được lưu/publish thẳng vào từ điển chung và không bao giờ khớp lại văn bản.
- **Root Cause:** `TokenTextView._pieces` bỏ hẳn token có text hiển thị rỗng (`了=` trong VietPhrase CN, `的` ở nhiều bộ) để không tạo khoảng trống thừa; token bị bỏ cũng không vào `ranges`, nên `_contextMenu` ghép key bằng `selectedTokens.map((t) => t.source).join()` mất luôn phần nguồn của nó. Cùng đường này còn cấp `word` cho "Tra online" và "Thêm vào Names".
- **Fix:** `selectionSourceKey(paragraph, selected)` — lấy biên `[first.sourceStart, last.sourceStart + last.source.length)` từ vùng chọn rồi nối `source` của MỌI token không-passthrough của đoạn nằm trong biên đó (token nghĩa rỗng ở giữa được đưa vào lại; passthrough vẫn bị loại để dấu câu không lọt vào key).
- **Do Not Repeat:** Key từ điển KHÔNG được suy ra từ danh sách token đã lọc để hiển thị — phần hiển thị và phần nguồn là hai tập khác nhau. Thêm bất kỳ luật lọc/ghép hiển thị mới nào ở `_pieces` thì phải kiểm lại đường sinh key ở `_contextMenu`.
- **Related Files:** `lib/features/translation/presentation/token_text_view.dart`, `test/token_display_rules_test.dart`

### 2026-08-10 - Disposing `TextEditingController` or `ValueNotifier` in dialog method after `await showAppDialog` causes crash
- **Symptom:** Exception thrown when interacting with dialogs in `glossary_sync_screen.dart`: `A TextEditingController was used after being disposed. Once you have called dispose() on a TextEditingController, it can no longer be used. The relevant error-causing widget was: TextField at glossary_sync_screen.dart:326:15`.
- **Root Cause:** Local `TextEditingController`s and `ValueNotifier`s were created in a helper method, passed into `StatefulBuilder`/`TextField` inside `showAppDialog`, and `.dispose()` was called immediately after `await showAppDialog` returned. Because `showAppDialog` resolves as soon as `Navigator.pop` is invoked, the dialog widget tree (`TextField`) is STILL mounted and rebuilding during the route exit animation. Disposing controllers before element unmount causes `TextField` to access disposed controllers during transition frames.
- **Fix:** Refactored dialog content into `StatefulWidget` classes (`_SingleEditDialogContent`, `_BulkEditDialogContent`, `_ConfirmDeleteDialogContent`) that own `TextEditingController`s in `initState()` and dispose them in `State.dispose()`. `State.dispose()` is executed automatically by Flutter AFTER element unmount and pop animation finish. `ValueNotifier`s are safely disposed via `.disposeAfterRouteAnimation()`.
- **Do Not Repeat:** Never instantiate local `TextEditingController`s outside of a `State` class for dialogs, and never call `.dispose()` on them immediately after `await showAppDialog`. Always let a `StatefulWidget` own and dispose its controllers in `State.dispose()`, or delay disposal until route unmount.
- **Related Files:** `lib/features/glossary/presentation/glossary_sync_screen.dart`, `lib/shared/widgets/entry_edit_dialog.dart`

### 2026-08-09 - `trad2simp.tsv` quy nhầm chữ VỐN ĐÃ giản thể (子→自, 三→叁, 斯→四…)
- **Symptom:** Màn Glossary ↔ VietPhrase, mode Trung, tab "Không trùng": bấm Cập nhật xong từ vẫn nằm nguyên trong danh sách, bấm bao nhiêu lần cũng không biến mất (98 mục kẹt vĩnh viễn). Không lỗi, không cảnh báo. Tra online cho các từ chứa những chữ này cũng trả kết quả rác.
- **Root Cause:** `cedict_ts.u8` có vài mục gõ sai cột giản thể (`鷹爪翻子拳 / 鹰爪翻自拳`, `哈根達斯 / 哈跟达斯`). Generator cũ chỉ đếm vị trí trad≠simp, nên với chữ vốn đã là giản thể, cặp rác duy nhất đó trở thành ứng viên DUY NHẤT và được chọn: `子→自` (1 lần so với 1.123 lần 子 đứng nguyên ở cột giản thể), `斯→四` (1/733), `三→叁` (1/361), `言→讠`, `座→坐`, `哈→加`, `根→跟`, `坦→谈`, `磁→铁`, `份→分`, `殖→植`, `黏→粘`, `甚→什`, `俱→具`… Mode Trung quy CẢ văn bản lẫn key dict nên tra vẫn khớp nhau ⇒ dịch trông vẫn "chạy", chỉ có 48k key bị bóp méo và va nhau (mất mục), còn màn glossary thì so source glossary thô (`小子`) với key dict đã bị quy (`小自`) ⇒ luôn báo "không trùng"; áp dụng xong lưu `小子` rồi lại bị quy thành `小自` ⇒ mục không bao giờ thành "trùng" được.
- **Fix:** Generator đếm thêm `selfCounts` (số lần ký tự đứng NGUYÊN VẸN ở cột giản thể); nếu cặp hay gặp nhất còn nhẹ ký hơn `selfCounts` thì bỏ hẳn ký tự đó khỏi bảng — 103 ký tự bị loại, bảng 2.538 → 2.455. Thêm `glossary_sync_controller` quy `term.source` phồn→giản trước khi đối chiếu (4 mục còn lại là source phồn thể thật). Sau fix: VietPhrase CN 690.006 → 680.777 key, chỉ 13.413 key bị quy (trước là 61.541 — phần lớn là quy bậy).
- **Do Not Repeat:** Bảng sinh tự động từ dữ liệu ngoài phải so tần suất với "phương án không đổi", không được lấy đa số của riêng nhánh đổi — một dòng gõ sai đủ để phá chữ thường gặp nhất. Test `chữ vốn đã giản thể không bị quy` trong `test/trad2simp_test.dart` chốt lại điều này. Không sửa tay `assets/mappings/*.tsv`, luôn `dart run tool/build_trad2simp.dart`.
- **Related Files:** `tool/build_trad2simp.dart`, `assets/mappings/trad2simp.tsv`, `lib/features/glossary/application/glossary_sync_controller.dart`, `test/trad2simp_test.dart`

### 2026-08-07 - `trad2simp.tsv` chứa cặp ngược chiều, dịch Trung tự biến giản thể thành phồn thể
- **Symptom:** Raw `席尔` (giản thể) qua mode Trung lại tra thành `席爾`, khớp nhầm mục phồn thể trong VietPhrase (`席爾=Llyr`) thay vì các mục `席尔…` đúng. Không lỗi, không cảnh báo — chỉ sai nghĩa.
- **Root Cause:** `cedict_ts.u8` có vài mục bị đảo cột (vd `提尔 提爾` — cột "phồn" lại là giản thể) hoặc lệch ký tự. `tool/build_trad2simp.dart` ghép ký tự theo vị trí nên sinh ra `尔→爾` (ngược chiều, nằm chung bảng với `爾→尔` đúng chiều) và cả cặp bậy tạo chuỗi (`託→托` trong khi `托→度`; `辛→緬` trong khi `緬→缅`). Tổng cộng 41 mắt xích rác.
- **Fix:** Generator đếm số lần xuất hiện cho từng cặp, rồi áp invariant "đích không bao giờ là nguồn của cặp khác" — gặp `a→b` mà `b→c` thì bỏ mắt xích nhẹ ký hơn, lặp tới khi hết chuỗi (luật này bao luôn cặp ngược chiều `a→b`/`b→a`). Regenerate bảng: 2579 → 2538 ký tự.
- **Do Not Repeat:** Bảng ánh xạ sinh tự động từ dữ liệu ngoài phải kiểm tra tính nhất quán, không tin cột nguồn. Invariant: quy đổi hai lần phải ra cùng kết quả (`convert(convert(x)) == convert(x)`) — còn cặp ngược chiều hay chuỗi thì kết quả sẽ dao động. Đã có test trong `test/trad2simp_test.dart`, mẫu thử phải gồm cả ký tự từng dính chuỗi (託麼麽衚鬍辛緬胡托么).
- **Ghi chú:** Cache `.vydc` của bộ dict Trung đã quy giản mang chữ ký bảng trong tên file (`Trad2SimpTable.signature`), nên sinh lại tsv là cache cũ tự bị bỏ qua — không cần nhớ xóa tay.
- **Related Files:** `tool/build_trad2simp.dart`, `assets/mappings/trad2simp.tsv`, `test/trad2simp_test.dart`

### 2026-07-25 - `WidgetStateTextStyle` trong `ChipThemeData.labelStyle` làm nhãn chip tàng hình
- **Symptom:** Toàn bộ FilterChip ("Từ điển trong popup") mất chữ — nhãn render gần trắng trên nền trắng. `flutter analyze` sạch, `flutter test` pass; chỉ thấy được khi chụp màn hình app đang chạy.
- **Root Cause:** `Chip` resolve nhãn bằng `resolveAs<Color?>(effectiveLabelStyle.color, states)` rồi `effectiveLabelStyle.copyWith(color: resolved)`. Một `WidgetStateTextStyle` có `.color == null`, nên style rút gọn thành `TextStyle` trống và nhãn kế thừa màu ambient. Chip chỉ resolve theo trạng thái ở thuộc tính `color`, KHÔNG ở bản thân TextStyle.
- **Fix:** Dùng `TextStyle` thường với `color: WidgetStateColor.resolveWith(...)`. Hệ quả: chỉ đổi được MÀU theo trạng thái, không đổi được `fontWeight`.
- **Do Not Repeat:** Không đặt `WidgetStateTextStyle` vào `ChipThemeData.labelStyle`. Tổng quát hơn: thay đổi thuần theme không được analyzer/unit test bắt lỗi — phải xác minh bằng ảnh chụp app chạy thật hoặc test invariant về màu (xem `test/app_theme_test.dart`).
- **Related Files:** `lib/core/theme/app_theme.dart`, `lib/features/settings/settings_screen.dart`, `test/app_theme_test.dart`

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

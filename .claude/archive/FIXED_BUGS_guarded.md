# Bẫy đã có rào chắn — VietYaku

> Lịch sử đã hết hiệu lực. **KHÔNG làm theo hướng dẫn thủ công trong file này** —
> mỗi bẫy dưới đây đã có một hàm trong code khiến nó không xảy ra được nữa. Giữ lại
> đây chỉ để biết **vì sao hàm đó tồn tại**, cho người sau không xoá nhầm.
>
> Một bẫy ở đây ⇔ một dòng ✅ trong `../IMPORTANT_FIXED_BUGS.md` §"Bảng bẫy".
> `guard_check.py` kiểm hai bên khớp số lượng.

### 2026-09-07 - Alias biến thể Sudachi dựng ngược kanji từ phiên âm katakana (`細工` → `Zaik`)

*Đã có rào chắn: `japanese_variant_index.dart::_isAllowedVariant` + `build_sudachi_assets.dart::safeVariant`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*
- **Symptom:** `細工` dịch ra `Zaik` (tên riêng) thay vì `tác phẩm/đồ thủ công/…`, dù `VietPhrase.txt` có mục `細工` đúng. Không lỗi, không log — chỉ có bản dịch sai ở đúng một từ, và tra trong Search Center vẫn thấy mục gốc còn nguyên.
- **Root Cause:** Nhóm Sudachi `ざいく / ザイク / 細工` gom cả CÁCH ĐỌC lẫn mặt chữ. `JapaneseVariantIndex` khi key khớp trọn một surface thì "tin cả nhóm" (`trustGroup`) nên mục `ザイク=Zaik` trong `SharedVietPhrase_japanese.txt` sinh alias `細工=Zaik`; shared VietPhrase merge SAU cùng nên alias này đè luôn mục gốc. Chiều ngược (`細工` → `ザイク`) cũng sai tương tự và đã lọt vào `SudachiVariants.txt` do `safeVariant` cũ nhận mọi biến thể thuần katakana.
- **Fix:** Alias chỉ đi một chiều và không bắc cầu Hán ⇄ katakana — nguồn có chữ Hán thì biến thể không được chứa katakana; nguồn thuần kana thì chỉ đổi hệ chữ kana, không dựng kanji. Áp ở `_isAllowedVariant` (lúc chạy) và `safeVariant` (lúc sinh asset); đã sinh lại `data/jp/Sudachi*.txt` (13.676 → 11.299 biến thể).
- **Do Not Repeat:** Trường 11 (読み) của Sudachi là katakana — mọi cơ chế gom "cách viết tương đương" đều kéo cách đọc vào cùng nhóm. Trước khi nhận một cặp biến thể, luôn hỏi "đây là cách VIẾT khác hay cách ĐỌC?". Một alias sai ở tầng overlay đè được cả từ điển gốc vì overlay merge sau cùng.
- **Related Files:** `lib/features/dictionary/domain/japanese_variant_index.dart`, `tool/build_sudachi_assets.dart`, `test/japanese_variant_index_test.dart`

### 2026-08-13 - Bôi đen ở ô kết quả cho key THIẾU token có nghĩa rỗng (`激出了火气` → `激出火气`)

*Đã có rào chắn: `token_text_view.dart::selectionSourceKey`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*
- **Symptom:** Ô VietPhrase bôi đen "kích động ra hỏa khí" rồi chuột phải → "Sửa vào VietPhrase": ô Từ nguồn chỉ hiện `激出火气`, trong khi ô Nguồn là `激出了火气`. Không lỗi, không cảnh báo — key sai được lưu/publish thẳng vào từ điển chung và không bao giờ khớp lại văn bản.
- **Root Cause:** `TokenTextView._pieces` bỏ hẳn token có text hiển thị rỗng (`了=` trong VietPhrase CN, `的` ở nhiều bộ) để không tạo khoảng trống thừa; token bị bỏ cũng không vào `ranges`, nên `_contextMenu` ghép key bằng `selectedTokens.map((t) => t.source).join()` mất luôn phần nguồn của nó. Cùng đường này còn cấp `word` cho "Tra online" và "Thêm vào Names".
- **Fix:** `selectionSourceKey(paragraph, selected)` — lấy biên `[first.sourceStart, last.sourceStart + last.source.length)` từ vùng chọn rồi nối `source` của MỌI token không-passthrough của đoạn nằm trong biên đó (token nghĩa rỗng ở giữa được đưa vào lại; passthrough vẫn bị loại để dấu câu không lọt vào key).
- **Do Not Repeat:** Key từ điển KHÔNG được suy ra từ danh sách token đã lọc để hiển thị — phần hiển thị và phần nguồn là hai tập khác nhau. Thêm bất kỳ luật lọc/ghép hiển thị mới nào ở `_pieces` thì phải kiểm lại đường sinh key ở `_contextMenu`.
- **Related Files:** `lib/features/translation/presentation/token_text_view.dart`, `test/token_display_rules_test.dart`

### 2026-08-09 - `trad2simp.tsv` quy nhầm chữ VỐN ĐÃ giản thể (子→自, 三→叁, 斯→四…)

*Đã có rào chắn: `build_trad2simp.dart::selfCounts`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*
- **Symptom:** Màn Glossary ↔ VietPhrase, mode Trung, tab "Không trùng": bấm Cập nhật xong từ vẫn nằm nguyên trong danh sách, bấm bao nhiêu lần cũng không biến mất (98 mục kẹt vĩnh viễn). Không lỗi, không cảnh báo. Tra online cho các từ chứa những chữ này cũng trả kết quả rác.
- **Root Cause:** `cedict_ts.u8` có vài mục gõ sai cột giản thể (`鷹爪翻子拳 / 鹰爪翻自拳`, `哈根達斯 / 哈跟达斯`). Generator cũ chỉ đếm vị trí trad≠simp, nên với chữ vốn đã là giản thể, cặp rác duy nhất đó trở thành ứng viên DUY NHẤT và được chọn: `子→自` (1 lần so với 1.123 lần 子 đứng nguyên ở cột giản thể), `斯→四` (1/733), `三→叁` (1/361), `言→讠`, `座→坐`, `哈→加`, `根→跟`, `坦→谈`, `磁→铁`, `份→分`, `殖→植`, `黏→粘`, `甚→什`, `俱→具`… Mode Trung quy CẢ văn bản lẫn key dict nên tra vẫn khớp nhau ⇒ dịch trông vẫn "chạy", chỉ có 48k key bị bóp méo và va nhau (mất mục), còn màn glossary thì so source glossary thô (`小子`) với key dict đã bị quy (`小自`) ⇒ luôn báo "không trùng"; áp dụng xong lưu `小子` rồi lại bị quy thành `小自` ⇒ mục không bao giờ thành "trùng" được.
- **Fix:** Generator đếm thêm `selfCounts` (số lần ký tự đứng NGUYÊN VẸN ở cột giản thể); nếu cặp hay gặp nhất còn nhẹ ký hơn `selfCounts` thì bỏ hẳn ký tự đó khỏi bảng — 103 ký tự bị loại, bảng 2.538 → 2.455. Thêm `glossary_sync_controller` quy `term.source` phồn→giản trước khi đối chiếu (4 mục còn lại là source phồn thể thật). Sau fix: VietPhrase CN 690.006 → 680.777 key, chỉ 13.413 key bị quy (trước là 61.541 — phần lớn là quy bậy).
- **Do Not Repeat:** Bảng sinh tự động từ dữ liệu ngoài phải so tần suất với "phương án không đổi", không được lấy đa số của riêng nhánh đổi — một dòng gõ sai đủ để phá chữ thường gặp nhất. Test `chữ vốn đã giản thể không bị quy` trong `test/trad2simp_test.dart` chốt lại điều này. Không sửa tay `assets/mappings/*.tsv`, luôn `dart run tool/build_trad2simp.dart`.
- **Related Files:** `tool/build_trad2simp.dart`, `assets/mappings/trad2simp.tsv`, `lib/features/glossary/application/glossary_sync_controller.dart`, `test/trad2simp_test.dart`

### 2026-08-07 - `trad2simp.tsv` chứa cặp ngược chiều, dịch Trung tự biến giản thể thành phồn thể

*Đã có rào chắn: `trad2simp_test.dart::Trad2SimpTable` — chốt `convert(convert(x)) == convert(x)`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*
- **Symptom:** Raw `席尔` (giản thể) qua mode Trung lại tra thành `席爾`, khớp nhầm mục phồn thể trong VietPhrase (`席爾=Llyr`) thay vì các mục `席尔…` đúng. Không lỗi, không cảnh báo — chỉ sai nghĩa.
- **Root Cause:** `cedict_ts.u8` có vài mục bị đảo cột (vd `提尔 提爾` — cột "phồn" lại là giản thể) hoặc lệch ký tự. `tool/build_trad2simp.dart` ghép ký tự theo vị trí nên sinh ra `尔→爾` (ngược chiều, nằm chung bảng với `爾→尔` đúng chiều) và cả cặp bậy tạo chuỗi (`託→托` trong khi `托→度`; `辛→緬` trong khi `緬→缅`). Tổng cộng 41 mắt xích rác.
- **Fix:** Generator đếm số lần xuất hiện cho từng cặp, rồi áp invariant "đích không bao giờ là nguồn của cặp khác" — gặp `a→b` mà `b→c` thì bỏ mắt xích nhẹ ký hơn, lặp tới khi hết chuỗi (luật này bao luôn cặp ngược chiều `a→b`/`b→a`). Regenerate bảng: 2579 → 2538 ký tự.
- **Do Not Repeat:** Bảng ánh xạ sinh tự động từ dữ liệu ngoài phải kiểm tra tính nhất quán, không tin cột nguồn. Invariant: quy đổi hai lần phải ra cùng kết quả (`convert(convert(x)) == convert(x)`) — còn cặp ngược chiều hay chuỗi thì kết quả sẽ dao động. Đã có test trong `test/trad2simp_test.dart`, mẫu thử phải gồm cả ký tự từng dính chuỗi (託麼麽衚鬍辛緬胡托么).
- **Ghi chú:** Cache `.vydc` của bộ dict Trung đã quy giản mang chữ ký bảng trong tên file (`Trad2SimpTable.signature`), nên sinh lại tsv là cache cũ tự bị bỏ qua — không cần nhớ xóa tay.
- **Related Files:** `tool/build_trad2simp.dart`, `assets/mappings/trad2simp.tsv`, `test/trad2simp_test.dart`

### 2026-07-25 - `WidgetStateTextStyle` trong `ChipThemeData.labelStyle` làm nhãn chip tàng hình

*Đã có rào chắn: `app_theme_test.dart::chipTheme`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*
- **Symptom:** Toàn bộ FilterChip ("Từ điển trong popup") mất chữ — nhãn render gần trắng trên nền trắng. `flutter analyze` sạch, `flutter test` pass; chỉ thấy được khi chụp màn hình app đang chạy.
- **Root Cause:** `Chip` resolve nhãn bằng `resolveAs<Color?>(effectiveLabelStyle.color, states)` rồi `effectiveLabelStyle.copyWith(color: resolved)`. Một `WidgetStateTextStyle` có `.color == null`, nên style rút gọn thành `TextStyle` trống và nhãn kế thừa màu ambient. Chip chỉ resolve theo trạng thái ở thuộc tính `color`, KHÔNG ở bản thân TextStyle.
- **Fix:** Dùng `TextStyle` thường với `color: WidgetStateColor.resolveWith(...)`. Hệ quả: chỉ đổi được MÀU theo trạng thái, không đổi được `fontWeight`.
- **Do Not Repeat:** Không đặt `WidgetStateTextStyle` vào `ChipThemeData.labelStyle`. Tổng quát hơn: thay đổi thuần theme không được analyzer/unit test bắt lỗi — phải xác minh bằng ảnh chụp app chạy thật hoặc test invariant về màu (xem `test/app_theme_test.dart`).
- **Related Files:** `lib/core/theme/app_theme.dart`, `lib/features/settings/settings_screen.dart`, `test/app_theme_test.dart`

### 2026-07-20 - Dialog action dùng context của widget gọi đã bị deactive

*Đã có rào chắn: `app_dialog.dart::actionsBuilder` — API bắt nhận `dialogContext`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*
- **Symptom:** Nút Hủy/Lưu trong dialog mở từ context menu báo `Looking up a deactivated widget's ancestor is unsafe` và không đóng dialog.
- **Root Cause:** Callback action giữ `BuildContext` của menu/widget gọi. Overlay context đó bị gỡ ngay sau khi mở dialog, nên `Navigator.of(context)` không còn hợp lệ.
- **Fix:** `showAppDialog` nhận `actionsBuilder(dialogContext)` và mọi action đóng bằng context thuộc chính route dialog; có widget test gỡ launcher trước khi bấm Hủy.
- **Do Not Repeat:** Callback sống lâu hơn overlay/menu mở nó phải dùng context của route/widget còn mounted, không capture context tạm của launcher.
- **Related Files:** `lib/shared/widgets/app_dialog.dart`, `lib/shared/widgets/entry_edit_dialog.dart`, `test/app_dialog_test.dart`

### 2026-07-18 - Flutter Windows accessibility_bridge AXTree crash (app tự tắt)

*Đã có rào chắn: `app.dart::ExcludeSemantics`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*
- **Symptom:** Log spam `[ERROR:...accessibility_bridge.cc(114)] Failed to update ui::AXTree, error: N will not be in the tree...` / `Nodes left pending by the update: ...` rồi `Lost connection to device` → app crash. Xuất hiện lúc khởi động và khi tra nghĩa online; số node đổi mỗi lần chạy.
- **Root Cause:** Bug engine Flutter Windows ở accessibility bridge — reconciliation cây semantics fail khi Windows AT poll (SelectableText.rich, SegmentedButton, NavigationRail, Tooltip đều có thể kích). KHÔNG sửa được bằng Dart, không phải lỗi widget cụ thể.
- **Fix:** Tắt cây semantics app-wide: `MaterialApp.builder: (c, child) => ExcludeSemantics(child: child ?? SizedBox.shrink())` trong `app.dart`. (Trước đó đã giữ `_OnlineLookupButton` không đổi loại widget khi loading — cần nhưng chưa đủ.)
- **Do Not Repeat:** Đừng đi tìm widget "thủ phạm" — đây là bug engine, blanket ExcludeSemantics là fix chuẩn. Đánh đổi: mất hỗ trợ screen-reader (chấp nhận cho desktop tool); chọn/copy text vẫn chạy. Nếu cần bật lại accessibility, phải nâng Flutter và test kỹ trên Windows.
- **Related Files:** `lib/app.dart` (MaterialApp.builder), `lacviet_panel.dart` (_OnlineLookupButton)

### 2026-07-19 - SudachiVariants sinh key thuần hiragana → してくれ dịch thành [tứ/bốn] て [chín] れ

*Đã có rào chắn: `build_sudachi_assets.dart::safeVariant` + `sudachi_data_test.dart` chốt trên file đã sinh. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*
- **Symptom:** Sau khi merge `data/jp/SudachiVariants.txt`, chuỗi ngữ pháp kana bị dịch bậy: `してくれ` → `し`=[tứ/bốn], `く`=[chín] (trước đó kana không match giữ nguyên).
- **Root Cause:** SudachiDict chuẩn hoá cả CÁCH ĐỌC kana về kanji (surface `し` normalized `四`, `く` → `九`...). Tool build chỉ lọc "canonical có trong VietPhrase, variant chưa có" nên sinh 6.285 key thuần hiragana; engine greedy match kana đơn giữa chuỗi ngữ pháp — Sudachi phân giải case này bằng lattice theo ngữ cảnh, VietYaku greedy thì không.
- **Fix:** `tool/build_sudachi_assets.dart` thêm `safeVariant()`: biến thể phải chứa ≥1 chữ Hán (okurigana 打込む→打ち込む) hoặc thuần katakana ≥2 code unit (ヴァイオリン→バイオリン); regenerate (20.465 → 13.677 mục). Test chốt chặn: `test/sudachi_data_test.dart`.
- **Do Not Repeat:** Mọi nguồn sinh key MỚI cho dict tham gia greedy match (VietPhrase/Names/UserDict) TUYỆT ĐỐI không được thêm key thuần hiragana — hiragana là vùng ngữ pháp. Chuẩn hoá cần ngữ cảnh thì không đưa vào dict tra thẳng (cùng nguyên tắc với quy tắc vàng jp_valid_kanji của repair).
- **Related Files:** `tool/build_sudachi_assets.dart`, `data/jp/SudachiVariants.txt`, `test/sudachi_data_test.dart`

### Tra online/AI lưu rồi nhưng click lại không hiện

*Đã có rào chắn: `user_dict_service.dart::upsertVietPhraseOverlay`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*

**Triệu chứng chung:** OnlineDict/AiDict đã có từ, click vào từ đó thì ô Nghĩa trống. Từ do AI tạo bấm "Xóa từ" cũng không mất (`比如铸铁者的冷面锡德`).

1. *Không tra lại được* — từ phải tra online/AI chính là từ VietPhrase **chưa có**; engine greedy vì thế cắt nó thành từng chữ (`再入荷` → `[再, 入荷]`), token sinh ra không bao giờ bằng key đã lưu nên `onlineDict.entries[word]` luôn trượt. 16/24 mục thật của người dùng dính lỗi này. Sửa: lưu xong thì thêm key vào overlay `VietPhrase_<mode>.txt` để engine cắt đúng cụm.

### Xóa từ do AI tạo không mất, người dùng thường xóa gì cũng no-op

*Đã có rào chắn: `user_dict_service.dart::removeGeneratedEntry`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*

**Triệu chứng chung:** OnlineDict/AiDict đã có từ, click vào từ đó thì ô Nghĩa trống. Từ do AI tạo bấm "Xóa từ" cũng không mất (`比如铸铁者的冷面锡德`).

2. *Không xóa được* — `stageLocalDelete` chỉ gỡ mục khỏi `SharedVietPhrase`; từ do AI tạo nằm ở overlay `VietPhrase_<mode>.txt`/`AiEntries_<mode>.txt` nên lệnh xóa chỉ ghi `__DELETE__` vào hàng chờ mà từ vẫn được dịch. Thêm nữa `if (!state.isAdmin) return;` khiến người dùng thường xóa gì cũng no-op im lặng. Sửa: `removeGeneratedEntry` gỡ cả hai overlay, chạy trước và không phụ thuộc quyền admin.

### Promote nghĩa tra online vào VietPhrase làm bẩn từ điển dịch

*Đã có rào chắn: `dict_entry_filter.dart::meaningMatchesWord` + `dict_entry_filter.dart::isWordLikeEntry` + `dict_entry_filter.dart::vietnameseLookupLabels`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*

**Bẫy đi kèm khi promote nghĩa online vào VietPhrase** (value VietPhrase chèn thẳng vào bản dịch nên sai là hỏng cả đoạn) — 3 rào chắn trong `dict_entry_filter.dart`:
- Nguồn online tra **mờ**: gõ `再入荷` trả mục của `再入`, `一愣` trả `eleven; 11` → `meaningMatchesWord` bắt buộc headword khớp đúng.
- Jisho/Youdao trả tiếng Anh, Weblio trả tiếng Trung → `vietnameseLookupLabels` chỉ nhận Mazii.
- Cả câu/mệnh đề không được vào từ điển dịch → `isWordLikeEntry` (≤10 rune, không dấu câu/khoảng trắng).

### Mazii mode Trung trả kết quả từ điển Nhật

*Đã có rào chắn: `mazii_api.dart::_hasKanaReading`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*

**Triệu chứng:** toàn bộ 35 mục `OnlineDict_chinese.txt` có phần Mazii là nghĩa của một từ tiếng Nhật khác hẳn — `一愣` → `eleven; 11`, `小正太` → `short sword`, `幸福` → `happiness` đọc `「こうふく」`.

**Nguyên nhân:** `https://mazii.net/api/search` **bỏ qua tham số `dict`**. Gửi `dict: "cnvi"` vẫn nhận về mục của từ điển Nhật (`phonetic` là kana, `pinyin` rỗng). Đã kiểm chứng bằng gọi API trực tiếp — lỗi còn sống, không phải dữ liệu cũ, nên xoá dữ liệu không thôi thì tra lại vẫn lưu rác.

**Sửa:** `MaziiApi.lookup` trả `null` khi `dict != 'javi'` mà kết quả có cách đọc kana. Mode Trung coi như Mazii miss; nguồn còn lại là 有道词典 (Trung→Anh).

**Bài học:** API không chính thức có thể im lặng bỏ qua tham số. Đừng tin `dict`/`lang` đã được tôn trọng — kiểm tra chính nội dung trả về có đúng ngôn ngữ không.

### Khởi động: nút title bar hiện icon Restore nhưng cửa sổ vẫn không maximize

*Đã có rào chắn: `window_maximize.dart::ensureWindowMaximized` + `win32_window.cpp::IsZoomed`. Giữ lại đây để biết vì sao hàm đó tồn tại — không làm theo hướng dẫn thủ công bên dưới nữa.*

**Triệu chứng:** thỉnh thoảng mở app, cửa sổ vẫn ở kích thước thường (1200×760) trong khi nút phóng to đã đổi sang icon Restore. Bấm nút đó chỉ "restore" về đúng chỗ cũ; muốn full màn hình phải bấm hai lần. Không lỗi, không log.

**Nguyên nhân:** trạng thái Win32 bị lệch — cờ `WS_MAXIMIZE` còn, nhưng khung cửa sổ đã bị `SetWindowPos` thu nhỏ. Hai chỗ trong runner mặc định của Flutter (`windows/runner/win32_window.cpp`) đụng vào cửa sổ sau khi `main.dart` gọi `windowManager.maximize()`:
1. `WM_DPICHANGED` gọi `SetWindowPos` với rect gợi ý. `SetWindowPos` đổi kích thước mà **không** xóa `WS_MAXIMIZE` → icon Restore + cửa sổ bé. DPI đổi ngay lúc khởi động khi cửa sổ được center rồi maximize trên máy nhiều màn hình khác mức scale → lỗi chỉ thỉnh thoảng mới xảy ra.
2. `Win32Window::Show()` dùng `SW_SHOWNORMAL`, mà engine gọi `Show()` qua `SetNextFrameCallback` **sau** khi `main()` đã maximize → `SW_SHOWNORMAL` khôi phục cửa sổ về kích thước thường.

`windowManager.maximize()` là `PostMessage(WM_SYSCOMMAND, SC_MAXIMIZE)` (bất đồng bộ) nên thứ tự với hai chỗ trên không định trước → lỗi không tái hiện đều.

**Sửa:** runner bỏ qua `SetWindowPos` khi `IsZoomed(hwnd)` (Windows tự resize cửa sổ maximize khi đổi DPI), `Show()` dùng `SW_SHOW`. Thêm `ensureWindowMaximized()` (`lib/core/window_maximize.dart`) chạy ở post-frame của `HomeShell`: nếu cờ báo maximized mà diện tích cửa sổ < 90% màn hình thì `unmaximize()` rồi `maximize()` lại.

**Bài học:** `windowManager.isMaximized()` chỉ đọc `WINDOWPLACEMENT.showCmd`, KHÔNG bảo đảm cửa sổ thật sự to — đừng dùng nó một mình làm điều kiện chặn maximize. Và mọi `SetWindowPos` có kích thước trong `win32_window.cpp` đều phải xét `IsZoomed`.

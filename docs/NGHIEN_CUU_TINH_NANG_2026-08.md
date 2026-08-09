# Nghiên cứu tính năng có thể bổ sung — VietYaku (chấm điểm 10)

**Ngày:** 2026-08-09
**Phạm vi:** VietYaku (Flutter Windows + Android), đối chiếu với `docs/NGHIEN_CUU_DINH_HUONG_PHAT_TRIEN.md` (2026-07-18)
**Câu hỏi:** App đã có dịch offline, tra đa từ điển, sửa/đồng bộ từ điển, EPUB converter, TTS, auto-update. Còn nên thêm gì, và mỗi thứ đáng bao nhiêu điểm?

---

## 1. Kết luận điều hành

Sau ~1 tháng kể từ nghiên cứu trước, VietYaku đã lấp gần hết khoảng trống **tra cứu** (4 nguồn online, Mazii offline, cụm từ điển phụ, Hán Việt, phồn→giản, TTS 2 giọng, glossary sync 2 chiều). Khoảng trống còn lại **không nằm ở chỗ tra thêm nghĩa** — mà ở ba chỗ khác:

1. **Công sức người dùng bốc hơi.** Ô "Bản dịch Việt" là `TextEditingController` thuần RAM (`viet_draft.dart:6`). Đóng app là mất trắng. Không có autosave, không mở file, không xuất bản dịch, không kéo-thả (`desktop_drop` đã không còn trong `pubspec.yaml`; `openFile` chỉ tồn tại ở màn EPUB). Người dịch một bộ truyện 200 chương hiện phải tự quản lý file bên ngoài app.
2. **Bồi từ điển vẫn mù.** App biết chính xác token nào không match, nhưng không nói cho người dùng biết. Không có báo cáo phủ, không có "top 50 từ chưa dịch trong chương này", không có phát hiện tên riêng. Đây là dữ liệu app đã có sẵn trong RAM nhưng đang vứt đi sau mỗi lượt dịch.
3. **Từ điển chung vẫn chỉ có add/edit.** Toàn bộ nhóm P0 của nghiên cứu tháng 7 (tombstone xóa, ghi file atomic, audit/rollback) **chưa được thực hiện** — grep `operation|deleted|delete` trong `lib/features/dictionary_sync/` không ra kết quả nào; `shared_dictionary_service` vẫn ghi đè trực tiếp, không temp+rename.

**Ba tính năng đáng làm nhất, theo điểm:**

| # | Tính năng | Điểm |
|---|---|---:|
| 1 | Autosave phiên làm việc + khôi phục khi mở lại | **9.3** |
| 2 | Báo cáo phủ + "top từ chưa dịch" của văn bản hiện tại | **9.0** |
| 3 | Từ điển theo bộ truyện (profile overlay) | **8.8** |

Tính năng #1 và #2 cộng lại ước chừng dưới một ngày công, và cả hai đều chỉ dùng dữ liệu app đã có.

---

## 2. Phương pháp chấm điểm

Điểm tổng là trung bình có trọng số của ba trục, mỗi trục thang 10:

- **V — Giá trị (45%):** mức độ giải quyết đau thật của người dịch tiểu thuyết Nhật/Trung. Không tính "hay ho".
- **F — Độ vừa vặn (30%):** hợp định vị offline/no-AI, hợp kiến trúc HashMap + overlay file + Riverpod manual. Buộc thay lõi → điểm thấp.
- **C — Chi phí đảo chiều (25%):** 10 = vài giờ, không thêm dependency; 1 = cần native runtime / đổi packaging / đổi model dữ liệu.

```
Điểm = 0.45·V + 0.30·F + 0.25·C
```

Cách tính này cố ý ưu ái thứ **rẻ và vừa vặn**, vì đây là dự án một người và mọi dependency native đều là nợ dài hạn (bài học đã ghi trong nghiên cứu tháng 7 về Sudachi/MeCab/OCR).

Điểm là đánh giá kỹ thuật tại thời điểm đọc code, **không phải số liệu người dùng**. Chưa có telemetry, chưa có beta tester.

---

## 3. Hiện trạng đã xác minh trong code

| Điều đã xác minh | Bằng chứng |
|---|---|
| Bản dịch Việt không được lưu ở bất kỳ đâu | `lib/features/translation/application/viet_draft.dart:6` — `Provider<TextEditingController>`, dispose là xong |
| Không mở được file văn bản vào ô Nguồn | `openFile` chỉ xuất hiện ở `epub_converter_screen.dart:27,100` |
| Không có kéo-thả | `desktop_drop` không có trong `pubspec.yaml` (PROJECT_SUMMARY.md dòng 150 đã lỗi thời) |
| Đồng bộ từ điển chung chưa có xóa | grep `operation\|deleted\|delete` trong `lib/features/dictionary_sync/` → 0 kết quả |
| Ghi overlay chưa atomic | `shared_dictionary_service` không dùng temp file + rename |
| `translate()` chạy đồng bộ trên UI thread | `translation_controller.dart:82` — `void translate(String)`, không isolate |
| Render kết quả đã virtualize | `token_text_view.dart:575` — `ListView.builder`, mỗi dòng một `SelectableText.rich`. Không cần tối ưu |
| Reading tiếng Nhật đã có cho từ nằm trong dict | `reading_extractor.dart` + `data/jp/SudachiReadings.txt` (43.996 mục). Chỉ thiếu OOV |

---

## 4. Nhóm 9.0+ — Nên làm ngay

### 4.1 Autosave phiên làm việc + khôi phục — **9.3** (V9 F10 C9)

**Vấn đề.** Người dùng dán một chương, click 200 lần để tra, gõ bản dịch Việt vào ô bên phải, rồi lỡ đóng app hoặc app crash → mất sạch. Đây không phải rủi ro lý thuyết: ô Việt là nơi duy nhất chứa lao động sáng tạo của người dùng, và nó là biến RAM.

**Đề xuất.** Ba mức, làm tăng dần:

1. **Mức tối thiểu (vài giờ):** debounce 2 giây → ghi `{sourceText, vietDraft, mode, caret}` xuống `userdata/session.json`. Mở app đọc lại, đổ vào ô Nguồn + ô Việt, **không tự dịch** (để người dùng bấm Dịch Lại nếu muốn — tránh tốn 300ms khởi động).
2. **Mức đủ dùng:** giữ N phiên gần nhất (`sessions/<timestamp>.json`), có menu "Mở lại phiên" liệt kê 20 dòng đầu của nguồn.
3. **Mức chuẩn:** thêm nút Lưu / Lưu thành / Mở, đặt tên phiên, hiện dấu `●` khi có thay đổi chưa lưu.

**Phác thảo kỹ thuật.** Thêm `lib/features/session/` (domain: `WorkSession`; data: `session_store.dart` đọc/ghi JSON trong `AppPaths`; application: `session_controller.dart` lắng nghe `translationControllerProvider` + `vietDraftControllerProvider`). Ghi file phải **atomic** ngay từ đầu (temp + rename) — không lặp lại lỗi của overlay đồng bộ.

**Rủi ro.** Gần như không. Điểm cần cẩn thận duy nhất: đừng autosave khi ô Nguồn rỗng (sẽ xóa mất phiên cũ).

---

### 4.2 Báo cáo phủ + "top từ chưa dịch" — **9.0** (V9 F10 C8)

**Vấn đề.** Quy trình bồi từ điển hiện tại là ngẫu nhiên: đọc tới đâu, thấy chữ lạ thì chuột phải sửa tới đó. Không ai biết chương này còn bao nhiêu % chưa dịch, và **từ nào đáng thêm nhất**.

**Đề xuất.** Một panel/dialog "Kiểm tra" cho văn bản đang mở, hiện:

- **Độ phủ:** % ký tự CJK đã match dict / tổng ký tự CJK. Một con số duy nhất, dễ theo dõi giữa các chương.
- **Bảng từ chưa dịch, xếp theo tần suất giảm dần:** `token chưa match × số lần xuất hiện × vị trí đầu tiên`. Click một dòng → nhảy tới vị trí; chuột phải → mở thẳng `entry_edit_dialog` để thêm vào dict.
- **Không nhất quán:** cùng một source term ra nhiều nghĩa khác nhau trong một chương (xảy ra khi UserDict và VietPhrase đá nhau, hoặc khi thuật toán chọn cụm khác nhau ở hai chỗ).
- **Cảnh báo rẻ tiền:** ngoặc `「」『』（）""` không cân bằng, số bị mất so với nguồn.

**Vì sao rẻ.** `engine.translate()` đã trả `List<Token>`, token không match đã được đánh dấu sẵn (cơ chế `secondary_phrase.dart` đang dựa vào đúng thông tin đó). Toàn bộ tính năng này là gom nhóm + đếm + một màn hình bảng. Không đụng engine, không đụng dữ liệu.

**Vì sao giá trị cao.** Nó biến "bồi từ điển" từ phản xạ thành quy trình có mục tiêu: mở chương → thấy 12 từ chiếm 60% chỗ thiếu → thêm 12 mục → phủ nhảy từ 88% lên 96%. Đây cũng là đầu vào tự nhiên cho việc publish lên từ điển chung.

---

## 5. Nhóm 8.0–8.9 — Nên làm sau đó

### 5.1 Từ điển theo bộ truyện (profile overlay) — **8.8** (V9 F9 C8)

**Vấn đề.** Tên nhân vật là thứ xung đột nặng nhất giữa các bộ truyện. `ハルカ` ở truyện A là "Haruka", ở truyện B lại là "Xuân Hương". Hiện chỉ có một `UserNames` toàn cục → dịch bộ mới là phải sửa lại, hoặc chấp nhận sai.

**Đề xuất.** Thêm một tầng overlay có tên: `userdata/profiles/<tên bộ>/{Names,UserDict}.txt`, chọn bằng dropdown ở menu bar cạnh nút Nhật/Trung. Thứ tự tie-break mới: **Profile > UserDict > Names > VietPhrase**.

**Phác thảo.** `dictionary_repository.loadAll` đã nạp 12 dict + overlay; thêm profile chỉ là thêm 1–2 file vào danh sách và một khóa vào `LoadedDictionaries`. `dictionariesProvider` watch thêm `currentProfileProvider` giống cách nó đang watch `currentModeProvider` — **lưu ý cùng cái bẫy vòng phụ thuộc Riverpod đã ghi trong IMPORTANT_FIXED_BUGS.md**, nên profile phải là provider độc lập, không đọc từ `translationControllerProvider`.

**Bonus gần như miễn phí.** Có profile rồi thì "xuất bộ tên riêng của truyện này để chia sẻ" chỉ là copy một file `.txt`.

### 5.2 Preview tác động trước khi sửa/publish entry — **8.2** (V7 F10 C8)

Dialog sửa entry hiện chỉ hỏi nghĩa mới. Nên hiện thêm: giá trị base ‖ giá trị shared hiện tại ‖ giá trị mới, **số lần key xuất hiện trong văn bản đang mở**, và cảnh báo key chứa `=`/newline/khoảng trắng đầu-cuối/sai script so với mode. Đếm occurrence là một vòng lặp trên `state.tokens` — rẻ, mà chặn được đúng loại lỗi tệ nhất: admin sửa một key phổ biến thành nghĩa sai rồi publish cho tất cả client.

### 5.3 Tombstone + ghi atomic + audit/rollback — **8.1** (V8 F10 C6)

Đây là P0 tồn đọng từ tháng 7, chi tiết thiết kế đã có sẵn ở `NGHIEN_CUU_DINH_HUONG_PHAT_TRIEN.md` §6.1–6.3, không nhắc lại. Ba việc theo thứ tự giá trị/chi phí:

1. **Ghi atomic** (`temp → flush → rename`, chỉ lưu cursor sau khi rename thành công) — vài chục dòng, chặn hỏng file overlay khi tắt máy giữa chừng.
2. **Tombstone** (`operation: delete` trong payload; client xóa key khỏi shared overlay, entry base tự lộ lại) — hiện **không có cách nào rút lại một entry đã publish sai**, chỉ có thể ghi đè bằng nghĩa khác.
3. **Audit + rollback** — cần đụng server, để sau cùng.

Điểm V=8 chứ không phải 10 vì đây là bảo hiểm, không phải tính năng người dùng nhìn thấy. Nhưng F=10: nó bảo vệ đúng thứ quý nhất của dự án.

### 5.4 Phát hiện tên riêng tự động — **8.1** (V8 F9 C7)

**Ý tưởng.** Chuỗi katakana ≥2 ký tự (mode Nhật) hoặc chuỗi Hán 2–3 ký tự (mode Trung) **lặp lại ≥3 lần** trong văn bản mà **không có trong Names cũng không có trong VietPhrase** → gần như chắc chắn là tên riêng. Hiện danh sách này, cho phép nhập nghĩa hàng loạt rồi ghi một lượt vào Names/profile.

Đây là mở rộng tự nhiên của §4.2 (dùng chung phần đếm tần suất token chưa match), nên nếu làm 4.2 trước thì cái này rẻ đi một nửa. Hợp đặc biệt với tiếng Nhật vì katakana là tín hiệu rất mạnh.

---

## 6. Nhóm 7.0–7.9 — Đáng làm khi có thời gian

### 6.1 Quy tắc hậu xử lý (regex find & replace) — **7.9** (V7 F9 C8)

Danh sách quy tắc do người dùng soạn, áp lên **kết quả** sau khi dịch: chuẩn hoá `「」`→`"`, gộp khoảng trắng thừa quanh dấu câu, thay các cách xưng hô cho nhất quán. Lưu thành file `.txt` theo profile, có nút bật/tắt từng nhóm và ô test thử.

**Nhận định quan trọng:** Luật Nhân (§6.3) chính là một trường hợp riêng của cơ chế này với placeholder `{0}`. Nếu định làm cả hai, hãy thiết kế một engine rule duy nhất và cho Luật Nhân là một loại rule — đừng viết hai hệ thống.

### 6.2 Search center / tra ngược từ điển — **8.1** (V8 F9 C7)

Hiện không có cách nào trả lời "từ điển có mục nào chứa 龍 không?" hay "mục nào có nghĩa chứa 'long vương'?". Đề xuất một tab tìm kiếm: exact / prefix / wildcard trên key, full-text trên nghĩa, lọc theo dict và mode, kết quả hiện lớp overlay nào đang thắng.

**Không cần database.** Quét tuyến tính 690k mục trong `Isolate.run` mất vài chục ms; kết quả stream về UI. Đúng nguyên tắc đã chốt: search là subsystem riêng, HashMap hot path giữ nguyên.

### 6.3 Luật Nhân (LuatNhan.txt) — **7.7** (V7 F10 C6)

211 rule dạng `把{0}挡住=ngăn cản {0}` đã có sẵn trong QuickTranslator_Jap; đây là feature parity còn thiếu, deterministic, offline, hợp kiến trúc tuyệt đối. Cần: parser có test cho `{0}`, giới hạn đệ quy/chồng lấn, thứ tự ưu tiên rõ, và một ô test rule. Người dùng đã chốt để đợt sau — điểm 7.7 xác nhận thứ tự đó là hợp lý, không phải bỏ.

### 6.4 Chế độ song ngữ theo câu — **7.3** (V8 F8 C5)

Tách câu theo `。！？\n` rồi hiện bảng ba cột `Nguồn ‖ VietPhrase ‖ Bản dịch của bạn`, mỗi câu một dòng, gõ thẳng vào cột ba. Đây là hình thái đúng cho công việc **biên tập** (khác với layout hiện tại tối ưu cho **đọc-tra**). Kết hợp autosave (§4.1) thì thành một trình biên tập bản dịch thực thụ mà không cần model project đầy đủ.

### 6.5 Clipboard reader + global hotkey — **7.3** (V8 F8 C5)

Bật/tắt rõ ràng; nghe `WM_CLIPBOARDUPDATE` qua FFI `win32` (thuần Dart, không cần plugin native mới); chỉ nhận text có CJK; debounce + hash chống lặp; bỏ qua clipboard do chính app ghi. Cho phép đọc raw ở trình duyệt/app khác mà không alt-tab. Kết hợp được với PowerToys Text Extractor để có OCR mà không phải nhúng OCR (kết luận này giữ nguyên từ tháng 7).

### 6.6 Hoàn tác sửa từ điển — **7.2** (V6 F9 C7)

Sửa nhầm một entry hiện không rút lại được ngoài việc nhớ nghĩa cũ và gõ lại. Giữ một stack `(dict, key, oldValue, newValue)` trong phiên, thêm Ctrl+Z + snackbar "Hoàn tác". Với admin thì đây là hàng rào cuối trước khi sai lệch lên server.

### 6.7 Dịch nền + tiến độ cho văn bản dài — **7.2** (V6 F9 C7)

`translate()` chạy đồng bộ trên UI thread. Một chương vài nghìn chữ thì không sao, nhưng dán cả quyển sẽ đơ. Nếu làm §4.1 (mở file) thì rủi ro này thành hiện thực. Cách rẻ: chia theo đoạn, dịch theo lô, `yield` giữa các lô, hiện thanh tiến độ + nút Hủy.

### 6.8 Sao lưu / khôi phục dữ liệu người dùng — **7.0** (V5 F9 C8)

Một nút xuất zip gồm UserDict, UserNames, OnlineDict, profiles, settings, phiên làm việc; một nút nhập lại. App đang chạy portable (`userdata/` cạnh exe) nên đây gần như là zip một thư mục — nhưng nó là thứ người dùng chỉ nhớ ra khi đã mất dữ liệu.

---

## 7. Bảng đầy đủ

| Tính năng | V | F | C | **Điểm** | Ghi chú |
|---|---:|---:|---:|---:|---|
| Autosave phiên + khôi phục | 9 | 10 | 9 | **9.3** | Rẻ nhất, chặn mất dữ liệu người dùng |
| Báo cáo phủ + top từ chưa dịch | 9 | 10 | 8 | **9.0** | Dùng dữ liệu engine đã có |
| Từ điển theo bộ truyện (profile) | 9 | 9 | 8 | **8.8** | Giải quyết xung đột tên nhân vật |
| Mở/kéo-thả file + chương + xuất bản dịch | 10 | 9 | 5 | **8.5** | Nối được với EPUB parser sẵn có |
| Preview tác động trước khi sửa/publish | 7 | 10 | 8 | **8.2** | Chặn lỗi admin hàng loạt |
| Tombstone + atomic write + audit | 8 | 10 | 6 | **8.1** | P0 tháng 7 còn treo |
| Search center / tra ngược từ điển | 8 | 9 | 7 | **8.1** | Isolate scan, không cần DB |
| Phát hiện tên riêng tự động | 8 | 9 | 7 | **8.1** | Rẻ đi một nửa nếu làm sau báo cáo phủ |
| Quy tắc hậu xử lý (regex) | 7 | 9 | 8 | **7.9** | Luật Nhân là trường hợp riêng |
| Luật Nhân + rule tester | 7 | 10 | 6 | **7.7** | Parity với QuickTranslator |
| Chế độ song ngữ theo câu | 8 | 8 | 5 | **7.3** | Hình thái đúng cho biên tập |
| Clipboard reader + global hotkey | 8 | 8 | 5 | **7.3** | FFI win32, không cần plugin mới |
| Hoàn tác sửa từ điển | 6 | 9 | 7 | **7.2** | Hàng rào cuối cho admin |
| Dịch nền + tiến độ | 6 | 9 | 7 | **7.2** | Bắt buộc nếu mở file lớn |
| Sao lưu/khôi phục dữ liệu người dùng | 5 | 9 | 8 | **7.0** | Zip một thư mục |
| TTS đọc cả đoạn + highlight câu | 6 | 9 | 6 | **6.9** | Giá trị cho người học |
| Cuộn đồng bộ giữa các pane | 6 | 9 | 6 | **6.9** | Highlight đã đồng bộ, cuộn thì chưa |
| Chế độ đọc một cột | 5 | 8 | 8 | **6.7** | Tách "đọc" khỏi "biên tập" |
| Lịch sử tra cứu (quay lại từ đã xem) | 5 | 8 | 8 | **6.7** | Rẻ, tiện |
| Batch dịch cả thư mục | 5 | 8 | 6 | **6.2** | Cần model project trước |
| Furigana OOV (fallback KANJIDIC) | 6 | 7 | 5 | **6.1** | Rẻ hơn MeCab, đúng ít hơn |
| Đồng bộ UserDict cá nhân qua server | 6 | 7 | 5 | **6.1** | Cần vai trò user thường |
| Translation memory câu | 7 | 6 | 3 | **5.7** | Cần model project trước |
| Cầu nối sang AI_Translation_Bridge | 6 | 5 | 6 | **5.7** | Giữ AI ở ngoài app |
| Fuzzy match / gợi ý key còn sót | 5 | 7 | 5 | **5.6** | Sau khi có search center |
| TMX/TBX import/export | 3 | 6 | 6 | **4.7** | Interop, chưa có nhu cầu |
| Anki / flashcard export | 3 | 4 | 7 | **4.3** | "Lưu từ" đã bị loại khỏi scope |
| OCR nhúng | 4 | 3 | 2 | **3.2** | Clipboard + PowerToys rẻ hơn nhiều |
| AI engine trong đường dịch mặc định | 4 | 2 | 2 | **2.9** | Mâu thuẫn định vị offline |
| Hỗ trợ tiếng Hàn | 2 | 3 | 3 | **2.6** | Không có dữ liệu VietPhrase KR |

---

## 8. Những thứ tiếp tục **không** nên làm

Giữ nguyên kết luận tháng 7, có bổ sung:

- **Không thay HashMap bằng DB/trie.** Search center là subsystem riêng, không đụng hot path.
- **Không nhúng OCR trước khi có clipboard bridge.** `Windows.Media.Ocr` kéo theo MSIX, phá bản portable `userdata/` cạnh exe vừa mới chốt.
- **Không đưa AI vào đường dịch mặc định.** Hệ sinh thái đã có AI_Translation_Bridge; nếu cần AI thì nối hai app (điểm 5.7), đừng nhúng.
- **Không làm TM câu trước khi có model project.** TM không có project là một file jsonl không ai mở.
- **Không làm proposal/approval workflow** khi vẫn chỉ có một admin.
- **Mới:** không thêm nguồn tra online thứ 5. Bốn nguồn hiện tại đã phủ Nhật/Trung ở cả bốn hướng ngôn ngữ; nguồn thứ 5 thêm điểm hỏng chứ không thêm thông tin.

---

## 9. Sprint tiếp theo được khuyến nghị

Nếu chỉ chọn một gói việc, chọn **"Không mất công của người dùng"** — ba mục ăn khớp nhau và đều rẻ:

1. `session_store` ghi atomic + autosave debounce 2s + khôi phục lúc mở app.
2. Nút Mở / Lưu bản dịch (`.txt`) ở màn Dịch, dùng `file_selector` đã có sẵn trong pubspec.
3. Dialog "Kiểm tra": % phủ + bảng từ chưa dịch theo tần suất + click để thêm vào dict.

**Tiêu chí hoàn tất:** đóng app giữa lúc dịch rồi mở lại, ô Nguồn và ô Việt còn nguyên; mở một chương `.txt` bất kỳ, bấm Kiểm tra, thấy độ phủ và danh sách từ thiếu; thêm 5 từ từ chính danh sách đó và thấy độ phủ tăng.

Gói này không đụng engine, không đụng định dạng dữ liệu từ điển, không thêm dependency — nên rủi ro gần như bằng không, trong khi nó vá đúng chỗ hiện đang mất mát nhiều nhất.

Gói thứ hai đề nghị là **"Toàn vẹn từ điển chung"** (§5.2 + §5.3), vì càng publish nhiều entry thì càng đắt để sửa sau.

---

## 10. Hạn chế của nghiên cứu

- Không có telemetry, không có beta tester; V (giá trị) là suy luận từ đặc thù công việc dịch tiểu thuyết, không phải đo đạc.
- C (chi phí) ước lượng từ việc đọc code, chưa prototype. Riêng clipboard FFI và tách câu tiếng Nhật/Trung có thể đắt hơn dự kiến.
- Chưa đo hiệu năng `translate()` với văn bản >100k ký tự — điểm của §6.7 dựa trên suy luận kiến trúc, chưa benchmark.
- Không đánh giá lại các mục đã có kết luận rõ ở nghiên cứu tháng 7 (TMX/TBX, RBAC, MongoDB Change Streams); chỉ mang điểm số sang.

## AI disclosure

Báo cáo do Claude soạn dựa trên đọc trực tiếp code VietYaku ngày 2026-08-09, `docs/NGHIEN_CUU_DINH_HUONG_PHAT_TRIEN.md` và `.claude/PROJECT_SUMMARY.md`. Các claim về hiện trạng code có dẫn file/dòng và đã được xác minh bằng grep. Điểm số là đánh giá kỹ thuật, cần xác nhận bằng phản hồi thực tế khi dùng.

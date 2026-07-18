# Nghiên cứu định hướng phát triển VietYaku và LittleKai Server

**Ngày nghiên cứu:** 2026-07-18  
**Phạm vi:** VietYaku (Flutter Windows) và luồng đồng bộ từ điển chung trên LittleKai Server  
**Câu hỏi nghiên cứu:** Sau khi đã có dịch offline Nhật/Trung sang Việt, tra cứu nhiều từ điển, sửa từ điển local và đồng bộ delta VietPhrase/Lạc Việt do admin quản lý, sản phẩm còn nên phát triển gì để tạo giá trị rõ ràng mà không làm hỏng kiến trúc offline-first?

## 1. Kết luận điều hành

VietYaku vẫn còn dư địa phát triển lớn, nhưng hướng có giá trị nhất không phải là thêm một engine dịch khác. Sản phẩm nên tiến từ một trình dịch dựa trên từ điển thành **môi trường biên tập bản dịch offline**, với ba trụ cột:

1. **Từ điển chung có vòng đời đầy đủ:** xóa bằng tombstone, lịch sử thay đổi, diff, rollback, kiểm tra trước khi publish, ghi file client an toàn và phiên admin có thể thu hồi.
2. **Bảo đảm chất lượng bản dịch:** phát hiện từ chưa phủ, tên/thuật ngữ không nhất quán, số và dấu câu bất thường, cùng một cụm bị dịch nhiều cách, và tác động của entry mới lên văn bản hiện tại.
3. **Quy trình dịch theo dự án:** nhiều chương/file, autosave, trạng thái đoạn, exact translation memory, concordance và batch TXT trước khi mở rộng sang EPUB/TMX/TBX.

Thứ tự khuyến nghị:

- **P0:** độ bền đồng bộ, xóa/lịch sử/rollback, bảo mật admin.
- **P1:** màn hình quản trị từ điển, QA trên văn bản hiện tại, clipboard reader, dự án TXT và exact translation memory.
- **P2:** Luật Nhân, fuzzy TM/concordance, furigana và phân tích hình thái qua plugin tùy chọn, search center, chuẩn trao đổi TMX/TBX.
- **P3:** OCR nhúng, cộng tác nhiều vai trò, Anki và AI tùy chọn.

Kết luận này dựa trên đối chiếu code hiện tại với tài liệu chính thức của OmegaT, memoQ, Yomitan, GoldenDict-ng, Microsoft Windows, W3C, ISO, IETF, MongoDB, OWASP và Vercel. Đây là nghiên cứu sản phẩm và kiến trúc, không phải nghiên cứu người dùng định lượng; cần beta test để xác nhận thứ tự sau P0.

## 2. Phương pháp nghiên cứu

### 2.1 Nguồn nội bộ

Các thành phần được đối chiếu trực tiếp:

- `lib/features/dictionary_sync/`: đăng nhập admin, publish và pull delta.
- `lib/features/dictionary/data/dictionary_repository.dart`: base dictionary cộng local/shared overlay.
- `lib/shared/widgets/entry_edit_dialog.dart`: luồng sửa local và publish từ điển chung.
- `../LittleKai-server/routes/glossary.js`: cursor delta public và admin write.
- `../LittleKai-server/models/GlobalGlossary.js`: trạng thái mới nhất của entry.
- `../LittleKai-server/routes/auth.js`: JWT admin.

### 2.2 Nguồn bên ngoài

Chỉ ưu tiên tài liệu chính thức, tiêu chuẩn hoặc repository gốc. Tài liệu marketing của nhà cung cấp được dùng để xác nhận sự tồn tại của tính năng, không được xem là bằng chứng rằng tính năng đó chắc chắn phù hợp với VietYaku.

Nhóm nguồn:

- CAT tools: OmegaT, memoQ.
- Công cụ đọc/tra từ: Yomitan, GoldenDict-ng, Pleco.
- Phân tích Nhật ngữ: Sudachi, MeCab.
- Nền tảng Windows: Clipboard, OCR, screen capture.
- Chuẩn trao đổi: TMX, TBX, XLIFF, EPUB.
- Đồng bộ và bảo mật: RFC 9110/9111, MongoDB, OWASP, Vercel.

### 2.3 Tiêu chí đánh giá

Mỗi cơ hội được đánh giá theo bốn yếu tố:

- **Giá trị người dùng:** giảm thao tác, giảm lỗi hay mở được workflow mới.
- **Phù hợp sản phẩm:** có phục vụ dịch tiểu thuyết Nhật/Trung và offline-first hay không.
- **Phù hợp kiến trúc:** có giữ HashMap, file overlay và Riverpod hiện tại hay buộc thay lõi.
- **Nỗ lực/rủi ro:** phụ thuộc native runtime, server state, bản quyền dữ liệu và độ khó kiểm thử.

Các mức P0-P3 là đánh giá kỹ thuật tại thời điểm nghiên cứu, không phải số liệu từ telemetry.

## 3. Bản đồ năng lực hiện tại

### 3.1 Điểm mạnh đã có

- Dịch offline nhanh bằng greedy longest-match với nhiều thuật toán chọn cụm.
- Hai bộ dữ liệu Nhật/Trung, nhiều nguồn nghĩa, Hán Việt, TTS và tra online tùy chọn.
- Base dictionary không bị ghi đè; UserDict/UserNames và shared VietPhrase/Lạc Việt là overlay riêng.
- Cache `.vydc`, isolate load và định dạng text đơn giản giúp khởi động nhanh, dễ khôi phục.
- Admin publish entry; mọi app pull theo opaque cursor và chỉ nhận trạng thái mới hơn cursor.
- JWT chỉ giữ trong RAM phía app; mật khẩu không ghi xuống đĩa.
- Sửa entry xong reload từ điển và dịch lại văn bản hiện tại ngay.

### 3.2 Khoảng trống quan trọng

#### Đồng bộ và quản trị

- Chưa có thao tác xóa shared entry. Xóa một overlay phải làm lộ lại nghĩa base, không được xóa entry trong bộ từ điển gốc.
- Chưa có lịch sử `oldValue -> newValue`, lý do sửa, diff hay rollback.
- Admin publish trực tiếp, chưa có preview tác động và cảnh báo xung đột.
- Server lưu trạng thái mới nhất đủ cho delta add/edit, nhưng không đủ cho audit đầy đủ.
- Client ghi đè file shared overlay trực tiếp. Nếu tiến trình dừng giữa lúc ghi, file cũ có thể bị cắt/hỏng.
- Chưa có manifest/checksum để phát hiện overlay hỏng và rebuild từ server.

#### Bảo mật

- JWT hiện có hạn `365d` và middleware tin quyền `admin` trong token. Nếu tài khoản bị hạ quyền hoặc cần thu hồi, token cũ vẫn có thể publish cho tới khi hết hạn.
- Chưa thấy rate limit riêng cho login/publish.
- Cơ chế “user đầu tiên là admin” dựa trên `countDocuments()` cần được thay bằng bootstrap rõ ràng và atomic trước khi mở server công khai.

#### Quy trình biên tập

- Chưa có project/chapter, autosave, trạng thái draft/reviewed hay batch export.
- Chưa lưu cặp câu nguồn-đích đã được người dùng sửa, nên không tái sử dụng câu lặp lại.
- Chưa có QA toàn văn cho thuật ngữ, tên riêng, số, dấu câu, ký tự lạ và phần CJK chưa dịch.
- Chưa có concordance để xem một từ/cụm từng xuất hiện và được dịch ra sao trong ngữ cảnh khác.

#### Ngôn ngữ và nhập liệu

- Chưa có deinflection/lemma/furigana dựa trên phân tích hình thái tiếng Nhật.
- Chưa có luồng lấy text từ ứng dụng khác qua clipboard listener/hotkey.
- OCR nhúng chưa phù hợp ngay với bản phát hành exe độc lập hiện tại.

## 4. Điều học được từ các công cụ liên quan

### 4.1 CAT tools: giá trị nằm ở tái sử dụng và QA

OmegaT xem fuzzy matching, match propagation, dự án nhiều file, nhiều translation memory và glossary là các tính năng chuyên nghiệp cốt lõi. Công cụ cũng dùng TMX để trao đổi dữ liệu với hệ sinh thái CAT khác. [OmegaT - Professional features](https://omegat.org/) và [OmegaT - Privacy/project memory](https://omegat.org/policies).

memoQ tách rõ:

- **Termbase:** thuật ngữ/cụm được yêu cầu dùng nhất quán, có local/online/offline, nhiều termbase và khả năng kiểm duyệt entry mới. [memoQ - Term bases](https://docs.memoq.com/current/en/Concepts/concepts-term-bases.html)
- **Translation memory:** lưu segment nguồn-đích đã xác nhận, trả exact/fuzzy match và ưu tiên bản đã review. [memoQ - Translation memories](https://docs.memoq.com/current/en/Workspace/project-home-translation-memories.html)
- **Concordance:** tìm từ/cụm trong các cặp câu cũ và hiển thị ngữ cảnh. [memoQ - Concordance](https://docs.memoq.com/10-3/en/Places/concordance.html)
- **QA:** kiểm tra thuật ngữ, số, khoảng trắng, dấu câu, độ dài, ký tự và tính nhất quán. [memoQ - QA warnings](https://docs.memoq.com/current/en/Concepts/concepts-quality-assurance-qa-warnings.html)

Suy luận cho VietYaku: không nên nhét bản dịch cấp câu vào VietPhrase. VietPhrase/Lạc Việt tiếp tục giải quyết từ/cụm; một translation memory nhẹ giải quyết câu/segment đã biên tập.

### 4.2 Công cụ đọc: tra ngay trong ngữ cảnh quan trọng hơn thêm tab

Yomitan tập trung vào popup tại vị trí đọc, nhiều dictionary, audio, frequency, reading và xuất Anki. Giá trị chính là người dùng không rời luồng đọc để tra cứu. [Yomitan](https://yomitan.wiki/) và [Yomitan repository](https://github.com/yomidevs/yomitan).

GoldenDict-ng hỗ trợ nhiều format từ điển, full-text search, quy mô hàng triệu headword và Anki integration. [GoldenDict-ng repository](https://github.com/xiaoyifang/goldendict-ng) và [GoldenDict-ng documentation](https://xiaoyifang.github.io/goldendict-ng/).

Pleco cung cấp tap-to-lookup, clipboard reader, lịch sử vị trí đọc, OCR và flashcard cho tiếng Trung. [Pleco](https://www.pleco.com/) và [Pleco Reader](https://android.pleco.com/manual/310/reader.html).

Suy luận cho VietYaku: clipboard reader và search center có giá trị cao hơn việc thêm nhiều màn hình tra online. App đã có nhiều nguồn nghĩa; bước tiếp theo là đưa chúng tới đúng ngữ cảnh nhanh hơn.

### 4.3 Phân tích hình thái có thể bổ sung, không thay engine

Sudachi cung cấp nhiều mức segmentation, dictionary form, reading form, part-of-speech, normalization và OOV flag. [Sudachi repository](https://github.com/WorksApplications/Sudachi).

MeCab là engine phân tích hình thái C/C++ có xử lý từ chưa biết, N-best và API thư viện; tài liệu chính thức mô tả nó nhanh hơn một số công cụ cùng loại trong thiết kế ban đầu. [MeCab](https://taku910.github.io/mecab/) và [MeCab library](https://taku910.github.io/mecab/libmecab.html).

Suy luận cho VietYaku:

- Furigana/deinflection có thể là một lớp phân tích tùy chọn chạy sau khi dịch hoặc khi lookup.
- Không nên thay greedy HashMap bằng Sudachi/MeCab. Hai lớp giải quyết hai bài toán khác nhau.
- Native binary/dictionary làm tăng kích thước bản phát hành và chi phí đóng gói; vì vậy nên là plugin/tùy chọn P2.

### 4.4 OCR nên đi qua clipboard trước

PowerToys Text Extractor đã cung cấp hotkey chọn vùng, OCR rồi đưa text vào clipboard. [Microsoft PowerToys Text Extractor](https://learn.microsoft.com/en-us/windows/powertoys/text-extractor).

Windows có `WM_CLIPBOARDUPDATE`/`AddClipboardFormatListener`, cho phép nhận sự kiện thay đổi thay vì polling. [Microsoft - AddClipboardFormatListener](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-addclipboardformatlistener).

`Windows.Media.Ocr` yêu cầu desktop app có package identity/MSIX. VietYaku hiện phát hành exe độc lập, nên dùng API này sẽ kéo theo thay đổi packaging. [Microsoft - Windows.Media.Ocr](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr).

Nếu sau này cần OCR nhúng đa nền tảng, Tesseract hỗ trợ UTF-8 và hơn 100 ngôn ngữ nhưng chất lượng phụ thuộc mạnh vào ảnh đầu vào; PaddleOCR có model đa ngôn ngữ gồm Trung/Nhật nhưng thêm runtime/model đáng kể. [Tesseract](https://github.com/tesseract-ocr/tesseract) và [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR).

Suy luận: P1 nên làm clipboard listener tương thích PowerToys/ShareX/Capture2Text. Embedded OCR chỉ được nâng ưu tiên nếu beta users thực sự cần và chấp nhận MSIX/native runtime.

## 5. Ma trận cơ hội

| Cơ hội | Giá trị | Phù hợp | Nỗ lực | Ưu tiên | Nhận định |
|---|---:|---:|---:|---|---|
| Atomic write + recovery shared overlay | 5 | 5 | 2 | P0 | Bảo vệ dữ liệu đã sync, không tạo UI phức tạp |
| Tombstone xóa shared entry | 5 | 5 | 2 | P0 | Hoàn thiện đúng nghĩa add/edit/delete |
| Audit history + diff + rollback | 5 | 5 | 3 | P0 | Giảm rủi ro admin sửa sai hàng loạt |
| Thu hẹp/revoke phiên admin + rate limit | 5 | 5 | 2 | P0 | Quyền ghi từ điển chung là tài sản nhạy cảm |
| Preview tác động trước publish | 5 | 5 | 2 | P0/P1 | Cho thấy base/shared hiện tại và số occurrence |
| QA văn bản hiện tại | 5 | 5 | 3 | P1 | Phát hiện lỗi thật mà không đổi engine |
| Màn hình quản trị/search shared entries | 4 | 5 | 3 | P1 | Không thể quản trị dài hạn chỉ bằng context menu |
| Clipboard reader + global hotkey | 4 | 5 | 2 | P1 | Nối VietYaku với OCR/browser/app khác |
| Project/chapter + autosave + batch TXT | 5 | 5 | 4 | P1 | Mở workflow dịch tiểu thuyết thực tế |
| Exact translation memory | 5 | 4 | 4 | P1 | Tái dùng câu lặp lại, vẫn tách khỏi VietPhrase |
| Luật Nhân + rule tester | 4 | 5 | 3 | P2 | Đã có dữ liệu backlog, phù hợp engine deterministic |
| Fuzzy TM + concordance | 4 | 4 | 4 | P2 | Hữu ích sau khi đã có đủ segment đã xác nhận |
| Furigana/deinflection plugin | 4 | 3 | 5 | P2 | Giá trị cao cho Nhật nhưng native packaging khó |
| Full-text dictionary search | 4 | 4 | 3 | P2 | Hữu ích khi cần tìm theo nội dung nghĩa |
| TMX/TBX import/export | 3 | 4 | 3 | P2 | Interoperability, không phải workflow đầu tiên |
| Proposal/approval cho user thường | 3 | 3 | 4 | P2/P3 | Chỉ đáng làm khi có nhiều contributor |
| Embedded OCR | 3 | 2 | 5 | P3 | Clipboard OCR bên ngoài rẻ và linh hoạt hơn |
| Anki export | 2 | 2 | 3 | P3 | “Lưu từ” từng bị loại khỏi scope |
| AI translation/editor trong app | 2 | 2 | 5 | Hoãn | Mâu thuẫn định vị offline/no-AI hiện tại nếu làm mặc định |

## 6. Thiết kế khuyến nghị cho P0

### 6.1 Giữ current-state sync, thêm audit log riêng

Cơ chế `GlobalGlossary` hiện tại có một document mới nhất cho mỗi `(language, kind, source)` và cập nhật `revision`. Đây là thiết kế hiệu quả cho client: nếu admin sửa cùng một key nhiều lần khi app offline, app chỉ cần trạng thái cuối cùng.

Không nên thay ngay bằng việc bắt mọi client replay toàn bộ event log. Thiết kế đề xuất:

#### `GlobalGlossary` - trạng thái đang có hiệu lực

```text
term_id
language
kind                  # vietPhrase | lacViet
source
target                # nullable/ignored khi deleted=true
deleted
revision
last_updated_by
updated_at
```

#### `GlossaryChange` - audit append-only

```text
revision
ordinal               # thứ tự trong một batch
term_id
language
kind
operation              # upsert | delete | rollback
source
old_target
new_target
actor_id
reason
request_id             # idempotency/audit
created_at
```

`GlobalGlossary` tiếp tục phục vụ public delta. `GlossaryChange` phục vụ history, diff, rollback và điều tra lỗi. Rollback không sửa lịch sử cũ; nó tạo một revision mới có giá trị lấy từ revision trước.

Nếu cần bảo đảm audit và current state luôn nhất quán, counter + insert history + update current state nên nằm trong cùng MongoDB transaction. Nếu chưa dùng transaction, phải có idempotency key và job đối soát; không được âm thầm chấp nhận trạng thái “current đã đổi nhưng history chưa ghi”.

### 6.2 Tombstone

Payload delta nên có operation rõ ràng:

```json
{
  "source": "対象語",
  "kind": "vietPhrase",
  "operation": "delete",
  "revision": 1234
}
```

Khi nhận `delete`, client chỉ xóa key khỏi `SharedVietPhrase_<mode>.txt` hoặc `SharedLacViet_<mode>.txt`. Entry base cùng key sẽ tự hiện lại qua thứ tự overlay. Không bao giờ sửa/xóa file bundle.

Tombstone không nên bị purge tùy tiện vì server hiện không biết mọi client đã tiến tới revision nào. Nếu sau này cần compaction, manifest phải có `min_supported_revision`; client cũ hơn mốc đó buộc rebuild snapshot shared overlay.

### 6.3 Ghi file atomic và recovery

Luồng client đề xuất:

1. Đọc overlay hiện tại.
2. Áp dụng upsert/delete vào map trong RAM.
3. Ghi UTF-8 BOM + CRLF vào file tạm trong cùng thư mục.
4. Flush file tạm.
5. Rename/replace atomic sang file chính; giữ một backup ngắn hạn nếu Windows replace thất bại.
6. Chỉ lưu cursor sau khi replace thành công.

Nếu app dừng sau bước 5 nhưng trước bước 6, lần sync sau chỉ reapply delta, vốn idempotent. Nếu checksum overlay sai, app xóa overlay hỏng, reset cursor về 0 và rebuild từ current state trên server.

### 6.4 Manifest và conditional request

Thêm endpoint nhỏ:

```text
GET /api/glossary/sync/manifest?language=japanese

latest_revision
min_supported_revision
schema_version
active_entry_count
state_hash (tùy chọn)
```

Manifest có `ETag`. App gửi `If-None-Match`; server/CDN trả `304 Not Modified` nếu không đổi. RFC 9110 nêu `If-None-Match` dùng cho conditional GET để cập nhật cache với transaction overhead tối thiểu. [RFC 9110 section 13.1.2](https://www.rfc-editor.org/rfc/rfc9110.html#name-if-none-match). RFC 9111 mô tả cache giúp giảm response time và bandwidth. [RFC 9111](https://www.rfc-editor.org/rfc/rfc9111.html).

Manifest phù hợp để:

- kiểm tra update nền mà không tải page rỗng;
- hiển thị badge có thay đổi;
- phát hiện cursor quá cũ;
- quyết định rebuild khi schema thay đổi.

Chưa cần WebSocket hoặc MongoDB Change Streams. MongoDB có resume token cho stream, nhưng stream dài hạn không phù hợp bằng polling/cache cho app desktop ít write chạy trên Vercel serverless. [MongoDB Change Streams](https://www.mongodb.com/docs/manual/changeStreams/). Chỉ xem xét real-time khi có số liệu cho thấy polling gây tải đáng kể.

### 6.5 Preview và validation trước publish

Dialog admin nên hiển thị:

- giá trị base;
- giá trị shared hiện tại;
- giá trị mới;
- loại từ điển và mode;
- số lần key xuất hiện trong văn bản đang mở;
- cảnh báo key chứa `=`, newline, null, khoảng trắng đầu/cuối hoặc script không phù hợp mode;
- diff nghĩa cũ/mới;
- trường `reason` ngắn cho audit.

Nút publish chỉ gửi một batch đã validate. Server vẫn là nguồn validation cuối cùng; client validation chỉ cải thiện UX.

### 6.6 Bảo mật admin

OWASP khuyến nghị timeout được thực thi phía server, tái xác thực ở hành động rủi ro và MFA cho tài khoản quan trọng. [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html) và [OWASP Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html).

Thay đổi tối thiểu:

- bỏ JWT `365d`; dùng access token ngắn theo phiên làm việc;
- vì app không lưu token, có thể yêu cầu login lại khi mở app thay vì xây refresh-token phức tạp ngay;
- kiểm tra role hiện tại hoặc `token_version` phía DB ở endpoint publish/delete/rollback;
- tăng `token_version` khi đổi mật khẩu, hạ quyền hoặc thu hồi mọi phiên;
- rate limit `/api/auth/login` và endpoint admin;
- bootstrap admin bằng biến môi trường/CLI migration hoặc thao tác atomic, không dựa vào hai request cùng thấy `count=0`;
- audit actor và request id cho mọi thay đổi.

Vercel WAF hỗ trợ rate limit theo nguồn và trả `429`; có thể log trước khi bật deny để chọn ngưỡng. [Vercel WAF Rate Limiting](https://vercel.com/docs/vercel-firewall/vercel-waf/rate-limiting).

## 7. Thiết kế khuyến nghị cho P1

### 7.1 Màn hình quản trị từ điển chung

Thêm một view dành cho admin, không đặt mọi chức năng trong context menu:

- search theo key/target;
- filter Nhật/Trung, VietPhrase/Lạc Việt, actor, thời gian;
- xem base/shared side-by-side;
- history theo entry;
- diff và rollback;
- bulk import preview;
- danh sách conflict/validation errors.

Runtime client thường vẫn chỉ tải `source`, `target`, `kind`, `operation`, `revision`. Metadata audit không đi vào payload public để giữ nhỏ.

### 7.2 QA trên văn bản hiện tại

MVP QA nên deterministic và chạy khi bấm “Kiểm tra”, sau dịch hoặc sau sync, không quét toàn bộ dictionary sau mỗi phím.

Các rule có giá trị cao:

1. CJK còn nguyên trong kết quả nhưng không thuộc danh sách cho phép.
2. Cùng source term có nhiều target trong một chương.
3. Tên riêng bị dịch không nhất quán.
4. Số/đơn vị bị mất hoặc thay đổi bất thường.
5. Dấu ngoặc/ngoặc kép không cân bằng.
6. Khoảng trắng hoặc dấu câu lặp.
7. Entry shared mới làm thay đổi số lượng match quá lớn so với preview.
8. Key dictionary là prefix/suffix của key khác và làm giảm match mong muốn theo thuật toán đang chọn.

Kết quả QA cần trỏ đến vị trí, cho phép bỏ qua có chủ đích và không tự sửa hàng loạt nếu chưa preview.

### 7.3 Clipboard reader

MVP:

- toggle bật/tắt rõ ràng;
- native listener theo `WM_CLIPBOARDUPDATE`, không polling;
- chỉ nhận text có CJK;
- debounce và hash để không dịch lặp;
- bỏ qua clipboard do chính VietYaku ghi;
- tùy chọn tự “Dán & Dịch” hoặc chỉ hiện notification;
- global hotkey đưa app lên foreground;
- lịch sử ngắn hạn local, mặc định tắt hoặc có nút xóa nhanh.

Clipboard có thể chứa mật khẩu hoặc dữ liệu riêng tư. Không upload clipboard và không lưu lâu nếu người dùng chưa bật rõ ràng.

### 7.4 Project TXT và exact translation memory

Không bắt đầu bằng DOCX/EPUB. MVP project:

```text
project.json
source/*.txt
segments.jsonl
target/*.txt
project_glossary.txt
tm.jsonl
backups/
```

Mỗi segment lưu:

```text
segment_id
source
machine_output
edited_target
status               # draft | reviewed
updated_at
source_hash
```

Khi người dùng xác nhận `edited_target`, ghi exact TM. Lần sau source giống hoàn toàn thì ưu tiên đề xuất TM đã review; không tự ghi đè nếu project cấu hình chỉ gợi ý.

Sau khi exact TM ổn định và corpus đủ lớn mới thêm:

- fuzzy match;
- concordance;
- auto-propagation cho câu lặp;
- Working/Master/reference TM.

TMX 1.4b vẫn là định dạng trao đổi translation memory được dùng rộng rãi; Microsoft liệt kê TMX và TBX trong tài liệu localization formats. [Microsoft - Localization file formats](https://learn.microsoft.com/en-us/globalization/localization/localization-file-formats).

### 7.5 Batch và EPUB

Batch TXT nên có:

- chọn folder;
- giữ encoding/newline hoặc xuất UTF-8 theo cấu hình;
- progress/cancel;
- không ghi đè source;
- report số đoạn, thời gian, unknown coverage và lỗi;
- checkpoint để resume.

EPUB chỉ làm sau khi project model ổn định. EPUB 3.3 là container gồm XHTML/CSS/assets và spine xác định thứ tự đọc, nên import/export đúng chuẩn phức tạp hơn đổi đuôi file. [W3C EPUB 3.3](https://www.w3.org/TR/epub-33/).

## 8. P2 và P3

### 8.1 Luật Nhân

Đây là extension phù hợp vì deterministic, offline và dữ liệu QuickTranslator_Jap đã tồn tại. Nên có:

- parser có test cho placeholder `{0}`;
- giới hạn recursion/overlap;
- rule priority rõ ràng;
- tester nhập câu và xem rule nào match;
- preview impact trước bật toàn project;
- option per project, không thay đổi global im lặng.

### 8.2 Search center

Search theo:

- exact key;
- prefix/wildcard;
- target/full-text meaning;
- dictionary source;
- mode và overlay layer;
- history/concordance.

Không cần đổi translation engine sang database. Search index là subsystem riêng, build bất đồng bộ và có thể bỏ/rebuild; HashMap runtime vẫn giữ nguyên.

### 8.3 Furigana/deinflection

Prototype nên đo:

- kích thước binary + dictionary;
- cold start và RAM;
- độ đúng reading với tên riêng;
- mapping span UTF-16 về source hiện tại;
- cách cập nhật native dependency trên Windows.

Chỉ ship khi có đường fallback: plugin thiếu/hỏng thì dịch VietPhrase vẫn hoạt động bình thường.

### 8.4 Chuẩn trao đổi termbase

TBX là chuẩn ISO 30042 cho lưu trữ và trao đổi dữ liệu thuật ngữ giàu metadata. [ISO 30042:2019](https://www.iso.org/standard/62510.html) và [TBX overview](https://www.tbxinfo.net/).

VietYaku không cần đổi file runtime sang XML. Có thể:

- import/export TBX ở rìa hệ thống;
- chuyển về model nội bộ;
- tiếp tục sinh overlay `key=value` tối giản cho engine.

### 8.5 Proposal/approval và RBAC

memoQ cho phép remote termbase được moderated, nghĩa là đóng góp cần được duyệt trước khi xuất bản. [memoQ - Term bases](https://docs.memoq.com/current/en/Concepts/concepts-term-bases.html).

Chỉ nên xây khi có contributor ngoài admin. Model tương lai:

- `viewer`: pull/search;
- `contributor`: tạo proposal;
- `reviewer`: approve/reject;
- `admin`: role/security/rollback;
- proposal chưa duyệt tuyệt đối không xuất hiện trong public delta.

Với một admin duy nhất, workflow này tạo nhiều UI và state hơn giá trị nhận được.

### 8.6 AI tùy chọn

LittleKai Server đã có công cụ AI web, nhưng VietYaku hiện định vị dịch chính offline/no-AI. Không nên đưa AI vào critical path.

Nếu sau này người dùng yêu cầu:

- explicit opt-in per request;
- hiển thị provider và dữ liệu sẽ gửi;
- không gửi toàn bộ project mặc định;
- timeout/cancel/fallback về engine offline;
- AI output là suggestion, không tự publish dictionary;
- QA deterministic vẫn là nguồn kiểm tra chính.

## 9. Roadmap đề xuất

### Giai đoạn A - Integrity và security

**Mục tiêu:** không mất dữ liệu, có thể xóa/khôi phục và thu hồi quyền admin.

- Atomic overlay write + backup/recovery test.
- Tombstone end-to-end.
- Audit model + history API + rollback API.
- JWT ngắn hơn, role/token revocation, login/publish rate limit.
- Sync manifest + schema version + cursor reset.
- Integration tests cho add/edit/delete/retry/crash/rebuild.

**Gate hoàn tất:** có thể tạo, sửa, xóa, rollback một entry và một client offline luôn hội tụ về đúng shared overlay mà không đụng base dictionary.

### Giai đoạn B - Dictionary Admin và QA

**Mục tiêu:** admin thấy rõ tác động trước/sau mỗi thay đổi.

- Admin search/history/diff UI.
- Publish preview và reason.
- QA văn bản hiện tại.
- Báo cáo coverage/unknown CJK.
- Bulk import preview, giới hạn batch và idempotency key.

**Gate hoàn tất:** mọi thay đổi shared có actor, lý do, diff, rollback và danh sách QA có vị trí cụ thể.

### Giai đoạn C - Workflow dịch

**Mục tiêu:** dịch trọn project TXT và tái sử dụng câu đã sửa.

- Project/chapter model + autosave + backup.
- Segment editor và draft/reviewed.
- Exact TM + auto-propagation có kiểm soát.
- Batch TXT + resume/report.
- Clipboard reader + global hotkey.

**Gate hoàn tất:** đóng/mở lại project không mất chỉnh sửa; câu lặp dùng lại bản reviewed; batch không ghi đè source.

### Giai đoạn D - Language intelligence và interoperability

**Mục tiêu:** tăng khả năng tra/biên tập mà không đổi lõi offline.

- Luật Nhân + rule tester.
- Fuzzy TM + concordance.
- Search center.
- TMX/TBX import/export.
- Prototype Sudachi/MeCab plugin.
- Đánh giá EPUB và OCR dựa trên nhu cầu beta.

## 10. Chỉ số thành công

### Sync và dữ liệu

- 0 trường hợp cursor advance khi overlay chưa commit bền vững.
- 100% test add/edit/delete/retry/rollback hội tụ về cùng state.
- Rebuild từ cursor 0 khôi phục đúng overlay từ server.
- Payload public không chứa audit metadata không cần thiết.
- Theo dõi p50/p95 latency, bytes per sync và số page; chỉ làm snapshot/compaction khi số liệu yêu cầu.

### QA

- Tỷ lệ cảnh báo được người dùng chấp nhận là lỗi thật.
- Tỷ lệ false positive theo rule.
- Số tên/thuật ngữ không nhất quán được sửa trước export.
- Thời gian scan một chương và không block UI.

### Project/TM

- Thời gian dịch lại câu lặp.
- Số exact match reused.
- Tỷ lệ project restore thành công sau app close/crash.
- Không ghi đè source và không mất edited target.

### Privacy/security

- Token admin có thể revoke ngay.
- Login abuse trả `429` theo policy.
- Clipboard watcher mặc định không upload và retention local rõ ràng.
- Mọi dictionary write có actor/request id.

## 11. Những thứ chưa nên làm

### Không thay HashMap bằng database/trie

Engine hiện đã nhanh, cache và loader đã ổn định. Database/search index chỉ nên phục vụ quản trị/search, không thay lookup hot path.

### Không tải lại toàn bộ base VietPhrase/Lạc Việt

Shared dictionary chỉ là overlay do admin thay đổi. Tiếp tục tải current shared delta; base bundle giữ nguyên.

### Không dùng CRDT

Hiện chỉ admin ghi và server cấp revision tuần tự. CRDT giải bài toán multi-writer offline conflict mà sản phẩm chưa có. Tombstone + revision + audit log đơn giản, kiểm thử được và rẻ hơn.

### Không dùng WebSocket/Change Streams ngay

Tần suất write thấp và người dùng đã có nút sync. ETag manifest/polling khi mở app hoặc theo interval dài đủ nhẹ. Real-time chỉ đáng làm khi có nhu cầu cộng tác trực tiếp.

### Không nhúng OCR trước clipboard bridge

PowerToys/ShareX/Capture2Text đã giải quyết capture/OCR. Clipboard listener đem lại phần lớn giá trị với ít native/model dependency hơn.

### Không đưa AI vào đường dịch mặc định

Điều này làm tăng latency, chi phí, rủi ro riêng tư và phá fallback offline. Nếu làm, giữ dưới dạng suggestion opt-in.

## 12. Sprint tiếp theo được khuyến nghị

Nếu chỉ chọn một gói việc kế tiếp, nên chọn **Shared Dictionary Integrity**:

1. Thêm `operation`/`deleted` vào API và model.
2. Client xóa key khỏi đúng shared overlay.
3. Đổi `_write` thành temp + flush + atomic replace.
4. Thêm manifest `latest_revision` + `schema_version`.
5. Thêm `GlossaryChange` và reason/request id.
6. Thêm history/rollback API tối thiểu.
7. Thu hẹp JWT và kiểm tra role/revocation khi write.
8. Test crash/retry/delete/rollback/reset cursor trên cả Nhật và Trung.

Đây là gói có tỷ lệ giá trị/rủi ro tốt nhất vì củng cố tính năng vừa xây, tránh tích lũy dữ liệu sai và tạo nền cho UI quản trị, proposal lẫn QA sau này.

## 13. Hạn chế của nghiên cứu

- Chưa có phỏng vấn người dùng, analytics hoặc log hành vi; mức ưu tiên P1-P3 cần beta validation.
- Tài liệu competitor xác nhận feature nhưng không chứng minh hiệu quả với nhóm người dùng VietYaku.
- Chưa benchmark Sudachi/MeCab/OCR trong bản build Flutter Windows hiện tại.
- Chưa đo quy mô shared overlay thực tế theo thời gian, nên snapshot/compaction chưa có ngưỡng dữ liệu đáng tin.
- Ước lượng nỗ lực mang tính tương đối, không phải cam kết thời gian.

## 14. Danh mục nguồn chính

1. [OmegaT - The Free Translation Memory Tool](https://omegat.org/)
2. [OmegaT - Policies and project TMX storage](https://omegat.org/policies)
3. [memoQ - Term bases](https://docs.memoq.com/current/en/Concepts/concepts-term-bases.html)
4. [memoQ - Translation memories](https://docs.memoq.com/current/en/Workspace/project-home-translation-memories.html)
5. [memoQ - Concordance](https://docs.memoq.com/10-3/en/Places/concordance.html)
6. [memoQ - QA warnings](https://docs.memoq.com/current/en/Concepts/concepts-quality-assurance-qa-warnings.html)
7. [Yomitan](https://yomitan.wiki/)
8. [GoldenDict-ng](https://github.com/xiaoyifang/goldendict-ng)
9. [Pleco](https://www.pleco.com/)
10. [Sudachi](https://github.com/WorksApplications/Sudachi)
11. [MeCab](https://taku910.github.io/mecab/)
12. [Microsoft PowerToys Text Extractor](https://learn.microsoft.com/en-us/windows/powertoys/text-extractor)
13. [Microsoft Windows.Media.Ocr](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr)
14. [Tesseract OCR](https://github.com/tesseract-ocr/tesseract)
15. [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)
16. [RFC 9110 - HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110.html)
17. [RFC 9111 - HTTP Caching](https://www.rfc-editor.org/rfc/rfc9111.html)
18. [MongoDB Change Streams](https://www.mongodb.com/docs/manual/changeStreams/)
19. [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
20. [OWASP Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)
21. [Vercel WAF Rate Limiting](https://vercel.com/docs/vercel-firewall/vercel-waf/rate-limiting)
22. [ISO 30042:2019 - TBX](https://www.iso.org/standard/62510.html)
23. [W3C EPUB 3.3](https://www.w3.org/TR/epub-33/)
24. [OASIS XLIFF 2.1](https://docs.oasis-open.org/xliff/xliff-core/v2.1/xliff-core-v2.1.html)

## AI disclosure

Báo cáo được tạo với hỗ trợ của công cụ nghiên cứu AI. Các claim về tính năng, tiêu chuẩn và API được đối chiếu với nguồn chính thức liên kết trong tài liệu. Các mức ưu tiên, suy luận kiến trúc và roadmap là đánh giá kỹ thuật, cần được xác nhận bằng phản hồi người dùng và benchmark trên codebase thực tế.

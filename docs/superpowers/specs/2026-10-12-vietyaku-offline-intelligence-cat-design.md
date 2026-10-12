# VietYaku: offline language intelligence và CAT workflow

**Ngày:** 2026-10-12  
**Phạm vi:** phím tắt chọn nghĩa, project TXT + exact Translation Memory,
Japanese deinflector prototype, và mở rộng rule tiếng Trung.

## Mục tiêu

Tăng tốc biên tập và cải thiện các trường hợp Nhật bị biến hình mà vẫn giữ
đường dịch mặc định offline, deterministic, không đưa AI vào critical path và
không thay HashMap hot path của translation engine.

## Ngoài phạm vi

- Autosave phiên làm việc và khôi phục tự động: đã loại khỏi đợt này.
- Fuzzy TM, concordance, auto-propagation và TMX/TBX: chỉ xem xét sau exact TM.
- Nhúng Sudachi runtime hoặc MeCab/native dependency.
- Tự động suy ra rồi chèn các từ “đã/đang/không” từ mọi tag biến hình.
- Rewrite ngữ pháp Trung tổng quát không có rule/test cụ thể.

## Chặng A — phím tắt chọn nghĩa

Tái sử dụng `tokenSelectionProvider` làm nguồn token active. Một lớp
`Shortcuts`/`Actions` ở màn Dịch nhận phím `1..9` khi token kết quả đang active.
Số được ánh xạ vào các alternative của `parseVietPhraseValue(token.rawValue)`;
nghĩa được chọn được chèn vào caret hiện tại của `vietDraftControllerProvider`.

Tính năng không sửa từ điển và không thay đổi `TranslationState`. Nếu token
không có alternative tương ứng thì không làm gì và hiển thị tooltip/hướng dẫn
ngắn. Trên mobile chỉ hoạt động khi có hardware keyboard. Cần test mapping,
focus, token không match và alternative vượt quá 9.

## Chặng B — project TXT và exact TM

Thêm feature-first `lib/features/project/` với model thuần Dart và IO tách
riêng. Project tối thiểu gồm:

```text
project.json
source/*.txt
target/*.txt
segments.jsonl
tm.jsonl
project_glossary.txt
```

Mỗi segment lưu `segmentId`, `source`, `machineOutput`, `editedTarget`,
`status` (`draft` hoặc `reviewed`), `updatedAt`, và `sourceHash`. Tách câu theo
quy tắc hiện có, giữ nguyên thứ tự và không ghi đè file nguồn. UI cần mở/lưu
project TXT, bảng ba cột Nguồn / VietPhrase / Bản dịch, và nút đánh dấu câu đã
review.

Exact TM chỉ ghi segment có `status=reviewed`. Khi source trùng tuyệt đối,
hiển thị bản dịch đã review như gợi ý; không tự ghi đè target hiện tại. File TM
được đọc/ghi độc lập với `.vydc`, không dùng database và không đổi format cache
từ điển.

## Chặng C — Japanese deinflector prototype

Thêm domain thuần Dart `jp_deinflector.dart` với API trả về các candidate gồm
surface gốc, span/độ dài, và metadata rule. Engine chỉ gọi deinflector sau khi
lookup tĩnh không khớp; candidate được tra lại trong cùng dictionary overlay.
Token vẫn giữ span của surface biến hình trong văn bản nguồn. Nếu không có
candidate hợp lệ, hành vi hiện tại giữ nguyên.

Prototype phải có fixture các dạng `た`, `ない`, `て`, bị động và sai khiến;
đo precision/recall trên corpus nhỏ trước khi thêm setting hoặc bật mặc định.
Metadata ngữ pháp chỉ dùng để chẩn đoán ở prototype, chưa tự sinh tiền tố
tiếng Việt.

## Chặng D — rule tiếng Trung

Mở rộng file rule hiện tại bằng các rule nhỏ cho `的`, `把`, `被`, `了`, `着`
chỉ khi có ví dụ nguồn/kết quả và test regression. Rule chạy trong pipeline hậu
xử lý hiện có, giữ tab trace/tester và nhóm bật/tắt. Không đưa rewrite vào
`TranslationEngine` và không thay đổi token span của kết quả VietPhrase.

## Thứ tự triển khai và kiểm chứng

1. Chặng A: unit test domain + widget test keyboard/focus.
2. Chặng B: unit test parser/segment/TM + widget test mở/lưu và gợi ý exact.
3. Chặng C: unit test deinflection, benchmark fixture và kiểm tra fallback.
4. Chặng D: test từng rule, `flutter analyze`, `flutter test`.

Mọi chặng phải cập nhật `.claude/PROJECT_SUMMARY.md`; deinflector/rule mới phải
ghi quyết định hoặc bẫy tái phát vào tài liệu tương ứng nếu phát hiện bất biến
mới. Không đụng các thay đổi đang có trong working tree ngoài file thuộc chặng.

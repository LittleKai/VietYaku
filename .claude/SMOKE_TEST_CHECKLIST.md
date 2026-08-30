# Smoke Test Checklist — VietYaku

**Mục đích:** Kiểm tra tay trước khi publish một bản build. Chạy trên **exe/APK đã build**, KHÔNG chạy qua IDE hay `flutter run`.
Lý do phải chạy trên bản build: đường dẫn dữ liệu đổi giữa debug và release (`AppPaths`: debug → `<repo>/data/userdata/`, release → `<thư mục chứa .exe>/userdata/`), và từ điển bundle đi theo assets — hai thứ này chỉ sai ở bản release.

---

## Trước khi test

- [ ] `flutter analyze` sạch và `flutter test` pass (347 tests)
- [ ] Build: `flutter build windows --release` → chạy `build\windows\x64\runner\Release\vietyaku.exe` **độc lập** (mở từ Explorer, không qua IDE)
- [ ] Test một lần trên máy/thư mục **chưa có `userdata/`** để bắt lỗi khởi động lần đầu (seed từ điển, tạo thư mục)

## Luồng chính

- [ ] **Dịch Nhật + clipboard:** dán một đoạn tiếng Nhật → Dịch → tab VietPhrase đa nghĩa hiện bản dịch; bật Clipboard reader, copy CJK từ app khác và thử `Ctrl+Shift+V` → ô Nguồn cập nhật + dịch đúng, copy từ chính VietYaku không tự kích hoạt lại
- [ ] **Đổi mode Trung + rule:** chuyển sang Tiếng Trung → dán đoạn **phồn thể** → Dịch → ra tiếng Việt đúng (ô Nguồn giữ nguyên); Cài đặt → chọn Luật Nhân `Pronouns`, tester với `把他挡住` phải ra `ngăn cản hắn`; thêm một regex, bật hậu xử lý và kiểm tra tab Hậu xử lý + nút Copy
- [ ] **Tra nghĩa + Search Center:** nháy chuột vào một cụm ở ô Nguồn → ô Nghĩa hiện các mục từ điển; mở Tìm kiếm, thử exact/wildcard key và full-text nghĩa → kết quả đúng lớp overlay đang thắng
- [ ] **Sửa từ điển + preview:** chuột phải một token → dialog hiện base/shared/new + số lần tác động; với VietPhrase, thêm nghĩa 2/3, chọn thử từ loại rồi lưu và kiểm tra tab một nghĩa có nhãn loại; nhập key lỗi phải bị chặn; lưu UserDict → **bản dịch tự đổi ngay**, không cần bấm Dịch Lại
- [ ] **Tra online:** bấm nút tra online ở ô Nghĩa → các nguồn đang bật trả kết quả; đóng dialog rồi tra lại cùng từ → lần này hiện offline ngay (đã lưu vào `OnlineDict_<mode>.txt`)
- [ ] **EPUB:** mở tab EPUB → chọn một file `.epub` → xem trước → xuất DOCX → mở file ra kiểm tra có nội dung và ảnh nhúng thật
- [ ] **Cập nhật:** Cài đặt → "Kiểm tra ngay" → trả về đúng phiên bản mới nhất trên GitHub Releases (hoặc báo đã mới nhất), không văng

## Android (APK release)

Chạy trên **APK release**, không phải `flutter run` — quyền `INTERNET` chỉ có sẵn ở manifest debug/profile, thiếu ở main là mọi thứ online chết mà debug không lộ ra.

- [ ] **Gỡ app cũ rồi cài mới** → lần mở đầu hiện màn "Đang chuẩn bị bộ từ điển" có tiến độ, xong thì vào thẳng màn Dịch (không đen màn hình, không ANR). Mở lại lần hai phải nhanh hơn hẳn (đọc cache `.vydc`)
- [ ] **Bố cục điện thoại:** thanh điều hướng nằm dưới đáy với 4 mục (Dịch · Tìm kiếm · Giao diện · Cài đặt — **không có EPUB**); màn Dịch có 5 tab phẳng Nguồn/Hán Việt/VietPhrase/Nghĩa/Bản dịch; không chỗ nào hiện sọc vàng-đen (overflow)
- [ ] **Dịch + chạm:** dán đoạn Nhật → Dịch → tab VietPhrase ra đúng; **nhấn giữ** một token → menu có "Chèn vào Bản dịch" (bấm thử, chữ phải vào tab Bản dịch) và "Thêm vào UserDict"
- [ ] **Online:** bấm nút Google Dịch → ra bản dịch cả đoạn; tra online một từ → có kết quả (nếu hai cái này im lặng thất bại, gần như chắc chắn manifest thiếu `INTERNET`)
- [ ] **Đổi mode Trung:** lần đầu chuyển sang Tiếng Trung phải hiện lại màn chuẩn bị (seed `data/cn`), xong thì dịch được đoạn phồn thể
- [ ] **TTS:** nút 🔊 đọc được; máy chưa cài giọng ja/zh thì nút mờ và tooltip chỉ đường **Cài đặt Android**, không phải đường dẫn Windows

## Sau khi test

- [ ] Không có exception/stack trace trong console khi chạy exe từ terminal
- [ ] Thư mục `userdata/` được tạo cạnh exe, có `cache/` (`.vydc`) và `dictionaries/`
- [ ] File từ điển gốc trong `data/jp` · `data/cn` **không bị sửa** (`git status` sạch)
- [ ] Ghi vấn đề phát hiện vào `Known Issues & TODOs` trong `.claude/PROJECT_SUMMARY.md`

---

**📌 NOTE:** Cập nhật checklist này khi có luồng nghiệp vụ chính mới. Giữ ở mức 5–7 mục ở phần "Luồng chính" — đây là smoke test, không phải regression suite (`flutter test` lo phần đó).

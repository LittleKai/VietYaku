# Instructions for Claude Code — VietYaku

App Flutter (Windows desktop + Android) dịch Nhật/Trung → Việt kiểu VietPhrase
(greedy longest-match, **offline, không dùng AI để dịch**) + công cụ sửa từ điển
Nhật bị hỏng của QuickTranslator_Jap. Online là tùy chọn; AI chỉ tra **một từ**.

File này là **bộ định tuyến** — nó nói *đọc gì* và *luật nào không được bỏ qua*.
Mọi chi tiết nằm ở file nó trỏ tới. Đây là file duy nhất nạp vô điều kiện mỗi
session, nên mỗi dòng ở đây đắt hơn một dòng bất kỳ chỗ khác: **thêm vào đây là
lựa chọn cuối cùng, không phải mặc định.**

---

## 🎯 ĐẦU RA LÀ GÌ

Artifact bàn giao: **`vietyaku.exe` đã build** (Windows, chạy portable — userdata
nằm cạnh exe) và **`.apk`** (Android). Source chạy được **không** phải artifact.

**Bàn giao bắt buộc:** exe/APK chạy độc lập · từ điển đi kèm dạng assets ·
`flutter analyze` sạch · `flutter test` pass · bằng chứng của **lần chạy này**.

---

## 📖 ĐỌC GÌ — theo việc đang làm

**Luôn luôn, trước mọi việc:** `.claude/PROJECT_SUMMARY.md`
(trạng thái dự án — đọc nó, đừng đọc lại toàn bộ code).

| Task đụng tới | Đọc trước |
|---|---|
| engine dịch · từ điển · cache `.vydc` · repair · nguồn online/AI · nơi ghi dữ liệu | `.claude/DESIGN_DECISIONS.md` — quyết định **không bàn lại** |
| repair/parser · trad2simp · Sudachi · provider Riverpod · dialog · theme | `.claude/IMPORTANT_FIXED_BUGS.md` — **BẮT BUỘC**: đây là vùng sinh lỗi im lặng của dự án này |
| thêm code mới · thêm feature mới | `.claude/CONVENTIONS.md` + tầng dùng chung `lib/core/`, `lib/shared/` |
| build · release · `version.json` · B2 | `.claude/RELEASE.md` + skill `.claude/skills/build-and-release/` |
| trước khi giao / release | `.claude/SMOKE_TEST_CHECKLIST.md` |

**KHÔNG đọc:**

- ❌ toàn bộ `lib/` chỉ để "hiểu dự án"
- ❌ file đã được tóm tắt trong `PROJECT_SUMMARY.md`
- ❌ `.claude/archive/` — lịch sử đã hết hiệu lực. Chỉ mở để biết **vì sao** một
  rào chắn tồn tại, và không bao giờ làm theo hướng dẫn thủ công trong đó
- ❌ `data/jp/`, `data/cn/` (~123MB từ điển), `build/`, `.dart_tool/`

---

## 🧪 VERIFY — chưa nhìn thấy thì chưa xong

Bằng chứng phải là **của lần chạy này**: một báo cáo build cũ trông y hệt một lần
chạy thành công. "Code chạy đúng" không phải bằng chứng.

1. **`flutter analyze` sạch** + **`flutter test` pass** — trước khi kết thúc mọi
   task có sửa code.
2. **Có test cho thứ vừa sửa.** Tính năng mới hoặc sửa lỗi **logic** trong
   `lib/features/*/domain/`, `lib/features/*/data/`, `lib/core/` ⇒ bắt buộc có
   unit test phủ case đó trong `test/`. Bug fix: viết test **tái hiện bug trước**,
   rồi mới sửa.
3. **Vùng có bất biến riêng:** đụng repair/parser ⇒ chạy thêm
   `dart run tool/export_jp.dart`, verify trên dữ liệu thật (bất biến VALUE KHÔNG
   ĐỔI 1 BYTE). Đụng `app_theme.dart` ⇒ `test/app_theme_test.dart` đang khoá
   invariant, cập nhật chứ không phá.
4. **Rào chắn còn nguyên** — `"D:/Dev/conda-envs/py312/python.exe" .claude/guard_check.py`
   trả `OK` (chạy khi task đụng bất kỳ hàm nào nêu trong Bảng bẫy).
5. **Chạy artifact đã build** — `vietyaku.exe` / `.apk`, đi hết luồng chính theo
   `.claude/SMOKE_TEST_CHECKLIST.md`, **xem bằng mắt**. Không kết luận "xong" từ
   việc đọc code.

**Miễn mục 2, 3, 5:** thay đổi thuần `presentation/` (bố cục, màu, cỡ chữ), đổi
tên biến, chỉ sửa docs. Nếu là luồng chính thì vẫn thêm một dòng vào
`.claude/SMOKE_TEST_CHECKLIST.md`.

---

## 🔒 BẢO MẬT

- **Không** ghi mật khẩu, JWT admin, API key, hay credential thật vào bất kỳ file
  nào bị Git theo dõi — kể cả `lib/`, `test/`, fixture, comment, `.md`.
  Chỉ dùng placeholder (`<JWT>`, `admin@example`, `<YOUR_API_KEY>`).
- Phiên admin (`dictionary_sync`): SharedPreferences chỉ lưu `username + JWT`,
  **không bao giờ lưu mật khẩu**; logout/401 phải xóa phiên.
- Không `debugPrint`/log token, header `Authorization`, hay response đăng nhập —
  kể cả khi debug tạm; xóa log trước khi kết thúc task.
- URL server đặt qua `--dart-define=LITTLEKAI_SERVER_URL=...`, không hardcode URL
  production. Credential B2 đọc từ `.env` (đã gitignore) — xem `.claude/RELEASE.md`.
- `.env` và `data/userdata/` đã nằm trong `.gitignore` — không gỡ, không commit
  dữ liệu người dùng thật (từ điển cá nhân, OnlineDict, cache `.vydc`).
- **Không dùng API trả phí / API cần key.** Nguồn online mới bắt đăng ký key ⇒ loại.

---

## 🧭 CÁCH LÀM

**1 · Đừng đoán.** Nêu giả định ra thành chữ. Yêu cầu hiểu được theo nhiều cách
thì **nêu các cách hiểu ra**, đừng tự chọn im lặng. Chưa rõ thì dừng lại và hỏi —
đặc biệt trước mọi thay đổi cấu trúc.

**2 · Ít nhất mà vẫn đúng.** Không thêm thứ ngoài yêu cầu. Không abstraction cho
code dùng một lần. Không "flexibility" không ai xin. Không xử lý lỗi cho tình
huống không thể xảy ra. Viết 200 dòng mà 50 dòng là đủ ⇒ viết lại.

**3 · Chỉ đụng thứ cần đụng.** Không "tiện tay" đổi format, đổi tên, refactor thứ
không hỏng. Bám style sẵn có kể cả khi mình thích kiểu khác. Thấy dead code không
liên quan thì **nói ra, đừng xóa**. Chỉ dọn thứ chính thay đổi của mình làm thừa.
Mỗi dòng đổi phải truy được về yêu cầu của user.

**4 · Đặt tiêu chí kiểm chứng được rồi lặp tới khi đạt.** "Thêm validation" →
*"viết test cho input sai, rồi làm nó pass"*. "Sửa bug" → *"viết test tái hiện
bug trước, rồi làm nó pass"*. Task nhiều bước thì nêu kế hoạch ngắn, **mỗi bước
kèm cách kiểm chứng**.

**Thứ tự ưu tiên khi phải đánh đổi:** tính đúng của dữ liệu từ điển (value không
đổi 1 byte, không ghi đè file gốc) > tốc độ > UI.

---

## ✍️ SAU MỖI TASK — viết lại vào đâu

`.claude/PROJECT_SUMMARY.md` — luật cập nhật nằm ngay đầu file đó.

| Loại | Ghi vào | Viết thế nào |
|---|---|---|
| Lỗi im lặng, khó phát hiện, dễ tái phát | `.claude/IMPORTANT_FIXED_BUGS.md` | Triệu chứng → nguyên nhân → Do Not Repeat + **một dòng trong Bảng bẫy** |
| Quy ước code, đặt tên | `.claude/CONVENTIONS.md` | Câu mệnh lệnh + ≥2 ví dụ `file:line` thật |
| Bước kiểm tra mới trước khi giao | `.claude/SMOKE_TEST_CHECKLIST.md` | Một dòng checkbox |
| Quyết định thiết kế mới, không bàn lại | `.claude/DESIGN_DECISIONS.md` | Một gạch đầu dòng, kèm **vì sao** |
| **Hàm** dùng lại được | `lib/core/` hoặc `lib/shared/` — **ngay trong task đó** | Bỏ mọi thứ gắn với một tính năng cụ thể |

**Tài liệu phải có cửa ra, không chỉ có cửa vào.** Viết được một hàm khiến một bẫy
không xảy ra được nữa ⇒ hạ bẫy đó xuống ✅, **chuyển văn xuôi xuống
`.claude/archive/`**, để lại một dòng + tên hàm rào chắn. Ba mức ✅/🔶/❌ và luật
rút gọn: `.claude/IMPORTANT_FIXED_BUGS.md` §"CỬA RA".

Mỗi session nên làm tài liệu **ngắn đi hoặc chặt hơn**, không chỉ dài thêm.

---

## 🗂️ BỘ KHUNG

**Công cụ:** Flutter 3.44.2 · Dart ^3.12 · Riverpod 2 manual providers (KHÔNG
codegen) · Material 3. Lệnh chạy & file quan trọng: `PROJECT_SUMMARY.md` §2, §9.

| Tầng | Ở đâu | Xóa được? |
|---|---|---|
| Điều hướng | `CLAUDE.md` (file này) | ✗ |
| Văn bản dùng chung | `.claude/*.md` — `archive/` là lịch sử, **không làm theo** | ✗ |
| Code dùng chung | `lib/core/`, `lib/shared/` | ✗ |
| Đơn vị công việc | `lib/features/<tên>/` (domain · data · application · presentation) | ✓ |

---

## ⚠️ TRƯỜNG HỢP RIÊNG

- **"Review toàn bộ dự án"** → ngoại lệ: đọc hết, dựng lại summary đầy đủ.
- **`PROJECT_SUMMARY.md` không có** → coi như "review toàn bộ dự án".
- **`PROJECT_SUMMARY.md` lệch so với code** → **hỏi user trước khi làm tiếp**.
- **Refactor lớn** → dựng lại trọn `File Structure` + `Architecture & Patterns`.

---

**📌 Tài liệu = nguồn sự thật duy nhất. exe/APK đã build = bằng chứng duy nhất.**

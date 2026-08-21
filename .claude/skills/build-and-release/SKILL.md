---
name: build-and-release
description: |
  Build VietYaku cho Windows (zip), sau đó phát hành đồng thời lên GitHub Release
  và Backblaze B2 (link tải cho tool /studio/vietyaku trên giaiphapsangtao.com).
  <!-- [DISABLED] Android (APK) build tạm thời bị tắt -->
  Trigger: khi user yêu cầu build, release, publish, xuất bản, deploy, hoặc tạo phiên bản mới.
---

# Build & Release VietYaku

Skill này tự động hóa quy trình: build Windows → tạo GitHub Release → upload artifacts → đẩy bản tải lên B2 cho web.

> ⚠️ **TẠM THỜI DISABLED**: Android (APK) build đang bị tắt. Khi cần bật lại, tìm và uncomment các phần `[DISABLED-ANDROID]` trong file này và trong `scripts/build.ps1`.

## ⚠️ Hai kênh phát hành — đừng nhầm

| Kênh | Phục vụ | Nguồn dữ liệu |
|------|---------|---------------|
| **GitHub Release** | **Cập nhật trong app** — `lib/features/update/data/github_release_api.dart` gọi `api.github.com/repos/LittleKai/VietYaku/releases/latest` | Asset ZIP đính kèm release |
| **Backblaze B2** | **Link tải trên web** — tool `giaiphapsangtao.com/studio/vietyaku` | `vietyaku-app/version.json` + `vietyaku-app/releases/*.zip` (bucket `alpha-studio`) |

- Cùng **một file ZIP** đi lên cả hai nơi, chỉ khác tên object: GitHub giữ `VietYaku-windows-x64.zip`, B2 lưu `VietYaku-windows-x64-v<version>.zip` (B2 cần tên có version vì mọi bản nằm chung một prefix).
- Bỏ bước B2 → web vẫn hiện bản cũ. Bỏ GitHub → người đang dùng app không nhận được thông báo cập nhật. **Mỗi lần release phải đủ cả hai.**
- Trang `/studio/vietyaku` đọc qua backend `GET /api/vietyaku/releases/latest` (repo `alpha-studio`), backend fetch `version.json` trên B2 rồi cache vào `SystemSetting`. Không cần deploy lại frontend khi ra bản mới.

## Yêu cầu trước khi chạy

1. **Flutter** phải có trong PATH (`D:\3.Flutter\flutter\bin\flutter.bat`)
2. **GITHUB_TOKEN** trong `.env` (root project) — đã có sẵn
3. **Credential B2** trong `.env` (root project) — lấy đúng 4 dòng này từ `alpha-studio-backend/.env`:
   ```
   B2_ACCESS_KEY_ID=<b2 keyID>
   B2_SECRET_ACCESS_KEY=<b2 applicationKey>
   B2_BUCKET_NAME=alpha-studio
   CDN_BASE_URL=https://cdn.giaiphapsangtao.com/file/alpha-studio
   ```
   `.env` đã nằm trong `.gitignore` — **không bao giờ commit giá trị thật**, không in ra log.
4. **Git** working directory sạch (không có uncommitted changes)
5. Máy phải là **Windows** (build Windows native cần chạy trên Windows)

## Quy trình release

### Bước 1: Xác nhận thông tin

Hỏi user:
- **Version**: tag mới (ví dụ `v1.0.0`). Nếu user không chỉ định, đọc version từ `pubspec.yaml` và đề xuất.
- **Release title**: tên hiển thị trên GitHub (mặc định: `VietYaku <version>`)
- **Release notes**: nội dung phiên bản, tổng hợp **TOÀN BỘ** các commit kể từ release tag trước đó.

  #### Cách thu thập commit:
  1. Tìm tag release gần nhất: `rtk git tag --sort=-creatordate -n1`
  2. Lấy tất cả commits từ tag đó đến HEAD: `rtk git log <tag_trước>..HEAD --oneline`
  3. BẮT BỘC kiểm tra chi tiết nội dung thay đổi của từng commit: `rtk git log <tag_trước>..HEAD -p` hoặc `rtk git show <commit_hash>` để nắm trọn vẹn từng tính năng, sửa lỗi UI, cập nhật từ điển và trải nghiệm người dùng.
  4. Nếu có uncommitted changes (`rtk git diff`), đọc kỹ các file thay đổi để đưa vào nội dung release.
  5. Tuyệt đối KHÔNG tóm tắt qua loa hay bỏ sót các chi tiết nhỏ (như nút bấm mới, sửa bo góc dialog, tối ưu bộ từ điển/glossary, icon mới...).

  #### Cấu trúc release notes (viết bằng tiếng Việt):

  ```markdown
  ## Có gì mới trong phiên bản <version>

  ### ✨ Tính năng mới & Cải tiến
  - **Tên tính năng 1:**
    - Chi tiết cải tiến 1.1
    - Chi tiết cải tiến 1.2
  - **Tên tính năng 2:**
    - Chi tiết cải tiến 2.1

  ### 🐛 Sửa lỗi & Tinh chỉnh Giao diện
  - **Mô tả lỗi/tinh chỉnh 1:**
    - Chi tiết sửa lỗi 1.1
  ```

  #### Quy tắc viết nội dung:
  - ⚠️ **Bắt buộc**: Kiểm tra KỸ LƯỠNG và ĐẦY ĐỦ toàn bộ thay đổi trước khi soạn Release Notes.
  - Tuyệt đối **TRÁNH nhắc đến các phần kỹ thuật code**, tên file (`.dart`), tên class, function hay refactor nội bộ.
  - Chỉ mô tả dưới **góc độ trải nghiệm người dùng** nhưng phải **CHI TIẾT và PHONG PHÚ** (dùng các nhóm gạch đầu dòng con để liệt kê rõ từng điểm cải tiến).
  - Gộp các commit cùng chủ đề thành một mục chính kèm các dòng mô tả chi tiết bên dưới.
  - Nếu một section không có nội dung, **bỏ section đó đi** (không để trống).
- **Prerelease?**: có đánh dấu là prerelease không (mặc định: không)
- **Build targets**: Windows (mặc định). <!-- [DISABLED-ANDROID] APK, Windows, hoặc cả hai (mặc định: cả hai) -->

### Bước 2: Kiểm tra trước khi build

```powershell
# Kiểm tra git sạch
rtk git status

# Chạy flutter analyze
flutter analyze

# (Tùy chọn) Chạy tests
flutter test
```

Nếu có lỗi analyze hoặc test fail → báo user, KHÔNG tiếp tục build.

### Bước 3: Build

Chạy script build:

```powershell
powershell -ExecutionPolicy Bypass -File ".claude\skills\build-and-release\scripts\build.ps1" -Version "<version>"
```

Script sẽ:
1. Cập nhật version trong `pubspec.yaml` (nếu khác version hiện tại)
2. Build Windows release: `flutter build windows --release`
3. Đóng gói Windows thành ZIP: `VietYaku-windows-x64.zip`
4. Tất cả output vào `build/release/`

> ⚠️ **Thứ tự commit: BUILD TRƯỚC, COMMIT SAU.** Bước 1 sửa `pubspec.yaml`. `release.ps1` tạo git tag trên HEAD mà **không** commit thay đổi đó, nên nếu commit trước rồi mới build thì tag sẽ trỏ vào commit vẫn ghi version cũ — tag và binary lệch nhau.
>
> Trình tự đúng khi working tree đang có thay đổi chưa commit:
> ```
> build.ps1 -Version <version>     # bump pubspec + build ZIP
> git add -A && git commit         # commit gồm luôn pubspec đã bump
> release.ps1 -Version <version> ... -SkipBuild
> ```

<!-- [DISABLED-ANDROID]
- Build APK release: `flutter build apk --release`
- Copy APK ra: `VietYaku-<version>.apk`
-->

### Bước 4: Release lên GitHub + B2

Chạy script release (một lệnh làm cả hai kênh):

```powershell
powershell -ExecutionPolicy Bypass -File ".claude\skills\build-and-release\scripts\release.ps1" -Version "<version>" -Title "<title>" -Notes "<notes>" [-Prerelease] [-SkipB2]
```

Script sẽ:
1. Đọc `GITHUB_TOKEN` từ `.env`
2. Tạo git tag `<version>`
3. Push tag lên origin
4. Tạo GitHub Release qua API (hoặc cập nhật release đã có cùng tag)
5. Upload Windows ZIP lên release <!-- [DISABLED-ANDROID] Upload APK và Windows ZIP lên release -->
6. Gọi `upload-b2.ps1` để đẩy bản tải web lên B2 (bỏ qua nếu truyền `-SkipB2`)

Bước 6 upload lên bucket `alpha-studio`:
- `vietyaku-app/releases/VietYaku-windows-x64-v<version>.zip` — file người dùng tải về từ web
- `vietyaku-app/version.json` — manifest cho backend, mang cùng `tag_name` / `body` / `html_url` với GitHub Release

> Nếu bước B2 fail: **GitHub Release đã publish xong rồi**, đừng tạo lại tag. Chỉ chạy lại một mình `upload-b2.ps1` (xem mục "Chạy từng bước thủ công").

### Bước 5: Xác nhận

Sau khi hoàn tất, hiển thị:
- Link đến GitHub Release
- Link tải trên CDN (`https://cdn.giaiphapsangtao.com/file/alpha-studio/vietyaku-app/releases/...`)
- Danh sách artifacts đã upload + kích thước từng file

Kiểm tra nhanh hai kênh:

```powershell
# Manifest B2 đã đúng version chưa
curl.exe -s https://cdn.giaiphapsangtao.com/file/alpha-studio/vietyaku-app/version.json

# Backend đã đọc được manifest chưa
curl.exe -s https://alpha-studio-backend.fly.dev/api/vietyaku/releases/latest
```

Rồi mở `https://giaiphapsangtao.com/studio/vietyaku` xem số version hiển thị đã khớp chưa.

## Cấu trúc output

```
build/release/
└── VietYaku-windows-x64.zip      # upload lên CẢ GitHub Release và B2
```

<!-- [DISABLED-ANDROID]
build/release/
├── VietYaku-<version>.apk
└── VietYaku-windows-x64.zip
-->

Trên B2 (bucket `alpha-studio`):

```
vietyaku-app/
├── version.json
└── releases/
    └── VietYaku-windows-x64-v<version>.zip
```

## Lưu ý quan trọng

<!-- [DISABLED-ANDROID] - **APK signing**: Hiện dùng debug signing key. Nếu cần production signing, user cần cung cấp keystore file và cấu hình trong `android/app/build.gradle.kts`. -->
- **Windows build**: Cần Visual Studio Build Tools C++ desktop workload.
- **Data size**: Thư mục `data/jp/` và `data/cn/` được bundle vào assets (~130MB), APK và Windows ZIP sẽ lớn.
- **Giới hạn 200MB cho upload B2**: `upload-b2.ps1` dùng `b2_upload_file` một phần. ZIP hiện ~64MB nên còn dư, nhưng nếu vượt 200MB script sẽ dừng và phải chuyển sang B2 large-file API.
- **Bản B2 cũ không tự xóa**: mỗi version là một object riêng trong `vietyaku-app/releases/`. Dọn tay trên B2 khi cần.
- **Không commit build artifacts**: Thư mục `build/` đã trong `.gitignore`.

## Chạy từng bước thủ công

Nếu cần build riêng lẻ (không release):

```powershell
# Chỉ build Windows
flutter build windows --release

# [DISABLED-ANDROID] Chỉ build APK
# flutter build apk --release
```

Nếu cần release mà đã build sẵn:

```powershell
powershell -ExecutionPolicy Bypass -File ".claude\skills\build-and-release\scripts\release.ps1" -Version "<version>" -Title "<title>" -Notes "<notes>" -SkipBuild
```

Nếu chỉ cần đẩy lại bản tải web lên B2 (GitHub Release đã có sẵn):

```powershell
powershell -ExecutionPolicy Bypass -File ".claude\skills\build-and-release\scripts\upload-b2.ps1" -Version "<version>" -Title "<title>" -Notes "<notes>" -ReleaseUrl "https://github.com/LittleKai/VietYaku/releases/tag/v<version>"
```

Chỉ `-Version` là bắt buộc; các tham số còn lại chỉ ảnh hưởng nội dung `version.json` hiển thị trên web.

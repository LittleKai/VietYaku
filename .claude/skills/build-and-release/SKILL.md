---
name: build-and-release
description: |
  Build VietYaku cho Windows (zip), sau đó tạo GitHub Release tự động.
  <!-- [DISABLED] Android (APK) build tạm thời bị tắt -->
  Trigger: khi user yêu cầu build, release, publish, xuất bản, deploy, hoặc tạo phiên bản mới.
---

# Build & Release VietYaku

Skill này tự động hóa quy trình: build Windows → tạo GitHub Release → upload artifacts.

> ⚠️ **TẠM THỜI DISABLED**: Android (APK) build đang bị tắt. Khi cần bật lại, tìm và uncomment các phần `[DISABLED-ANDROID]` trong file này và trong `scripts/build.ps1`.

## Yêu cầu trước khi chạy

1. **Flutter** phải có trong PATH (`D:\3.Flutter\flutter\bin\flutter.bat`)
2. **GITHUB_TOKEN** trong `.env` (root project) — đã có sẵn
3. **Git** working directory sạch (không có uncommitted changes)
4. Máy phải là **Windows** (build Windows native cần chạy trên Windows)

## Quy trình release

### Bước 1: Xác nhận thông tin

Hỏi user:
- **Version**: tag mới (ví dụ `v1.0.0`). Nếu user không chỉ định, đọc version từ `pubspec.yaml` và đề xuất.
- **Release title**: tên hiển thị trên GitHub (mặc định: `VietYaku <version>`)
- **Release notes**: mô tả thay đổi (mặc định: bỏ trống).
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

<!-- [DISABLED-ANDROID]
- Build APK release: `flutter build apk --release`
- Copy APK ra: `VietYaku-<version>.apk`
-->

### Bước 4: Release lên GitHub

Chạy script release:

```powershell
powershell -ExecutionPolicy Bypass -File ".claude\skills\build-and-release\scripts\release.ps1" -Version "<version>" -Title "<title>" -Notes "<notes>" [-Prerelease]
```

Script sẽ:
1. Đọc `GITHUB_TOKEN` từ `.env`
2. Tạo git tag `<version>`
3. Push tag lên origin
4. Tạo GitHub Release qua API
5. Upload Windows ZIP lên release <!-- [DISABLED-ANDROID] Upload APK và Windows ZIP lên release -->

### Bước 5: Xác nhận

Sau khi hoàn tất, hiển thị:
- Link đến GitHub Release
- Danh sách artifacts đã upload
- Kích thước từng file

## Cấu trúc output

```
build/release/
└── VietYaku-windows-x64.zip
```

<!-- [DISABLED-ANDROID]
build/release/
├── VietYaku-<version>.apk
└── VietYaku-windows-x64.zip
-->

## Lưu ý quan trọng

<!-- [DISABLED-ANDROID] - **APK signing**: Hiện dùng debug signing key. Nếu cần production signing, user cần cung cấp keystore file và cấu hình trong `android/app/build.gradle.kts`. -->
- **Windows build**: Cần Visual Studio Build Tools C++ desktop workload.
- **Data size**: Thư mục `data/jp/` và `data/cn/` được bundle vào assets (~130MB), APK và Windows ZIP sẽ lớn.
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

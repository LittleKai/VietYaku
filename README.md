# VietYaku (越訳)

<div align="center">

<img src="assets/branding/app_icon.png" alt="VietYaku Logo" width="128" height="128" />

### Ứng dụng Dịch Truyện &amp; Tài Liệu Nhật/Trung sang Việt Ngoại Tuyến (Offline VietPhrase Translator)

![Flutter](https://img.shields.io/badge/Flutter-3.44.2-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-4E73DF)
![Release](https://img.shields.io/github/v/release/LittleKai/VietYaku?color=success&label=Release)
![License](https://img.shields.io/badge/License-Proprietary-blue.svg)

</div>

---

## 📖 Giới thiệu &amp; Nguồn gốc

**VietYaku** (越訳 — Việt Dịch) là ứng dụng dịch thuật ngoại tuyến chuyên dụng cho truyện, tiểu thuyết và tài liệu tiếng Nhật, tiếng Trung sang tiếng Việt theo cơ chế **VietPhrase** (khớp cụm dài nhất — *greedy longest-match*). 

Kế thừa và phát triển từ tinh thần của các công cụ kinh điển như **QuickTranslator** và **QuickConverter** (cộng đồng **Tàng Thư Viện**), VietYaku khắc phục hoàn toàn các nhược điểm cố hữu của phần mềm cũ (giao diện WinForms lỗi thời, bộ từ điển Nhật bị lỗi font/mojibake do trộn chữ Hán giản thể, thiếu hỗ trợ di động), đồng thời mang đến một trải nghiệm hiện đại, mượt mà và đa nền tảng.

### 🌟 Ưu điểm cốt lõi

- ⚡ **Dịch Ngoại Tuyến Siêu Tốc (100% Offline):** Động cơ dịch VietPhrase thuần thuật toán, không cần kết nối mạng, dịch hàng chục nghìn chữ chỉ trong chớp mắt mà không tốn chi phí API.
- 📱 **Đa Nền Tảng (Windows &amp; Android):** Giao diện Material 3 đáp ứng linh hoạt từ màn hình máy tính để bàn đến điện thoại thông minh.

- 🔧 **Bộ Công Cụ Sửa Từ Điển (Repair Tool):** Sửa triệt để các bộ từ điển QuickTranslator_Jap bị hỏng hoặc trộn chữ Hán giản thể Trung Quốc.
- 🌐 **Mở Rộng Linh Hoạt:** Hỗ trợ tra từ Online đa nguồn (không cần API key) và tích hợp AI phân tích sâu từ vựng.

---

## 🚀 Tính năng nổi bật

### 1. Động cơ dịch VietPhrase hiện đại

- **Hỗ trợ song ngữ nguồn:** Chuyển đổi linh hoạt giữa chế độ **Tiếng Nhật** và **Tiếng Trung**.
- **Nhiều thuật toán quét cụm:**
  - *Trái → Phải* (chuẩn truyền thống).
  - *Ưu tiên cụm dài* (tối ưu độ mạch lạc của câu văn).
  - *Cụm dài ≥ 4* (cân bằng giữa cụm thành ngữ và từ ghép).
  - *Ưu tiên Tên riêng (Prioritize Names)*: Tránh nhận nhầm tên nhân vật/địa danh thành từ thông dụng.
- **Hán Việt song song:** Bảng Hán Việt toàn văn được tính toán đồng thời cùng lượt dịch.
- **Quy tắc hậu xử lý &amp; Luật Nhân:** Tích hợp hơn 200 quy tắc Luật Nhân kế thừa từ QuickTranslator_Jap và bộ quy tắc Regex linh hoạt có kèm công cụ kiểm thử trực quan.
- **Chuẩn hóa tự động:**
  - Tự động quy đổi chữ phồn thể sang giản thể (2.455 ký tự mapping chuẩn Unicode).
  - Chuyển đổi ký tự Katakana nửa chiều (*halfwidth*) sang độ rộng đầy đủ (*fullwidth*) với thuật toán bảo toàn vị trí token gốc.
  - Tự động gộp các chuỗi số Hán (kanji numerals) thành số Ả Rập.

### 2. Giao diện người dùng &amp; Trải nghiệm đọc (UX/UI)

- **Bố cục QuickTranslator tối ưu:**
  - Cột trái: Văn bản nguồn / Hán Việt và Bảng hiển thị nghĩa chi tiết.
  - Cột phải: Bản dịch VietPhrase một nghĩa / Đa nghĩa / Tab Google Dịch toàn văn.
- **Đa nghĩa phân cấp màu trực quan:** Tách bạch các tầng nghĩa ngữ pháp và từ loại (`[DT]` danh từ, `[ĐT]` động từ, `[TT]` tính từ...). Chuyển đổi giữa 1 nghĩa và đa nghĩa tức thì mà không cần nạp lại văn bản.
- **Đồng bộ vị trí 3 chiều:** Nhấp chọn một từ ở bất kỳ ô nào (Nguồn / VietPhrase / Hán Việt), con trỏ và vùng sáng ở hai ô còn lại sẽ tự động cuộn đến vị trí tương ứng.
- **Theme Material 3 hiện đại:** Hỗ trợ giao diện **Sáng (Light)**, **Tối (Dark)** và **Tự động theo hệ thống**. Chế độ ban đêm tự động tăng tương phản cho chữ Katakana, bảo vệ thị lực khi đọc lâu.
- **Đọc giọng nói (TTS) Ngoại tuyến:** Tích hợp bộ đọc giọng Nhật/Trung ngoại tuyến với khả năng điều chỉnh cao độ, tốc độ riêng biệt.
- **Bắt Clipboard thông minh:** Phím tắt toàn cục `Ctrl+Shift+V` trên Windows tự động lấy nội dung tiếng Nhật/Trung từ bộ nhớ tạm và dịch ngay.

### 3. Kho từ điển tích hợp đồ sộ (Bundled Offline Dicts)

VietYaku đi kèm sẵn các bộ dữ liệu từ điển đã được làm sạch và tối ưu:

- **Dữ liệu Tiếng Nhật (`data/jp/`):**
  - `VietPhrase.txt` (~190.000 mục — bản đã repair sạch lỗi ký tự).
  - `LacViet.txt` (~104.000 mục).
  - `Names.txt` (danh mục tên riêng Nhật Bản).
  - `JaViDict.txt` (~172.000 mục trích xuất chuẩn hóa).
  - `Mazii.txt` (~171.000 mục từ điển Mazii Nhật - Việt offline).
  - `SudachiVariants & VariantGroups` (~110.000 nhóm biến thể chữ kana/kanji tự động nhận diện).
- **Dữ liệu Tiếng Trung (`data/cn/`):**
  - `VietPhrase.txt` (~691.000 mục).
  - `LacViet.txt` (~66.000 mục).
  - `Names.txt` (danh mục tên riêng Trung Quốc).
  - `ZhViDict.txt` (~161.000 mục Trung - Việt).
  - Các bộ từ điển phụ trợ: Thiều Chửu, Babylon, CEDICT, Phụ từ...
- **Cache nhị phân siêu tốc (`.vydc`):** Đọc nạp từ điển nền qua Dart Isolate, mở ứng dụng chỉ mất vài trăm mili-giây.

### 4. Tra cứu tức thì &amp; Tích hợp Online / AI

- **Tra cứu nhanh trong bảng Nghĩa:** Hiển thị chi tiết từ VietPhrase, Lạc Việt, Mazii, Nhật-Việt/Trung-Việt và cả các cụm từ con nằm bên trong cụm đang chọn.
- **Tra Online đa nguồn không cần API Key:**
  - *Tiếng Nhật:* Mazii, Google Translate, Jisho, Weblio (Nhật - Trung).
  - *Tiếng Trung:* Youdao (Hữu Đạo), Google Translate.
  - Lưu nghĩa online vào từ điển cục bộ (`OnlineDict`) chỉ với 1 click để sử dụng ngoại tuyến cho những lần sau.
- **Hỗ trợ AI Phân Tích Chuyên Sâu:** Tùy chọn kết nối các mô hình AI hàng đầu (**Google Gemini, OpenAI ChatGPT, Anthropic Claude, xAI Grok**) để giải thích ngữ cảnh, ngữ pháp câu khó. Cơ chế xoay vòng API key (Key Rotator) tự động cân bằng tải và tự bóc tách từ mới lưu vào từ điển.

### 5. Trung tâm tra cứu (Search Center) &amp; Tra ngược

- Tra cứu kho từ điển độc lập không cần dán cả đoạn văn.
- Hỗ trợ nhiều chế độ: Khớp chính xác (*Exact*), Bắt đầu bằng (*Prefix*), Ký tự đại diện (*Wildcard `*` và `?`*), Tìm kiếm toàn văn (*Full-text*).
- **Tra ngược từ điển:** Nhập nghĩa tiếng Việt để tìm lại từ gốc tiếng Nhật / tiếng Trung.

### 6. Công cụ chuyển đổi EPUB (EPUB Converter)

- Đọc và bóc tách cấu trúc sách EPUB (tiểu thuyết, tài liệu).
- Xuất ra nhiều định dạng tiện ích: **DOCX** (nhúng sẵn ảnh minh họa gốc), **Markdown**, **XLSX**, **CSV**, **TXT** để tiện dịch hàng loạt hoặc lưu trữ.

---

## 💻 Yêu cầu hệ thống


| Nền tảng    | Yêu cầu tối thiểu                  | Khuyến nghị                                       |
| ----------- | ---------------------------------- | ------------------------------------------------- |
| **Windows** | Windows 10 64-bit (1809 trở lên)   | Windows 10/11 64-bit, RAM 4GB+, SSD               |
| **Android** | Android 7.0 (Nougat, API level 24) | Android 10+, RAM 3GB+, bộ nhớ trong trống \~500MB |


---

## 📥 Tải về &amp; Cài đặt

### Windows

1. Truy cập [Releases](https://github.com/LittleKai/VietYaku/releases/latest) hoặc trang [Giải Pháp Sáng Tạo Studio](https://giaiphapsangtao.com/studio/vietyaku).
2. Tải về file `VietYaku-windows-x64-v<version>.zip`.
3. Giải nén vào một thư mục bất kỳ (ví dụ: `D:\VietYaku`).
4. Chạy trực tiếp `vietyaku.exe` (Bản portable, toàn bộ cài đặt và từ điển cá nhân được lưu trong thư mục `userdata` nằm cạnh file thực thi).

### Android

1. Tải về file `VietYaku-android-v<version>.apk` từ [Releases](https://github.com/LittleKai/VietYaku/releases/latest).
2. Mở file APK trên thiết bị và tiến hành cài đặt (cho phép cài đặt ứng dụng từ nguồn không xác định nếu được yêu cầu).
3. Trong lần khởi động đầu tiên, ứng dụng sẽ tự động giải nén dữ liệu từ điển offline vào bộ nhớ máy (~15–20 giây).

---

## 🛠️ Hướng dẫn Build từ Mã nguồn

Dành cho lập trình viên muốn tự build hoặc đóng góp phát triển:

### 1. Chuẩn bị môi trường

- Đã cài đặt [Flutter SDK](https://docs.flutter.dev/get-started/install) phiên bản **3.44.2** trở lên (kèm Dart ^3.12).
- Cài đặt Visual Studio (kèm C++ Desktop Development) nếu build Windows.
- Cài đặt Android Studio và Android SDK/JDK 17 nếu build Android.

### 2. Clone mã nguồn &amp; Cài đặt dependencies

```bash
git clone https://github.com/LittleKai/VietYaku.git
cd VietYaku
flutter pub get
```

### 3. Chạy ứng dụng trong môi trường phát triển

```bash
# Chạy trên Windows
flutter run -d windows

# Chạy trên thiết bị / máy ảo Android
flutter run -d android
```

### 4. Build bản phát hành (Production Release)

```bash
# Build Windows Desktop (Portable)
flutter build windows --release
# File exe hoàn chỉnh sẽ nằm tại: build\windows\x64\runner\Release\

# Build Android APK
flutter build apk --release
# File APK hoàn chỉnh sẽ nằm tại: build\app\outputs\flutter-apk\app-release.apk
```

### 5. Chạy kiểm thử (Automated Tests)

VietYaku có bộ kiểm thử tự động toàn diện với hơn 560+ bài kiểm thử:

```bash
flutter analyze
flutter test
```

---

## 📂 Cấu trúc dự án

Dự án được tổ chức theo kiến trúc **Feature-First**:

```
lib/
├── app.dart                   # MaterialApp, điều hướng Responsive (Rail / Bottom Bar)
├── main.dart                  # Điểm khởi chạy, khởi tạo kích thước cửa sổ & DI
├── core/                      # Các tiện ích nền tảng (CJK, theme, TTS, concurrency, app paths)
│   ├── theme/                 # Hệ thiết kế Material 3 tập trung (AppTheme, AppSemanticColors)
│   └── platform_features.dart # Điều phối tính năng theo từng hệ điều hành
├── features/
│   ├── translation/           # Động cơ dịch VietPhrase, Hán Việt, token highlighter
│   ├── dictionary/            # Quản lý từ điển, nạp đa luồng Isolate, cache nhị phân .vydc
│   ├── dictionary_search/     # Trung tâm tìm kiếm & Tra ngược từ điển
│   ├── dictionary_sync/       # Đồng bộ từ điển cộng đồng qua server
│   ├── ai_translation/        # Bộ phân tích từ vựng & ngữ cảnh qua AI
│   ├── epub_converter/        # Bộ trích xuất & chuyển đổi định dạng sách EPUB
│   ├── glossary/              # Kết nối Global Glossary với AI_Translation_Bridge
│   ├── analysis/              # Kiểm tra độ phủ, cảnh báo lệch cụm từ, phát hiện tên riêng
│   ├── clipboard/             # Trình theo dõi Clipboard & Hotkey toàn cục
│   ├── repair/                # Pipeline sửa lỗi từ điển tiếng Nhật QuickTranslator
│   └── settings/              # Cài đặt thuật toán, giao diện, giọng đọc, sao lưu
└── shared/                    # Các widget dùng chung (dialog, context menu, buttons)
```

---
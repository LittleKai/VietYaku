---
name: VietYaku
description: Bàn biên dịch Nhật và Trung sang tiếng Việt, tập trung và đáng tin cậy.
colors:
  translation-indigo: "#4F46E5"
  meaning-red-light: "#D32F2F"
  meaning-red-dark: "#FF8A80"
  names-teal-light: "#00796B"
  names-teal-dark: "#4DB6AC"
typography:
  headline:
    fontFamily: "Segoe UI"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.27
    letterSpacing: "-0.2px"
  title:
    fontFamily: "Segoe UI"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.5
    letterSpacing: "-0.1px"
  body:
    fontFamily: "Segoe UI"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.43
  label:
    fontFamily: "Segoe UI"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.43
    letterSpacing: "0.1px"
rounded:
  swatch: "6px"
  compact: "8px"
  control: "10px"
  surface: "12px"
  dialog: "16px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.translation-indigo}"
    textColor: "#FFFFFF"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "12px 18px"
  input:
    backgroundColor: "#F0F0F5"
    textColor: "#1B1B1F"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "13px 14px"
  settings-section:
    backgroundColor: "#F7F7FC"
    textColor: "#1B1B1F"
    rounded: "{rounded.surface}"
    padding: "16px"
---

# Design System: VietYaku

## Overview

**Creative North Star: "Bàn biên dịch tĩnh"**

VietYaku mang cảm giác của một bàn làm việc ngôn ngữ được sắp xếp kỹ: yên tĩnh,
chính xác và đủ dày thông tin cho phiên dịch dài. Hệ thống giữ Material 3 làm nền
tảng quen thuộc, sau đó siết lại khoảng cách, trạng thái và cấu trúc để mọi điều
khiển biến mất vào tác vụ.

Màu chàm chỉ xuất hiện khi cần chỉ hướng hoặc xác nhận trạng thái. Các bề mặt
trung tính mát tạo lớp cho sidebar, nhóm cài đặt và dialog. Hệ thống loại bỏ giao
diện desktop cũ nhiều đường viền, phong cách manga trang trí, dashboard SaaS
chung chung và các thành phần Material mặc định thiếu tinh chỉnh.

**Key Characteristics:**

- Mật độ desktop có nhịp, không để điều khiển trôi tự do trên nền.
- Một màu hành động chính, màu ngữ nghĩa chỉ dành cho nội dung dịch.
- Điều khiển tiêu chuẩn, trạng thái rõ, nhãn tiếng Việt trực tiếp.
- Chuyển động 150 đến 200 ms chỉ để giải thích thay đổi trạng thái.

## Colors

Bảng màu trung tính mát với một giọng chàm điều hướng và hai màu ngữ nghĩa dành
riêng cho văn bản dịch.

### Primary

- **Chàm chuyển ngữ:** dùng cho hành động chính, focus, lựa chọn hiện tại và chỉ
  báo điều hướng. Không dùng làm trang trí nền lớn.

### Secondary

- **Đỏ nghĩa:** đánh dấu cụm đang chọn, có biến thể sáng và tối để giữ tương phản.
- **Xanh Names:** nhận diện token thuộc từ điển Names, tách biệt khỏi màu tương tác.

### Neutral

- Các vai trò `surface`, `surfaceContainerLow`, `surfaceContainer` và
  `surfaceContainerHigh` từ Material 3 tạo thứ bậc nền cho nội dung, sidebar,
  nhóm cài đặt và dialog.
- `onSurfaceVariant` chỉ dùng cho mô tả phụ; nội dung cần đọc lâu dùng
  `onSurface`.

**The One Action Color Rule.** Chàm chuyển ngữ chỉ dành cho hành động, focus và
trạng thái được chọn. Mọi màu khác phải có ý nghĩa nội dung cụ thể.

## Typography

**Display Font:** Segoe UI
**Body Font:** Segoe UI

**Character:** Một họ sans quen thuộc trên Windows, hiển thị tiếng Việt rõ và
fallback CJK ổn định. Phân cấp đến từ cỡ chữ và độ đậm, không từ nhiều họ font.

### Hierarchy

- **Headline** (600, 22 px, 1.27): tên màn hình và tiêu đề dialog.
- **Title** (600, 16 px, 1.5): tiêu đề nhóm và tên điều khiển quan trọng.
- **Body** (400, 14 px, 1.43): nội dung và mô tả, tối đa khoảng 70 ký tự mỗi dòng
  khi trình bày văn xuôi.
- **Label** (600, 14 px, 0.1 px): nút, tab và nhãn điều khiển.

**The Reading First Rule.** Chữ trong các pane do người dùng chọn riêng; chrome
ứng dụng luôn dùng Segoe UI để giữ điều hướng ổn định.

## Elevation

Hệ thống phẳng theo mặc định và tạo chiều sâu bằng lớp màu bề mặt. Bóng chỉ xuất
hiện ở menu, dialog, snackbar và phần tử thực sự nổi khỏi luồng; card cài đặt
không ghép viền mảnh với bóng rộng.

### Shadow Vocabulary

- **Menu thấp** (Material elevation 3): dropdown và menu ngữ cảnh.
- **Phản hồi** (Material elevation 4): snackbar nổi.
- **Dialog** (Material elevation 6): lớp tác vụ cần tập trung tạm thời.

**The Structural Depth Rule.** Nếu một bề mặt vẫn nằm trong luồng trang, dùng
màu nền hoặc đường phân cách; không thêm bóng để làm nó trông quan trọng hơn.

## Components

### Buttons

- **Shape:** góc cong gọn (10 px), vùng bấm tối thiểu 40 px trên desktop.
- **Primary:** nền chàm, chữ tương phản, đệm 12 px theo dọc và 18 px theo ngang.
- **Hover / Focus:** overlay nhẹ và focus ring theo `ColorScheme.primary`.
- **Secondary:** tonal cho hành động an toàn, text cho hủy hoặc hành động phụ.

### Cards / Containers

- **Corner Style:** góc 12 px.
- **Background:** `surfaceContainerLow` hoặc `surfaceContainer` theo cấp.
- **Shadow Strategy:** phẳng trong luồng.
- **Border:** chỉ dùng đường `outlineVariant` khi cần xác định ranh giới tương tác.
- **Internal Padding:** 16 px, tăng lên 24 px cho trang rộng.

### Inputs / Fields

- **Style:** nền filled, góc 10 px, nội dung đệm 13 px theo dọc và 14 px theo ngang.
- **Focus:** viền chàm 2 px.
- **Error / Disabled:** dùng vai trò error và opacity Material, không chỉ đổi màu
  nhãn.

### Navigation

Sidebar có nền riêng, brand mark ở đầu, nhãn luôn hiện khi đủ chiều rộng và trạng
thái chọn là một bề mặt tonal kín. Thu gọn giữ tooltip và icon 24 px; chuyển trạng
thái trong 200 ms và tắt animation khi reduced motion.

### Settings Row

Mỗi lựa chọn là một hàng có icon ngữ nghĩa, tiêu đề, mô tả và vùng điều khiển rõ.
Các hàng trong cùng nhóm dùng divider toàn chiều rộng; click cả hàng khi điều
khiển là switch. Control phức tạp chuyển xuống dòng ở chiều rộng hẹp.

### Dialog

Mọi dialog dùng cùng header có icon, tiêu đề và mô tả tùy chọn; content có giới
hạn chiều rộng rõ; actions căn phải theo thứ tự hủy trước, hành động chính sau.
Dialog cỡ chữ dùng chiều rộng lớn hơn để slider thực sự phục vụ việc tinh chỉnh.

## Do's and Don'ts

### Do:

- **Do** dùng chàm chuyển ngữ cho hành động chính, focus và lựa chọn hiện tại.
- **Do** dùng icon, tiêu đề, mô tả và divider để phân biệt từng dòng Settings.
- **Do** giữ control quen thuộc, trạng thái hover, focus, active và disabled đầy đủ.
- **Do** dùng layer bề mặt thay cho bóng trên các nhóm nằm trong luồng.
- **Do** giữ các pane văn bản là vùng thị giác quan trọng nhất.

### Don't:

- **Don't** tạo giao diện desktop cũ với đường viền dày, điều khiển chen chúc và
  phân cấp bằng nhiều màu không có ý nghĩa.
- **Don't** dùng phong cách manga, anime hoặc biểu tượng văn hóa trang trí không
  phục vụ tác vụ.
- **Don't** tạo dashboard SaaS chung chung với nhiều thẻ nổi, gradient và khoảng
  trắng quá lớn.
- **Don't** để các thành phần Material mặc định chưa được điều chỉnh thành một hệ
  thống thống nhất.
- **Don't** dùng viền màu dày một cạnh, gradient text, glassmorphism hoặc card bo
  góc trên 16 px.

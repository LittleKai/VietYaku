/// Các nguồn tra online (menu chuột phải "Tra online" ở tab Dịch).
///
/// Nguồn nào chạy API nào còn tùy mode: xem `startOnlineLookup`. Nhãn ở đây chỉ
/// dùng cho Cài đặt — nhãn `<<Từ điển>>` hiện trong ô Nghĩa và lưu vào
/// `OnlineDict_<mode>.txt` do controller đặt theo mode.
enum OnlineLookupSource {
  mazii('Mazii Online', 'Nhật→Việt (javi) hoặc Trung→Việt (cnvi)'),
  googleVi('Google Việt', 'Google Dịch sang tiếng Việt'),
  english('Nghĩa tiếng Anh', 'Nhật: Jisho (JMdict) · Trung: 有道词典'),
  chinese(
    'Nghĩa tiếng Trung',
    'Weblio 日中中日辞典 để đối chiếu Hán tự (chỉ mode Nhật)',
  );

  const OnlineLookupSource(this.label, this.hint);

  final String label;

  /// Mô tả ngắn hiện dưới dạng tooltip trong Cài đặt.
  final String hint;
}

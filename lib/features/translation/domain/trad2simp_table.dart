/// Bảng quy phồn thể → giản thể theo từng ký tự.
///
/// Nguồn: assets/mappings/trad2simp.tsv (sinh bởi tool/build_trad2simp.dart từ
/// CC-CEDICT). Dòng tsv `trad\tsimp`.
///
/// Bộ từ điển tiếng Trung của app là giản thể (VietPhrase 89.630 key giản so
/// với 753 key phồn), nên văn bản phồn thể dán vào gần như tra hụt hoàn toàn.
/// Quy về giản thể ngay trước khi tra, KHÔNG đụng vào văn bản trong ô Nguồn.
///
/// Mọi cặp trong bảng đều là 1 UTF-16 code unit → 1 UTF-16 code unit, nên
/// [convert] giữ nguyên độ dài chuỗi và token vẫn trỏ đúng offset của văn bản
/// gốc. Chỉ dùng cho mode Trung — kanji Nhật quy giản thể là hỏng.
class Trad2SimpTable {
  final Map<int, int> _map;

  const Trad2SimpTable(this._map);

  static const Trad2SimpTable empty = Trad2SimpTable(<int, int>{});

  factory Trad2SimpTable.parse(String tsv) {
    final map = <int, int>{};
    for (final line in tsv.split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final tab = line.indexOf('\t');
      if (tab != 1) continue;
      final simp = line.substring(tab + 1).trimRight();
      if (simp.length != 1) continue;
      map[line.codeUnitAt(0)] = simp.codeUnitAt(0);
    }
    return Trad2SimpTable(map);
  }

  bool get isEmpty => _map.isEmpty;

  /// Chữ ký của bảng, dùng đặt tên file cache `.vydc` của bộ dict đã quy giản.
  /// Sinh lại `trad2simp.tsv` là đổi chữ ký → cache cũ tự bị bỏ qua thay vì
  /// âm thầm giữ key quy sai.
  String get signature {
    var hash = 0xcbf29ce484222325;
    for (final key in _map.keys.toList()..sort()) {
      hash = (hash ^ key) * 0x100000001b3;
      hash = (hash ^ _map[key]!) * 0x100000001b3;
    }
    return hash.toUnsigned(32).toRadixString(36);
  }

  /// Trả về chính [text] khi không có ký tự phồn thể nào — trường hợp phổ biến
  /// nhất, không cấp phát thêm.
  String convert(String text) {
    List<int>? units;
    for (var i = 0; i < text.length; i++) {
      final simp = _map[text.codeUnitAt(i)];
      if (simp == null) continue;
      units ??= text.codeUnits.toList();
      units[i] = simp;
    }
    return units == null ? text : String.fromCharCodes(units);
  }
}

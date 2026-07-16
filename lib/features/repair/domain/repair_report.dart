/// Kết quả chạy repair trên một file từ điển.
class RepairReport {
  /// Số ký tự space (U+0020/U+3000) đã xóa khỏi key.
  int spacesRemoved = 0;

  /// Số ký tự đã convert giản thể/kyūjitai → JP.
  int charsConverted = 0;

  /// Số dòng bị loại vì trùng key với value giống hệt.
  int dupesIdenticalValue = 0;

  /// Trùng key nhưng value khác — giữ dòng đầu, log lại đây.
  final List<String> conflicts = [];

  /// Ký tự ambiguous gặp phải: char → các candidate + 1 key mẫu.
  final Map<String, String> ambiguous = {};

  /// Số dòng entry đã xử lý và tổng dòng.
  int entryLines = 0;
  int totalLines = 0;

  /// Số dòng variant chèn thêm (policy addVariant).
  int variantsAdded = 0;

  bool get hasChanges => spacesRemoved > 0 || charsConverted > 0;

  @override
  String toString() =>
      'RepairReport(spaces=$spacesRemoved, converted=$charsConverted, '
      'dupes=$dupesIdenticalValue, conflicts=${conflicts.length}, '
      'ambiguous=${ambiguous.length}, variants=$variantsAdded)';
}

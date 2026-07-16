import 'dict_type.dart';

/// Từ điển tra cụm: HashMap + index độ dài key lớn nhất theo code unit đầu.
///
/// Độ dài key đo bằng UTF-16 code unit. `maxLenByFirstUnit[firstUnit]` cho
/// biết cần thử match tối đa bao nhiêu code unit khi gặp ký tự bắt đầu đó.
class PhraseDictionary {
  final DictType type;
  final Map<String, String> entries;
  final Map<int, int> maxLenByFirstUnit;

  PhraseDictionary(this.type, this.entries)
      : maxLenByFirstUnit = _buildIndex(entries);

  PhraseDictionary.raw(this.type, this.entries, this.maxLenByFirstUnit);

  int get length => entries.length;

  bool get isEmpty => entries.isEmpty;

  int maxLenFor(int firstCodeUnit) => maxLenByFirstUnit[firstCodeUnit] ?? 0;

  String? lookup(String key) => entries[key];

  static Map<int, int> _buildIndex(Map<String, String> entries) {
    final index = <int, int>{};
    for (final key in entries.keys) {
      if (key.isEmpty) continue;
      final first = key.codeUnitAt(0);
      final current = index[first];
      if (current == null || key.length > current) {
        index[first] = key.length;
      }
    }
    return index;
  }
}

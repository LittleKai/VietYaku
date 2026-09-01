import '../../../core/cjk.dart';

/// Mở rộng entry tiếng Nhật bằng nhóm cách viết tương đương từ Sudachi.
///
/// Ba ràng buộc giữ alias sạch:
/// - Nhóm Sudachi chỉ chứa thể chia đầy đủ (`吞み込ま`), còn entry người dùng
///   thường là thân từ (`吞み込`) → mỗi nhóm được cắt dần đuôi kana chung để
///   sinh thêm nhóm thân từ.
/// - Key khớp trọn một surface thì mọi cách viết trong nhóm là cùng một từ →
///   nhận hết. Phải ghép nhiều mảnh thì mảnh phụ chỉ được kana hoá; đổi kanji
///   sang kanji tạo ra từ khác nghĩa (`扱い切れ` → `扱い斬れ`, `扱い伐れ` — cùng
///   nhóm Sudachi vì chung dạng chuẩn và cách đọc).
/// - Alias thuần kana ngắn bị loại theo độ dài KEY, vì kana của key ngắn hay
///   trùng hư từ trong câu (`空` → `から`), còn key dài là từ nội dung.
///
/// Entry người dùng ghi rõ luôn được phủ lại sau cùng.
class JapaneseVariantIndex {
  final List<List<String>> _groups;
  final Map<String, List<int>> _groupIdsBySurface;
  final Map<int, int> _maxLenByFirstUnit;
  final Map<String, List<String>> _reductionCache = <String, List<String>>{};

  JapaneseVariantIndex(List<List<String>> groups)
    : _groups = _normalizeGroups(groups),
      _groupIdsBySurface = <String, List<int>>{},
      _maxLenByFirstUnit = <int, int>{} {
    for (var groupId = 0; groupId < _groups.length; groupId++) {
      for (final surface in _groups[groupId]) {
        _groupIdsBySurface.putIfAbsent(surface, () => []).add(groupId);
        final first = surface.codeUnitAt(0);
        final current = _maxLenByFirstUnit[first] ?? 0;
        if (surface.length > current) {
          _maxLenByFirstUnit[first] = surface.length;
        }
      }
    }
  }

  bool get isEmpty => _groups.isEmpty;

  /// Sinh tối đa [maxAliasesPerEntry] alias cho mỗi entry rồi phủ entry ghi
  /// rõ lên trên để dữ liệu tự nhập không bao giờ bị alias thay thế.
  Map<String, String> expandEntries(
    Map<String, String> explicitEntries, {
    int maxAliasesPerEntry = 64,
  }) {
    if (isEmpty || explicitEntries.isEmpty || maxAliasesPerEntry <= 0) {
      return Map<String, String>.of(explicitEntries);
    }

    final expanded = <String, String>{};
    for (final entry in explicitEntries.entries) {
      final aliases = _aliasesFor(entry.key, maxAliasesPerEntry);
      for (final alias in aliases) {
        expanded.putIfAbsent(alias, () => entry.value);
      }
    }
    expanded.addAll(explicitEntries);
    return expanded;
  }

  List<String> _aliasesFor(String source, int limit) {
    if (source.isEmpty) return const [];

    final aliases = <String>{};
    final pieces = <String>[];

    void visit(int offset, bool substituted) {
      if (aliases.length >= limit) return;
      if (offset == source.length) {
        if (!substituted) return;
        final alias = pieces.join();
        if (_isSafeAlias(alias, source)) aliases.add(alias);
        return;
      }

      final first = source.codeUnitAt(offset);
      var maxTry = _maxLenByFirstUnit[first] ?? 0;
      final remaining = source.length - offset;
      if (maxTry > remaining) maxTry = remaining;

      // Greedy longest-match như engine dịch: chỉ mảnh dài nhất được xét, nếu
      // không số nhánh nhân theo mọi cách cắt và expand cả bộ dict thành phút.
      for (var length = maxTry; length >= 1; length--) {
        final surface = source.substring(offset, offset + length);
        if (!_groupIdsBySurface.containsKey(surface)) continue;
        // Cả key gói gọn trong một surface → tin cả nhóm.
        final wholeKey = offset == 0 && length == source.length && length >= 2;
        for (final variant in _variantsOf(surface, trustGroup: wholeKey)) {
          pieces.add(variant);
          visit(offset + length, substituted || variant != surface);
          pieces.removeLast();
          if (aliases.length >= limit) return;
        }
        return;
      }

      // Mảnh không thuộc nhóm nào (kanji hiếm, dấu câu) giữ nguyên để các mảnh
      // còn lại vẫn sinh được alias.
      final runeLength = runeLengthAt(source, offset);
      pieces.add(source.substring(offset, offset + runeLength));
      visit(offset + runeLength, substituted);
      pieces.removeLast();
    }

    visit(0, false);
    return aliases.take(limit).toList(growable: false);
  }

  /// Các cách viết thay được cho [surface], gộp mọi nhóm chứa nó và luôn có
  /// chính nó. Kết quả kana hoá phụ thuộc mỗi surface nên cache lại được.
  List<String> _variantsOf(String surface, {required bool trustGroup}) {
    if (!trustGroup) {
      final cached = _reductionCache[surface];
      if (cached != null) return cached;
    }
    final variants = <String>{surface};
    for (final groupId in _groupIdsBySurface[surface]!) {
      for (final variant in _groups[groupId]) {
        if (trustGroup || _isKanaReduction(surface, variant)) {
          variants.add(variant);
        }
      }
    }
    final result = variants.toList(growable: false);
    if (!trustGroup) _reductionCache[surface] = result;
    return result;
  }

  /// Mảnh phụ chỉ được giữ nguyên hoặc kana hoá.
  ///
  /// Chặn kanji → kanji (`切れ` → `斬れ`: cùng nhóm Sudachi vì chung dạng chuẩn
  /// và cách đọc, nhưng khác nghĩa) lẫn kana → kanji (một cách đọc ứng với hàng
  /// chục kanji: `きれ` → `訊れ`, `衣れ`, `気れ`… — nhiễu nhiều và có thể tạo
  /// alias trùng từ khác nghĩa). Kana hoá thì an toàn vì đi từ mặt chữ cụ thể.
  static bool _isKanaReduction(String surface, String variant) =>
      surface == variant || (!_isKanaOnly(surface) && _isKanaOnly(variant));

  static bool _isKanaOnly(String text) {
    for (var i = 0; i < text.length; i += runeLengthAt(text, i)) {
      if (!isKanaCodePoint(codePointAt(text, i))) return false;
    }
    return true;
  }

  /// Alias thuần kana ngắn dễ ăn nhầm hư từ trong câu, nhưng chặn cứng theo độ
  /// dài alias thì key 3 đơn vị như `吞み込` mất luôn bản kana `のみこ`. Mốc
  /// thật nằm ở KEY: key từ 3 đơn vị trở lên là từ nội dung nên bản kana của nó
  /// cũng là từ nội dung (`吞み込` → `のみこ`, `出来る` → `できる`); key ngắn hơn
  /// mới sinh ra kana đụng ngữ pháp (`空` → `から`, `呉れ` → `くれ`).
  static bool _isSafeAlias(String alias, String source) {
    for (var i = 0; i < alias.length; i += runeLengthAt(alias, i)) {
      if (isHanCodePoint(codePointAt(alias, i))) return true;
    }
    if (alias.length >= 4) return true;
    return alias.length >= 3 && source.length >= 3;
  }

  static List<List<String>> _normalizeGroups(List<List<String>> groups) {
    final normalized = <List<String>>[];
    final seen = <String>{};

    void register(Set<String> surfaces) {
      if (surfaces.length < 2) return;
      final sorted = surfaces.toList()..sort();
      final key = sorted.join('\t');
      if (!seen.add(key)) return;
      normalized.add(List<String>.unmodifiable(sorted));
    }

    for (final group in groups) {
      final surfaces = group.where((surface) => surface.isNotEmpty).toSet()
        ..removeWhere((surface) => surface.length < 2);
      if (surfaces.length < 2) continue;
      register(surfaces);
      // Nhóm thân từ: cắt dần đuôi kana chung để entry dạng gốc động từ
      // (`吞み込`, `扱い切`) vẫn bắt được nhóm.
      for (
        var stem = _stripCommonKanaTail(surfaces);
        stem != null;
        stem = _stripCommonKanaTail(stem)
      ) {
        register(stem);
      }
    }

    normalized.sort((a, b) => a.join('\t').compareTo(b.join('\t')));
    return List<List<String>>.unmodifiable(normalized);
  }

  /// Bỏ một code unit kana cuối nếu MỌI surface trong nhóm cùng kết thúc bằng
  /// nó; null khi không cắt được nữa.
  static Set<String>? _stripCommonKanaTail(Set<String> surfaces) {
    final sample = surfaces.first;
    if (sample.length < 2) return null;
    final tail = sample.codeUnitAt(sample.length - 1);
    if (!isKanaCodePoint(tail)) return null;
    for (final surface in surfaces) {
      if (surface.length < 2 ||
          surface.codeUnitAt(surface.length - 1) != tail) {
        return null;
      }
    }
    final stems = surfaces
        .map((surface) => surface.substring(0, surface.length - 1))
        .toSet();
    return stems.length < 2 ? null : stems;
  }
}

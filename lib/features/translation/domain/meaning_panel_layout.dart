import 'lookup_dictionary_type.dart';
import 'translation_engine.dart';

/// Loại từ điển KHÔNG dùng ở từng mode (giống quy tắc của popup):
/// - Nhật: bỏ Trung Việt.
/// - Trung: bỏ Nhật Việt và Mazii.
bool _availableFor(LookupDictionaryType type, TranslationMode mode) =>
    mode == TranslationMode.japanese
    ? type != LookupDictionaryType.zhVi
    : type != LookupDictionaryType.jaVi && type != LookupDictionaryType.mazii;

/// Các loại từ điển có thể bật/sắp xếp trong ô Nghĩa của [mode].
List<LookupDictionaryType> availableMeaningPanelTypes(TranslationMode mode) => [
  for (final type in LookupDictionaryType.defaultPanelOrder)
    if (_availableFor(type, mode)) type,
];

/// Bố cục ô Nghĩa: thứ tự hiển thị + các loại bị tắt, riêng cho từng ngôn ngữ.
///
/// [order] luôn chứa ĐỦ các loại khả dụng của mode; ẩn/hiện tách riêng qua
/// [hidden]. Nhờ vậy tắt một loại rồi bật lại vẫn giữ đúng vị trí cũ, và loại
/// mới thêm về sau không bị hiểu nhầm là "người dùng đã tắt".
class MeaningPanelLayout {
  final List<LookupDictionaryType> order;
  final Set<LookupDictionaryType> hidden;

  const MeaningPanelLayout({required this.order, this.hidden = const {}});

  factory MeaningPanelLayout.defaultsFor(TranslationMode mode) =>
      MeaningPanelLayout(order: availableMeaningPanelTypes(mode));

  bool isVisible(LookupDictionaryType type) => !hidden.contains(type);

  List<LookupDictionaryType> get visible => [
    for (final type in order)
      if (!hidden.contains(type)) type,
  ];

  /// Vị trí hiển thị của [type]; loại lạ (chưa có trong bố cục) xuống cuối.
  int indexOf(LookupDictionaryType? type) {
    if (type == null) return order.length;
    final i = order.indexOf(type);
    return i < 0 ? order.length : i;
  }

  MeaningPanelLayout withVisibility(LookupDictionaryType type, bool visible) =>
      MeaningPanelLayout(
        order: order,
        hidden: {
          ...hidden.where((t) => t != type),
          if (!visible) type,
        },
      );

  /// Kéo thả: chuyển mục ở [oldIndex] tới [newIndex] trong [order].
  ///
  /// [newIndex] tính theo danh sách ĐÃ gỡ mục ra — đúng ngữ nghĩa callback
  /// `onReorderItem` của ReorderableListView (bản `onReorder` cũ đã deprecated
  /// vì bắt người gọi tự trừ 1).
  MeaningPanelLayout reordered(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= order.length) return this;
    final next = List<LookupDictionaryType>.from(order);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    return MeaningPanelLayout(order: next, hidden: hidden);
  }

  /// Kéo chip [type] thả lên chip [target]: [type] về đúng chỗ [target] đang
  /// đứng, phần còn lại dồn lại.
  ///
  /// Chỉ số tính trên [order] đầy đủ nên kéo thả giữa các chip ĐANG HIỆN vẫn
  /// đặt đúng vị trí tương đối với cả những loại đang tắt.
  MeaningPanelLayout movedOnto(
    LookupDictionaryType type,
    LookupDictionaryType target,
  ) {
    final from = order.indexOf(type);
    final to = order.indexOf(target);
    if (from < 0 || to < 0 || from == to) return this;
    // Sau khi gỡ `type`, chèn tại `to` cho cả hai chiều: kéo xuống thì `target`
    // lùi một bậc nên `to` chính là ngay sau nó; kéo lên thì `to` là chỗ của nó.
    return reordered(from, to);
  }

  /// `name:0|1` cách nhau bằng `,` — giữ cả thứ tự lẫn trạng thái bật/tắt
  /// trong một khoá SharedPreferences.
  String encode() =>
      [for (final t in order) '${t.name}:${hidden.contains(t) ? 0 : 1}'].join(',');

  /// Đọc chuỗi đã lưu; mục lạ bị bỏ, loại khả dụng còn thiếu được nối vào cuối
  /// và mặc định BẬT (phiên bản sau thêm từ điển mới thì nó tự hiện ra).
  static MeaningPanelLayout decode(String? raw, TranslationMode mode) {
    final available = availableMeaningPanelTypes(mode);
    if (raw == null || raw.trim().isEmpty) {
      return MeaningPanelLayout.defaultsFor(mode);
    }

    final byName = LookupDictionaryType.values.asNameMap();
    final order = <LookupDictionaryType>[];
    final hidden = <LookupDictionaryType>{};

    for (final part in raw.split(',')) {
      final bits = part.split(':');
      final type = byName[bits.first.trim()];
      if (type == null || !available.contains(type) || order.contains(type)) {
        continue;
      }
      order.add(type);
      if (bits.length > 1 && bits[1].trim() == '0') hidden.add(type);
    }

    for (final type in available) {
      if (!order.contains(type)) order.add(type);
    }
    return MeaningPanelLayout(order: order, hidden: hidden);
  }
}

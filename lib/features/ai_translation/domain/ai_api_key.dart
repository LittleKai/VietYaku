/// Một API key kèm trọng số dùng cho vòng xoay key.
///
/// [weight] càng lớn thì key càng được gọi nhiều trong cùng một chu kỳ (key
/// weight 3 được dùng 3 lần trong khi key weight 1 được dùng 1 lần). Dùng để
/// ưu tiên key còn nhiều hạn ngạch hoặc key trả phí.
class AiApiKey {
  static const int minWeight = 1;
  static const int maxWeight = 100;

  final String value;
  final int weight;

  AiApiKey(String value, {int weight = minWeight})
    : value = value.trim(),
      weight = weight < minWeight
          ? minWeight
          : (weight > maxWeight ? maxWeight : weight);

  AiApiKey copyWith({String? value, int? weight}) =>
      AiApiKey(value ?? this.value, weight: weight ?? this.weight);

  Map<String, dynamic> toJson() => {'key': value, 'weight': weight};

  /// Chấp nhận cả dạng cũ (chuỗi key trần, weight = 1) lẫn dạng
  /// `{"key": ..., "weight": ...}`.
  static AiApiKey? tryParse(Object? raw) {
    if (raw is String) {
      final v = raw.trim();
      return v.isEmpty ? null : AiApiKey(v);
    }
    if (raw is Map) {
      final v = (raw['key'] as String?)?.trim();
      if (v == null || v.isEmpty) return null;
      return AiApiKey(v, weight: (raw['weight'] as num?)?.toInt() ?? minWeight);
    }
    return null;
  }

  static List<AiApiKey> parseList(Object? raw) {
    if (raw is! List) return const [];
    final out = <AiApiKey>[];
    for (final item in raw) {
      final key = tryParse(item);
      if (key != null) out.add(key);
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is AiApiKey && other.value == value && other.weight == weight;

  @override
  int get hashCode => Object.hash(value, weight);
}

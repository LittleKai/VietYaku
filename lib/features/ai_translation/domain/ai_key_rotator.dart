import 'ai_api_key.dart';

/// Xoay vòng API key theo trọng số (smooth weighted round-robin).
///
/// Mỗi lần gọi trả về key kế tiếp thay vì bốc ngẫu nhiên: trong một chu kỳ
/// `tổng weight` lần gọi, key weight `w` được dùng đúng `w` lần và các lần đó
/// nằm rải đều chứ không dồn cục. Nhờ vậy hạn ngạch của từng key tiêu đều theo
/// đúng tỉ lệ người dùng đặt.
///
/// State nằm ngoài cấu hình (chỉ trong bộ nhớ phiên chạy) nên đổi weight hay
/// thêm/bớt key lúc nào cũng được.
class AiKeyRotator {
  /// Điểm tích lũy của từng key, khóa theo giá trị key.
  final Map<String, int> _credit = {};

  /// Key kế tiếp trong vòng xoay, bỏ qua các key trong [skip] (đang cooldown).
  /// Trả `null` khi không còn key nào khả dụng.
  AiApiKey? next(List<AiApiKey> keys, {Set<String> skip = const {}}) {
    final pool = [
      for (final k in keys)
        if (k.value.isNotEmpty && !skip.contains(k.value)) k,
    ];
    if (pool.isEmpty) return null;

    // Key đã bị xóa khỏi cấu hình thì bỏ luôn điểm tích lũy (key đang cooldown
    // vẫn giữ để lúc hồi phục không bị dồn hết lượt về nó).
    _credit.removeWhere(
      (value, _) => !skip.contains(value) && !pool.any((k) => k.value == value),
    );

    if (pool.length == 1) return pool.first;

    var total = 0;
    AiApiKey? best;
    var bestCredit = 0;
    for (final k in pool) {
      total += k.weight;
      final credit = (_credit[k.value] ?? 0) + k.weight;
      _credit[k.value] = credit;
      if (best == null || credit > bestCredit) {
        best = k;
        bestCredit = credit;
      }
    }
    _credit[best!.value] = bestCredit - total;
    return best;
  }

  void reset() => _credit.clear();
}

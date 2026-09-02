/// Quy tắc nhắc cập nhật từ điển chung định kỳ.
///
/// Mốc đếm (`baseline`) là lần gần nhất người dùng cập nhật từ điển chung
/// **hoặc** lần gần nhất trả lời hộp thoại nhắc — bấm "Để sau" đẩy lần hỏi kế
/// tiếp lùi đúng một chu kỳ nữa, không hỏi lại mỗi lần mở app.
class SyncReminder {
  const SyncReminder._();

  /// Chu kỳ nhắc ngắn nhất cho phép (2 tuần).
  static const minIntervalDays = 14;

  /// Chu kỳ mặc định (1 tháng).
  static const defaultIntervalDays = 30;

  /// Giá trị chu kỳ nghĩa là tắt hẳn nhắc nhở.
  static const disabledIntervalDays = 0;

  /// Kẹp chu kỳ về giá trị hợp lệ: 0 (tắt) hoặc ít nhất [minIntervalDays].
  static int normalizeIntervalDays(int days) {
    if (days <= 0) return disabledIntervalDays;
    return days < minIntervalDays ? minIntervalDays : days;
  }

  /// Đã tới hạn nhắc chưa. [baseline] `null` (chưa từng có mốc) → chưa tới hạn:
  /// phía gọi ghi mốc là thời điểm hiện tại rồi mới bắt đầu đếm.
  static bool isDue({
    required int intervalDays,
    required DateTime? baseline,
    required DateTime now,
  }) {
    final interval = normalizeIntervalDays(intervalDays);
    if (interval == disabledIntervalDays || baseline == null) return false;
    // Mốc ở tương lai (đồng hồ máy bị chỉnh lùi) coi như chưa tới hạn.
    if (baseline.isAfter(now)) return false;
    return !now.isBefore(baseline.add(Duration(days: interval)));
  }

  /// Số ngày đã trôi qua kể từ [baseline], để hiện trong hộp thoại nhắc.
  static int daysSince(DateTime baseline, DateTime now) =>
      now.difference(baseline).inDays;
}

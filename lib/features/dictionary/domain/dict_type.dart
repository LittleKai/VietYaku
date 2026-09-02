import '../../translation/domain/translation_engine.dart';

/// Các loại từ điển, thứ tự khai báo cũng là thứ tự ưu tiên khi tie-break
/// (UserDict > Names > VietPhrase). LacViet/Mazii/ChinesePhienAmWords/Pronouns
/// không tham gia greedy match chính; Mazii/Babylon/ThieuChuu/Cedict/
/// ChinesePhienAmEnglish/JaVi/ZhVi/OnlineDict chỉ dùng cho ô Nghĩa.
enum DictType {
  userDict,
  names,
  vietPhrase,
  lacViet,
  mazii,
  chinesePhienAm,
  pronouns,
  babylon,
  thieuChuu,
  cedict,
  chinesePhienAmEnglish,
  jaVi,
  zhVi,
  onlineDict,
  aiDict,

  /// Các từ/cụm con AI tách ra khi tra (`AiEntries_<mode>.txt`), format
  /// `key=nghĩa ngắn` như VietPhrase. Đây là loại AI duy nhất tham gia greedy
  /// match — `aiDict` giữ đoạn phân tích dài, chỉ dùng cho ô Nghĩa.
  aiEntries,
}

extension DictTypeX on DictType {
  /// Kiểm tra loại từ điển có thuộc ngôn ngữ đang chọn hay không:
  /// - Tiếng Nhật (japanese): loại bỏ Trung Việt (`zhVi`).
  /// - Tiếng Trung (chinese): loại bỏ Nhật Việt (`jaVi`) và Mazii (`mazii`).
  bool isAvailableFor(TranslationMode mode) {
    if (mode == TranslationMode.japanese) {
      return this != DictType.zhVi;
    } else {
      return this != DictType.jaVi && this != DictType.mazii;
    }
  }
}


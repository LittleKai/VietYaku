/// Các loại từ điển, thứ tự khai báo cũng là thứ tự ưu tiên khi tie-break
/// (UserDict > Names > VietPhrase). LacViet/ChinesePhienAmWords/Pronouns
/// không tham gia greedy match chính; Babylon/ThieuChuu/Cedict/
/// ChinesePhienAmEnglish/JaVi/ZhVi chỉ dùng cho ô Nghĩa.
enum DictType {
  userDict,
  names,
  vietPhrase,
  lacViet,
  chinesePhienAm,
  pronouns,
  babylon,
  thieuChuu,
  cedict,
  chinesePhienAmEnglish,
  jaVi,
  zhVi,
}

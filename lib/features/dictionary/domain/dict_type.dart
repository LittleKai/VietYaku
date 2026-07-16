/// Các loại từ điển, thứ tự khai báo cũng là thứ tự ưu tiên khi tie-break
/// (UserDict > Names > VietPhrase). LacViet/ChinesePhienAmWords/Pronouns
/// không tham gia greedy match chính.
enum DictType {
  userDict,
  names,
  vietPhrase,
  lacViet,
  chinesePhienAm,
  pronouns,
}

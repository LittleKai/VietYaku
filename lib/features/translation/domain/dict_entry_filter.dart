/// Độ dài tối đa (tính theo rune) của một key được phép thêm vào VietPhrase.
///
/// Danh từ ghép tiếng Nhật/Trung dài nhất trong bộ dict gốc quanh 8-9 rune;
/// dài hơn 10 gần như chắc chắn là một mệnh đề chứ không phải từ.
const maxWordLikeRunes = 10;

/// Ký tự chỉ xuất hiện khi chuỗi là câu/mệnh đề chứ không phải từ hay cụm từ.
const _sentenceMarks = {
  '。', '．', '.', '、', '，', ',', '！', '!', '？', '?', '…', '；', ';', '：', ':',
  '「', '」', '『', '』', '（', '）', '(', ')', '【', '】', '《', '》', '〈', '〉',
  '～', '~', '—', '–', '"', "'", '“', '”', '‘', '’',
};

/// Chuỗi [key] có phải một TỪ hoặc CỤM TỪ (danh/động/tính/trạng từ…) đủ tư cách
/// làm mục VietPhrase hay không.
///
/// Cả câu thì không: value VietPhrase được chèn thẳng vào bản dịch, nên một
/// mệnh đề lọt vào sẽ nuốt trọn đoạn văn và làm hỏng kết quả dịch. Đây là bộ
/// lọc duy nhất giữa kết quả tra AI/online và từ điển dịch.
bool isWordLikeEntry(String key) {
  final trimmed = key.trim();
  if (trimmed.isEmpty) return false;

  // Khoảng trắng/xuống dòng bên trong → đã là chuỗi nhiều thành phần.
  for (final unit in trimmed.codeUnits) {
    if (unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D) {
      return false;
    }
  }

  for (final ch in trimmed.characters) {
    if (_sentenceMarks.contains(ch)) return false;
  }

  return trimmed.runes.length <= maxWordLikeRunes;
}

/// Độ dài tối đa của value rút từ kết quả tra online khi đưa vào VietPhrase.
const maxShortMeaningChars = 120;

/// Dòng nhãn nguồn `<<Mazii Online>>` khi đọc lại value đã lưu trong OnlineDict
/// (thân đến thẳng từ API thì chưa có dòng này).
bool _isSourceLabel(String line) =>
    line.startsWith('<<') && line.endsWith('>>');

/// Rút một nghĩa NGẮN kiểu từ điển từ thân kết quả tra online.
///
/// Thân Mazii/Jisho có dạng nhiều dòng: dòng đầu là headword + cách đọc + âm
/// Hán, các dòng nghĩa bắt đầu bằng `-`. Value VietPhrase phải ngắn vì nó được
/// chèn thẳng vào bản dịch, nên chỉ lấy dòng nghĩa đầu tiên.
///
/// Trả chuỗi rỗng khi không rút được gì dùng được — khi đó không ghi gì cả.
String shortMeaningOf(String body) {
  String? firstNonEmpty;
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || _isSourceLabel(line)) continue;
    firstNonEmpty ??= line;
    if (line.startsWith('-')) {
      final meaning = line.substring(1).trim();
      if (meaning.isNotEmpty) return _cap(meaning);
    }
  }
  return firstNonEmpty == null ? '' : _cap(firstNonEmpty);
}

String _cap(String value) => value.length <= maxShortMeaningChars
    ? value
    : value.substring(0, maxShortMeaningChars).trimRight();

/// Nhãn nguồn online trả nghĩa TIẾNG VIỆT.
///
/// Chỉ nghĩa tiếng Việt mới được đưa vào VietPhrase: Jisho/Youdao trả tiếng
/// Anh, Weblio trả tiếng Trung — nhét vào từ điển dịch thì bản dịch ra tiếng
/// Anh/Trung giữa câu tiếng Việt.
const vietnameseLookupLabels = {'Mazii Online'};

/// Headword mà nguồn online thực sự trả về, đọc từ dòng đầu của thân kết quả.
///
/// Mazii/Jisho mở đầu bằng `<từ> 「<cách đọc>」 …`; phần trước dấu `「` hoặc
/// trước khoảng trắng đầu tiên chính là từ mà nguồn tra được.
/// Trả chuỗi rỗng khi không đọc được.
String headwordOf(String body) {
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('-') || _isSourceLabel(line)) continue;
    final cut = line.indexOf('「');
    final head = (cut > 0 ? line.substring(0, cut) : line).trim();
    final space = head.indexOf(' ');
    return (space > 0 ? head.substring(0, space) : head).trim();
  }
  return '';
}

/// Nghĩa rút từ [body] có thực sự nói về [word] hay không.
///
/// Mazii/Jisho/Youdao đều tra mờ: gõ `再入荷` có thể trả về mục của `再入`, gõ
/// `一愣` trả về `eleven; 11`. Đọc thì người dùng tự nhận ra lệch, nhưng đưa
/// thẳng vào VietPhrase là nhét bản dịch SAI vào từ điển dịch. Không xác nhận
/// được headword đúng bằng [word] thì không promote.
bool meaningMatchesWord(String word, String body) {
  final head = headwordOf(body);
  return head.isNotEmpty && head == word.trim();
}

extension _Characters on String {
  /// Duyệt theo rune (surrogate pair tính là một ký tự).
  Iterable<String> get characters sync* {
    for (final rune in runes) {
      yield String.fromCharCode(rune);
    }
  }
}

import 'vietphrase_value.dart';

/// Các cách dịch sạch, đánh số từ 1 để map trực tiếp với phím số.
List<String> meaningChoicesFromValue(String value) => parseVietPhraseValue(
  value,
).expand((meaning) => meaning.alternatives).toList(growable: false);

/// Trả về lựa chọn theo index bàn phím 1..9; ngoài khoảng thì không chọn.
String? choiceAt(List<String> choices, int index) {
  if (index < 1 || index > 9 || index > choices.length) return null;
  return choices[index - 1];
}

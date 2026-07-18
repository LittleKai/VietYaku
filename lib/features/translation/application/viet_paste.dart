import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sự kiện chép một nghĩa sang ô Việt: TokenTextView (ô VietPhrase) phát,
/// ResultPane lắng nghe rồi chèn vào vị trí con trỏ trong ô Việt.
/// [seq] tăng mỗi lần để cùng một chữ chép nhiều lần vẫn kích hoạt listener.
class VietPasteNotifier extends Notifier<({String text, int seq})?> {
  var _seq = 0;

  @override
  ({String text, int seq})? build() => null;

  void paste(String text) {
    if (text.isEmpty) return;
    state = (text: text, seq: ++_seq);
  }
}

final vietPasteProvider =
    NotifierProvider<VietPasteNotifier, ({String text, int seq})?>(
      VietPasteNotifier.new,
    );

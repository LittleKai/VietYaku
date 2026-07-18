import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controller dùng chung cho ô "Bản dịch Việt" (người dùng tự gõ). Chia sẻ để
/// menu chuột phải trong ô VietPhrase có thể chèn từ vào đúng vị trí con trỏ.
final vietDraftControllerProvider = Provider<TextEditingController>((ref) {
  final controller = TextEditingController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Chèn [word] vào vị trí con trỏ hiện tại của [controller] (thêm khoảng trắng
/// phân tách khi cần); không có con trỏ hợp lệ → nối vào cuối.
void insertIntoVietDraft(TextEditingController controller, String word) {
  final text = controller.text;
  final selection = controller.selection;
  final at = selection.isValid ? selection.baseOffset : text.length;
  final pos = at.clamp(0, text.length);

  final before = text.substring(0, pos);
  final after = text.substring(pos);
  final needSpaceBefore =
      before.isNotEmpty && !before.endsWith(' ') && !before.endsWith('\n');
  final insert = needSpaceBefore ? ' $word' : word;

  final newText = '$before$insert$after';
  final caret = before.length + insert.length;
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: caret),
  );
}

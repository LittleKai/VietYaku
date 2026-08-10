import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/theme/app_theme.dart';

/// Tỉ lệ tương phản WCAG giữa hai màu đục.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // Bản redesign đảo ngược quy ước M3: các lớp "nổi" (card, ô nhập, dropdown)
  // phải SÁNG HƠN canvas ở cả hai chế độ, nếu không card lại chìm xuống nền.
  for (final entry in {
    'sáng': AppTheme.light(),
    'tối': AppTheme.dark(),
  }.entries) {
    final String mode = entry.key;
    final ColorScheme s = entry.value.colorScheme;

    group('AppTheme ($mode)', () {
      test('lớp nổi sáng hơn canvas', () {
        expect(
          s.surfaceContainerLowest.computeLuminance(),
          greaterThan(s.surface.computeLuminance()),
        );
      });

      test('chữ mô tả đủ tương phản trên nền card', () {
        expect(
          _contrast(s.onSurfaceVariant, s.surfaceContainerLowest),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('viền phân biệt được với nền card', () {
        expect(
          _contrast(s.outlineVariant, s.surfaceContainerLowest),
          greaterThanOrEqualTo(1.3),
        );
      });

      test('chữ trên nền primary đủ tương phản', () {
        expect(_contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
      });
    });

    test('AppTheme ($mode): nhãn chip resolve được theo trạng thái', () {
      // Bẫy đã mắc một lần: dùng WidgetStateTextStyle ở đây làm Chip mất kiểu
      // chữ và nhãn tàng hình. Màu phải nằm ở thuộc tính `color`.
      final TextStyle? label = entry.value.chipTheme.labelStyle;
      expect(label, isNotNull);
      expect(label!.color, isA<WidgetStateColor>());
      final WidgetStateColor color = label.color! as WidgetStateColor;
      expect(color.resolve({WidgetState.selected}), s.primary);
      expect(color.resolve(<WidgetState>{}), s.onSurfaceVariant);
    });

    test('AppTheme ($mode): dialogTheme cắt xén góc bo mượt mà', () {
      expect(entry.value.dialogTheme.clipBehavior, Clip.antiAlias);
    });
  }
}

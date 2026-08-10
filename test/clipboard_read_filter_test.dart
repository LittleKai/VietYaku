import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/clipboard/domain/clipboard_read_filter.dart';

void main() {
  test('chỉ nhận nội dung có CJK và chống lặp bằng hash', () {
    final filter = ClipboardReadFilter();
    final now = DateTime(2026, 8, 9);
    expect(filter.shouldAccept('hello', now), isFalse);
    expect(filter.shouldAccept('少女です', now), isTrue);
    expect(
      filter.shouldAccept('少女です', now.add(const Duration(seconds: 3))),
      isFalse,
    );
  });

  test('debounce sự kiện khác nhau đến quá sát nhau', () {
    final filter = ClipboardReadFilter();
    final now = DateTime(2026, 8, 9);
    expect(filter.shouldAccept('少女', now), isTrue);
    expect(
      filter.shouldAccept('少年', now.add(const Duration(milliseconds: 100))),
      isFalse,
    );
    expect(
      filter.shouldAccept('少年', now.add(const Duration(milliseconds: 400))),
      isTrue,
    );
  });

  test('bỏ qua clipboard do chính app vừa ghi', () {
    final filter = ClipboardReadFilter();
    final now = DateTime(2026, 8, 9);
    filter.markOwnWrite('少女', now);
    expect(
      filter.shouldAccept('少女', now.add(const Duration(milliseconds: 50))),
      isFalse,
    );
    expect(
      filter.shouldAccept('少女', now.add(const Duration(seconds: 3))),
      isTrue,
    );
  });
}

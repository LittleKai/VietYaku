import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/concurrency.dart';

void main() {
  group('runWithConcurrency', () {
    test('giữ đúng thứ tự kết quả theo thứ tự đầu vào', () async {
      // Tác vụ đầu chậm nhất: nếu ghép kết quả theo thứ tự HOÀN THÀNH thì
      // thứ tự sẽ đảo, test này bắt được.
      final results = await runWithConcurrency<int>([
        () => Future.delayed(const Duration(milliseconds: 30), () => 1),
        () => Future.delayed(const Duration(milliseconds: 20), () => 2),
        () => Future.delayed(const Duration(milliseconds: 10), () => 3),
        () => Future.value(4),
      ], limit: 2);

      expect(results, [1, 2, 3, 4]);
    });

    test('không bao giờ chạy quá [limit] tác vụ cùng lúc', () async {
      var running = 0;
      var peak = 0;
      final completers = <Completer<int>>[];

      Future<int> Function() task(int value) => () async {
        running++;
        peak = running > peak ? running : peak;
        final completer = Completer<int>();
        completers.add(completer);
        // Nhả về event loop để worker khác có cơ hội khởi động.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        completer.complete(value);
        return value;
      };

      final results = await runWithConcurrency<int>([
        for (var i = 0; i < 8; i++) task(i),
      ], limit: 3);

      expect(peak, lessThanOrEqualTo(3));
      expect(results, [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('limit 0 hoặc lớn hơn số tác vụ → chạy song song hết', () async {
      var running = 0;
      var peak = 0;

      Future<int> Function() task(int value) => () async {
        running++;
        peak = running > peak ? running : peak;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        return value;
      };

      final results = await runWithConcurrency<int>([
        for (var i = 0; i < 4; i++) task(i),
      ], limit: 0);

      expect(peak, 4);
      expect(results, [0, 1, 2, 3]);
    });

    test('danh sách rỗng trả về rỗng', () async {
      expect(await runWithConcurrency<int>([], limit: 2), isEmpty);
    });

    test('lỗi của một tác vụ được ném ra ngoài', () async {
      expect(
        runWithConcurrency<int>([
          () => Future.value(1),
          () => Future<int>.error(StateError('hỏng')),
        ], limit: 1),
        throwsStateError,
      );
    });
  });
}

/// Chạy [tasks] với tối đa [limit] tác vụ cùng lúc, trả kết quả theo ĐÚNG thứ
/// tự đầu vào (như `Future.wait`).
///
/// [tasks] là danh sách hàm khởi tạo, không phải Future — Future được tạo ra là
/// đã chạy, nên muốn giới hạn thì phải hoãn việc tạo lại.
///
/// [limit] <= 0 hoặc >= số tác vụ → chạy song song hết, hệt `Future.wait`.
Future<List<T>> runWithConcurrency<T>(
  List<Future<T> Function()> tasks, {
  required int limit,
}) async {
  if (limit <= 0 || limit >= tasks.length) {
    return Future.wait(tasks.map((task) => task()));
  }
  final results = List<T?>.filled(tasks.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= tasks.length) return;
      results[index] = await tasks[index]();
    }
  }

  await Future.wait([for (var i = 0; i < limit; i++) worker()]);
  return [for (final result in results) result as T];
}

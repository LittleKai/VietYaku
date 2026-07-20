import 'dart:io';

import 'package:http/http.dart' as http;

/// Tải [url] về [savePath], gọi [onProgress] với giá trị 0..1 (hoặc -1 nếu
/// server không trả `content-length`).
Future<File> downloadWithProgress({
  required String url,
  required String savePath,
  required void Function(double progress) onProgress,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final owns = client == null;
  try {
    final request = http.Request('GET', Uri.parse(url));
    final response = await httpClient.send(request);
    if (response.statusCode != 200) {
      throw Exception('Tải file thất bại (mã lỗi ${response.statusCode}).');
    }

    final total = response.contentLength ?? -1;
    var received = 0;
    final file = File(savePath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total > 0 ? received / total : -1);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return file;
  } finally {
    if (owns) httpClient.close();
  }
}

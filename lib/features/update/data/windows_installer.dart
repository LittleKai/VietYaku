import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Giải nén zip release Windows (nội dung nằm thẳng ở root zip, không có
/// thư mục con bọc ngoài — xem `.claude/skills/build-and-release/scripts/build.ps1`)
/// vào [destDir].
Future<void> extractWindowsZip(String zipPath, String destDir) async {
  final bytes = await File(zipPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive.files) {
    final outPath = p.join(destDir, file.name);
    if (file.isFile) {
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    } else {
      await Directory(outPath).create(recursive: true);
    }
  }
}

/// Sinh script `.bat` chờ [exePath] thoát hẳn, thay toàn bộ [installDir] bằng
/// nội dung [stagingDir], khởi động lại app rồi tự xoá chính nó.
Future<String> writeSelfUpdateScript({
  required String stagingDir,
  required String installDir,
  required String exePath,
}) async {
  final exeName = p.basename(exePath);
  final scriptPath = p.join(
    Directory.systemTemp.path,
    'vietyaku_update_${DateTime.now().millisecondsSinceEpoch}.bat',
  );
  final script =
      '''
@echo off
:waitloop
tasklist /FI "IMAGENAME eq $exeName" 2>NUL | find /I "$exeName" >NUL
if "%ERRORLEVEL%"=="0" (
  timeout /t 1 /nobreak >NUL
  goto waitloop
)
xcopy "$stagingDir\\*" "$installDir\\" /E /Y /I /Q >NUL
rmdir /S /Q "$stagingDir"
start "" "$exePath"
(goto) 2>nul & del "%~f0"
''';
  await File(scriptPath).writeAsString(script, encoding: SystemEncoding());
  return scriptPath;
}

/// Chạy script `.bat` ở tiến trình tách biệt (detached) để nó tiếp tục sống
/// sau khi app thoát.
Future<void> spawnSelfUpdateScript(String scriptPath) {
  return Process.start(
    'cmd',
    ['/c', 'start', '', '/min', scriptPath],
    mode: ProcessStartMode.detached,
  );
}

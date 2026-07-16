# Project Conventions — VietYaku

**Last Updated:** 2026-07-15

---

## 📁 File & Folder Naming

### Files
- Dart files: `snake_case.dart` (vd: `translation_engine.dart`, `binary_cache.dart`)
- Widgets/screens: theo vai trò — `*_screen.dart`, `*_pane.dart`, `*_panel.dart`, `*_dialog.dart`, `*_button.dart`
- Providers/controllers: `*_provider.dart`, `*_controller.dart`, `*_service.dart`
- Tests: `<đối tượng>_test.dart`; integration dữ liệu thật: `*_real_data_test.dart` / `translate_flow_test.dart`

### Folders
Feature-first, mỗi feature chia layer:
```
lib/features/<feature>/
├── domain/         # thuần Dart, KHÔNG import Flutter (trừ foundation nếu bất khả kháng)
├── data/           # IO, parse, cache, file system
├── application/    # Riverpod providers, controllers
└── presentation/   # widgets
lib/core/           # dùng chung không thuộc feature (cjk, app_paths, fnv_hash, tts_service)
lib/shared/widgets/ # widget dùng chéo feature
tool/               # script CLI dev (dart run tool/...)
```

---

## 🧩 Component Structure

### Widget pattern
```dart
// Stateless đọc provider:
class TranslateScreen extends ConsumerWidget {
  const TranslateScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) { ... }
}

// Có local state (TextEditingController, Timer, recognizers):
class SourcePane extends ConsumerStatefulWidget {
  const SourcePane({super.key});
  @override
  ConsumerState<SourcePane> createState() => _SourcePaneState();
}
```
- Luôn `const` constructor + `super.key`.
- Dispose đầy đủ: `TextEditingController`, `Timer`, `TapGestureRecognizer` (xem `result_pane.dart`).
- Widget private trong cùng file dùng prefix `_` (vd `_ReportCard`).

### Provider pattern (Riverpod manual — KHÔNG codegen)
```dart
class TranslationController extends Notifier<TranslationState> {
  @override
  TranslationState build() => ...;
}
final translationControllerProvider =
    NotifierProvider<TranslationController, TranslationState>(
        TranslationController.new);
```
- State class immutable + `copyWith`.
- `ref.watch` trong `build()`, `ref.read` trong callbacks.
- Rebuild chọn lọc: `ref.watch(provider.select((s) => s.field))`.
- `sharedPreferencesProvider` là `Provider` throw UnimplementedError, override trong `main()`.

---

## 🎨 Code Style

### Imports Order (dart style chuẩn, mỗi nhóm cách 1 dòng trống)
```dart
// 1. dart: (async, convert, io, isolate, typed_data)
// 2. package: (flutter trước, third-party sau, alphabetical)
// 3. Relative imports (../../..., alphabetical)
```
- `path` import as: `import 'package:path/path.dart' as p;`

### Spacing & Formatting
- Theo `dart format` mặc định: 2 spaces, line ~80
- Quotes: single `'...'`; raw string `r'...'` cho chuỗi có `\n\t` literal
- Trailing commas: có (để format đẹp widget tree)
- Lint: `flutter_lints` ^6.0.0 (analysis_options.yaml mặc định) — `flutter analyze` phải sạch

### Comments
- Tiếng Việt, giải thích ràng buộc/quyết định (WHY), không diễn giải code.
- Doc comment `///` cho class/hàm public quan trọng; ghi rõ bất biến (vd "VALUE KHÔNG ĐỔI 1 BYTE").

---

## 📝 Dart Conventions

### Types & modern syntax
- Records cho trả về nhiều giá trị: `(String, int) fixKeySpaces(...)`, named record `({int srcHash, int srcSize, ...})?` cho header.
- Switch expressions / pattern matching destructuring: `final (spaceFixed, removed) = fixKeySpaces(rawKey);`
- Enum thuần cho phân loại (`DictType`, `TokenKind`, `RepairPolicy`, `TranslationMode`) — thứ tự khai báo `DictType` = thứ tự ưu tiên.
- Đo chuỗi CJK: UTF-16 code unit (`codeUnitAt`); helper `codePointAt`/`runeLengthAt` trong `core/cjk.dart` khi cần rune. KHÔNG dùng `characters` package.

### Isolates
- Tác vụ nặng một-kết-quả: `Isolate.run(() => ...)` (transfer qua Isolate.exit).
- Cần progress: `Isolate.spawn` + `SendPort.send(double)` cho progress, `Isolate.exit(port, result)` cho kết quả (xem `repair_controller.dart`).
- Hàm chạy trong isolate viết dạng sync thuần (`loadDictionarySync`, `repairFile`) để test không cần isolate.

### File IO
- File từ điển: đọc `readAsString`, strip BOM bằng check `codeUnitAt(0) == 0xFEFF`; ghi UTF-8 BOM CRLF: `'﻿${lines.join('\r\n')}\r\n'`.
- Đường dẫn appdata qua `AppPaths` (core/app_paths.dart), không gọi path_provider rải rác.

---

## 🔤 Naming Conventions

### Variables & Functions
- Boolean: tiền tố `is`/`has`/`from` (`isValid`, `hasResult`, `fromCache`)
- Functions: camelCase, top-level cho pure functions domain (`fixKeySpaces`, `parseEntries`, `extractReading`)
- Constants: lowerCamelCase (`defaultSourceDir`, `dictFileNames`, `sourceDir` trong test)
- Event handlers trong widget: `_verb` private (`_translate`, `_openFile`, `_pollClipboard`)
- Provider: `<tên>Provider`; Notifier: `<Tên>Notifier` hoặc `<Tên>Controller` (controller = có action từ UI)

---

## 🧪 Testing

### Test File Naming
`test/<đối_tượng>_test.dart` — nhóm bằng `group()`, tên test tiếng Việt mô tả hành vi.

### Test Structure
```dart
group('repairFile (test case bắt buộc, nguyên văn dữ liệu thật)', () {
  test('覚 悟 → 覚悟', () {
    final r = run('覚 悟=(kakugo)giác ngộ\r\n');
    expect(r.content, '覚悟=(kakugo)giác ngộ\r\n');
  });
});
```
- Integration test dữ liệu thật: hardcode `sourceDir`, `skip: available ? false : 'lý do'` (testWidgets chỉ nhận bool: `skip: !available`).
- Temp files: `Directory.systemTemp.createTempSync('prefix')` + tearDown delete.
- Widget test cần provider: `ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(prefs), appPathsProvider.overrideWith(...)])` + `SharedPreferences.setMockInitialValues({})`.
- Benchmark trong test: `Stopwatch` + `// ignore: avoid_print` khi cần print số liệu.

---

## ✅ Do / ❌ Don't

### Do:
- ✅ Logic domain thuần Dart, tách khỏi Flutter → test được không cần widget.
- ✅ Chạy `flutter analyze` + `flutter test` trước khi kết thúc task.
- ✅ Đụng repair/parser → chạy thêm `dart run tool/export_jp.dart` verify dữ liệu thật.
- ✅ UI text tiếng Việt, tooltip đầy đủ cho icon button (kể cả lý do disable).

### Don't:
- ❌ Không thêm codegen (freezed/riverpod_generator), GoRouter, Dio, SQLite/Isar/Hive — quyết định đã chốt.
- ❌ Không ghi đè file từ điển gốc trong Google Drive; chỉ xuất `*_JP.txt`.
- ❌ Không sửa tay `assets/mappings/simp2jp.tsv` — sửa build script/overrides rồi regenerate.
- ❌ Không đổi format `.vydc` mà quên tăng `BinaryCache.version`.
- ❌ Không dùng trie/DB cho engine tra — HashMap + maxLenByFirstUnit là thiết kế chốt.

---

**📌 NOTE:** These conventions are derived from existing code patterns. When in doubt, follow the pattern of similar existing files.

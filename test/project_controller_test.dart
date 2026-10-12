import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vietyaku/features/project/application/project_controller.dart';
import 'package:vietyaku/features/project/domain/project_segment.dart';

void main() {
  late Directory temp;

  setUp(
    () => temp = Directory.systemTemp.createTempSync('vietyaku_controller_'),
  );
  tearDown(() => temp.deleteSync(recursive: true));

  test('open TXT builds machine segments and reviewed target', () async {
    final source = File('${temp.path}/chapter.txt')
      ..writeAsStringSync('第一句。\n第二句！');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(projectControllerProvider.notifier);

    await controller.openSourcePath(
      source.path,
      projectRoot: temp,
      machineTranslate: (value) => 'máy:$value',
    );
    controller.setTarget(0, 'Bản dịch');
    controller.markReviewed(0);
    await controller.save();

    final state = container.read(projectControllerProvider);
    expect(state.document!.segments, hasLength(2));
    expect(state.document!.segments.first.machineOutput, 'máy:第一句。');
    expect(
      state.document!.segments.first.status,
      ProjectSegmentStatus.reviewed,
    );
    expect(
      File('${temp.path}/target/translated.txt').readAsStringSync(),
      contains('Bản dịch'),
    );
    expect(File('${temp.path}/tm.jsonl').existsSync(), isTrue);
  });

  test('TM suggestion never overwrites a non-empty target', () async {
    final source = File('${temp.path}/chapter.txt')..writeAsStringSync('重複');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(projectControllerProvider.notifier);
    await controller.openSourcePath(
      source.path,
      projectRoot: temp,
      machineTranslate: (_) => 'máy',
    );
    controller.setTarget(0, 'đã sửa');
    await controller.applyTmSuggestion(0, 'gợi ý');
    expect(
      container
          .read(projectControllerProvider)
          .document!
          .segments
          .first
          .editedTarget,
      'đã sửa',
    );
  });
}

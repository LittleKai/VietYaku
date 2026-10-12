import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vietyaku/features/project/data/project_store.dart';
import 'package:vietyaku/features/project/domain/project_document.dart';
import 'package:vietyaku/features/project/domain/project_segment.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('vietyaku_project_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('save and open preserve project JSONL and target text', () async {
    final project = ProjectDocument(
      name: 'Chương 1',
      segments: [
        ProjectSegment.fromSource(
          segmentId: 's1',
          source: '彼は言った。',
          machineOutput: 'anh ấy nói.',
          editedTarget: 'Anh ấy nói “được”.',
        ),
      ],
    );
    final store = ProjectStore(temp);

    await store.save(project);
    final restored = await store.open();

    expect(restored.name, 'Chương 1');
    expect(restored.segments.single.editedTarget, 'Anh ấy nói “được”.');
    expect(File('${temp.path}/segments.jsonl').readAsLinesSync(), hasLength(1));
  });

  test('malformed records do not replace an existing project', () async {
    final store = ProjectStore(temp);
    final project = ProjectDocument(name: 'giữ lại', segments: const []);
    await store.save(project);
    File('${temp.path}/segments.jsonl').writeAsStringSync('{bad json\n');

    expect(store.open(), throwsA(isA<ProjectFormatException>()));
    expect(
      File('${temp.path}/project.json').readAsStringSync(),
      contains('giữ lại'),
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vietyaku/features/project/data/translation_memory_store.dart';
import 'package:vietyaku/features/project/domain/project_segment.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('vietyaku_tm_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test(
    'only reviewed segments enter exact TM and latest reviewed wins',
    () async {
      final store = TranslationMemoryStore(temp);
      final draft = ProjectSegment.fromSource(
        segmentId: 's1',
        source: '同じ。',
        machineOutput: 'máy',
        editedTarget: 'bản nháp',
      );
      await store.upsertReviewed(draft);
      expect(await store.lookupExact('同じ。'), isNull);

      final reviewed = draft.copyWith(
        editedTarget: 'bản đã duyệt',
        status: ProjectSegmentStatus.reviewed,
      );
      await store.upsertReviewed(reviewed);
      expect(await store.lookupExact('同じ。'), 'bản đã duyệt');
    },
  );

  test('duplicate source resolves to the newest reviewed target', () async {
    final store = TranslationMemoryStore(temp);
    final first = ProjectSegment.fromSource(
      segmentId: 'a',
      source: '重複',
      machineOutput: '',
      editedTarget: 'một',
      status: ProjectSegmentStatus.reviewed,
    );
    final second = first.copyWith(segmentId: 'b', editedTarget: 'hai');
    await store.upsertReviewed(first);
    await store.upsertReviewed(second);
    expect(await store.lookupExact('重複'), 'hai');
  });
}

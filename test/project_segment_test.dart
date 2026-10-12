import 'package:flutter_test/flutter_test.dart';

import 'package:vietyaku/features/project/domain/project_segment.dart';

void main() {
  test('ProjectSegment serializes reviewed metadata and source hash', () {
    final segment =
        ProjectSegment.fromSource(
          segmentId: 's1',
          source: '彼は走った。',
          machineOutput: 'anh ấy đã chạy.',
          updatedAt: DateTime.utc(2026, 10, 12),
        ).copyWith(
          editedTarget: 'Anh ấy đã chạy.',
          status: ProjectSegmentStatus.reviewed,
        );

    final restored = ProjectSegment.fromJson(segment.toJson());
    expect(restored.segmentId, 's1');
    expect(restored.source, '彼は走った。');
    expect(restored.editedTarget, 'Anh ấy đã chạy.');
    expect(restored.status, ProjectSegmentStatus.reviewed);
    expect(restored.sourceHash, isNotEmpty);
    expect(restored.updatedAt, DateTime.utc(2026, 10, 12));
  });
}

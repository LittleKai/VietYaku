import 'dart:convert';

import '../../../core/fnv_hash.dart';

enum ProjectSegmentStatus { draft, reviewed }

class ProjectSegment {
  const ProjectSegment({
    required this.segmentId,
    required this.source,
    required this.machineOutput,
    required this.editedTarget,
    required this.status,
    required this.updatedAt,
    required this.sourceHash,
  });

  factory ProjectSegment.fromSource({
    required String segmentId,
    required String source,
    required String machineOutput,
    String editedTarget = '',
    ProjectSegmentStatus status = ProjectSegmentStatus.draft,
    DateTime? updatedAt,
  }) {
    final bytes = utf8.encode(source);
    return ProjectSegment(
      segmentId: segmentId,
      source: source,
      machineOutput: machineOutput,
      editedTarget: editedTarget,
      status: status,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      sourceHash: fnv1a64(bytes).toRadixString(16).padLeft(16, '0'),
    );
  }

  factory ProjectSegment.fromJson(Map<String, Object?> json) {
    final status = ProjectSegmentStatus.values.byName(json['status'] as String);
    return ProjectSegment(
      segmentId: json['segmentId'] as String,
      source: json['source'] as String,
      machineOutput: json['machineOutput'] as String,
      editedTarget: json['editedTarget'] as String,
      status: status,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sourceHash: json['sourceHash'] as String,
    );
  }

  final String segmentId;
  final String source;
  final String machineOutput;
  final String editedTarget;
  final ProjectSegmentStatus status;
  final DateTime updatedAt;
  final String sourceHash;

  Map<String, Object?> toJson() => {
    'segmentId': segmentId,
    'source': source,
    'machineOutput': machineOutput,
    'editedTarget': editedTarget,
    'status': status.name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'sourceHash': sourceHash,
  };

  ProjectSegment copyWith({
    String? segmentId,
    String? source,
    String? machineOutput,
    String? editedTarget,
    ProjectSegmentStatus? status,
    DateTime? updatedAt,
  }) => ProjectSegment.fromSource(
    segmentId: segmentId ?? this.segmentId,
    source: source ?? this.source,
    machineOutput: machineOutput ?? this.machineOutput,
    editedTarget: editedTarget ?? this.editedTarget,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

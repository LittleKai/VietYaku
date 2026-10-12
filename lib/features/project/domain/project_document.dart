import 'project_segment.dart';

class ProjectDocument {
  const ProjectDocument({required this.name, required this.segments});

  factory ProjectDocument.fromJson(Map<String, Object?> json) =>
      ProjectDocument(name: json['name'] as String, segments: const []);

  final String name;
  final List<ProjectSegment> segments;

  Map<String, Object?> toJson() => {'version': 1, 'name': name};

  ProjectDocument copyWith({String? name, List<ProjectSegment>? segments}) =>
      ProjectDocument(
        name: name ?? this.name,
        segments: List<ProjectSegment>.unmodifiable(segments ?? this.segments),
      );
}

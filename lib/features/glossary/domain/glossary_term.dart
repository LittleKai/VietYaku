/// Một mục từ trong file `Global Glossary.json` của AI_Translation_Bridge.
///
/// Thứ tự field khi ghi phải khớp `GlossaryManager._normalize_term` bên Python
/// (source, target, kind, notes, created_by, date_added) để diff file sạch.
class GlossaryTerm {
  final String source;
  final String target;
  final String kind;
  final String notes;
  final String createdBy;
  final String dateAdded;

  const GlossaryTerm({
    required this.source,
    required this.target,
    this.kind = 'proper_noun',
    this.notes = '',
    this.createdBy = 'user',
    required this.dateAdded,
  });

  factory GlossaryTerm.fromJson(Map<String, dynamic> json) => GlossaryTerm(
    source: (json['source'] ?? '').toString(),
    target: (json['target'] ?? '').toString(),
    kind: (json['kind'] ?? 'proper_noun').toString(),
    notes: (json['notes'] ?? '').toString(),
    createdBy: (json['created_by'] ?? 'user').toString(),
    dateAdded: (json['date_added'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {
    'source': source,
    'target': target,
    'kind': kind,
    'notes': notes,
    'created_by': createdBy,
    'date_added': dateAdded,
  };

  GlossaryTerm copyWith({String? target, String? createdBy}) => GlossaryTerm(
    source: source,
    target: target ?? this.target,
    kind: kind,
    notes: notes,
    createdBy: createdBy ?? this.createdBy,
    dateAdded: dateAdded,
  );
}

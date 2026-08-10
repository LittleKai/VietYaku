enum SharedDictionaryKind { vietPhrase, lacViet }

enum EntryOperation { upsert, delete }

class SharedDictionaryEntry {
  final SharedDictionaryKind kind;
  final String source;
  final String target;
  final int revision;
  final EntryOperation operation;

  const SharedDictionaryEntry({
    required this.kind,
    required this.source,
    this.target = '',
    this.revision = 0,
    this.operation = EntryOperation.upsert,
  });

  bool get isDelete => operation == EntryOperation.delete;

  factory SharedDictionaryEntry.fromJson(Map<String, dynamic> json) {
    final op = json['operation'] as String?;
    return SharedDictionaryEntry(
      kind: SharedDictionaryKind.values.byName(json['kind'] as String),
      source: json['source'] as String,
      target: json['target'] as String? ?? '',
      revision: json['revision'] as int? ?? 0,
      operation: op == 'delete' ? EntryOperation.delete : EntryOperation.upsert,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'source': source,
    if (!isDelete) 'target': target,
    if (isDelete) 'operation': 'delete',
  };
}

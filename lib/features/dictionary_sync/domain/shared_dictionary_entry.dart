enum SharedDictionaryKind { vietPhrase, lacViet }

class SharedDictionaryEntry {
  final SharedDictionaryKind kind;
  final String source;
  final String target;
  final int revision;

  const SharedDictionaryEntry({
    required this.kind,
    required this.source,
    required this.target,
    this.revision = 0,
  });

  factory SharedDictionaryEntry.fromJson(Map<String, dynamic> json) {
    return SharedDictionaryEntry(
      kind: SharedDictionaryKind.values.byName(json['kind'] as String),
      source: json['source'] as String,
      target: json['target'] as String,
      revision: json['revision'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'source': source,
    'target': target,
  };
}

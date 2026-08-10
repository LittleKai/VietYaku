import '../../dictionary/domain/dict_type.dart';

enum DictionarySearchMode { exactKey, prefixKey, wildcardKey, fullTextValue }

class DictionarySearchLayer {
  final String id;
  final String label;
  final DictType type;
  final Map<String, String> entries;

  const DictionarySearchLayer({
    required this.id,
    required this.label,
    required this.type,
    required this.entries,
  });
}

class DictionarySearchQuery {
  final String text;
  final DictionarySearchMode mode;
  final Set<DictType> dictionaryTypes;
  final int limit;

  const DictionarySearchQuery({
    required this.text,
    required this.mode,
    this.dictionaryTypes = const {},
    this.limit = 300,
  });

  @override
  bool operator ==(Object other) =>
      other is DictionarySearchQuery &&
      other.text == text &&
      other.mode == mode &&
      _sameTypes(other.dictionaryTypes, dictionaryTypes) &&
      other.limit == limit;

  @override
  int get hashCode =>
      Object.hash(text, mode, Object.hashAllUnordered(dictionaryTypes), limit);
}

class DictionarySearchResult {
  final String key;
  final String value;
  final DictType dictionaryType;
  final String layerId;
  final String layerLabel;
  final bool isWinningLayer;

  const DictionarySearchResult({
    required this.key,
    required this.value,
    required this.dictionaryType,
    required this.layerId,
    required this.layerLabel,
    required this.isWinningLayer,
  });
}

class DictionarySearchResponse {
  final List<DictionarySearchResult> results;
  final int totalMatches;

  const DictionarySearchResponse({
    required this.results,
    required this.totalMatches,
  });

  bool get isTruncated => totalMatches > results.length;
}

DictionarySearchResponse searchDictionaryLayers(
  List<DictionarySearchLayer> layers,
  DictionarySearchQuery query,
) {
  final needle = query.text.trim();
  if (needle.isEmpty) {
    return const DictionarySearchResponse(results: [], totalMatches: 0);
  }

  final normalizedNeedle = needle.toLowerCase();
  final wildcard = query.mode == DictionarySearchMode.wildcardKey
      ? _compileWildcard(needle)
      : null;
  final results = <DictionarySearchResult>[];
  var totalMatches = 0;

  for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
    final layer = layers[layerIndex];
    if (query.dictionaryTypes.isNotEmpty &&
        !query.dictionaryTypes.contains(layer.type)) {
      continue;
    }
    for (final entry in layer.entries.entries) {
      final matches = switch (query.mode) {
        DictionarySearchMode.exactKey => entry.key == needle,
        DictionarySearchMode.prefixKey => entry.key.startsWith(needle),
        DictionarySearchMode.wildcardKey => wildcard!.hasMatch(entry.key),
        DictionarySearchMode.fullTextValue =>
          entry.value.toLowerCase().contains(normalizedNeedle),
      };
      if (!matches) continue;
      totalMatches++;
      if (results.length >= query.limit) continue;
      results.add(
        DictionarySearchResult(
          key: entry.key,
          value: entry.value,
          dictionaryType: layer.type,
          layerId: layer.id,
          layerLabel: layer.label,
          isWinningLayer: !_hasHigherLayerWithKey(
            layers,
            layerIndex,
            layer.type,
            entry.key,
          ),
        ),
      );
    }
  }

  return DictionarySearchResponse(results: results, totalMatches: totalMatches);
}

bool _hasHigherLayerWithKey(
  List<DictionarySearchLayer> layers,
  int layerIndex,
  DictType type,
  String key,
) {
  for (var i = 0; i < layerIndex; i++) {
    final higher = layers[i];
    if (higher.type == type && higher.entries.containsKey(key)) return true;
  }
  return false;
}

RegExp _compileWildcard(String pattern) {
  final buffer = StringBuffer('^');
  var literalStart = 0;
  for (var i = 0; i < pattern.length; i++) {
    final unit = pattern.codeUnitAt(i);
    if (unit != 0x2A && unit != 0x3F) continue;
    if (literalStart < i) {
      buffer.write(RegExp.escape(pattern.substring(literalStart, i)));
    }
    buffer.write(unit == 0x2A ? '.*' : '.');
    literalStart = i + 1;
  }
  if (literalStart < pattern.length) {
    buffer.write(RegExp.escape(pattern.substring(literalStart)));
  }
  buffer.write(r'$');
  return RegExp(buffer.toString(), dotAll: true);
}

bool _sameTypes(Set<DictType> a, Set<DictType> b) =>
    a.length == b.length && a.containsAll(b);

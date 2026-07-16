/// Bảng convert giản thể/kyūjitai → kanji Nhật đúng.
///
/// Nguồn: assets/mappings/simp2jp.tsv (sinh bởi tool/build_simp2jp.dart)
/// + simp2jp_overrides.tsv (soạn tay, override thắng).
/// Dòng tsv `simp\tjp`; nhiều candidate `simp\tc1|c2` = ambiguous
/// (không convert, ghi vào RepairReport.ambiguous).
class Simp2JpTable {
  /// simp → jp (1 candidate duy nhất, convert được).
  final Map<String, String> resolved;

  /// simp → các candidate (không tự quyết được).
  final Map<String, List<String>> ambiguous;

  const Simp2JpTable({required this.resolved, required this.ambiguous});

  factory Simp2JpTable.parse(String tsv, {String overridesTsv = ''}) {
    final resolved = <String, String>{};
    final ambiguous = <String, List<String>>{};

    void addLine(String line, {required bool isOverride}) {
      if (line.isEmpty || line.startsWith('#')) return;
      final tab = line.indexOf('\t');
      if (tab <= 0) return;
      final key = line.substring(0, tab).trim();
      final value = line.substring(tab + 1).trim();
      if (key.isEmpty || value.isEmpty) return;
      final candidates = value.split('|');
      if (candidates.length == 1 || isOverride) {
        resolved[key] = candidates.first;
        ambiguous.remove(key);
      } else if (!resolved.containsKey(key)) {
        ambiguous[key] = candidates;
      }
    }

    for (final line in tsv.split('\n')) {
      addLine(line.trimRight(), isOverride: false);
    }
    for (final line in overridesTsv.split('\n')) {
      addLine(line.trimRight(), isOverride: true);
    }
    return Simp2JpTable(resolved: resolved, ambiguous: ambiguous);
  }

  String? convert(String char) => resolved[char];

  bool isAmbiguous(String char) => ambiguous.containsKey(char);
}

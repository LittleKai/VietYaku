/// Một ứng viên từ dạng biến hình về dạng từ điển.
class JapaneseDeinflectionCandidate {
  JapaneseDeinflectionCandidate({
    required this.surface,
    required this.lemma,
    required Iterable<String> rules,
  }) : surfaceLength = surface.length,
       rules = List.unmodifiable(rules);

  final String surface;
  final String lemma;
  final int surfaceLength;
  final List<String> rules;
}

/// Bộ luật nhỏ, có chủ đích, cho fallback tra từ Nhật.
///
/// Đây là candidate generator, không đoán nghĩa hay chèn ngữ pháp tiếng Việt.
class JapaneseDeinflector {
  const JapaneseDeinflector();

  static const int maxCandidates = 24;

  static List<JapaneseDeinflectionCandidate> deinflect(String surface) {
    if (surface.isEmpty) return const [];
    final candidates = <JapaneseDeinflectionCandidate>[];
    final seen = <String>{};

    void add(String lemma, String rule) {
      if (lemma.isEmpty || lemma == surface || !seen.add('$lemma\u0000$rule')) {
        return;
      }
      candidates.add(
        JapaneseDeinflectionCandidate(
          surface: surface,
          lemma: lemma,
          rules: [rule],
        ),
      );
    }

    void addSuffix(String suffix, String replacement, String rule) {
      if (!surface.endsWith(suffix)) return;
      add(
        '${surface.substring(0, surface.length - suffix.length)}$replacement',
        rule,
      );
    }

    // た/て dạng ichidan và các biến âm godan thông dụng.
    addSuffix('た', 'る', 'past-ta');
    addSuffix('て', 'る', 'te-form');
    addSuffix('んだ', 'む', 'past-ta-nasal');
    addSuffix('んで', 'む', 'te-form-nasal');
    addSuffix('いた', 'く', 'past-ta-kana');
    addSuffix('いて', 'く', 'te-form-kana');
    addSuffix('いだ', 'ぐ', 'past-ta-gi');
    addSuffix('いで', 'ぐ', 'te-form-gi');
    addSuffix('した', 'す', 'past-ta-s');
    addSuffix('して', 'す', 'te-form-s');

    // 行く là ngoại lệ của いった/いって.
    if (surface == '行った' || surface == '行って') {
      add('行く', 'past-ta-kana');
    }

    // ない: bảng đổi âm a-row về âm cuối từ điển.
    const negative = <String, String>{
      'かない': 'く',
      'がない': 'ぐ',
      'さない': 'す',
      'たない': 'つ',
      'なない': 'ぬ',
      'ばない': 'ぶ',
      'まない': 'む',
      'らない': 'る',
      'わない': 'う',
      'ない': 'る',
    };
    for (final entry in negative.entries) {
      addSuffix(entry.key, entry.value, 'negative-nai');
    }

    // Bị động: 読まれた → 読む, 食べられた → 食べる.
    addSuffix('られた', 'る', 'passive');
    const passiveGodan = <String, String>{
      'かれた': 'く',
      'がれた': 'ぐ',
      'された': 'す',
      'たれた': 'つ',
      'なれた': 'ぬ',
      'ばれた': 'ぶ',
      'まれた': 'む',
      'られた': 'る',
      'われた': 'う',
    };
    for (final entry in passiveGodan.entries) {
      addSuffix(entry.key, entry.value, 'passive');
    }

    // Sai khiến: 読ませた → 読む, 食べさせた → 食べる.
    addSuffix('させた', 'る', 'causative');
    const causativeGodan = <String, String>{
      'かせた': 'く',
      'がせた': 'ぐ',
      'させた': 'す',
      'たせた': 'つ',
      'なせた': 'ぬ',
      'ばせた': 'ぶ',
      'ませた': 'む',
      'らせた': 'る',
      'わせた': 'う',
    };
    for (final entry in causativeGodan.entries) {
      addSuffix(entry.key, entry.value, 'causative');
    }

    if (candidates.length > maxCandidates) {
      return candidates.take(maxCandidates).toList(growable: false);
    }
    return candidates;
  }
}

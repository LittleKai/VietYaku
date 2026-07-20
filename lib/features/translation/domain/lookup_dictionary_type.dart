enum LookupDictionaryType {
  userDict('UserDict'),
  names('Names'),
  vietPhrase('VietPhrase'),
  lacViet('Lạc Việt'),
  jaVi('Nhật Việt'),
  cedictBabylon('Cedict / Babylon'),
  thieuChuu('Thiều Chửu'),
  zhVi('Trung Việt'),
  phonetic('Phiên âm');

  const LookupDictionaryType(this.label);

  final String label;

  bool matchesLabel(String value) => switch (this) {
    LookupDictionaryType.cedictBabylon =>
      value == 'Cedict' || value == 'Babylon',
    LookupDictionaryType.phonetic => value.startsWith('Phiên Âm'),
    _ => value == label,
  };
}

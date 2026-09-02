enum LookupDictionaryType {
  userDict('UserDict'),
  names('Names'),
  vietPhrase('VietPhrase'),
  lacViet('Lạc Việt'),
  mazii('Mazii'),
  jaVi('Nhật Việt'),
  cedictBabylon('Cedict / Babylon'),
  thieuChuu('Thiều Chửu'),
  zhVi('Trung Việt'),
  phonetic('Phiên âm'),
  online('Online'),
  ai('AI Dịch'),
  aiEntries('AI tách từ');

  const LookupDictionaryType(this.label);

  final String label;

  bool matchesLabel(String value) => switch (this) {
    LookupDictionaryType.cedictBabylon =>
      value == 'Cedict' || value == 'Babylon',
    LookupDictionaryType.phonetic => value.startsWith('Phiên Âm'),
    LookupDictionaryType.online =>
      value == 'Mazii Online' ||
          value == 'Jisho' ||
          value == 'Weblio 日中' ||
          value == 'Youdao 中英' ||
          value == 'Google Dịch' ||
          value == 'Online',
    LookupDictionaryType.ai => value == 'AI Dịch' || value == 'AI Tra Cứu',
    _ => value == label,
  };

  /// Thứ tự hiển thị mặc định trong ô Nghĩa — khớp đúng thứ tự
  /// `LookupController.lookup()` sinh section, để bật mặc định thì bố cục y
  /// như trước khi có tuỳ chọn sắp xếp.
  static const defaultPanelOrder = <LookupDictionaryType>[
    LookupDictionaryType.userDict,
    LookupDictionaryType.names,
    LookupDictionaryType.vietPhrase,
    LookupDictionaryType.lacViet,
    LookupDictionaryType.mazii,
    LookupDictionaryType.jaVi,
    LookupDictionaryType.cedictBabylon,
    LookupDictionaryType.thieuChuu,
    LookupDictionaryType.zhVi,
    LookupDictionaryType.online,
    LookupDictionaryType.ai,
    LookupDictionaryType.aiEntries,
    LookupDictionaryType.phonetic,
  ];
}

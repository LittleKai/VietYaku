import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

enum EpubOutputFormat {
  csv('CSV', 'csv'),
  xlsx('Excel', 'xlsx'),
  markdown('Markdown', 'md'),
  docx('Word', 'docx'),
  txt('Văn bản', 'txt');

  const EpubOutputFormat(this.label, this.extension);

  final String label;
  final String extension;
}

enum EpubLanguage {
  japanese('JP', 'Tiếng Nhật'),
  chinese('CN', 'Tiếng Trung'),
  korean('KR', 'Tiếng Hàn'),
  vietnamese('VI', 'Tiếng Việt'),
  english('EN', 'Tiếng Anh');

  const EpubLanguage(this.code, this.label);

  final String code;
  final String label;
}

enum EpubRubyHandling {
  keepAll('Giữ tất cả furigana'),
  removeAll('Bỏ tất cả furigana'),
  removeHiragana('Chỉ bỏ furigana Hiragana');

  const EpubRubyHandling(this.label);

  final String label;
}

class EpubChapter {
  const EpubChapter({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

class EpubBook {
  const EpubBook({
    required this.title,
    required this.language,
    required this.chapters,
  });

  final String title;
  final EpubLanguage language;
  final List<EpubChapter> chapters;

  List<String> get translationRows => [
    for (final chapter in chapters) ...[
      if (chapter.title.isNotEmpty) chapter.title,
      ...chapter.paragraphs,
    ],
  ];
}

class EpubParseRequest {
  const EpubParseRequest({
    required this.bytes,
    this.rubyHandling = EpubRubyHandling.removeHiragana,
  });

  final Uint8List bytes;
  final EpubRubyHandling rubyHandling;
}

class EpubExportRequest {
  const EpubExportRequest({required this.book, required this.format});

  final EpubBook book;
  final EpubOutputFormat format;
}

/// Entry-point có thể truyền thẳng cho `compute`, không capture Widget State.
EpubBook parseEpubRequest(EpubParseRequest request) =>
    parseEpub(request.bytes, rubyHandling: request.rubyHandling);

/// Entry-point có thể truyền thẳng cho `compute`, không capture Widget State.
Uint8List exportEpubRequest(EpubExportRequest request) =>
    exportEpubBook(request.book, request.format);

EpubBook parseEpub(
  Uint8List bytes, {
  EpubRubyHandling rubyHandling = EpubRubyHandling.removeHiragana,
}) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final files = <String, ArchiveFile>{
    for (final file in archive.files)
      if (file.isFile) _normalizePath(file.name): file,
  };
  final container = files['META-INF/container.xml'];
  if (container == null) {
    throw const FormatException('EPUB không có META-INF/container.xml.');
  }

  final containerXml = XmlDocument.parse(_decode(container.content));
  final rootFile = _elements(containerXml, 'rootfile').firstOrNull;
  final opfPath = rootFile?.getAttribute('full-path');
  if (opfPath == null || opfPath.trim().isEmpty) {
    throw const FormatException('Không tìm thấy package OPF trong EPUB.');
  }
  final normalizedOpf = _normalizePath(Uri.decodeComponent(opfPath));
  final opf = files[normalizedOpf];
  if (opf == null) {
    throw FormatException('Không đọc được package OPF: $normalizedOpf');
  }

  final opfXml = XmlDocument.parse(_decode(opf.content));
  final title = _elements(opfXml, 'title')
      .map((element) => element.innerText.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => 'EPUB');
  final manifest = <String, String>{};
  for (final item in _elements(opfXml, 'item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id == null || href == null) continue;
    manifest[id] = _resolveArchivePath(normalizedOpf, href);
  }
  final spine = <String>[];
  for (final itemRef in _elements(opfXml, 'itemref')) {
    final href = manifest[itemRef.getAttribute('idref')];
    if (href != null && _isHtml(href)) spine.add(href);
  }
  if (spine.isEmpty) {
    spine.addAll(files.keys.where(_isHtml).toList()..sort());
  }

  final chapterSources = <({String html, String path})>[];
  for (final path in spine) {
    final file = files[path] ?? _findByBasename(files, path);
    if (file == null) continue;
    chapterSources.add((html: _decode(file.content), path: path));
  }
  final language = detectEpubLanguage(_sampleChapterText(chapterSources));
  final chapters = <EpubChapter>[];
  for (final source in chapterSources) {
    final chapter = _extractChapter(
      source.html,
      source.path,
      language == EpubLanguage.japanese ? rubyHandling : null,
    );
    if (chapter.title.isNotEmpty || chapter.paragraphs.isNotEmpty) {
      chapters.add(chapter);
    }
  }
  if (chapters.isEmpty) {
    throw const FormatException('EPUB không có nội dung văn bản có thể xuất.');
  }
  return EpubBook(title: title, language: language, chapters: chapters);
}

Uint8List exportEpubBook(EpubBook book, EpubOutputFormat format) =>
    switch (format) {
      EpubOutputFormat.csv => _textBytes(_toCsv(book), withBom: true),
      EpubOutputFormat.xlsx => _toXlsx(book),
      EpubOutputFormat.markdown => _textBytes(_toMarkdown(book)),
      EpubOutputFormat.docx => _toDocx(book),
      EpubOutputFormat.txt => _textBytes(_toText(book)),
    };

Iterable<XmlElement> _elements(XmlNode node, String localName) => node
    .descendants
    .whereType<XmlElement>()
    .where((element) => element.name.local == localName);

String _decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

String _normalizePath(String value) => p.posix.normalize(
  value.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), ''),
);

String _resolveArchivePath(String opfPath, String href) {
  final clean = Uri.decodeComponent(href.split('#').first.split('?').first);
  return _normalizePath(p.posix.join(p.posix.dirname(opfPath), clean));
}

bool _isHtml(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.html') ||
      lower.endsWith('.xhtml') ||
      lower.endsWith('.htm');
}

ArchiveFile? _findByBasename(Map<String, ArchiveFile> files, String path) {
  final name = p.posix.basename(path).toLowerCase();
  for (final entry in files.entries) {
    if (p.posix.basename(entry.key).toLowerCase() == name) return entry.value;
  }
  return null;
}

String _sampleChapterText(
  List<({String html, String path})> chapters, {
  int maxChars = 500,
}) {
  if (chapters.isEmpty) return '';
  final buffer = StringBuffer();
  final start = chapters.length ~/ 3;
  for (final chapter in chapters.skip(start).take(5)) {
    final text = html_parser
        .parse(chapter.html, generateSpans: false)
        .body
        ?.text;
    if (text != null) buffer.write(text);
    if (buffer.length >= maxChars) break;
  }
  final sample = buffer.toString();
  return sample.length <= maxChars ? sample : sample.substring(0, maxChars);
}

/// Nhận diện ngôn ngữ theo cùng ngưỡng Unicode của AI Translation Bridge.
EpubLanguage detectEpubLanguage(String text) {
  if (text.isEmpty) return EpubLanguage.english;
  final runes = text.runes.toList(growable: false);
  final total = runes.length;
  var hiragana = 0;
  var katakana = 0;
  var hangul = 0;
  var cjk = 0;
  var vietnamese = 0;
  const vietnameseMarkers = 'ăâđêôơưĂÂĐÊÔƠƯ';
  for (final rune in runes) {
    if (rune >= 0x3040 && rune <= 0x309F) hiragana++;
    if (rune >= 0x30A0 && rune <= 0x30FF) katakana++;
    if (rune >= 0xAC00 && rune <= 0xD7AF) hangul++;
    if (rune >= 0x4E00 && rune <= 0x9FFF) cjk++;
    if (vietnameseMarkers.runes.contains(rune)) vietnamese++;
  }
  if ((hiragana + katakana) / total > 0.01) {
    return EpubLanguage.japanese;
  }
  if (hangul / total > 0.01) return EpubLanguage.korean;
  if (cjk / total > 0.05) return EpubLanguage.chinese;
  if (vietnamese / total > 0.005) return EpubLanguage.vietnamese;
  return EpubLanguage.english;
}

EpubChapter _extractChapter(
  String html,
  String path,
  EpubRubyHandling? rubyHandling,
) {
  final document = html_parser.parse(html, generateSpans: false);
  document.querySelectorAll('script,style,svg,noscript').forEach((node) {
    node.remove();
  });
  if (rubyHandling != null) {
    _processRubyTags(document, rubyHandling);
  }
  final blocks = document.querySelectorAll(
    'h1,h2,h3,h4,h5,h6,p,li,blockquote,figcaption',
  );
  final lines = <String>[];
  String? heading;
  for (final block in blocks) {
    final text = _cleanText(
      rubyHandling == null ? block.text : _mergeConsecutiveRuby(block.text),
    );
    if (text.isEmpty) continue;
    if (heading == null && _isHeading(block)) {
      heading = text;
    } else if (!lines.contains(text) || lines.lastOrNull != text) {
      lines.add(text);
    }
  }
  if (lines.isEmpty) {
    lines.addAll(
      (document.body?.text ?? '')
          .split(RegExp(r'[\r\n]+'))
          .map(_cleanText)
          .where((line) => line.isNotEmpty),
    );
  }
  return EpubChapter(
    title: heading ?? p.posix.basenameWithoutExtension(path),
    paragraphs: List.unmodifiable(lines),
  );
}

void _processRubyTags(dom.Document document, EpubRubyHandling handling) {
  for (final ruby in document.querySelectorAll('ruby')) {
    final readings = ruby
        .querySelectorAll('rt')
        .map((node) => node.text.trim())
        .where((text) => text.isNotEmpty)
        .join();
    ruby.querySelectorAll('rt,rp').forEach((node) => node.remove());
    final base = ruby.text.trim();
    final replacement = switch (handling) {
      EpubRubyHandling.removeAll => base,
      EpubRubyHandling.removeHiragana =>
        readings.isEmpty || _isHiragana(readings) ? base : '$base($readings)',
      EpubRubyHandling.keepAll => readings.isEmpty ? base : '$base($readings)',
    };
    ruby.replaceWith(dom.Text(replacement));
  }
}

bool _isHiragana(String text) => RegExp(r'^[\u3040-\u309F]+$').hasMatch(text);

String _mergeConsecutiveRuby(String text) {
  return text.replaceAllMapped(RegExp(r'(?:[^\(]+\([^\)]+\)){2,}'), (match) {
    final pairs = RegExp(r'([^\(]+)\(([^\)]+)\)').allMatches(match.group(0)!);
    if (pairs.length < 2) return match.group(0)!;
    final base = pairs.map((pair) => pair.group(1)!).join();
    final reading = pairs.map((pair) => pair.group(2)!).join();
    return '$base($reading)';
  });
}

bool _isHeading(dom.Element element) =>
    RegExp(r'^h[1-6]$').hasMatch(element.localName ?? '');

String _cleanText(String value) => value
    .replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\uFEFF]'), '')
    .replaceAll(RegExp(r'[ \t\u00A0]+'), ' ')
    .replaceAll(RegExp(r'\s*\n\s*'), '\n')
    .trim();

Uint8List _textBytes(String value, {bool withBom = false}) =>
    Uint8List.fromList([
      if (withBom) ...const [0xEF, 0xBB, 0xBF],
      ...utf8.encode(value),
    ]);

String _toCsv(EpubBook book) {
  final buffer = StringBuffer('id,text\r\n');
  final rows = book.translationRows;
  for (var index = 0; index < rows.length; index++) {
    buffer
      ..write(index + 1)
      ..write(',')
      ..write(_csvCell(rows[index]))
      ..write('\r\n');
  }
  return buffer.toString();
}

String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

String _toMarkdown(EpubBook book) {
  final buffer = StringBuffer('# ${book.title}\n');
  for (final chapter in book.chapters) {
    buffer.write('\n## ${chapter.title}\n\n');
    for (final paragraph in chapter.paragraphs) {
      buffer.write('$paragraph\n\n');
    }
  }
  return '${buffer.toString().trimRight()}\n';
}

String _toText(EpubBook book) {
  final buffer = StringBuffer('${book.title}\n');
  for (final chapter in book.chapters) {
    buffer.write('\n${chapter.title}\n\n');
    buffer.write(chapter.paragraphs.join('\n\n'));
    buffer.write('\n');
  }
  return '${buffer.toString().trimRight()}\n';
}

Uint8List _toXlsx(EpubBook book) {
  final rows = <(String, String)>[
    ('id', 'text'),
    for (var i = 0; i < book.translationRows.length; i++)
      ('${i + 1}', book.translationRows[i]),
  ];
  final sheet = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<sheetViews><sheetView workbookViewId="0">'
    '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
    '</sheetView></sheetViews>'
    '<cols><col min="1" max="1" width="10" customWidth="1"/>'
    '<col min="2" max="2" width="80" customWidth="1"/></cols><sheetData>',
  );
  for (var index = 0; index < rows.length; index++) {
    final row = index + 1;
    final style = index == 0 ? ' s="1"' : '';
    sheet
      ..write('<row r="$row">')
      ..write(
        '<c r="A$row" t="inlineStr"$style><is><t>${_xml(rows[index].$1)}</t></is></c>',
      )
      ..write(
        '<c r="B$row" t="inlineStr"$style><is><t xml:space="preserve">${_xml(rows[index].$2)}</t></is></c>',
      )
      ..write('</row>');
  }
  sheet.write('</sheetData><autoFilter ref="A1:B1"/></worksheet>');
  return _zip({
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Nội dung" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF1565C0"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>'
        '</styleSheet>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  });
}

Uint8List _toDocx(EpubBook book) {
  final body = StringBuffer();
  void paragraph(String text, {String? style}) {
    body
      ..write('<w:p>')
      ..write(style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>')
      ..write('<w:r><w:t xml:space="preserve">${_xml(text)}</w:t></w:r></w:p>');
  }

  paragraph(book.title, style: 'Title');
  for (final chapter in book.chapters) {
    paragraph(chapter.title, style: 'Heading1');
    for (final text in chapter.paragraphs) {
      paragraph(text);
    }
  }
  return _zip({
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>',
    'word/document.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr>'
        '</w:body></w:document>',
    'word/_rels/document.xml.rels':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'word/styles.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>'
        '<w:rPr><w:rFonts w:ascii="Aptos" w:hAnsi="Aptos"/><w:sz w:val="22"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/>'
        '<w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="240"/></w:pPr>'
        '<w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>'
        '<w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/></w:pPr>'
        '<w:rPr><w:b/><w:color w:val="1565C0"/><w:sz w:val="28"/></w:rPr></w:style>'
        '</w:styles>',
  });
}

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

String _xml(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}

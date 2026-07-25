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

/// Ảnh trích từ EPUB, giữ nguyên bytes để nhúng thật vào DOCX.
class EpubImage {
  const EpubImage({
    required this.id,
    required this.extension,
    required this.bytes,
  });

  final String id; // duy nhất trong sách, vd 'img1'
  final String extension; // 'png' | 'jpeg' | 'gif' | 'bmp'
  final Uint8List bytes;
}

class EpubChapter {
  const EpubChapter({required this.title, required this.paragraphs});

  final String title;

  /// Văn bản đoạn; vị trí ảnh giữ bằng token `⟦img:ID⟧` (resolve được) hoặc
  /// literal `(img)` (không resolve được). Text exporter hiển thị qua `_toDisplay`.
  final List<String> paragraphs;
}

class EpubBook {
  const EpubBook({
    required this.title,
    required this.language,
    required this.chapters,
    this.images = const {},
  });

  final String title;
  final EpubLanguage language;
  final List<EpubChapter> chapters;
  final Map<String, EpubImage> images; // id → ảnh

  List<String> get translationRows => [
    for (final chapter in chapters) ...[
      if (chapter.title.isNotEmpty) _toDisplay(chapter.title),
      for (final paragraph in chapter.paragraphs) _toDisplay(paragraph),
    ],
  ];
}

final RegExp _imgTokenRe = RegExp(r'⟦img:([^⟧]+)⟧');

/// Chuyển token ảnh về placeholder `(img)` cho các định dạng text.
String _toDisplay(String text) => text.replaceAll(_imgTokenRe, '(img)');

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
    chapterSources.add((
      html: _decode(file.content),
      path: _normalizePath(file.name),
    ));
  }
  final language = detectEpubLanguage(
    _sampleChapterText([for (final source in chapterSources) source.html]),
  );
  final images = _ImageCollector(files);
  final chapters = <EpubChapter>[];
  for (final source in chapterSources) {
    final chapter = _extractChapter(
      source.html,
      source.path,
      language == EpubLanguage.japanese ? rubyHandling : null,
      images,
    );
    if (chapter.title.isNotEmpty || chapter.paragraphs.isNotEmpty) {
      chapters.add(chapter);
    }
  }
  if (chapters.isEmpty) {
    throw const FormatException('EPUB không có nội dung văn bản có thể xuất.');
  }
  return EpubBook(
    title: title,
    language: language,
    chapters: chapters,
    images: images.images,
  );
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

/// Thu thập ảnh trong lúc parse: resolve `<img src>` → bytes trong zip, đánh id
/// duy nhất `imgN`, dedupe theo đường dẫn (một ảnh dùng nhiều lần → một part).
class _ImageCollector {
  _ImageCollector(this.files);

  final Map<String, ArchiveFile> files;
  final Map<String, EpubImage> _byKey = {}; // đường dẫn zip → ảnh (dedupe)
  final Map<String, EpubImage> images = {}; // id → ảnh (giữ thứ tự chèn)
  int _counter = 0;

  /// Trả id ảnh, hoặc null nếu không resolve được ra ảnh raster hỗ trợ.
  String? register(String chapterPath, String src) {
    final resolved = _resolveArchivePath(chapterPath, src);
    final file = files[resolved] ?? _findByBasename(files, resolved);
    if (file == null) return null;
    final key = _normalizePath(file.name);
    final existing = _byKey[key];
    if (existing != null) return existing.id;
    final content = file.content as List<int>;
    final ext = _imageExtension(file.name, content);
    if (ext == null) return null;
    final image = EpubImage(
      id: 'img${++_counter}',
      extension: ext,
      bytes: Uint8List.fromList(content),
    );
    _byKey[key] = image;
    images[image.id] = image;
    return image.id;
  }
}

/// Xác định phần mở rộng chuẩn hóa cho ảnh raster; null nếu không hỗ trợ.
String? _imageExtension(String name, List<int> bytes) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpeg';
  if (lower.endsWith('.gif')) return 'gif';
  if (lower.endsWith('.bmp')) return 'bmp';
  if (bytes.length >= 4) {
    if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'png';
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpeg';
    if (bytes[0] == 0x47 && bytes[1] == 0x49) return 'gif';
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return 'bmp';
  }
  return null;
}

String _imageContentType(String extension) => switch (extension) {
  'png' => 'image/png',
  'jpeg' => 'image/jpeg',
  'gif' => 'image/gif',
  'bmp' => 'image/bmp',
  _ => 'application/octet-stream',
};

/// Kích thước pixel đọc từ header ảnh; null nếu không đọc được.
({int width, int height})? _imageSizePx(List<int> b, String extension) {
  try {
    switch (extension) {
      case 'png':
        if (b.length < 24) return null;
        return (width: _be32(b, 16), height: _be32(b, 20));
      case 'gif':
        if (b.length < 10) return null;
        return (width: b[6] | b[7] << 8, height: b[8] | b[9] << 8);
      case 'bmp':
        if (b.length < 26) return null;
        return (width: _le32(b, 18), height: _le32(b, 22).abs());
      case 'jpeg':
        return _jpegSizePx(b);
    }
  } catch (_) {}
  return null;
}

({int width, int height})? _jpegSizePx(List<int> b) {
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    final isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      return (width: b[i + 7] << 8 | b[i + 8], height: b[i + 5] << 8 | b[i + 6]);
    }
    final length = b[i + 2] << 8 | b[i + 3];
    if (length < 2) return null;
    i += 2 + length;
  }
  return null;
}

int _be32(List<int> b, int o) =>
    b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];

int _le32(List<int> b, int o) =>
    b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24;

const int _emuPerPx = 9525; // 96 dpi
const int _maxWidthEmu = 5486400; // 6 inch — vừa lề trang A4

/// EMU (cx, cy) cho ảnh, co theo tỉ lệ nếu rộng quá khổ trang.
({int cx, int cy}) _imageExtentEmu(({int width, int height})? size) {
  if (size == null || size.width <= 0 || size.height <= 0) {
    return (cx: _maxWidthEmu, cy: (_maxWidthEmu * 0.75).round());
  }
  var cx = size.width * _emuPerPx;
  var cy = size.height * _emuPerPx;
  if (cx > _maxWidthEmu) {
    cy = (cy * _maxWidthEmu / cx).round();
    cx = _maxWidthEmu;
  }
  return (cx: cx, cy: cy);
}

String _sampleChapterText(List<String> chapters, {int maxChars = 500}) {
  if (chapters.isEmpty) return '';
  final buffer = StringBuffer();
  final start = chapters.length ~/ 3;
  for (final chapter in chapters.skip(start).take(5)) {
    final text = html_parser
        .parse(chapter, generateSpans: false)
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
  String chapterPath,
  EpubRubyHandling? rubyHandling,
  _ImageCollector images,
) {
  final document = html_parser.parse(html, generateSpans: false);
  document.querySelectorAll('script,style,svg,noscript').forEach((node) {
    node.remove();
  });
  // Giữ vị trí ảnh: token `⟦img:ID⟧` nếu resolve được bytes (để nhúng thật vào
  // DOCX), ngược lại literal `(img)` như AI Translation Bridge (svg đã xóa ở trên).
  for (final img in document.querySelectorAll('img')) {
    final src = img.attributes['src'] ?? img.attributes['xlink:href'] ?? '';
    final id = src.isEmpty ? null : images.register(chapterPath, src);
    img.replaceWith(dom.Text(id == null ? '(img)' : '⟦img:$id⟧'));
  }
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
    title: heading ?? '',
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
    if (chapter.title.isNotEmpty) {
      buffer.write('\n## ${_toDisplay(chapter.title)}\n');
    }
    buffer.write('\n');
    for (final paragraph in chapter.paragraphs) {
      buffer.write('${_toDisplay(paragraph)}\n\n');
    }
  }
  return '${buffer.toString().trimRight()}\n';
}

String _toText(EpubBook book) {
  final buffer = StringBuffer('${book.title}\n');
  for (final chapter in book.chapters) {
    if (chapter.title.isNotEmpty) buffer.write('\n${_toDisplay(chapter.title)}\n');
    buffer.write('\n');
    buffer.write(chapter.paragraphs.map(_toDisplay).join('\n\n'));
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

class _DocxImage {
  const _DocxImage({
    required this.image,
    required this.rId,
    required this.cx,
    required this.cy,
  });

  final EpubImage image;
  final String rId;
  final int cx;
  final int cy;
}

Uint8List _toDocx(EpubBook book) {
  // Gán rId (rId1 = styles) + kích thước hiển thị cho từng ảnh, giữ thứ tự id.
  final docxImages = <String, _DocxImage>{};
  final orderedImages = book.images.values.toList()
    ..sort((a, b) => _imageOrder(a.id).compareTo(_imageOrder(b.id)));
  var rid = 2;
  for (final image in orderedImages) {
    final extent = _imageExtentEmu(_imageSizePx(image.bytes, image.extension));
    docxImages[image.id] = _DocxImage(
      image: image,
      rId: 'rId$rid',
      cx: extent.cx,
      cy: extent.cy,
    );
    rid++;
  }

  final body = StringBuffer();
  var docPrId = 1; // wp:docPr @id phải duy nhất trên toàn document
  String run(String text) =>
      '<w:r><w:t xml:space="preserve">${_xml(text)}</w:t></w:r>';
  String drawing(_DocxImage image) {
    final id = docPrId++;
    return '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="${image.cx}" cy="${image.cy}"/>'
        '<wp:docPr id="$id" name="${image.image.id}"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="${image.image.id}"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="${image.rId}"/>'
        '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/>'
        '<a:ext cx="${image.cx}" cy="${image.cy}"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
  }

  void paragraph(String text, {String? style}) {
    body
      ..write('<w:p>')
      ..write(style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>');
    var last = 0;
    var wrote = false;
    for (final match in _imgTokenRe.allMatches(text)) {
      final pre = text.substring(last, match.start);
      if (pre.isNotEmpty) {
        body.write(run(pre));
        wrote = true;
      }
      final image = docxImages[match.group(1)];
      body.write(image == null ? run('(img)') : drawing(image));
      wrote = true;
      last = match.end;
    }
    final tail = text.substring(last);
    if (tail.isNotEmpty || !wrote) body.write(run(tail));
    body.write('</w:p>');
  }

  paragraph(book.title, style: 'Title');
  for (final chapter in book.chapters) {
    if (chapter.title.isNotEmpty) paragraph(chapter.title, style: 'Heading1');
    for (final text in chapter.paragraphs) {
      paragraph(text);
    }
  }

  final usedExtensions = {for (final image in orderedImages) image.extension};
  final imageDefaults = StringBuffer();
  for (final extension in usedExtensions) {
    imageDefaults.write(
      '<Default Extension="$extension" ContentType="${_imageContentType(extension)}"/>',
    );
  }
  final imageRels = StringBuffer();
  final mediaParts = <String, Object>{};
  for (final image in orderedImages) {
    final docx = docxImages[image.id]!;
    imageRels.write(
      '<Relationship Id="${docx.rId}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      'Target="media/${image.id}.${image.extension}"/>',
    );
    mediaParts['word/media/${image.id}.${image.extension}'] = image.bytes;
  }

  return _zip({
    ...mediaParts,
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '$imageDefaults'
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
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr>'
        '</w:body></w:document>',
    'word/_rels/document.xml.rels':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '$imageRels'
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

/// Thứ tự numeric của id `imgN` (tránh sort chuỗi img1 < img10 < img2).
int _imageOrder(String id) => int.tryParse(id.replaceAll('img', '')) ?? 0;

Uint8List _zip(Map<String, Object> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final value = entry.value;
    final bytes = value is String ? utf8.encode(value) : value as List<int>;
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}

String _xml(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}

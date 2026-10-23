import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vietyaku/features/epub_converter/domain/epub_converter.dart';
import 'package:xml/xml.dart';

void main() {
  late EpubBook book;

  setUpAll(() {
    book = parseEpub(_sampleEpub());
  });

  test('đọc EPUB theo spine và bỏ furigana', () {
    expect(book.title, 'Sách thử');
    expect(book.language, EpubLanguage.japanese);
    expect(book.chapters, hasLength(2));
    expect(book.chapters.first.title, '第一章');
    expect(book.translationRows, contains('漢字 đầu tiên.'));
    expect(book.translationRows.join('\n'), isNot(contains('かんじ')));
    expect(book.translationRows.last, 'Dòng thứ hai.');
    expect(book.translationRows, contains('妨害煙幕(ジャミングスモーク)'));
  });

  test('ba chế độ furigana giống AI Translation Bridge', () {
    final keepAll = parseEpub(
      _sampleEpub(),
      rubyHandling: EpubRubyHandling.keepAll,
    );
    final removeAll = parseEpub(
      _sampleEpub(),
      rubyHandling: EpubRubyHandling.removeAll,
    );

    expect(keepAll.translationRows, contains('漢字(かんじ) đầu tiên.'));
    expect(removeAll.translationRows, contains('漢字 đầu tiên.'));
    expect(removeAll.translationRows, contains('妨害煙幕'));
    expect(removeAll.translationRows.join('\n'), isNot(contains('ジャミング')));
  });

  test('nhận diện ngôn ngữ theo Unicode', () {
    expect(detectEpubLanguage('これは日本語です。'), EpubLanguage.japanese);
    expect(detectEpubLanguage('这是一本中文小说。'), EpubLanguage.chinese);
    expect(detectEpubLanguage('안녕하세요 세계'), EpubLanguage.korean);
    expect(detectEpubLanguage('đây là tiếng Việt'), EpubLanguage.vietnamese);
    expect(detectEpubLanguage('An English novel'), EpubLanguage.english);
  });

  test('parse/export entry-point truyền được qua isolate', () async {
    final isolatedBook = await compute(
      parseEpubRequest,
      EpubParseRequest(bytes: _sampleEpub()),
    );
    final csv = await compute(
      exportEpubRequest,
      EpubExportRequest(book: isolatedBook, format: EpubOutputFormat.csv),
    );
    expect(isolatedBook.language, EpubLanguage.japanese);
    expect(utf8.decode(csv.skip(3).toList()), startsWith('id,raw'));
  });

  test('CSV dùng schema id,raw và escape đúng', () {
    final bytes = exportEpubBook(book, EpubOutputFormat.csv);
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    final csv = utf8.decode(bytes.skip(3).toList());
    expect(csv, startsWith('id,raw\r\n'));
    expect(csv, contains('1,"第一章"'));
  });

  test('Markdown và TXT giữ chương', () {
    final markdown = utf8.decode(
      exportEpubBook(book, EpubOutputFormat.markdown),
    );
    final text = utf8.decode(exportEpubBook(book, EpubOutputFormat.txt));
    expect(markdown, contains('# Sách thử'));
    expect(markdown, contains('## 第一章'));
    expect(text, contains('第二章\n\nDòng thứ hai.'));
  });

  test('XLSX có workbook, styles và sheet XML hợp lệ', () {
    final files = _unzip(exportEpubBook(book, EpubOutputFormat.xlsx));
    expect(files.keys, containsAll(['xl/workbook.xml', 'xl/styles.xml']));
    final sheet = files['xl/worksheets/sheet1.xml']!;
    expect(XmlDocument.parse(utf8.decode(sheet)), isA<XmlDocument>());
    expect(utf8.decode(files['xl/workbook.xml']!), contains('Nội dung'));
    expect(utf8.decode(sheet), contains('漢字 đầu tiên.'));
    expect(utf8.decode(sheet), contains('>raw</t>'));
  });

  test('DOCX có document, styles và relationship hợp lệ', () {
    final files = _unzip(exportEpubBook(book, EpubOutputFormat.docx));
    expect(
      files.keys,
      containsAll([
        'word/document.xml',
        'word/styles.xml',
        'word/_rels/document.xml.rels',
      ]),
    );
    final document = files['word/document.xml']!;
    expect(XmlDocument.parse(utf8.decode(document)), isA<XmlDocument>());
    expect(utf8.decode(document), contains('Sách thử'));
  });

  test('DOCX nhúng ảnh thật, các định dạng text vẫn hiển thị (img)', () {
    final imageBook = parseEpub(_realImageEpub());
    // Ảnh resolve được bytes → có trong book.images.
    expect(imageBook.images, hasLength(1));
    expect(imageBook.images.values.first.extension, 'png');

    final files = _unzip(exportEpubBook(imageBook, EpubOutputFormat.docx));
    // Media part chứa đúng bytes ảnh gốc.
    expect(files.keys, contains('word/media/img1.png'));
    expect(files['word/media/img1.png'], _onePixelPng());
    // Document chèn drawing tham chiếu relationship ảnh.
    final document = utf8.decode(files['word/document.xml']!);
    expect(document, contains('<w:drawing>'));
    expect(document, contains('r:embed="rId2"'));
    expect(XmlDocument.parse(document), isA<XmlDocument>());
    // Relationship + content type khai báo ảnh.
    expect(
      utf8.decode(files['word/_rels/document.xml.rels']!),
      contains('media/img1.png'),
    );
    expect(
      utf8.decode(files['[Content_Types].xml']!),
      contains('Extension="png"'),
    );

    // Text formats không lộ token, vẫn là (img).
    expect(imageBook.translationRows, contains('Trước(img)sau.'));
    expect(imageBook.translationRows.join('\n'), isNot(contains('⟦img')));
    final csv = utf8.decode(exportEpubBook(imageBook, EpubOutputFormat.csv));
    expect(csv, contains('(img)'));
    expect(csv, isNot(contains('⟦img')));
  });

  test('ảnh giữ vị trí bằng placeholder (img)', () {
    final imageBook = parseEpub(_imageEpub());
    final rows = imageBook.translationRows;
    // Ảnh nằm riêng trong <p> → thành một dòng (img).
    expect(rows, contains('(img)'));
    // Ảnh inline giữa câu → chèn đúng chỗ trong đoạn.
    expect(rows, contains('Trước(img)sau.'));
    // Trang chỉ có ảnh trong <div> → vẫn giữ được (img).
    expect(rows.where((row) => row == '(img)').length, greaterThanOrEqualTo(2));
    // Chương không có <h1> KHÔNG được chèn tên file làm dòng (ch1/ch2).
    expect(
      rows.any((row) => row.contains('ch1') || row.contains('ch2')),
      isFalse,
    );
  });
  test('lọc cấu trúc CSS và thuộc tính HTML nhưng giữ nguyên văn xuôi', () {
    // CSS cấu trúc phải bị lọc
    expect(isCssContent('p.c2 { margin: 0; text-align: left }'), isTrue);
    expect(isCssContent('font-size: 1.2em;'), isTrue);
    expect(isCssContent('margin: 0'), isTrue);
    expect(isCssContent('@page { margin: 5pt }'), isTrue);
    expect(
      isCssContent('"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd"'),
      isTrue,
    );

    // Thuộc tính HTML / XML rò rỉ phải bị lọc
    expect(isHtmlTagOrAttribute('xmlns="http://www.w3.org/1999/xhtml"'), isTrue);
    expect(isHtmlTagOrAttribute('class="c3"'), isTrue);
    expect(isHtmlTagOrAttribute('width="600" height="800"'), isTrue);
    expect(isHtmlTagOrAttribute('   '), isTrue);
    expect(isHtmlTagOrAttribute('http://www.w3.org/1999/xhtml'), isTrue);

    // Văn xuôi, lời thoại tiểu thuyết KHÔNG ĐƯỢC bị lọc nhầm
    expect(isCssContent('"Sorry. Did I wake you?"'), isFalse);
    expect(isCssContent("'Not again,' she thought."), isFalse);
    expect(isCssContent('Alice: Hello there'), isFalse);
    expect(isCssContent('Her favorite color: red'), isFalse);
    expect(isCssContent('Link'), isFalse);
    expect(isCssContent('Height: 180 cm'), isFalse);
    expect(isCssContent('{Name: Alice}'), isFalse);
    expect(isCssContent('[Skill {Fireball} acquired]'), isFalse);
    expect(isCssContent('“Who is there?”'), isFalse);

    expect(isHtmlTagOrAttribute('"Sorry. Did I wake you?"'), isFalse);
    expect(isHtmlTagOrAttribute("'Not again,' she thought."), isFalse);
    expect(isHtmlTagOrAttribute('He said, "x = 5 is wrong"'), isFalse);
    expect(isHtmlTagOrAttribute('Link'), isFalse);
  });

  test('xử lý SVG cover, lọc rò rỉ và giữ thứ tự đánh số ảnh (img)', () async {
    final book = parseEpub(_svgCoverAndFilterEpub());
    final rows = book.translationRows;

    // Lời thoại và văn xuôi vẫn còn
    expect(rows, contains('"Sorry. Did I wake you?"'));
    expect(rows, contains('Her favorite color: red'));
    expect(rows, contains('Alice: Hello there'));
    expect(rows, contains('Height: 180 cm'));

    // CSS và HTML attribute đã bị lọc sạch
    expect(rows.join('\n'), isNot(contains('font-size: 1.2em;')));
    expect(rows.join('\n'), isNot(contains('xmlns=')));

    // SVG thuần (không có <image>) bị xóa, không tạo (img) thừa
    // Bìa cover trong <svg><image .../></svg> tạo đúng (img) ở đầu
    expect(rows.first, '(img)');

    // Tổng số marker (img): cover=1, missing=2, no-src=3, fig 1=4 -> 4 markers
    expect(rows.where((r) => r == '(img)').length, 4);

    // exportedImages giữ đúng 2 ảnh tìm thấy, đánh số khớp vị trí marker: 0001 và 0004
    expect(book.exportedImages, hasLength(2));
    expect(book.exportedImages[0].markerIndex, 1);
    expect(book.exportedImages[0].fileName, '0001_cover.png');
    expect(book.exportedImages[1].markerIndex, 4);
    expect(book.exportedImages[1].fileName, '0004_fig 1.png');

    // Kiểm tra ghi file qua exportEpubImages vào thư mục tạm
    final tempDir = Directory.systemTemp.createTempSync('vietyaku_img_test_');
    try {
      final exportedCount = await exportEpubImages(book, tempDir.path);
      expect(exportedCount, 2);
      final files = tempDir.listSync().map((f) => p.basename(f.path)).toList()
        ..sort();
      expect(files, ['0001_cover.png', '0004_fig 1.png']);
      final coverFile = File(p.join(tempDir.path, '0001_cover.png'));
      expect(coverFile.existsSync(), isTrue);
      expect(coverFile.lengthSync(), _onePixelPng().length);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('SVG chứa 2 thẻ image chỉ tính là 1 marker (img) và 1 ảnh', () {
    final doubleBook = parseEpub(_svgDoubleImageEpub());
    expect(doubleBook.translationRows.where((r) => r == '(img)').length, 1);
    expect(doubleBook.exportedImages, hasLength(1));
    expect(doubleBook.exportedImages.first.fileName, '0001_p1.png');
  });

  test('giữ đúng thứ tự DOM khi img đứng trước svg và không lặp đoạn blockquote', () {
    final png = _onePixelPng();
    final archive = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<?xml version="1.0"?>'
              '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
              '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
              '</container>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/content.opf',
          '<?xml version="1.0"?>'
              '<package xmlns="http://www.idpf.org/2007/opf">'
              '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
              '<dc:title>DOM Order</dc:title></metadata>'
              '<manifest><item id="c1" href="Text/ch1.xhtml"/>'
              '<item id="i1" href="Text/first.png"/>'
              '<item id="i2" href="Text/second.png"/></manifest>'
              '<spine><itemref idref="c1"/></spine>'
              '</package>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/Text/ch1.xhtml',
          '<html><body>'
              '<blockquote><p>Lời trích dẫn</p></blockquote>'
              '<p><img src="first.png"/><svg><image href="second.png"/></svg></p>'
              '</body></html>',
        ),
      )
      ..addFile(ArchiveFile('OEBPS/Text/first.png', png.length, png))
      ..addFile(ArchiveFile('OEBPS/Text/second.png', png.length, png));
    final book = parseEpub(ZipEncoder().encodeBytes(archive));
    expect(
      book.translationRows.where((r) => r == 'Lời trích dẫn').length,
      1,
    );
    expect(
      book.exportedImages.map((e) => e.fileName).toList(),
      ['0001_first.png', '0002_second.png'],
    );
  });
}

Uint8List _onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Uint8List _realImageEpub() {
  final png = _onePixelPng();
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?>'
            '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?>'
            '<package xmlns="http://www.idpf.org/2007/opf">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:title>Sách ảnh thật</dc:title></metadata>'
            '<manifest><item id="c1" href="Text/ch1.xhtml"/>'
            '<item id="p" href="Text/p.png"/></manifest>'
            '<spine><itemref idref="c1"/></spine>'
            '</package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/Text/ch1.xhtml',
        '<html><body><h1>第一章</h1>'
            '<p>Trước<img src="p.png"/>sau.</p></body></html>',
      ),
    )
    ..addFile(ArchiveFile('OEBPS/Text/p.png', png.length, png));
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _imageEpub() {
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?>'
            '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?>'
            '<package xmlns="http://www.idpf.org/2007/opf">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:title>Sách ảnh</dc:title></metadata>'
            '<manifest><item id="c1" href="Text/ch1.xhtml"/>'
            '<item id="c2" href="Text/ch2.xhtml"/></manifest>'
            '<spine><itemref idref="c1"/><itemref idref="c2"/></spine>'
            '</package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/Text/ch1.xhtml',
        '<html><body><h1>Chương ảnh</h1>'
            '<p><img src="a.jpg" alt="x"/></p>'
            '<p>Trước<img src="b.jpg"/>sau.</p></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/Text/ch2.xhtml',
        '<html><body><div class="cover"><img src="c.jpg"/></div></body></html>',
      ),
    );
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _sampleEpub() {
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?>'
            '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?>'
            '<package xmlns="http://www.idpf.org/2007/opf">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:title>Sách thử</dc:title></metadata>'
            '<manifest><item id="c1" href="Text/ch1.xhtml"/>'
            '<item id="c2" href="Text/ch2.xhtml"/></manifest>'
            '<spine><itemref idref="c1"/><itemref idref="c2"/></spine>'
            '</package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/Text/ch1.xhtml',
        '<html><body><h1>第一章</h1>'
            '<p><ruby>漢字<rt>かんじ</rt></ruby> đầu tiên.</p>'
            '<p><ruby>妨害<rt>ジャミング</rt></ruby>'
            '<ruby>煙幕<rt>スモーク</rt></ruby></p></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/Text/ch2.xhtml',
        '<html><body><h2>第二章</h2><p>Dòng thứ hai.</p></body></html>',
      ),
    );
  return ZipEncoder().encodeBytes(archive);
}

Map<String, Uint8List> _unzip(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes).files)
    if (file.isFile) file.name: file.content,
};

Uint8List _svgCoverAndFilterEpub() {
  final png = _onePixelPng();
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?>'
            '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?>'
            '<package xmlns="http://www.idpf.org/2007/opf">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:title>Sách SVG Cover</dc:title></metadata>'
            '<manifest>'
            '<item id="cov" href="Text/cover.xhtml"/>'
            '<item id="c1" href="Text/ch1.xhtml"/>'
            '<item id="img_cover" href="images/cover.png"/>'
            '<item id="img_fig1" href="images/fig 1.png"/>'
            '</manifest>'
            '<spine><itemref idref="cov"/><itemref idref="c1"/></spine>'
            '</package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/Text/cover.xhtml',
        '<html><body>'
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 800">'
            '<image width="600" height="800" xlink:href="../images/cover.png"/>'
            '</svg></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/Text/ch1.xhtml',
        '<html><body>'
            '<p class="c2"><span class="c3">"Sorry. Did I wake you?"</span></p>'
            '<p>font-size: 1.2em;</p>'
            '<p>xmlns="http://www.w3.org/1999/xhtml"</p>'
            '<p><img src="../images/missing.png"/></p>'
            '<p><img alt="no-src"/></p>'
            '<p><img src="../images/fig%201.png" alt="fig1"/></p>'
            '<p>Her favorite color: red</p>'
            '<p>Alice: Hello there</p>'
            '<p>Height: 180 cm</p>'
            '<svg viewBox="0 0 10 10"><path d="M0 0"/></svg>'
            '</body></html>',
      ),
    )
    ..addFile(ArchiveFile('OEBPS/images/cover.png', png.length, png))
    ..addFile(ArchiveFile('OEBPS/images/fig 1.png', png.length, png));
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _svgDoubleImageEpub() {
  final png = _onePixelPng();
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?>'
            '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?>'
            '<package xmlns="http://www.idpf.org/2007/opf">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:title>Double SVG</dc:title></metadata>'
            '<manifest>'
            '<item id="cov" href="Text/cover.xhtml"/>'
            '<item id="img1" href="images/p1.png"/>'
            '<item id="img2" href="images/p2.png"/>'
            '</manifest>'
            '<spine><itemref idref="cov"/></spine>'
            '</package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/Text/cover.xhtml',
        '<html><body><svg>'
            '<image xlink:href="../images/p1.png"/>'
            '<image xlink:href="../images/p2.png"/>'
            '</svg></body></html>',
      ),
    )
    ..addFile(ArchiveFile('OEBPS/images/p1.png', png.length, png))
    ..addFile(ArchiveFile('OEBPS/images/p2.png', png.length, png));
  return ZipEncoder().encodeBytes(archive);
}

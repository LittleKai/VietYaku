import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/repair/domain/jp_repair_pipeline.dart';
import 'package:vietyaku/features/repair/domain/repair_report.dart';
import 'package:vietyaku/features/repair/domain/simp2jp_table.dart';

void main() {
  late Simp2JpTable table;

  setUpAll(() {
    // Asset thật đã commit (sinh bởi tool/build_simp2jp.dart).
    final tsv = File('assets/mappings/simp2jp.tsv').readAsStringSync();
    final overrides = File(
      'assets/mappings/simp2jp_overrides.tsv',
    ).readAsStringSync();
    table = Simp2JpTable.parse(tsv, overridesTsv: overrides);
  });

  group('fixKeySpaces (quy tắc A)', () {
    test('覚 悟 → 覚悟', () {
      expect(fixKeySpaces('覚 悟').$1, '覚悟');
    });

    test('持 ち 歩 → 持ち歩', () {
      expect(fixKeySpaces('持 ち 歩').$1, '持ち歩');
    });

    test('space cạnh chữ/số Latin giữ nguyên', () {
      expect(fixKeySpaces('Level 5').$1, 'Level 5');
      expect(fixKeySpaces('abc 覚').$1, 'abc 覚');
      expect(fixKeySpaces('覚 abc').$1, '覚 abc');
    });

    test('space quanh dấu phẩy ASCII bị xóa (hai phía non-alnum)', () {
      expect(fixKeySpaces('様, 只今').$1, '様,只今');
    });

    test('trim space đầu/cuối + ideographic space U+3000', () {
      expect(fixKeySpaces('　覚　悟　').$1, '覚悟');
    });

    test('run nhiều space liên tiếp xóa cả cụm', () {
      expect(fixKeySpaces('覚   悟').$1, '覚悟');
      expect(fixKeySpaces('覚   悟').$2, 3);
    });
  });

  group('convertKeyChars (quy tắc B + bảng thật)', () {
    test('giản thể → JP: 军→軍, 夺→奪, 骑→騎, 异→異, 挂→掛', () {
      final report = RepairReport();
      expect(convertKeyChars('军', table, report).$1, '軍');
      expect(convertKeyChars('夺', table, report).$1, '奪');
      expect(convertKeyChars('骑士', table, report).$1, '騎士');
      expect(convertKeyChars('异世界', table, report).$1, '異世界');
      expect(convertKeyChars('出挂け', table, report).$1, '出掛け');
    });

    test('quy tắc vàng: 芸/后/叶/国/学 là chữ Nhật hợp lệ → giữ nguyên', () {
      final report = RepairReport();
      expect(convertKeyChars('芸后叶国学', table, report).$1, '芸后叶国学');
      expect(report.ambiguous, isEmpty);
    });

    test('overrides chữ sáp nhập đồng âm: 机→機, 准→準, 采→採, 筑→築, 斗→闘, 雕→彫, 凉→涼, 升→昇, 坛→壇', () {
      final report = RepairReport();
      expect(convertKeyChars('せっかくの机会', table, report).$1, 'せっかくの機会');
      expect(convertKeyChars('机械仕掛け', table, report).$1, '機械仕掛け');
      expect(convertKeyChars('准備', table, report).$1, '準備');
      expect(convertKeyChars('採取', table, report).$1, '採取');
      expect(convertKeyChars('建築', table, report).$1, '建築');
      expect(convertKeyChars('戦闘', table, report).$1, '戦闘');
      expect(convertKeyChars('彫刻', table, report).$1, '彫刻');
      expect(convertKeyChars('清凉', table, report).$1, '清涼');
      expect(convertKeyChars('上昇', table, report).$1, '上昇');
      expect(convertKeyChars('祭坛', table, report).$1, '祭壇');
    });

    test('phraseReplacements: 言叶→言葉, 関系→関係, 舍て→捨て, 获物→獲物, 修复→修復 nhưng giữ nguyên 叶う', () {
      final report = RepairReport();
      expect(convertKeyChars('売り言叶に買い言叶', table, report).$1, '売り言葉に買い言葉');
      expect(convertKeyChars('関系者以外立ち入', table, report).$1, '関係者以外立ち入');
      expect(convertKeyChars('使い舍て', table, report).$1, '使い捨て');
      expect(convertKeyChars('获物を狙う獣', table, report).$1, '獲物を狙う獣');
      expect(convertKeyChars('武器の修复', table, report).$1, '武器の修復');
      expect(convertKeyChars('願ったり叶ったり', table, report).$1, '願ったり叶ったり');
    });

    test('ambiguous (复) không convert, ghi vào report', () {
      final report = RepairReport();
      expect(convertKeyChars('复', table, report).$1, '复');
      expect(report.ambiguous.keys, contains('复'));
    });
  });

  group('repairFile (test case bắt buộc, nguyên văn dữ liệu thật)', () {
    RepairedFile run(
      String content, [
      RepairPolicy policy = RepairPolicy.addVariant,
    ]) => repairFile(content, table, policy);

    test('覚 悟 → 覚悟', () {
      final r = run('覚 悟=(kakugo)giác ngộ\r\n');
      expect(r.content, '覚悟=(kakugo)giác ngộ\r\n');
      expect(r.report.spacesRemoved, 1);
    });

    test('持 ち 歩 → 持ち歩 · 目 を 夺 → 目を奪', () {
      final r = run('持 ち 歩=mochiaru\r\n目 を 夺=ánh mắt bị hấp dẫn bởi\r\n');
      expect(r.content, '持ち歩=mochiaru\r\n目を奪=ánh mắt bị hấp dẫn bởi\r\n');
    });

    test('ワイトの 率 いるスケルトン 军 団 → ワイトの率いるスケルトン軍団', () {
      final r = run('ワイトの 率 いるスケルトン 军 団=x\r\n');
      expect(r.content, 'ワイトの率いるスケルトン軍団=x\r\n');
    });

    test('骸骨骑士様, 只今异世界 へお 出挂 け 中 (space quanh phẩy ASCII)', () {
      final r = run('骸骨骑士様, 只今异世界 へお 出挂 け 中=y\r\n');
      expect(r.content, '骸骨騎士様,只今異世界へお出掛け中=y\r\n');
    });

    test('key có chữ/số Latin: space cạnh Latin giữ nguyên', () {
      final r = run('Lv 99 冒険者=nhà mạo hiểm Lv 99\r\n');
      expect(r.content, 'Lv 99 冒険者=nhà mạo hiểm Lv 99\r\n');
    });

    test('value LacViet giữ nguyên tuyệt đối từng byte', () {
      const value = r'✚[fānyì] \n\t1. dịch; phiên dịch\n\t2. người dịch';
      final r = run('翻译=$value\r\n', RepairPolicy.convert);
      final out = r.content.split('\r\n').first;
      expect(out.substring(out.indexOf('=') + 1), value);
    });

    test('value chứa = không bị đụng', () {
      final r = run('数 式=a=b+c\r\n');
      expect(r.content, '数式=a=b+c\r\n');
    });

    test('dòng không có = pass through nguyên vẹn', () {
      final r = run('# comment lạ\r\n一=nhất\r\n');
      expect(r.content, '# comment lạ\r\n一=nhất\r\n');
    });

    test('policy addVariant: key thuần Hán giữ gốc + chèn converted sau', () {
      final r = run('军団=quân đoàn\r\n');
      expect(r.content, '军団=quân đoàn\r\n軍団=quân đoàn\r\n');
      expect(r.report.variantsAdded, 1);
    });

    test('policy convert: chỉ giữ dòng converted', () {
      final r = run('军団=quân đoàn\r\n', RepairPolicy.convert);
      expect(r.content, '軍団=quân đoàn\r\n');
    });

    test('policy keepOnly: không convert key thuần Hán', () {
      final r = run('军団=quân đoàn\r\n', RepairPolicy.keepOnly);
      expect(r.content, '军団=quân đoàn\r\n');
      expect(r.report.charsConverted, 0);
    });

    test('dedupe: key repair xong trùng key sẵn có → giữ dòng đầu', () {
      final r = run('覚悟=nghĩa gốc\r\n覚 悟=nghĩa gốc\r\n');
      expect(r.content, '覚悟=nghĩa gốc\r\n');
      expect(r.report.dupesIdenticalValue, 1);
      expect(r.report.conflicts, isEmpty);
    });

    test('dedupe: value khác → conflict, giữ dòng đầu', () {
      final r = run('覚悟=nghĩa A\r\n覚 悟=nghĩa B\r\n');
      expect(r.content, '覚悟=nghĩa A\r\n');
      expect(r.report.conflicts, hasLength(1));
    });

    test('BOM đầu file bị strip, LF-only cũng xử lý được', () {
      final r = run('﻿覚 悟=giác ngộ\n持 ち 歩=mang theo\n');
      expect(r.content, '覚悟=giác ngộ\r\n持ち歩=mang theo\r\n');
    });
  });
}

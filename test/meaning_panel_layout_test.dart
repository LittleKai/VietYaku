import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/translation/domain/lookup_dictionary_type.dart';
import 'package:vietyaku/features/translation/domain/meaning_panel_layout.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  group('availableMeaningPanelTypes', () {
    test('Nhật bỏ Trung Việt, Trung bỏ Nhật Việt + Mazii', () {
      final ja = availableMeaningPanelTypes(TranslationMode.japanese);
      expect(ja, isNot(contains(LookupDictionaryType.zhVi)));
      expect(ja, contains(LookupDictionaryType.jaVi));
      expect(ja, contains(LookupDictionaryType.mazii));

      final zh = availableMeaningPanelTypes(TranslationMode.chinese);
      expect(zh, contains(LookupDictionaryType.zhVi));
      expect(zh, isNot(contains(LookupDictionaryType.jaVi)));
      expect(zh, isNot(contains(LookupDictionaryType.mazii)));
    });

    test('AiEntries có mặt để tra được như một từ điển', () {
      for (final mode in TranslationMode.values) {
        expect(
          availableMeaningPanelTypes(mode),
          contains(LookupDictionaryType.aiEntries),
        );
      }
    });

    test('thứ tự mặc định khớp thứ tự lookup() sinh section', () {
      final ja = availableMeaningPanelTypes(TranslationMode.japanese);
      expect(ja.first, equals(LookupDictionaryType.userDict));
      expect(ja.last, equals(LookupDictionaryType.phonetic));
      expect(
        ja.indexOf(LookupDictionaryType.lacViet),
        lessThan(ja.indexOf(LookupDictionaryType.online)),
      );
    });
  });

  group('bật/tắt và sắp xếp', () {
    test('mặc định hiện hết', () {
      final layout = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);
      expect(layout.visible.length, equals(layout.order.length));
      expect(layout.hidden, isEmpty);
    });

    test('tắt một loại thì nó biến khỏi visible nhưng giữ vị trí trong order', () {
      final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);
      final at = base.order.indexOf(LookupDictionaryType.mazii);

      final off = base.withVisibility(LookupDictionaryType.mazii, false);
      expect(off.visible, isNot(contains(LookupDictionaryType.mazii)));
      expect(off.order.indexOf(LookupDictionaryType.mazii), equals(at));

      final on = off.withVisibility(LookupDictionaryType.mazii, true);
      expect(on.visible, contains(LookupDictionaryType.mazii));
      expect(on.order.indexOf(LookupDictionaryType.mazii), equals(at));
    });

    test('kéo xuống dưới', () {
      final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);
      final first = base.order.first;
      final moved = base.reordered(0, 2);

      expect(moved.order[2], equals(first));
      expect(moved.order.length, equals(base.order.length));
      expect(moved.order.toSet(), equals(base.order.toSet()));
    });

    test('kéo lên trên', () {
      final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);
      final third = base.order[2];
      expect(base.reordered(2, 0).order.first, equals(third));
    });

    test('index ngoài phạm vi thì không đổi gì', () {
      final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);
      expect(base.reordered(-1, 0).order, equals(base.order));
      expect(base.reordered(99, 0).order, equals(base.order));
    });

    test('movedOnto: kéo thẻ xuống, nó về đúng chỗ thẻ đích', () {
      final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);
      final a = base.order[0];
      final b = base.order[3];

      final moved = base.movedOnto(a, b);
      expect(moved.order.indexOf(a), equals(3));
      // b bị đẩy lùi một bậc chứ không mất.
      expect(moved.order.indexOf(b), equals(2));
      expect(moved.order.toSet(), equals(base.order.toSet()));
    });

    test('movedOnto: kéo thẻ lên, nó chiếm chỗ thẻ đích', () {
      final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);
      final a = base.order[4];
      final b = base.order[1];

      final moved = base.movedOnto(a, b);
      expect(moved.order.indexOf(a), equals(1));
      expect(moved.order.indexOf(b), equals(2));
    });

    test('movedOnto: thả lên chính nó hoặc loại lạ thì không đổi gì', () {
      final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);
      final a = base.order.first;

      expect(base.movedOnto(a, a).order, equals(base.order));
      // zhVi không có trong bố cục mode Nhật.
      expect(
        base.movedOnto(a, LookupDictionaryType.zhVi).order,
        equals(base.order),
      );
    });

    test('movedOnto giữa hai thẻ ĐANG HIỆN vẫn đặt đúng chỗ dù có thẻ bị tắt', () {
      // Tắt thẻ nằm giữa: chỉ số phải tính trên order đầy đủ, không phải trên
      // danh sách đang hiện, nếu không thẻ sẽ nhảy sai vị trí.
      final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese)
          .withVisibility(LookupDictionaryType.names, false);
      final visible = base.visible;
      final first = visible.first;
      final third = visible[2];

      final moved = base.movedOnto(first, third);
      expect(moved.visible.indexOf(first), equals(2));
      expect(moved.hidden, equals({LookupDictionaryType.names}));
    });

    test('indexOf: loại lạ xuống cuối', () {
      final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);
      expect(base.indexOf(null), equals(base.order.length));
      // zhVi không khả dụng ở mode Nhật.
      expect(
        base.indexOf(LookupDictionaryType.zhVi),
        equals(base.order.length),
      );
    });
  });

  group('lưu/đọc lại', () {
    test('round-trip giữ cả thứ tự lẫn trạng thái tắt', () {
      final layout = MeaningPanelLayout.defaultsFor(TranslationMode.japanese)
          .reordered(0, 3)
          .withVisibility(LookupDictionaryType.thieuChuu, false);

      final decoded = MeaningPanelLayout.decode(
        layout.encode(),
        TranslationMode.japanese,
      );
      expect(decoded.order, equals(layout.order));
      expect(decoded.hidden, equals(layout.hidden));
    });

    test('chuỗi rỗng / null → mặc định', () {
      for (final raw in [null, '', '   ']) {
        final decoded = MeaningPanelLayout.decode(raw, TranslationMode.chinese);
        expect(
          decoded.order,
          equals(availableMeaningPanelTypes(TranslationMode.chinese)),
        );
        expect(decoded.hidden, isEmpty);
      }
    });

    test('loại còn thiếu được nối vào cuối và mặc định BẬT', () {
      // Bản cũ chỉ lưu 2 loại; các loại thêm về sau phải tự hiện ra.
      final decoded = MeaningPanelLayout.decode(
        'lacViet:1,userDict:0',
        TranslationMode.japanese,
      );

      expect(decoded.order.first, equals(LookupDictionaryType.lacViet));
      expect(decoded.order[1], equals(LookupDictionaryType.userDict));
      expect(decoded.hidden, equals({LookupDictionaryType.userDict}));
      expect(
        decoded.order.toSet(),
        equals(availableMeaningPanelTypes(TranslationMode.japanese).toSet()),
      );
      expect(decoded.visible, contains(LookupDictionaryType.aiEntries));
    });

    test('bỏ tên lạ, mục trùng và loại không hợp mode', () {
      final decoded = MeaningPanelLayout.decode(
        'khongTonTai:1,lacViet:1,lacViet:0,zhVi:1',
        TranslationMode.japanese,
      );

      expect(decoded.order.where((t) => t == LookupDictionaryType.lacViet).length, 1);
      expect(decoded.order, isNot(contains(LookupDictionaryType.zhVi)));
      // Lần đọc thứ hai của lacViet bị bỏ nên trạng thái vẫn là BẬT.
      expect(decoded.hidden, isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';
import 'package:vietyaku/features/translation/domain/lookup_dictionary_type.dart';
import 'package:vietyaku/features/translation/domain/meaning_panel_layout.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';
import 'package:vietyaku/features/translation/presentation/lacviet_panel.dart';

/// Các section theo đúng thứ tự `lookup()` sinh ra.
final _sections = [
  const LookupSection('x', 'VietPhrase', 'vp'),
  const LookupSection('x', 'Lạc Việt', 'lv'),
  const LookupSection('x', 'Mazii', 'mz'),
  const LookupSection('x', 'Mazii Online', 'online-1'),
  const LookupSection('x', 'Jisho', 'online-2'),
  const LookupSection('x', 'AI Dịch', 'ai'),
  const LookupSection('x', 'AI tách từ', 'ai-entry'),
  const LookupSection('x', 'Phiên Âm English', 'pa'),
];

List<String> _labels(List<LookupSection> s) => [for (final x in s) x.label];

void main() {
  final base = MeaningPanelLayout.defaultsFor(TranslationMode.japanese);

  test('mặc định giữ nguyên thứ tự lookup() sinh ra', () {
    expect(
      _labels(orderMeaningSections(_sections, base, const [])),
      equals(_labels(_sections)),
    );
  });

  test('tắt một loại thì mọi section của loại đó biến mất', () {
    final layout = base.withVisibility(LookupDictionaryType.online, false);
    final out = _labels(orderMeaningSections(_sections, layout, const []));

    expect(out, isNot(contains('Mazii Online')));
    expect(out, isNot(contains('Jisho')));
    // Mazii offline là loại khác, không bị tắt lây.
    expect(out, contains('Mazii'));
  });

  test('đổi thứ tự loại thì section đi theo', () {
    final from = base.order.indexOf(LookupDictionaryType.phonetic);
    final layout = base.reordered(from, 0);

    expect(
      _labels(orderMeaningSections(_sections, layout, const [])).first,
      equals('Phiên Âm English'),
    );
  });

  test('nhiều section cùng loại giữ nguyên thứ tự tương đối', () {
    final from = base.order.indexOf(LookupDictionaryType.online);
    final layout = base.reordered(from, 0);
    final out = _labels(orderMeaningSections(_sections, layout, const []));

    expect(out.take(2), equals(['Mazii Online', 'Jisho']));
  });

  test('loại đang hiện ở popup bị ẩn khỏi panel để khỏi trùng', () {
    final out = _labels(
      orderMeaningSections(_sections, base, const [
        LookupDictionaryType.lacViet,
      ]),
    );
    expect(out, isNot(contains('Lạc Việt')));
    expect(out, contains('VietPhrase'));
  });

  test('section có nhãn lạ vẫn hiện, xếp cuối', () {
    final sections = [..._sections, const LookupSection('x', 'Nguồn Lạ', 'v')];
    final out = _labels(orderMeaningSections(sections, base, const []));

    expect(out.last, equals('Nguồn Lạ'));
    expect(out.length, equals(sections.length));
  });

  test('AiEntries tắt được riêng, không ảnh hưởng AI Dịch', () {
    final layout = base.withVisibility(LookupDictionaryType.aiEntries, false);
    final out = _labels(orderMeaningSections(_sections, layout, const []));

    expect(out, isNot(contains('AI tách từ')));
    expect(out, contains('AI Dịch'));
  });
}

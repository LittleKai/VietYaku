import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';
import 'package:vietyaku/features/translation/data/jisho_api.dart';
import 'package:vietyaku/features/translation/data/weblio_api.dart';
import 'package:vietyaku/features/translation/data/youdao_api.dart';
import 'package:vietyaku/features/translation/domain/online_lookup_source.dart';

void main() {
  group('OnlineDict encode/decode', () {
    test('giữ nguyên các mục qua 1 vòng encode → decode', () {
      const sections = [
        LookupSection('取り消し', 'Mazii Online', '取り消し「とりけし」\n- (danh từ) hủy bỏ'),
        LookupSection('取り消し', 'Google Dịch', 'hủy bỏ'),
        LookupSection('取り消し', 'Google Anh', 'cancellation'),
      ];

      final value = encodeOnlineSections(sections);
      // Value dict phải nằm trọn 1 dòng (xuống dòng escape như LacViet).
      expect(value.contains('\n'), isFalse);

      final decoded = decodeOnlineSections('取り消し', value);
      expect(decoded.map((s) => s.label), [
        'Mazii Online',
        'Google Dịch',
        'Google Anh',
      ]);
      expect(decoded.map((s) => s.body), sections.map((s) => s.body));
      expect(decoded.every((s) => s.word == '取り消し'), isTrue);
    });

    test('bỏ qua mục rỗng và nội dung trước nhãn đầu tiên', () {
      final decoded = decodeOnlineSections(
        '猫',
        r'rác\n<<Google Dịch>>\ncon mèo\n<<Google Anh>>\n',
      );
      expect(decoded, hasLength(1));
      expect(decoded.single.label, 'Google Dịch');
      expect(decoded.single.body, 'con mèo');
    });
  });

  test('JishoApi.format: header + nghĩa theo từ loại', () {
    final body = JishoApi.format(const {
      'is_common': true,
      'jlpt': ['jlpt-n5'],
      'japanese': [
        {'word': '猫', 'reading': 'ねこ'},
      ],
      'senses': [
        {
          'english_definitions': ['cat', 'feline'],
          'parts_of_speech': ['Noun'],
        },
        {
          'english_definitions': ['shamisen'],
          'parts_of_speech': ['Noun'],
        },
      ],
    });
    expect(
      body,
      '猫 「ねこ」 (thường dùng, N5)\n- (Noun) cat; feline\n- (Noun) shamisen',
    );
  });

  test('JishoApi.format: không có nghĩa nào thì trả null', () {
    expect(
      JishoApi.format(const {
        'japanese': [
          {'word': '猫'},
        ],
        'senses': [],
      }),
      isNull,
    );
  });

  group('WeblioApi.format (meta description thật của cjjc.weblio.jp)', () {
    test('tách nhãn thành dòng, bỏ tiền tố và đuôi giới thiệu site', () {
      const html =
          '<meta name="description" content="勉強の意味や日本語訳。中国語訳功课ピンインgōngkè'
          ' - 約160万語の日中中日辞典。読み方・発音も分かる中国語辞書。">';
      expect(WeblioApi.format(html, '勉強'), '中国語訳 功课\nピンイン gōngkè');
    });

    test('tiền tố "〜の中国語訳。" cũng bị bỏ', () {
      const html =
          '<meta name="description" content="取り消しの中国語訳。読み方とりけし中国語訳取消，废除'
          '中国語品詞動詞 - 約160万語の日中中日辞典。">';
      expect(WeblioApi.format(html, '取り消し'), '読み方 とりけし\n中国語訳 取消，废除\n中国語品詞 動詞');
    });

    test('không có thẻ description thì trả null', () {
      expect(WeblioApi.format('<html><body>404</body></html>', '猫'), isNull);
    });
  });

  group('YoudaoApi.format (response thật của dict.youdao.com/jsonapi)', () {
    /// Một nghĩa: `l.i` là các mảnh, mảnh tra được là map có `#text`.
    Map<String, dynamic> sense(List<Object> parts, [String? pos]) => {
      'tr': [
        {
          'l': {'i': parts, 'pos': ?pos},
        },
      ],
    };

    test('header có pinyin, mỗi nghĩa một dòng kèm từ loại', () {
      final json = {
        'ce': {
          'word': [
            {
              'return-phrase': {
                'l': {'i': '取消'},
              },
              'phone': 'qǔ xiāo',
              'trs': [
                sense(['', 'cancel'], 'vt.'),
                // "call off" bị chẻ làm 2 mảnh tra được + 1 space.
                sense([
                  '',
                  {'#text': 'call'},
                  ' ',
                  {'#text': 'off'},
                ]),
              ],
            },
          ],
        },
      };
      expect(
        YoudaoApi.format(json, '取消'),
        '取消 「qǔ xiāo」\n- (vt.) cancel\n- call off',
      );
    });

    test('phồn thể: header hiện headword giản thể mà Youdao quy về', () {
      final json = {
        'ce': {
          'word': [
            {
              'return-phrase': {
                'l': {'i': '时间'},
              },
              'phone': 'shí jiān',
              'trs': [
                sense(['', 'time'], 'n.'),
              ],
            },
          ],
        },
      };
      expect(YoudaoApi.format(json, '時間'), '时间 「shí jiān」\n- (n.) time');
    });

    test('không có phone thì header chỉ có headword', () {
      final json = {
        'ce': {
          'word': [
            {
              'return-phrase': {
                'l': {'i': '电车'},
              },
              'trs': [
                sense(['', 'tram']),
              ],
            },
          ],
        },
      };
      expect(YoudaoApi.format(json, '电车'), '电车\n- tram');
    });

    test('từ không có trong từ điển: response thiếu khoá ce → null', () {
      expect(
        YoudaoApi.format(const {
          'input': '一露头',
          'meta': {'guessLanguage': 'zh'},
        }, '一露头'),
        isNull,
      );
    });
  });

  test('nguồn tra online mặc định bật cả 4, bật/tắt được từng nguồn', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(settingsProvider).onlineLookupSources,
      OnlineLookupSource.values,
    );

    await container.read(settingsProvider.notifier).setOnlineLookupSources(
      const [OnlineLookupSource.english, OnlineLookupSource.mazii],
    );
    // Giữ thứ tự khai báo của enum, không theo thứ tự truyền vào.
    expect(container.read(settingsProvider).onlineLookupSources, const [
      OnlineLookupSource.mazii,
      OnlineLookupSource.english,
    ]);

    await container
        .read(settingsProvider.notifier)
        .setOnlineLookupSources(const []);
    expect(container.read(settingsProvider).onlineLookupSources, isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/app_paths.dart';

void main() {
  group('AppPaths.assetKeysForLanguage', () {
    const allAssets = [
      'assets/mappings/simp2jp.tsv',
      'assets/branding/app_icon.png',
      'data/cn/VietPhrase.txt',
      'data/cn/ZhViDict.txt',
      'data/jp/VietPhrase.txt',
      'data/jp/JaViDict.txt',
      'data/jp/Names.txt',
    ];

    test('chỉ lấy asset của đúng bộ ngôn ngữ', () {
      expect(AppPaths.assetKeysForLanguage(allAssets, 'jp'), [
        'data/jp/JaViDict.txt',
        'data/jp/Names.txt',
        'data/jp/VietPhrase.txt',
      ]);
      expect(AppPaths.assetKeysForLanguage(allAssets, 'cn'), [
        'data/cn/VietPhrase.txt',
        'data/cn/ZhViDict.txt',
      ]);
    });

    test('không kéo nhầm asset ngoài thư mục data/', () {
      final jp = AppPaths.assetKeysForLanguage(allAssets, 'jp');
      expect(jp.any((a) => a.startsWith('assets/')), isFalse);
    });

    test('tiền tố phải khớp cả dấu / — "j" không kéo được bộ "jp"', () {
      expect(AppPaths.assetKeysForLanguage(allAssets, 'j'), isEmpty);
    });

    test('ngôn ngữ không có asset nào → rỗng', () {
      expect(AppPaths.assetKeysForLanguage(allAssets, 'kr'), isEmpty);
    });
  });

  group('AppPaths.seedMarkerContent', () {
    test('đổi phiên bản app → chữ ký khác (buộc seed lại)', () {
      expect(
        AppPaths.seedMarkerContent('1.1.1+13', 13),
        isNot(AppPaths.seedMarkerContent('1.1.2+14', 13)),
      );
    });

    test('đổi số file trong bộ → chữ ký khác', () {
      expect(
        AppPaths.seedMarkerContent('1.1.1+13', 13),
        isNot(AppPaths.seedMarkerContent('1.1.1+13', 14)),
      );
    });

    test('cùng phiên bản + cùng số file → chữ ký trùng (bỏ qua seed)', () {
      expect(
        AppPaths.seedMarkerContent('1.1.1+13', 13),
        AppPaths.seedMarkerContent('1.1.1+13', 13),
      );
    });
  });

  group('SeedProgress', () {
    test('fraction theo số file đã xử lý', () {
      const progress = SeedProgress(
        fileIndex: 3,
        fileCount: 12,
        fileName: 'JaViDict.txt',
        bytesCopied: 1024,
      );
      expect(progress.fraction, closeTo(0.25, 1e-9));
      expect(progress.isDone, isFalse);
    });

    test('fileCount 0 không chia cho 0', () {
      const progress = SeedProgress(
        fileIndex: 0,
        fileCount: 0,
        fileName: '',
        bytesCopied: 0,
      );
      expect(progress.fraction, 0);
    });

    test('isDone khi đã hết file và không còn tên file đang chép', () {
      const progress = SeedProgress(
        fileIndex: 12,
        fileCount: 12,
        fileName: '',
        bytesCopied: 99,
      );
      expect(progress.isDone, isTrue);
      expect(progress.fraction, 1);
    });
  });
}

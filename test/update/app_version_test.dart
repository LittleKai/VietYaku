import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/update/domain/app_version.dart';

void main() {
  group('AppVersion.parse', () {
    test('parses plain semver', () {
      final v = AppVersion.parse('1.2.3');
      expect(v, const AppVersion(1, 2, 3));
    });

    test('bỏ prefix v', () {
      expect(AppVersion.parse('v1.2.0'), const AppVersion(1, 2, 0));
      expect(AppVersion.parse('V2.0.0'), const AppVersion(2, 0, 0));
    });

    test('bỏ build metadata sau dấu +', () {
      expect(AppVersion.parse('v1.2.0+3'), const AppVersion(1, 2, 0));
    });

    test('thiếu patch/minor mặc định 0', () {
      expect(AppVersion.parse('1.2'), const AppVersion(1, 2, 0));
      expect(AppVersion.parse('1'), const AppVersion(1, 0, 0));
    });

    test('phần không phải số mặc định 0', () {
      expect(AppVersion.parse('1.x.0'), const AppVersion(1, 0, 0));
    });
  });

  group('AppVersion comparison', () {
    test('so sánh major/minor/patch', () {
      expect(AppVersion.parse('1.2.0') > AppVersion.parse('1.1.9'), isTrue);
      expect(AppVersion.parse('2.0.0') > AppVersion.parse('1.9.9'), isTrue);
      expect(AppVersion.parse('1.2.3') > AppVersion.parse('1.2.2'), isTrue);
      expect(AppVersion.parse('1.2.3') < AppVersion.parse('1.3.0'), isTrue);
    });

    test('bằng nhau không lớn hơn', () {
      expect(AppVersion.parse('1.0.0') > AppVersion.parse('v1.0.0+9'), isFalse);
      expect(AppVersion.parse('1.0.0') >= AppVersion.parse('1.0.0'), isTrue);
    });

    test('toString rút gọn về major.minor.patch', () {
      expect(AppVersion.parse('v1.2.0+3').toString(), '1.2.0');
    });
  });
}
